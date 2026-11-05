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

// MARK: Reading history

/// One finished read: a completed, skimmed or abandoned attempt.
struct HistoryItem: Codable, Identifiable, Hashable {
    let id: Int
    var bookId: Int?
    var title: String?
    var authors: [String]
    var seriesName: String?
    var seriesIndex: String?
    var format: String?
    var endedOn: String?
    var outcome: String
    var readNumber: Int?
    var progressPercent: Double?
    var seconds: Int
    var rating: Double?
    var highlightCount: Int
    var journalCount: Int

    enum CodingKeys: String, CodingKey {
        case id, bookId, title, authors, seriesName, seriesIndex, format, endedOn, outcome, readNumber
        case progressPercent, seconds, rating, highlightCount, journalCount
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bookId = try c.decodeIfPresent(Int.self, forKey: .bookId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
        seriesIndex = try c.decodeIfPresent(String.self, forKey: .seriesIndex)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        endedOn = try c.decodeIfPresent(String.self, forKey: .endedOn)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? "completed"
        readNumber = try c.decodeIfPresent(Int.self, forKey: .readNumber)
        progressPercent = try c.decodeIfPresent(Double.self, forKey: .progressPercent)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        highlightCount = try c.decodeIfPresent(Int.self, forKey: .highlightCount) ?? 0
        journalCount = try c.decodeIfPresent(Int.self, forKey: .journalCount) ?? 0
    }
}

/// A month of the list, in order, so section headers can be laid out before the rows load.
struct HistoryMonth: Codable, Hashable {
    var month: String   // YYYY-MM or "undated"
    var reads: Int
    var seconds: Int
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        reads = try c.decodeIfPresent(Int.self, forKey: .reads) ?? 0
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
    }
    enum CodingKeys: String, CodingKey { case month, reads, seconds }
}

struct HistoryPage: Codable {
    var items: [HistoryItem]
    var offset: Int
    var total: Int
    var months: [HistoryMonth]?
}

struct HistorySummary: Codable {
    struct YearCount: Codable, Hashable { var year: Int; var reads: Int }
    struct MonthCount: Codable, Hashable { var month: Int; var reads: Int }
    struct Goal: Codable, Hashable { var target: Int; var reached: Int; var metOn: String? }
    var years: [YearCount]
    var reads: Int
    var books: Int
    var rereads: Int
    var months: [MonthCount]
    var goal: Goal?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        years = try c.decodeIfPresent([YearCount].self, forKey: .years) ?? []
        reads = try c.decodeIfPresent(Int.self, forKey: .reads) ?? 0
        books = try c.decodeIfPresent(Int.self, forKey: .books) ?? 0
        rereads = try c.decodeIfPresent(Int.self, forKey: .rereads) ?? 0
        months = try c.decodeIfPresent([MonthCount].self, forKey: .months) ?? []
        goal = try c.decodeIfPresent(Goal.self, forKey: .goal)
    }
    enum CodingKeys: String, CodingKey { case years, reads, books, rereads, months, goal }
}

// MARK: Activity (user-statistics/activity-overview)

struct ActivityDuration: Codable, Hashable {
    var totalSeconds: Double
    var readingSeconds: Double
    var listeningSeconds: Double
}

struct ActivityDay: Codable, Hashable {
    var day: String            // yyyy-MM-dd
    var totalSeconds: Double
    var readingSeconds: Double
    var listeningSeconds: Double
    var sessionsCount: Int
}

struct ActivityCalendar: Codable {
    var year: Int
    var availableYears: [Int]
    var days: [ActivityDay]
}

struct ActivityOverview: Codable {
    struct Snapshot: Codable {
        var today: ActivityDuration
        var lastSevenDays: ActivityDuration
        var previousSevenDays: ActivityDuration
        var currentStreak: Int
        var longestStreak: Int
        var completedBooksYtd: Int
    }
    struct Daily: Codable { var days: [ActivityDay] }
    struct Goal: Codable {
        struct Point: Codable, Hashable { var month: Int; var actualCumulative: Double; var targetCumulative: Double? }
        var year: Int
        var goalBooks: Int?
        var completedBooks: Int
        var projectedBooks: Double
        var status: String?
        var points: [Point]
    }
    struct Rhythm: Codable {
        struct Weekday: Codable, Hashable { var dayOfWeek: Int; var averageSeconds: Double }
        struct Hour: Codable, Hashable { var hour: Int; var totalSeconds: Double }
        var weekdays: [Weekday]
        var hours: [Hour]
        var favoriteDayOfWeek: Int?
        var peakHour: Int?
    }
    struct Completion: Codable {
        struct Month: Codable, Hashable { var year: Int; var month: Int; var count: Int }
        var months: [Month]
    }
    struct Sources: Codable {
        struct Slice: Codable, Hashable { var bucket: String; var totalSeconds: Double }
        var totals: ActivityDuration
        var slices: [Slice]
    }
    struct Pace: Codable {
        var eligibleSessions: Int
        var medianDurationSeconds: Double?
        var medianProgressDelta: Double?
    }
    var snapshot: Snapshot
    var dailyActivity: Daily
    var calendar: ActivityCalendar
    var goal: Goal
    var rhythm: Rhythm
    var completion: Completion
    var sources: Sources
    var pace: Pace
}
