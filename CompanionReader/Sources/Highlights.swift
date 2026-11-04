import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator

/// Wraps the navigator and answers the "Highlight" item in the text selection menu, which iOS looks
/// for up the responder chain.
final class NavigatorHostController: UIViewController {
    let navigator: EPUBNavigatorViewController
    var onHighlight: (() -> Void)?

    init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(navigator)
        navigator.view.frame = view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigator.view)
        navigator.didMove(toParent: self)
    }

    @objc func highlightSelection(_ sender: Any?) { onHighlight?() }
}

/// Two-way highlight sync with the server. Positions are stored as EPUB CFIs, the same format the web
/// reader writes, so highlights made here show up there and vice versa.
///
/// Device to server: the selection's CFI is computed in the page with foliate-js's CFI code (the
/// implementation the web reader uses). Server to device: the CFI's spine step picks the chapter and
/// the highlighted text is located inside it, with the text around it to tell repeats apart.
@MainActor
final class HighlightSync {
    static let group = "bookorbit-highlights"
    static let colors: [(name: String, hex: String)] = [("yellow", "#FACC15"), ("green", "#4ADE80"), ("blue", "#38BDF8"), ("pink", "#F472B6")]
    private static let allNames: [String: String] = [
        "yellow": "#FACC15", "green": "#4ADE80", "blue": "#38BDF8", "pink": "#F472B6", "orange": "#FB923C",
        "red": "#F87171", "olive": "#84CC16", "cyan": "#22D3EE", "purple": "#C084FC", "gray": "#9CA3AF",
    ]

    private struct Anchor { var before: String; var after: String; var locations: Locator.Locations }

    private let pub: Publication
    private let app: AppState
    private let bookId: Int
    private let fileId: Int
    weak var nav: EPUBNavigatorViewController?
    /// Called on the main actor when a highlight is tapped.
    var onActivated: ((Annotation) -> Void)?
    var onMessage: ((String) -> Void)?

    private var items: [Int: Annotation] = [:]
    private var context: [Int: Anchor] = [:]
    private var lastChapter: String?
    private lazy var cfiScript: String = {
        guard let u = Bundle.main.url(forResource: "epubcfi", withExtension: "js"), let s = try? String(contentsOf: u) else { return "" }
        return s
    }()

    init(pub: Publication, app: AppState, bookId: Int, fileId: Int) {
        self.pub = pub; self.app = app; self.bookId = bookId; self.fileId = fileId
    }

    func attach(_ nav: EPUBNavigatorViewController) {
        self.nav = nav
        nav.observeDecorationInteractions(inGroup: Self.group) { [weak self] event in
            guard let id = Int(event.decoration.id) else { return }
            Task { @MainActor in if let a = self?.items[id] { self?.onActivated?(a) } }
        }
    }

    /// Replaces the local set with the server's and redraws. Safe to call repeatedly.
    func sync() async {
        guard let remote = await app.api.annotations(bookId: bookId, fileId: fileId) else { return }
        items = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        applyPending()
        context = context.filter { items.keys.contains($0.key) }
        _ = await loadContext()
        render()
    }

    /// Puts back changes made here that the server hasn't received yet, so they show while offline.
    private func applyPending() {
        for op in app.outbox.pendingOps() where op.bookId == bookId {
            switch op.type {
            case "ann_create":
                items[-op.id] = Annotation(id: -op.id, cfi: op.cfi, text: op.text ?? "", color: op.color ?? "yellow")
            case "ann_color":
                if let id = op.annId, var a = items[id] { a.color = op.color ?? a.color; items[id] = a }
            case "ann_delete":
                if let id = op.annId { items.removeValue(forKey: id) }
            default: break
            }
        }
    }

