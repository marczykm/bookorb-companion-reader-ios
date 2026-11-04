import SwiftUI
import UIKit
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

private let idleLimit: TimeInterval = 120

@MainActor
final class ReaderModel: NSObject, ObservableObject, EPUBNavigatorDelegate {
    let book: BookCard
    let file: BookFileRef
    let app: AppState
    var api: ServerAPI { app.api }

    @Published var navigator: EPUBNavigatorViewController?
    @Published var host: NavigatorHostController?
    @Published var activeAnnotation: Annotation?
    @Published var notice: String?
    private var highlights: HighlightSync?
    @Published var error: String?
    @Published var showBars = false
    @Published var title = ""
    @Published var progress: Double = 0
    @Published var minutesLeft = ""
    /// Where each table-of-contents chapter starts, as a fraction of the book.
    @Published var chapters: [(title: String, start: Double)] = []
    @Published var jumpOffer: (server: Double, local: Double)?
    @Published var toc: [(depth: Int, link: ReadiumShared.Link)] = []

    private(set) var publication: Publication?
    private var counter = ProgressSyncCounter(pagesPerSync: 10)
    private var openedAt: Double?
    private var moved = false
    private var lastPercent = -1.0
    private var pendingInitial: (saved: Locator?, server: Locator?)?

    // For "minutes left in chapter": words in each resource, and which resources open a chapter.
    private var wordsByResource: [Int]?
    private var chapterStartIndexes: [Int] = []
    // Learning the reader's pace: words moved forward per second of active reading, this session.
    private var lastWordPosition: Double?
    private var lastSampleAt: Date?
    private var paceWords = 0.0
    private var paceSeconds = 0.0
    private let minPace = 80.0, maxPace = 600.0

    // Reading-time tracking: time between page turns counts only while under the idle limit.
    private let sessionId = UUID().uuidString
    private let startedAt = Date()
    private var activeSeconds: TimeInterval = 0
    private var lastActivity: Date?
    private var startProgress: Double?
    private var currentProgress: Double?
    private var uploaded = false

    private var locKey: String { "loc_\(file.id)" }

    init(book: BookCard, file: BookFileRef, app: AppState) {
        self.book = book; self.file = file; self.app = app
    }

    func open() async {
        do {
            let url = try await api.downloadFile(fileId: file.id)
            let http = DefaultHTTPClient()
            let retriever = AssetRetriever(httpClient: http)
            guard let fileURL = FileURL(url: url) else { throw ReaderError.message("Bad file") }
            let asset = try await retriever.retrieve(url: fileURL).get()
            let opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: http, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()))
            let pub = try await opener.open(asset: asset, allowUserInteraction: false).get()
            publication = pub

            let saved = UserDefaults.standard.string(forKey: locKey).flatMap { try? Locator(jsonString: $0) }
            let serverPct = await api.getProgress(fileId: file.id)
            let localPct = (saved?.locations.totalProgression ?? 0) * 100
            let positions = (try? await pub.positions().get()) ?? []
            let serverLocator: Locator? = serverPct > 0 && !positions.isEmpty
                ? positions[min(max(Int(Double(positions.count - 1) * serverPct / 100), 0), positions.count - 1)] : nil

