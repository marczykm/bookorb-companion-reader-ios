import Foundation

/// What the Home tab can show, in the default order.
let homeItems: [(id: String, title: String)] = [
    ("hero", "Continue reading card"), ("clock", "Clock"), ("pet", "Reading companion"),
    ("reading-streak", "Reading streak"), ("reading-goal", "Yearly goal"), ("reading-rhythm", "Reading rhythm"),
    ("year-projection", "On pace for the year"), ("monthly-challenge", "Monthly challenge"),
    ("highlight-of-the-day", "Highlight of the day"), ("long-wait", "Waiting the longest"),
    ("library-overview", "Library overview"),
    ("shelf:continue", "More in progress"), ("shelf:next", "Up next in series"),
    ("shelf:want", "Want to read"), ("shelf:recent", "Recently added"),
]

let widgetTypes = [
    "reading-streak", "reading-goal", "reading-rhythm", "year-projection",
    "monthly-challenge", "highlight-of-the-day", "library-overview", "long-wait",
]

let itemSizes = ["s", "m", "l"]

/// Cards that can sit two to a row when small. Hero and shelves scale their covers instead.
let halfWidthItems: Set<String> = Set(homeItems.map(\.id).filter { $0 != "hero" && !$0.hasPrefix("shelf:") })

/// The order, visibility and size of Home items, kept on the device.
final class HomeLayout: ObservableObject {
    private let d = UserDefaults.standard
    private let defaults = homeItems.map(\.id)
    /// Everything starts small except the continue-reading card and its shelf.
    private let mediumByDefault: Set<String> = ["hero", "shelf:continue"]

    @Published private(set) var order: [String] = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var sizes: [String: String] = [:]

    init() {
        let saved = (d.string(forKey: "home_order") ?? "").split(separator: ",").map(String.init).filter { defaults.contains($0) }
        // Items added in later versions go at the end of the saved order.
        order = saved + defaults.filter { !saved.contains($0) }
        hidden = Set((d.string(forKey: "home_hidden") ?? "").split(separator: ",").map(String.init))
        for e in (d.string(forKey: "home_sizes") ?? "").split(separator: ",") {
            let kv = e.split(separator: "=").map(String.init)
            if kv.count == 2, itemSizes.contains(kv[1]) { sizes[kv[0]] = kv[1] }
        }
    }

    func sizeOf(_ id: String) -> String { sizes[id] ?? (mediumByDefault.contains(id) ? "m" : "s") }

    func cycleSize(_ id: String) {
        sizes[id] = itemSizes[(itemSizes.firstIndex(of: sizeOf(id))! + 1) % itemSizes.count]
        save()
    }

    var visible: [String] { order.filter { !hidden.contains($0) } }

    /// Visible items grouped into rows: neighbouring small cards share one.
    var rows: [[String]] {
        var out: [[String]] = []
        for id in visible {
            if halfWidthItems.contains(id), sizeOf(id) == "s", let last = out.last, last.count == 1,
               halfWidthItems.contains(last[0]), sizeOf(last[0]) == "s" {
                out[out.count - 1].append(id)
            } else {
                out.append([id])
            }
        }
        return out
    }

    func move(_ id: String, _ delta: Int) {
        guard let from = order.firstIndex(of: id) else { return }
        let to = min(max(from + delta, 0), order.count - 1)
        guard from != to else { return }
        order.insert(order.remove(at: from), at: to)
        save()
    }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        save()
    }

    func reset() { order = defaults; hidden = []; sizes = [:]; save() }

    private func save() {
        d.set(sizes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","), forKey: "home_sizes")
        d.set(order.joined(separator: ","), forKey: "home_order")
        d.set(hidden.sorted().joined(separator: ","), forKey: "home_hidden")
    }
}
