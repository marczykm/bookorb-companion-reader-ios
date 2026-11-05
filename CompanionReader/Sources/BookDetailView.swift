import SwiftUI

/// The page of one book: cover, reading progress, details, notes and related books.
struct BookPage: View {
    /// True for the page opened as a sheet; it owns the back/close button and the navigation destinations.
    var isRoot = false
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var book: BookCard
    @State private var detail: BookDetail?
    @State private var sessions: SessionsPage?
    @State private var journal: [JournalEntry] = []
    @State private var inSeries: [RelatedBook] = []
    @State private var byAuthor: [RelatedBook] = []
    @State private var similar: [RelatedBook] = []
    @State private var reading = false
    @State private var downloading = false
    @State private var onDevice = false
    @State private var error: String?
    @State private var showEntry = false
    @State private var entryText = ""
    @State private var showNote = false
    @State private var noteText = ""

    var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    readButton
                    actions
                    stats
                    if let s = sessions, s.stats.totalSessions > 0 { yourReading(s) }
                    about
                    files
                    details
                    collections
                    notebook
                    review
                    related("More in \(detail?.seriesName ?? "series")", inSeries, showIndex: true)
                    related("More by \(detail?.authors.first?.name ?? "author")", byAuthor, showIndex: false)
                    related("Similar books", similar, showIndex: false)
                }.padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if isRoot { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.down") } } } }
            .fullScreenCover(isPresented: $reading, onDismiss: { refresh() }) {
                if let f = epub { ReaderScreen(book: book, file: f) }
            }
            .alert("New entry", isPresented: $showEntry) {
                TextField("What do you think?", text: $entryText, axis: .vertical)
                Button("Cancel", role: .cancel) { entryText = "" }
                Button("Save") { addEntry() }
            } message: { Text("It is dated and remembers where you were in the book.") }
            .alert("My review", isPresented: $showNote) {
                TextField("Private note", text: $noteText, axis: .vertical)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveNote() }
            }
            .task { await load() }
    }

    // MARK: Derived

    private var epub: BookFileRef? {
        if let f = book.epubFile() { return f }
        return detail?.files.first { ["epub", "kepub"].contains($0.format?.lowercased() ?? "") }.map { BookFileRef(id: $0.id, format: $0.format, role: $0.role) }
    }
    private var progress: Double? { sessions?.stats.latestEndProgress ?? book.readingProgress }
    private var title: String { detail?.title ?? book.title ?? "Untitled" }
    private var authors: String { (detail?.authors.map(\.name)).flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? book.authors.joined(separator: ", ") }

    // MARK: Pieces

    private var hero: some View {
        VStack(spacing: 10) {
            CoverView(book: book).frame(width: 210).shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            Text(title).font(.system(size: 30, weight: .semibold, design: .serif)).multilineTextAlignment(.center).padding(.horizontal)
            if let a = detail?.authors.first {
                NavigationLink(value: Opened(kind: .author, id: a.id, title: a.name)) {
                    Label(authors, systemImage: "chevron.right").labelStyle(TrailingIcon()).font(.title3.weight(.medium))
                }
            } else if !authors.isEmpty { Text(authors).font(.title3).foregroundStyle(.secondary) }
            if let d = detail, let name = d.seriesName {
                let text = name + (d.seriesIndex.map { " · Book \($0)" } ?? "")
                if let sid = d.seriesId {
                    NavigationLink(value: Opened(kind: .series, id: sid, title: name)) { Label(text, systemImage: "chevron.right").labelStyle(TrailingIcon()).font(.subheadline) }.foregroundStyle(.secondary)
                } else { Text(text).font(.subheadline).foregroundStyle(.secondary) }
            }
        }.padding(.top, 8)
    }

    private var readButton: some View {
        Group {
            if epub != nil {
                Button { reading = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.fill").font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((progress ?? 0) > 0 ? "Continue Reading" : "Read").font(.title3.weight(.semibold))
                            Text(["EPUB", progress.map { "\(Int($0.rounded()))%" }].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).opacity(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(alignment: .leading) {
                        GeometryReader { g in Color.accentColor.opacity(0.35).frame(width: g.size.width * min(max((progress ?? 0) / 100, 0), 1)) }
                    }
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule()).foregroundStyle(.primary)
                }.padding(.horizontal)
            } else {
                Text("Only EPUB books can be read in this app.").foregroundStyle(.secondary).padding(.horizontal)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Status", selection: Binding(get: { book.readStatus?.status ?? "unread" }, set: setStatus)) {
                    ForEach(bookStatuses, id: \.key) { Text($0.label).tag($0.key) }
                }
            } label: {
                tile(systemImage: "book", title: bookStatuses.first { $0.key == (book.readStatus?.status ?? "unread") }?.label ?? "Status", chevron: true)
            }
            if let f = epub {
                Button {
                    if onDevice { api.removeDownload(fileId: f.id); onDevice = false } else { download(f) }
                } label: {
                    if downloading { tile(systemImage: "arrow.down.circle", title: "Downloading…", chevron: false) }
                    else if onDevice { tile(systemImage: "checkmark.circle.fill", title: "Downloaded", chevron: false, tint: .green) }
                    else { tile(systemImage: "arrow.down.circle", title: "Download", chevron: false) }
                }.disabled(downloading)
            }
        }.padding(.horizontal)
    }

    private func tile(systemImage: String, title: String, chevron: Bool, tint: Color = .primary) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
            HStack(spacing: 3) { Text(title); if chevron { Image(systemName: "chevron.down").font(.caption2) } }.font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 74).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private var stats: some View {
        HStack(alignment: .top) {
            VStack(spacing: 4) {
                Text("RATING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(book.rating.map { String(format: "%g", $0) } ?? "Rate").font(.title2.weight(.semibold)).foregroundStyle(.tint)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= (book.rating ?? 0) ? "star.fill" : "star").font(.caption).foregroundStyle(.orange)
                            .onTapGesture { setRating(Int(book.rating ?? 0) == i ? nil : i) }
                    }
                }
            }.frame(maxWidth: .infinity)
            stat("LENGTH", detail?.pageCount.map(String.init) ?? "–", "pages")
            stat("PUBLISHED", detail?.publishedYear.map(String.init) ?? "–", detail?.publisher ?? "")
            stat("LANGUAGE", detail?.language?.uppercased() ?? "–", languageName)
        }.padding(.horizontal)
    }

    private var languageName: String {
        guard let l = detail?.language else { return "" }
        return Locale(identifier: "en").localizedString(forLanguageCode: l) ?? ""
    }

    private func stat(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Your reading

    private func yourReading(_ s: SessionsPage) -> some View {
        let p = (progress ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Your reading")
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
                        Circle().trim(from: 0, to: min(p / 100, 1)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(Int(p.rounded()))%").font(.title3.weight(.semibold))
                    }.frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EPUB").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(timeLeft(s).map { "About \($0) left" } ?? "In progress").font(.title3.weight(.semibold))
                        if let last = Self.date(s.stats.lastSessionAt) { Text("Last read \(Self.full.string(from: last))").foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }.padding(16)
                Divider()
                HStack {
                    VStack(alignment: .leading) { Text(hm(s.stats.totalSeconds)).font(.title3.weight(.semibold)); Text("read").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider().frame(height: 40)
                    VStack(alignment: .leading) {
                        Text(Self.date(s.stats.firstSessionAt).map { Self.full.string(from: $0) } ?? "–").font(.title3.weight(.semibold)); Text("started").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                }.padding(16)
                Divider()
                NavigationLink { BookTimelineView(book: book, title: title, sessions: s) } label: {
                    HStack {
                        Label("Timeline", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                        Spacer()
                        Text("\(s.stats.totalSessions) sessions").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }.padding(16).foregroundStyle(.primary)
                }
            }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        }.padding(.horizontal)
    }

    private func timeLeft(_ s: SessionsPage) -> String? {
        guard let left = Self.secondsLeft(s.stats, progress: progress) else { return nil }
        return hm(left)
    }

    static func secondsLeft(_ st: SessionsPage.Stats, progress: Double?) -> Double? {
        guard let p = progress, st.paceProgressDelta > 0, st.paceDurationSeconds > 0 else { return nil }
        return max(100 - p, 0) / st.paceProgressDelta * st.paceDurationSeconds
    }

    // MARK: About, file, details

    @ViewBuilder private var about: some View {
        if let d = detail, (d.description?.isEmpty == false) || !d.genres.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("About this book")
                if let desc = d.description, !desc.isEmpty { Text(Self.plain(desc)).font(.body) }
                FlowLayout(spacing: 8) { ForEach(d.genres.prefix(6), id: \.self) { chip($0) } }
            }.padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var files: some View {
        if let d = detail, !d.files.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("File")
                VStack(spacing: 0) {
                    ForEach(Array(d.files.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Divider().padding(.leading, 70) }
                        HStack(spacing: 14) {
                            Text((f.format ?? "FILE").uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.green)
                                .frame(width: 46, height: 56).overlay(RoundedRectangle(cornerRadius: 6).stroke(.green.opacity(0.6)))
                            VStack(alignment: .leading) {
                                Text("\((f.format ?? "File").uppercased()) \(f.format?.lowercased() == "mp3" || f.format?.lowercased() == "m4b" ? "audiobook" : "ebook")").font(.headline)
                                if let b = f.sizeBytes { Text(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if onDevice, f.id == epub?.id { Label("Downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline.weight(.medium)) }
                        }.padding(14)
                    }
                }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.horizontal)
        }
    }

    @ViewBuilder private var details: some View {
        if let d = detail {
            let rows: [(String, String, Opened?)] = [
                ("Series", d.seriesName.map { $0 + (d.seriesIndex.map { " #\($0)" } ?? "") } ?? "", d.seriesId.flatMap { id in d.seriesName.map { Opened(kind: .series, id: id, title: $0) } }),
                ("Publisher", d.publisher ?? "", nil),
                ("ISBN", d.isbn13 ?? d.isbn10 ?? "", nil),
                ("Library", d.libraryName ?? "", nil),
                ("Added", Self.date(d.addedAt).map { Self.full.string(from: $0) } ?? "", nil),
            ].filter { !$0.1.isEmpty }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Details")
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Divider() }
                            HStack(alignment: .top) {
                                Text(r.0).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                                if let o = r.2 { NavigationLink(value: o) { Label(r.1, systemImage: "chevron.right").labelStyle(TrailingIcon()) } }
                                else { Text(r.1) }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 12).padding(.horizontal, 16)
                        }
                    }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                }.padding(.horizontal)
            }
        }
    }

    @ViewBuilder private var collections: some View {
        if let d = detail, !d.collections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Collections")
                FlowLayout(spacing: 8) { ForEach(d.collections, id: \.id) { chip($0.name) } }
            }.padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notebook: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Notebook")
            VStack(alignment: .leading, spacing: 12) {
                if journal.isEmpty {
                    Text("Jot down what you think as you read. Each entry is dated and remembers where you were in the book.").foregroundStyle(.secondary)
                } else {
                    ForEach(journal.prefix(5)) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.body)
                            Text([Self.date(e.createdAt).map { Self.full.string(from: $0) }, e.positionPercent.map { "\(Int($0.rounded()))%" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
                Button { entryText = ""; showEntry = true } label: {
                    Label("New Entry", systemImage: "square.and.pencil").font(.headline).frame(maxWidth: .infinity, minHeight: 44).background(.quaternary, in: Capsule())
                }.buttonStyle(.plain)
            }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        }.padding(.horizontal)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("My review")
            Button { noteText = detail?.personalNote ?? ""; showNote = true } label: {
                HStack {
                    Text((detail?.personalNote).flatMap { $0.isEmpty ? nil : $0 } ?? "Add a private note").foregroundStyle((detail?.personalNote ?? "").isEmpty ? .secondary : .primary).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
        }.padding(.horizontal)
    }

    @ViewBuilder private func related(_ title: String, _ list: [RelatedBook], showIndex: Bool) -> some View {
        let items = list.filter { $0.id != book.id }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(title).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { r in
                            NavigationLink(value: r) {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverView(book: r.card).frame(width: 118)
                                    Text(r.title ?? "Untitled").font(.subheadline.weight(.medium)).lineLimit(1).frame(width: 118, alignment: .leading)
                                    Text(showIndex ? (r.seriesIndex.map { "Book \($0)" } ?? "") : r.authors.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).lineLimit(1).frame(width: 118, alignment: .leading)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal)
                }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View { Text(t).font(.system(size: 24, weight: .semibold, design: .serif)) }
    private func chip(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8).background(.quaternary.opacity(0.6), in: Capsule())
    }

    // MARK: Actions

    private func load() async {
        if let f = epub { onDevice = api.isOnDevice(f.id) }
        async let d = try? api.bookDetail(id: book.id)
        async let s = try? api.sessions(bookId: book.id)
        async let j = api.journal(bookId: book.id)
        detail = await d; sessions = await s; journal = await j
        if let f = epub { onDevice = api.isOnDevice(f.id) }
        async let a = api.seriesBooks(bookId: book.id)
        async let b = api.authorBooks(bookId: book.id)
        async let c = api.recommendations(bookId: book.id)
        inSeries = await a; byAuthor = await b; similar = await c
    }

    private func refresh() { Task { await load() } }

    private func download(_ file: BookFileRef) {
        downloading = true; error = nil
        Task {
            do { _ = try await api.downloadFile(fileId: file.id); onDevice = true } catch { self.error = error.localizedDescription }
            downloading = false
        }
    }

    private func setStatus(_ s: String) {
        book.readStatus = StatusInfo(status: s)
        app.outbox.status(bookId: book.id, s); app.syncNow()
    }
    private func setRating(_ r: Int?) {
        book.rating = r.map(Double.init)
        app.outbox.rating(bookId: book.id, r); app.syncNow()
    }

    private func addEntry() {
        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        entryText = ""
        guard !text.isEmpty else { return }
        Task {
            do { try await api.addJournalEntry(bookId: book.id, body: text, positionPercent: progress); journal = await api.journal(bookId: book.id) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func saveNote() {
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do { try await api.setPersonalNote(bookId: book.id, note: note.isEmpty ? nil : note); detail?.personalNote = note.isEmpty ? nil : note }
            catch { self.error = error.localizedDescription }
        }
    }

    // MARK: Formatting

    static let full: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f }()
    static func date(_ iso: String?) -> Date? { HighlightsHubView.parse(iso) }
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}

func hm(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    let h = s / 3600, m = (s % 3600) / 60
    return h == 0 ? "\(m)m" : "\(h)h \(String(format: "%02d", m))m"
}

/// The book page as a sheet: it hosts the navigation for series, authors, related books and the timeline.
struct BookDetailView: View {
    let book: BookCard
    init(book: BookCard) { self.book = book }
    var body: some View {
        NavigationStack {
            BookPage(isRoot: true, book: book)
                .navigationDestination(for: Opened.self) { PagedBooksView(opened: $0) }
                .navigationDestination(for: RelatedBook.self) { BookPage(book: $0.card) }
        }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.footnote.weight(.semibold)) }
    }
}

/// A row of items that wraps onto further lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing; rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowHeight = max(rowHeight, s.height)
        }
    }
}
