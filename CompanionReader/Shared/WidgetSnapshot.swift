import Foundation

/// What the Home Screen widgets show. The app writes it into the shared App Group; the widgets only read it,
/// so they never need the network or the sign-in tokens.
struct WidgetSnapshot: Codable {
    struct Book: Codable {
        var id: Int
        var title: String
        var authors: String
        /// Percent read, 0 to 100.
        var progress: Double?
    }
    var book: Book?
    var streak = 0
    var longestStreak = 0
    var goalDone = 0
    var goalTotal = 0
    var goalYear = 0
    var updatedAt = Date()
}

enum WidgetStore {
    static let group = "group.app.bookorb.companion.reader"
    static let kind = (continueReading: "ContinueReadingWidget", stats: "ReadingStatsWidget")

    private static var dir: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    private static var snapshotURL: URL? { dir?.appendingPathComponent("widget-snapshot.json") }
    private static var coverURL: URL? { dir?.appendingPathComponent("widget-cover.jpg") }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot, cover: Data?) {
        guard let url = snapshotURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        if let coverURL {
            if let cover { try? cover.write(to: coverURL, options: .atomic) } else { try? FileManager.default.removeItem(at: coverURL) }
        }
    }

    static func coverData() -> Data? { coverURL.flatMap { try? Data(contentsOf: $0) } }
}
