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
    /// The selected reading companion and what it is doing right now.
    struct Pet: Codable {
        var name: String
        var pose: String
        var line1: String
        var line2: String
    }
    var book: Book?
    var pet: Pet?
    var streak = 0
    var longestStreak = 0
    var goalDone = 0
    var goalTotal = 0
    var goalYear = 0
    var updatedAt = Date()
}

enum WidgetStore {
    static let defaultGroup = "group.app.bookorb.companion.reader"
    /// AltStore rewrites the App Group when it re-signs the app and lists the real one under ALTAppGroups.
    static var group: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? defaultGroup
    }
    static let kind = (continueReading: "ContinueReadingWidget", stats: "ReadingStatsWidget", pet: "PetWidget")

    private static var dir: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    private static var snapshotURL: URL? { dir?.appendingPathComponent("widget-snapshot.json") }
    private static var coverURL: URL? { dir?.appendingPathComponent("widget-cover.jpg") }
    private static var petURL: URL? { dir?.appendingPathComponent("widget-pet.png") }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot, cover: Data?, pet: Data?) {
        guard let url = snapshotURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        if let coverURL {
            if let cover { try? cover.write(to: coverURL, options: .atomic) } else { try? FileManager.default.removeItem(at: coverURL) }
        }
        if let petURL {
            if let pet { try? pet.write(to: petURL, options: .atomic) } else { try? FileManager.default.removeItem(at: petURL) }
        }
    }

    static func coverData() -> Data? { coverURL.flatMap { try? Data(contentsOf: $0) } }
    static func petData() -> Data? { petURL.flatMap { try? Data(contentsOf: $0) } }
}