            if saved == nil {
                try start(at: serverLocator)
            } else if serverPct > localPct + 1, let serverLocator {
                pendingInitial = (saved, serverLocator)
                jumpOffer = (serverPct, localPct)
            } else {
                try start(at: saved)
            }
            let links = try await pub.tableOfContents().get()
            toc = flatten(links, 0)
            await buildChapters(pub, toc: links)
            await buildReadingModel(pub, toc: links)
        } catch {
            let offline = (error is URLError) && !api.isOnDevice(file.id)
            self.error = offline ? "This book isn't on the device yet. Open it once while connected." : error.localizedDescription
        }
    }

    func resolveJump(accept: Bool) {
        guard let p = pendingInitial else { return }
        jumpOffer = nil
        try? start(at: accept ? p.server : p.saved)
        pendingInitial = nil
    }

    private func start(at locator: Locator?) throws {
        guard let pub = publication else { return }
        var config = EPUBNavigatorViewController.Configuration(preferences: app.settings.preferences)
        config.editingActions = EditingAction.defaultActions + [EditingAction(title: "Highlight", action: #selector(NavigatorHostController.highlightSelection(_:)))]
        let nav = try EPUBNavigatorViewController(publication: pub, initialLocation: locator, config: config)
        nav.delegate = self
        navigator = nav
        let hostVC = NavigatorHostController(navigator: nav)
        host = hostVC
        if book.id != 0 {
            let hl = HighlightSync(pub: pub, app: app, bookId: book.id, fileId: file.id)
            hl.attach(nav)
            hl.onActivated = { [weak self] in self?.activeAnnotation = $0 }
            hl.onMessage = { [weak self] in self?.notice = $0 }
            hostVC.onHighlight = { [weak hl] in Task { @MainActor in await hl?.highlightSelection() } }
            highlights = hl
            Task { await hl.sync() }
        }
        lastActivity = Date()
    }

    private func flatten(_ links: [ReadiumShared.Link], _ depth: Int) -> [(depth: Int, link: ReadiumShared.Link)] {
        links.flatMap { l -> [(depth: Int, link: ReadiumShared.Link)] in
            (!(l.title?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ?[(depth, l)] : []) + flatten(l.children, depth + 1)
        }
    }

    func applySettings() { navigator?.submitPreferences(app.settings.preferences) }
    func goForward() { Task { _ = await navigator?.goForward(options: .init(animated: false)) } }
    func goBackward() { Task { _ = await navigator?.goBackward(options: .init(animated: false)) } }
    func go(to link: ReadiumShared.Link) { showBars = false; Task { _ = await navigator?.go(to: link, options: .init(animated: false)) } }

    // MARK: Navigator callbacks

    nonisolated func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        Task { @MainActor in self.located(locator) }
    }
    nonisolated func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        Task { @MainActor in self.error = "\(error)" }
    }
    nonisolated func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        Task { @MainActor in
            let w = navigator.view.bounds.width
            if point.x < w * 0.2 { self.goBackward() }
            else if point.x > w * 0.8 { self.goForward() }
            else { self.showBars.toggle() }
        }
    }

    private func touchActivity() {
        let now = Date()
        if let last = lastActivity { activeSeconds += min(now.timeIntervalSince(last), idleLimit) }
        lastActivity = now
    }

    func recolor(_ a: Annotation, _ hex: String) { highlights?.recolor(a, to: hex) }
    func delete(_ a: Annotation) { highlights?.delete(a) }
    /// Pick up highlights edited on the web while the app was in the background.
    func refreshHighlights() { if let hl = highlights { Task { await hl.sync() } } }

    /// Where each table-of-contents chapter starts, as a fraction of the book (from the first position in its file).
    private func buildChapters(_ pub: Publication, toc: [ReadiumShared.Link]) async {
        let positions = (try? await pub.positions().get()) ?? []
        var starts: [String: Double] = [:]
        for p in positions {
            if let t = p.locations.totalProgression, starts[Self.key(p.href.string)] == nil { starts[Self.key(p.href.string)] = t }
        }
        var out: [(title: String, start: Double)] = []
        var seen = Set<String>()
        func walk(_ links: [ReadiumShared.Link]) {
            for l in links {
                let href = Self.key(l.url().string)
                let title = (l.title ?? "").trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, let start = starts[href], seen.insert(href).inserted { out.append((title, start)) }
                walk(l.children)
            }
        }
        walk(toc)
        chapters = out.sorted { $0.start < $1.start }
        if let loc = navigator?.currentLocation { title = chapterTitle(loc) }
    }

    private func chapterTitle(_ loc: Locator) -> String {
        let p = loc.locations.totalProgression ?? 0
        return chapters.last(where: { $0.start <= p + 0.0005 })?.title ?? loc.title ?? ""
    }

    // MARK: Minutes left

    private static func key(_ href: String) -> String { HighlightSync.key(href) }

    /// Counts the words in every resource, once, so the time left in a chapter can be estimated.
    private func buildReadingModel(_ pub: Publication, toc: [ReadiumShared.Link]) async {
        var words: [Int] = []
        for link in pub.readingOrder {
            var count = 0
            if let resource = pub.get(link), let data = try? await resource.read().get(), let html = String(data: data, encoding: .utf8) {
                let plain = html
                    .replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                count = plain.split(whereSeparator: { $0.isWhitespace }).count
            }
            words.append(count)
        }
        let indexByHref = Dictionary(pub.readingOrder.enumerated().map { (Self.key($1.url().string), $0) }, uniquingKeysWith: { a, _ in a })
        var starts = Set<Int>()
        func walk(_ links: [ReadiumShared.Link]) {
            for l in links {
                if let i = indexByHref[Self.key(l.url().string)] { starts.insert(i) }
                walk(l.children)
            }
        }
        walk(toc)
        chapterStartIndexes = starts.sorted()
        wordsByResource = words
        if let loc = navigator?.currentLocation { minutesLeft = minutesLeftText(loc) }
    }

    private func resourceIndex(_ loc: Locator) -> Int? {
        guard let pub = publication else { return nil }
        let href = Self.key(loc.href.string)
        return pub.readingOrder.firstIndex { Self.key($0.url().string) == href }
    }

    /// How many words into the book `loc` is, or nil while word counts are still being made.
    private func wordPosition(_ loc: Locator) -> Double? {
        guard let words = wordsByResource, let index = resourceIndex(loc) else { return nil }
        let before = words[..<index].reduce(0, +)
        return Double(before) + Double(words[index]) * min(max(loc.locations.progression ?? 0, 0), 1)
    }

    /// Records one reading step. Only ordinary page turns count: forward, a plausible number of words and
    /// a plausible time (not a flick through pages, not a pause), so jumps and skimming don't skew it.
    private func samplePace(_ loc: Locator) {
        guard let position = wordPosition(loc) else { return }
        let now = Date()
        if let previous = lastWordPosition, let since = lastSampleAt {
            let words = position - previous
            let seconds = now.timeIntervalSince(since)
            if (20.0...900.0).contains(words), (3.0...120.0).contains(seconds), words / seconds * 60 <= 1000 {
                paceWords += words; paceSeconds += seconds
            }
        }
        lastWordPosition = position; lastSampleAt = now
    }

    /// Pace used for the estimate: what was learned before, nudged by this session once it has enough to say.
    private func currentPace() -> Double {
        let stored = app.settings.learnedPace > 0 ? app.settings.learnedPace : defaultWordsPerMinute
        if paceSeconds < 90 { return stored }
        let session = min(max(paceWords / paceSeconds * 60, minPace), maxPace)
        return (stored + session) / 2
    }

    /// Folds this session's pace into the saved one (30% new, 70% old) so one odd session can't swing it.
    private func commitPace() {
        if paceSeconds >= 60 {
            let session = min(max(paceWords / paceSeconds * 60, minPace), maxPace)
            let old = app.settings.learnedPace
            app.settings.learnedPace = old > 0 ? old * 0.7 + session * 0.3 : session
            paceWords = 0; paceSeconds = 0
        }
        lastWordPosition = nil; lastSampleAt = nil
    }

    /// "12 min left" for the rest of the current chapter, or empty until word counts are known.
    private func minutesLeftText(_ loc: Locator) -> String {
        guard let words = wordsByResource, let index = resourceIndex(loc) else { return "" }
        // The chapter ends where the next one starts; with no table of contents it runs to the end of the book.
        let end = chapterStartIndexes.first { $0 > index } ?? words.count
        let within = min(max(loc.locations.progression ?? 0, 0), 1)
        var remaining = Double(words[index]) * (1 - within)
        for i in (index + 1)..<max(end, index + 1) { remaining += Double(words[i]) }
        if remaining < 10 { return "<1 min left" }
        return "\(max(Int((remaining / currentPace()).rounded()), 1)) min left"
    }

    private func located(_ loc: Locator) {
        samplePace(loc)
        minutesLeft = minutesLeftText(loc)
        highlights?.chapterMayHaveChanged(href: loc.href.string)
        title = chapterTitle(loc)
        touchActivity()
        guard let p = loc.locations.totalProgression else { return }
        progress = p
        if openedAt == nil { openedAt = p } else if p != openedAt { moved = true }
        if counter.onPosition(p, moved: moved) {
            lastPercent = p * 100
            app.outbox.progress(fileId: file.id, percentage: lastPercent)
            app.syncNow()
        }
        currentProgress = p * 100
        if startProgress == nil { startProgress = p * 100 }
        if moved { if let s = try? loc.jsonString() { UserDefaults.standard.set(s, forKey: locKey) } }
    }

    /// Called when the reader goes to the background or closes: saves position, progress and reading time.
    func flushState() {
        touchActivity(); lastActivity = nil
        commitPace()
        if let loc = navigator?.currentLocation, moved {
            if let s = try? loc.jsonString() { UserDefaults.standard.set(s, forKey: locKey) }
            if let p = loc.locations.totalProgression, p * 100 != lastPercent {
                lastPercent = p * 100
                app.outbox.progress(fileId: file.id, percentage: lastPercent)
            }
        }
        let seconds = Int(activeSeconds)
        if seconds >= 5 {
            let end = currentProgress
            let f = ISO8601DateFormatter()
            app.outbox.session(fileId: file.id, ReadingSession(
                sessionId: sessionId, startedAt: f.string(from: startedAt), endedAt: f.string(from: Date()),
                durationSeconds: seconds,
                progressDelta: (end != nil && startProgress != nil) ? end! - startProgress! : nil,
                endProgress: end.map { min(max($0, 0), 100) }))
        }
        app.syncNow()
    }

    func resume() {
        lastActivity = Date(); refreshHighlights()
        // The pace may have just been updated, so redo the estimate.
        if let loc = navigator?.currentLocation { minutesLeft = minutesLeftText(loc) }
    }
}

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

