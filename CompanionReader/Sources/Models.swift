import Foundation

struct AuthResponse: Codable { let accessToken: String; let refreshToken: String }
struct BookFileRef: Codable, Hashable {
    let id: Int
    var format: String?
    var role: String?
}
struct StatusInfo: Codable, Hashable { let status: String }
struct Library: Codable, Identifiable, Hashable { let id: Int; let name: String }

struct BookCard: Codable, Identifiable, Hashable {
    let id: Int
    var title: String?
    var authors: [String]
    var seriesName: String?
    var files: [BookFileRef]
    var readingProgress: Double?
    var hasCover: Bool
    var rating: Double?
    var readStatus: StatusInfo?

    enum CodingKeys: String, CodingKey { case id, title, authors, seriesName, files, readingProgress, hasCover, rating, readStatus }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
        files = try c.decodeIfPresent([BookFileRef].self, forKey: .files) ?? []
        readingProgress = try c.decodeIfPresent(Double.self, forKey: .readingProgress)
        hasCover = try c.decodeIfPresent(Bool.self, forKey: .hasCover) ?? false
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        readStatus = try c.decodeIfPresent(StatusInfo.self, forKey: .readStatus)
    }

    func epubFile() -> BookFileRef? {
        files.first { ["epub", "kepub"].contains($0.format?.lowercased() ?? "") }
    }
}

struct BooksPage: Codable { var items: [BookCard]; let total: Int; let page: Int; let size: Int }

struct ReadingSession: Codable {
    let sessionId: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
    var progressDelta: Double?
    var endProgress: Double?
    var sessionType = "read"
    var source = "ios"
}

struct FileProgress: Codable { var percentage: Double = 0 }

struct ScrollerResult: Codable {
    let id: String
    var books: [BookCard]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        books = try c.decodeIfPresent([BookCard].self, forKey: .books) ?? []
    }
    enum CodingKeys: String, CodingKey { case id, books }
}
struct ScrollerBatchResponse: Codable { let items: [ScrollerResult] }

let bookStatuses: [(key: String, label: String)] = [
    ("reading", "Reading"), ("want_to_read", "Want to read"), ("unread", "Unread"),
    ("read", "Read"), ("on_hold", "On hold"), ("abandoned", "Abandoned"),
]

struct Annotation: Codable, Identifiable, Hashable {
    let id: Int
    var cfi: String?
    var text: String
    var color: String
    var style: String
    var note: String?

    init(id: Int, cfi: String?, text: String, color: String, style: String = "highlight", note: String? = nil) {
        self.id = id; self.cfi = cfi; self.text = text; self.color = color; self.style = style; self.note = note
    }
    enum CodingKeys: String, CodingKey { case id, cfi, text, color, style, note }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        cfi = try c.decodeIfPresent(String.self, forKey: .cfi)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "yellow"
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "highlight"
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct SeriesItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var bookCount = 0
    var readCount = 0
    var authors: [String] = []
    var coverBookIds: [Int] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        bookCount = try c.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
        readCount = try c.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        coverBookIds = try c.decodeIfPresent([Int].self, forKey: .coverBookIds) ?? []
    }
    enum CodingKeys: String, CodingKey { case id, name, bookCount, readCount, authors, coverBookIds }
}
struct SeriesPage: Codable { let items: [SeriesItem]; let total: Int }

struct AuthorItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var bookCount = 0
    var coverBookId: Int?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        bookCount = try c.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
        coverBookId = try c.decodeIfPresent(Int.self, forKey: .coverBookId)
    }
    enum CodingKeys: String, CodingKey { case id, name, bookCount, coverBookId }
}
struct AuthorsPage: Codable { let items: [AuthorItem]; let total: Int }

struct SmartScopeItem: Codable, Identifiable, Hashable { let id: Int; let name: String; var bookCount: Int? }