    /// Re-anchors highlights when the reader moves into another chapter.
    func chapterMayHaveChanged(href: String) {
        let key = Self.key(href)
        guard key != lastChapter else { return }
        lastChapter = key
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // let the new chapter finish loading
            if await loadContext() { render() }
        }
    }

    private func spineIndex(ofHref href: String) -> Int {
        let target = Self.key(href)
        return pub.readingOrder.firstIndex { Self.key($0.url().string) == target } ?? -1
    }

    static func key(_ href: String) -> String { String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }

    /// The top-level step of a CFI, `/6/N`, names spine item N/2 - 1.
    static func spineIndex(ofCFI cfi: String) -> Int? {
        guard let m = cfi.range(of: #"^epubcfi\(/6/(\d+)"#, options: .regularExpression) else { return nil }
        let digits = cfi[m].drop { !$0.isNumber || false }.split(separator: "/").last.flatMap { Int($0) }
        guard let n = digits, n / 2 - 1 >= 0 else { return nil }
        return n / 2 - 1
    }

    /// Resolves the CFIs of highlights in the chapter on screen to their surrounding text. True if anything new was found.
    private func loadContext() async -> Bool {
        guard let nav, let here = nav.currentLocation else { return false }
        let chapter = spineIndex(ofHref: here.href.string)
        let pending = items.values.filter { context[$0.id] == nil && $0.cfi != nil && Self.spineIndex(ofCFI: $0.cfi!) == chapter }
        guard !pending.isEmpty else { return false }
        let arg = pending.map { ["id": String($0.id), "cfi": $0.cfi!] }
        guard let argData = try? JSONSerialization.data(withJSONObject: arg), let argJSON = String(data: argData, encoding: .utf8) else { return false }
        guard case .success(let value) = await nav.evaluateJavaScript("\(cfiScript);(\(Self.contextJS))(\(argJSON))"),
              let raw = value as? String, let data = raw.data(using: .utf8),
              let found = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: String]] else { return false }
        var changed = false
        for (id, o) in found {
            guard let id = Int(id) else { continue }
            var loc = Locator.Locations()
            if let s = o["s"] { loc.otherLocations = ["cssSelector": .string(s)] }
            context[id] = Anchor(before: o["b"] ?? "", after: o["a"] ?? "", locations: loc)
            changed = true
        }
        return changed
    }

    /// Called from the selection menu: stores a highlight for the current selection.
    func highlightSelection() async {
        guard let nav, let selection = nav.currentSelection else { return }
        let text = (selection.locator.text.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let spine = spineIndex(ofHref: selection.locator.href.string)
        guard !text.isEmpty, spine >= 0 else { return onMessage?("Can't highlight this selection") ?? () }

        guard case .success(let value) = await nav.evaluateJavaScript("\(cfiScript);(\(Self.selectionJS))"),
              let local = value as? String else { return onMessage?("Can't highlight this selection") ?? () }
        let inner = local.replacingOccurrences(of: "epubcfi(", with: "", options: .anchored).dropLast()
        let cfi = "epubcfi(/6/\((spine + 1) * 2)!\(inner))"

        let color = Self.colors[0].hex
        let temp = app.outbox.createAnnotation(bookId: bookId, fileId: fileId, cfi: cfi, text: text, color: color)
        app.syncNow()
        items[temp] = Annotation(id: temp, cfi: cfi, text: text, color: color)
        context[temp] = Anchor(before: String((selection.locator.text.before ?? "").suffix(40)),
                               after: String((selection.locator.text.after ?? "").prefix(40)),
                               locations: selection.locator.locations)
        nav.clearSelection()
        render()
    }

    func recolor(_ a: Annotation, to hex: String) {
        app.outbox.recolorAnnotation(bookId: bookId, annId: a.id, color: hex)
        var b = a; b.color = hex; items[a.id] = b
        app.syncNow(); render()
    }

    func delete(_ a: Annotation) {
        app.outbox.deleteAnnotation(bookId: bookId, annId: a.id)
        items.removeValue(forKey: a.id)
        app.syncNow(); render()
    }

    private func render() {
        let decorations: [Decoration] = items.values.compactMap { a in
            guard let cfi = a.cfi, let index = Self.spineIndex(ofCFI: cfi), pub.readingOrder.indices.contains(index), !a.text.isEmpty else { return nil }
            let link = pub.readingOrder[index]
            let anchor = context[a.id]
            let locator = Locator(
                href: link.url(),
                mediaType: link.mediaType ?? .xhtml,
                locations: anchor?.locations ?? Locator.Locations(),
                text: anchor.map { Locator.Text(after: $0.after, before: $0.before, highlight: a.text) } ?? Locator.Text(highlight: a.text)
            )
            let tint = Self.tint(a.color)
            let style: Decoration.Style = a.style == "underline" ? .underline(tint: tint) : .highlight(tint: tint)
            return Decoration(id: String(a.id), locator: locator, style: style)
        }
        // Redrawn from scratch: an unchanged id would otherwise keep its first (unanchored) position.
        nav?.apply(decorations: [], in: Self.group)
        nav?.apply(decorations: decorations, in: Self.group)
    }

    static func tint(_ color: String) -> UIColor {
        let hex = color.hasPrefix("#") ? color : (allNames[color.lowercased()] ?? "#FACC15")
        return UIColor(hex: hex) ?? UIColor(hex: "#FACC15")!
    }

    private static let contextJS = #"""
    function (items) {
        var out = {};
        items.forEach(function (it) {
            try {
                var parts = window.__boCfi.parse(it.cfi);
                (parts.parent || parts).shift();
                var r = window.__boCfi.toRange(document, parts);
                // The element holding the start of the range. Readium searches for the text inside it only,
                // so the text around the highlight is taken within that element too, to tell repeats apart.
                var el = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement;
                var pre = document.createRange();
                pre.setStart(el, 0);
                pre.setEnd(r.startContainer, r.startOffset);
                var post = document.createRange();
                post.setStart(r.endContainer, r.endOffset);
                post.setEnd(el, el.childNodes.length);
                var path = [];
                var node = el;
                while (node && node !== document.body && node.parentElement) {
                    var i = Array.prototype.indexOf.call(node.parentElement.children, node) + 1;
                    path.unshift(node.tagName.toLowerCase() + ':nth-child(' + i + ')');
                    node = node.parentElement;
                }
                out[it.id] = { b: pre.toString().slice(-40), a: post.toString().slice(0, 40), s: 'body > ' + path.join(' > ') };
            } catch (e) {}
        });
        return JSON.stringify(out);
    }
    """#

    // Skips the elements Readium adds to the page so they don't shift sibling indexes.
    private static let selectionJS = #"""
    function () {
        var s = window.getSelection();
        if (!s || s.rangeCount === 0 || s.isCollapsed) return null;
        var filter = function (n) {
            return n.nodeType === 1 && /^(readium|r2)/i.test(n.id || '') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
        };
        return window.__boCfi.fromRange(s.getRangeAt(0), filter);
    }()
    """#
}

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