struct NavigatorHost: UIViewControllerRepresentable {
    let host: NavigatorHostController
    func makeUIViewController(context: Context) -> NavigatorHostController { host }
    func updateUIViewController(_ vc: NavigatorHostController, context: Context) {}
}

struct ReaderScreen: View {
    @EnvironmentObject var app: AppState
    let book: BookCard
    let file: BookFileRef
    var body: some View { ReaderContent(model: ReaderModel(book: book, file: file, app: app)) }
}

private struct ReaderContent: View {
    @StateObject var model: ReaderModel
    @ObservedObject private var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var showToc = false
    @State private var showSettings = false

    init(model: ReaderModel) {
        _model = StateObject(wrappedValue: model)
        settings = model.app.settings
    }

    private var bg: SwiftUI.Color { settings.dark ? SwiftUI.Color.black : SwiftUI.Color.white }
    private var fg: SwiftUI.Color { settings.dark ? .white : .black }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if let host = model.host {
                NavigatorHost(host: host).ignoresSafeArea(.container, edges: .bottom).padding(.top, 28).padding(.bottom, 28)
            } else if model.error == nil {
                ProgressView()
            }
            VStack {
                Text(model.title).font(.caption).lineLimit(1).foregroundStyle(fg.opacity(0.6)).padding(.top, 4)
                Spacer()
                HStack {
                    ProgressMarksView(progress: model.progress, marks: model.chapters.map(\.start), color: fg)
                    if !model.minutesLeft.isEmpty { Text(model.minutesLeft).font(.caption).foregroundStyle(fg.opacity(0.6)) }
                    Text("\(Int(model.progress * 100))%").font(.caption).foregroundStyle(fg.opacity(0.6))
                }.padding(.horizontal).padding(.bottom, 6)
            }.allowsHitTesting(false)
            if model.showBars { toolbar }
            if let e = model.error {
                VStack(spacing: 12) { Text(e).multilineTextAlignment(.center); Button("Close") { close() } }.padding().foregroundStyle(fg)
            }
        }
        .preferredColorScheme(settings.dark ? .dark : .light)
        .statusBarHidden(true)
        .task { await model.open() }
        .onChange(of: phase) { _, p in if p == .active { model.resume() } else { model.flushState() } }
        .onChange(of: settings.fontSize) { _, _ in model.applySettings() }
        .onChange(of: settings.margins) { _, _ in model.applySettings() }
        .onChange(of: settings.justify) { _, _ in model.applySettings() }
        .onChange(of: settings.dark) { _, _ in model.applySettings() }
        .confirmationDialog(model.activeAnnotation.map { String($0.text.prefix(80)) } ?? "", isPresented: Binding(get: { model.activeAnnotation != nil }, set: { if !$0 { model.activeAnnotation = nil } }), titleVisibility: .visible) {
            if let a = model.activeAnnotation {
                ForEach(HighlightSync.colors, id: \.name) { c in Button(c.name.capitalized) { model.recolor(a, c.hex) } }
                Button("Delete highlight", role: .destructive) { model.delete(a) }
            }
        }
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") {} }
        .sheet(isPresented: $showToc) { tocSheet }
        .sheet(isPresented: $showSettings) { settingsSheet.presentationDetents([.medium]) }
        .alert("Continue from another device?", isPresented: Binding(get: { model.jumpOffer != nil }, set: { _ in })) {
            Button("Jump to \(Int(model.jumpOffer?.server ?? 0))%") { model.resolveJump(accept: true) }
            Button("Stay here", role: .cancel) { model.resolveJump(accept: false) }
        } message: {
            Text("Your server is at \(Int(model.jumpOffer?.server ?? 0))%, this device is at \(Int(model.jumpOffer?.local ?? 0))%.")
        }
    }

    private func close() { model.flushState(); dismiss() }

    private var toolbar: some View {
        VStack {
            HStack(spacing: 22) {
                Button { close() } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button { settings.dark.toggle() } label: { Image(systemName: settings.dark ? "sun.max" : "moon") }
                Button { showToc = true } label: { Image(systemName: "list.bullet") }
                Button { showSettings = true } label: { Text("Aa") }
            }
            .font(.title3).foregroundStyle(.white).padding().background(Color(white: 0.13))
            Spacer()
        }
    }

    private var tocSheet: some View {
        NavigationStack {
            List(Array(model.toc.enumerated()), id: \.offset) { _, e in
                Button { showToc = false; model.go(to: e.link) } label: {
                    Text(e.link.title ?? "").padding(.leading, CGFloat(e.depth) * 16)
                }
            }
            .overlay { if model.toc.isEmpty { Text("This book has no table of contents.").foregroundStyle(.secondary) } }
            .navigationTitle("Contents").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Stepper("Font size: \(Int(settings.fontSize * 100))%", value: $settings.fontSize, in: 0.5...2.5, step: 0.1)
                Stepper("Margins: \(settings.margins == 1 ? "default" : "\(Int(settings.margins * 100))%")", value: $settings.margins, in: 0...4, step: 0.25)
                Toggle("Justify text", isOn: $settings.justify)
                Text(settings.learnedPace > 0
                     ? "Reading speed: about \(Int(settings.learnedPace)) words/min (learned from your reading)"
                     : "Reading speed: \(Int(defaultWordsPerMinute)) words/min (until it learns yours)")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset", role: .destructive) { settings.reset() }
            }
            .navigationTitle("Reading settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
    }
}

/// A thin progress bar with a tick at the start of every chapter and a dot for the current position.
struct ProgressMarksView: View {
    let progress: Double
    let marks: [Double]
    let color: SwiftUI.Color

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 4, right = size.width - 4, cy = size.height / 2, track: CGFloat = 3
            let span = right - left
            let p = CGFloat(min(max(progress, 0), 1))
            ctx.fill(Path(roundedRect: CGRect(x: left, y: cy - track / 2, width: span, height: track), cornerRadius: track / 2), with: .color(color.opacity(0.2)))
            ctx.fill(Path(roundedRect: CGRect(x: left, y: cy - track / 2, width: span * p, height: track), cornerRadius: track / 2), with: .color(color.opacity(0.6)))
            // Chapter starts; the first one is the left end of the bar, so it needs no tick.
            for m in marks where m > 0.002 && m < 0.998 {
                let x = left + span * CGFloat(m)
                ctx.fill(Path(CGRect(x: x - 0.75, y: cy - 5, width: 1.5, height: 10)), with: .color(color.opacity(0.65)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: left + span * p - 5, y: cy - 5, width: 10, height: 10)), with: .color(color.opacity(0.85)))
        }
        .frame(height: 14)
    }
}
