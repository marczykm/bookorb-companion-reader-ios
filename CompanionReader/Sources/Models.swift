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

// MARK: Achievements

struct AchievementItem: Codable, Identifiable, Hashable {
    var key: String
    var groupKey: String?
    var tier: Int?
    var category: String
    var name: String
    var description: String
    var iconName: String
    var rarity: String
    var threshold: Double?
    var hidden: Bool
    var sortOrder: Int?
    var earned: Bool
    var awardedAt: String?
    var currentProgress: Double?
    var id: String { key }
}

struct AchievementCategory: Codable, Hashable {
    var key: String
    var label: String
    var earnedCount: Int
    var totalCount: Int
    var achievements: [AchievementItem]
}

struct AchievementCatalogue: Codable {
    var categories: [AchievementCategory]
    var totalEarned: Int
    var totalAvailable: Int
}

// MARK: Highlights hub (annotations)

struct HubHighlight: Codable, Identifiable, Hashable {
    var id: Int
    var bookId: Int
    var text: String
    var color: String
    var style: String
    var note: String?
    var chapterTitle: String?
    var origin: String
    var highlightedAt: String?
    var createdAt: String?
    var bookTitle: String?
    var author: String?
    var starredAt: String?

    enum CodingKeys: String, CodingKey {
        case id, bookId, text, color, style, note, chapterTitle, origin, highlightedAt, createdAt, bookTitle, author, starredAt
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bookId = try c.decodeIfPresent(Int.self, forKey: .bookId) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "yellow"
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "highlight"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        chapterTitle = try c.decodeIfPresent(String.self, forKey: .chapterTitle)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? "web"
        highlightedAt = try c.decodeIfPresent(String.self, forKey: .highlightedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        bookTitle = try c.decodeIfPresent(String.self, forKey: .bookTitle)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        starredAt = try c.decodeIfPresent(String.self, forKey: .starredAt)
    }
}

struct HubPage: Codable {
    var items: [HubHighlight]
    var total: Int
    var page: Int
    var pageSize: Int
}

struct HubOverview: Codable {
    struct ColorCount: Codable, Hashable { var color: String; var count: Int }
    var total: Int
    var books: Int
    var withNotes: Int
    var colorBreakdown: [ColorCount]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        books = try c.decodeIfPresent(Int.self, forKey: .books) ?? 0
        withNotes = try c.decodeIfPresent(Int.self, forKey: .withNotes) ?? 0
        colorBreakdown = try c.decodeIfPresent([ColorCount].self, forKey: .colorBreakdown) ?? []
    }
    enum CodingKeys: String, CodingKey { case total, books, withNotes, colorBreakdown }
}

// MARK: Book page

struct BookDetail: Codable {
    struct Author: Codable, Hashable { var id: Int; var name: String }
    struct File: Codable, Hashable {
        var id: Int
        var format: String?
        var role: String?
        var sizeBytes: Int?
        var durationSeconds: Double?
    }
    struct Collection: Codable, Hashable { var id: Int; var name: String }
    struct Status: Codable, Hashable { var status: String; var startedAt: String?; var finishedAt: String? }

    var id: Int
    var title: String?
    var subtitle: String?
    var description: String?
    var isbn10: String?
    var isbn13: String?
    var publisher: String?
    var publishedYear: Int?
    var language: String?
    var pageCount: Int?
    var seriesId: Int?
    var seriesName: String?
    var seriesIndex: String?
    var rating: Double?
    var personalNote: String?
    var libraryName: String?
    var addedAt: String?
    var authors: [Author]
    var genres: [String]
    var files: [File]
    var collections: [Collection]
    var readStatus: Status?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, description, isbn10, isbn13, publisher, publishedYear, language, pageCount, seriesId, seriesName, seriesIndex
        case rating, personalNote, libraryName, addedAt, authors, genres, files, collections, readStatus
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isbn10 = try c.decodeIfPresent(String.self, forKey: .isbn10)
        isbn13 = try c.decodeIfPresent(String.self, forKey: .isbn13)
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        publishedYear = try c.decodeIfPresent(Int.self, forKey: .publishedYear)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        seriesId = try c.decodeIfPresent(Int.self, forKey: .seriesId)
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
        seriesIndex = try? c.decodeIfPresent(String.self, forKey: .seriesIndex)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        personalNote = try c.decodeIfPresent(String.self, forKey: .personalNote)
        libraryName = try c.decodeIfPresent(String.self, forKey: .libraryName)
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt)
        authors = try c.decodeIfPresent([Author].self, forKey: .authors) ?? []
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        files = try c.decodeIfPresent([File].self, forKey: .files) ?? []
        collections = try c.decodeIfPresent([Collection].self, forKey: .collections) ?? []
        readStatus = try c.decodeIfPresent(Status.self, forKey: .readStatus)
    }
}

