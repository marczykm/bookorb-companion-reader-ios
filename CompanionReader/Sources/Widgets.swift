import SwiftUI

typealias WidgetData = [String: [String: Any]]

private extension Dictionary where Key == String, Value == Any {
    func int(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue }
    func num(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue }
    func str(_ k: String) -> String? { self[k] as? String }
    func bool(_ k: String) -> Bool? { (self[k] as? NSNumber)?.boolValue }
}

/// One Home widget by id; draws nothing when the server had no data for it. "s" is half width, "l" shows more.
struct WidgetItemView: View {
    let id: String
    let data: WidgetData
    let hasBook: Bool
    let size: String

    var body: some View {
        switch id {
        case "clock": ClockCard(size: size)
        case "pet": PetCard(data: data, hasBook: hasBook, size: size)
        case "reading-streak": if let d = data[id] { StreakCard(d: d, size: size) }
        case "reading-goal": if let d = data[id] { GoalCard(d: d) }
        case "reading-rhythm": if let d = data[id] { RhythmCard(d: d, size: size) }
        case "year-projection": if let d = data[id] { ProjectionCard(d: d, size: size) }
        case "monthly-challenge": if let d = data[id] { ChallengeCard(d: d, size: size) }
        case "highlight-of-the-day": if let d = data[id] { HighlightCard(d: d, size: size) }
        case "long-wait": if let d = data[id] { LongWaitCard(d: d) }
        case "library-overview": if let d = data[id] { OverviewCard(d: d, size: size) }
        default: EmptyView()
        }
    }
}

private struct WidgetCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The time and date, in the phone's own 12 or 24 hour format. It needs nothing from the server.
private struct ClockCard: View {
    let size: String
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            WidgetCard(title: "Clock") {
                Text(ctx.date, style: .time).font(size == "s" ? .title : size == "l" ? .system(size: 64, weight: .light) : .system(size: 44, weight: .light))
                Text(ctx.date.formatted(date: size == "s" ? .abbreviated : .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StreakCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        let current = d.int("currentStreak") ?? 0
        let days = (d["lastSevenDays"] as? [Any])?.map { ($0 as? NSNumber)?.boolValue == true } ?? []
        WidgetCard(title: "Reading streak") {
            Text("\(current) day\(current == 1 ? "" : "s")").font(.title2.weight(.semibold))
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, read in
                    Circle().fill(read ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 10, height: 10)
                }
            }
            if size != "s", let longest = d.int("longestStreak") { Text("Longest: \(longest)").font(.footnote) }
        }
    }
}

private struct GoalCard: View {
    let d: [String: Any]
    var body: some View {
        let done = d.int("completedBooks") ?? 0
        WidgetCard(title: "\(d.int("year").map(String.init) ?? "") goal") {
            if let goal = d.int("goalBooks"), goal > 0 {
                Text("\(done) / \(goal)").font(.title2.weight(.semibold))
                ProgressView(value: min(Double(done) / Double(goal), 1))
                Text("books").font(.footnote)
            } else {
                Text("\(done) read").font(.title2.weight(.semibold))
                Text("No goal set").font(.footnote)
            }
        }
    }
}

private struct RhythmCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        let seconds = (d["days"] as? [[String: Any]])?.compactMap { $0.num("readingSeconds") } ?? []
        let maxS = max(seconds.max() ?? 0, 1)
        let height: CGFloat = size == "s" ? 40 : size == "l" ? 96 : 48
        let avgMin = Int((d.num("avgSecondsPerDay") ?? 0) / 60)
        WidgetCard(title: "Reading rhythm") {
            if !seconds.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(seconds.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 2).fill(s > 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: max(height * CGFloat(s / maxS), height * 0.04))
                    }
                }.frame(height: height, alignment: .bottom)
            }
            Text(size == "s" ? "\(avgMin) min/day" : "\(avgMin) min/day on average · \(d.int("consistencyPercent") ?? 0)% of days read").font(.footnote)
        }
    }
}

private struct ProjectionCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        let trend = ["up": "trending up", "down": "trending down"][d.str("trend") ?? ""] ?? "steady"
        WidgetCard(title: "On pace for \(Calendar.current.component(.year, from: Date()))") {
            Text("\(d.int("projectedBooks") ?? 0) books").font(.title2.weight(.semibold))
            if size != "s" { Text("\(d.int("booksCompletedYtd") ?? 0) done so far · about \(d.int("projectedHours") ?? 0) h of reading · \(trend)").font(.footnote) }
        }
    }
}

private struct ChallengeCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        let progress = d.num("progress") ?? 0
        let target = max(d.num("target") ?? 1, 1)
        WidgetCard(title: "Monthly challenge") {
            Text(d.str("title") ?? "").font(.headline)
            if size != "s", let desc = d.str("description") { Text(desc).font(.footnote) }
            ProgressView(value: min(progress / target, 1))
            Text(d.bool("completed") == true ? "Completed" : "\(Int(progress)) / \(Int(target))").font(.caption2)
        }
    }
}

private struct HighlightCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        WidgetCard(title: "Highlight of the day") {
            Text("“\(d.str("text") ?? "")”").font(.subheadline).lineLimit(size == "s" ? 3 : size == "l" ? 14 : 6)
            if let t = d.str("bookTitle") { Text(t).font(.caption.weight(.medium)).foregroundStyle(.tint) }
        }
    }
}

private struct LongWaitCard: View {
    let d: [String: Any]
    var body: some View {
        WidgetCard(title: "Waiting the longest") {
            Text(d.str("title") ?? "Untitled").font(.headline).lineLimit(2)
            Text("On your shelf for \(d.int("waitingDays") ?? 0) days").font(.footnote)
        }
    }
}

private struct OverviewCard: View {
    let d: [String: Any]; let size: String
    var body: some View {
        let stats = [("Books", "totalBooks"), ("Authors", "totalAuthors"), ("Series", "totalSeries"), ("This year", "booksAddedThisYear")]
        WidgetCard(title: "Library") {
            HStack {
                ForEach(Array((size == "s" ? Array(stats.prefix(2)) : stats).enumerated()), id: \.offset) { _, s in
                    VStack { Text("\(d.int(s.1) ?? 0)").font(.title3.weight(.semibold)); Text(s.0).font(.caption2) }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}