/// A book in the "More in series", "More by" and "Similar books" rows.
struct RelatedBook: Codable, Identifiable, Hashable {
    var id: Int
    var title: String?
    var authors: [String]
    var seriesIndex: String?
    var hasCover: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        seriesIndex = try? c.decodeIfPresent(String.self, forKey: .seriesIndex)
        hasCover = try c.decodeIfPresent(Bool.self, forKey: .hasCover) ?? true
    }
    enum CodingKeys: String, CodingKey { case id, title, authors, seriesIndex, hasCover }

    /// Enough of a card to open the book's own page.
    var card: BookCard {
        BookCard(id: id, title: title, authors: authors, seriesName: nil, files: [], readingProgress: nil, hasCover: hasCover, rating: nil, readStatus: nil)
    }
}

struct JournalEntry: Codable, Identifiable, Hashable {
    var id: Int
    var clientId: String
    var body: String
    var quote: String?
    var chapterTitle: String?
    var positionPercent: Double?
    var createdAt: String?
}

struct SessionsPage: Codable {
    struct Item: Codable, Identifiable, Hashable {
        var id: Int
        var startedAt: String
        var endedAt: String
        var durationSeconds: Double
        var progressDelta: Double?
        var endProgress: Double?
        var source: String?
    }
    struct Stats: Codable {
        struct Slice: Codable, Hashable { var bucket: String; var totalSeconds: Double; var totalSessions: Int }
        struct Day: Codable, Hashable { var day: String; var totalMinutes: Double }
        struct Progress: Codable, Hashable { var day: String; var endProgress: Double }
        var totalSessions: Int
        var totalSeconds: Double
        var firstSessionAt: String?
        var lastSessionAt: String?
        var bySource: [Slice]
        var dailySummary: [Day]
        var progressSummary: [Progress]
        var paceProgressDelta: Double
        var paceDurationSeconds: Double
        var latestEndProgress: Double?

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            totalSessions = try c.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
            totalSeconds = try c.decodeIfPresent(Double.self, forKey: .totalSeconds) ?? 0
            firstSessionAt = try c.decodeIfPresent(String.self, forKey: .firstSessionAt)
            lastSessionAt = try c.decodeIfPresent(String.self, forKey: .lastSessionAt)
            bySource = try c.decodeIfPresent([Slice].self, forKey: .bySource) ?? []
            dailySummary = try c.decodeIfPresent([Day].self, forKey: .dailySummary) ?? []
            progressSummary = try c.decodeIfPresent([Progress].self, forKey: .progressSummary) ?? []
            paceProgressDelta = try c.decodeIfPresent(Double.self, forKey: .paceProgressDelta) ?? 0
            paceDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .paceDurationSeconds) ?? 0
            latestEndProgress = try c.decodeIfPresent(Double.self, forKey: .latestEndProgress)
        }
        enum CodingKeys: String, CodingKey {
            case totalSessions, totalSeconds, firstSessionAt, lastSessionAt, bySource, dailySummary, progressSummary
            case paceProgressDelta, paceDurationSeconds, latestEndProgress
        }
    }
    var items: [Item]
    var total: Int
    var page: Int
    var pageSize: Int
    var stats: Stats
}

extension BookCard {
    init(id: Int, title: String?, authors: [String], seriesName: String?, files: [BookFileRef], readingProgress: Double?, hasCover: Bool, rating: Double?, readStatus: StatusInfo?) {
        self.id = id; self.title = title; self.authors = authors; self.seriesName = seriesName; self.files = files
        self.readingProgress = readingProgress; self.hasCover = hasCover; self.rating = rating; self.readStatus = readStatus
    }
}
