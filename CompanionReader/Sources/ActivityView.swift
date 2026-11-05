import SwiftUI
import Charts

private let readingColor = Color(red: 0.42, green: 0.62, blue: 0.85)
private let listeningColor = Color(red: 0.80, green: 0.50, blue: 0.35)

private func isoDay(_ s: String) -> Date? {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
    return f.date(from: String(s.prefix(10)))
}

private func long(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s) secs" }
    let h = s / 3600, m = (s % 3600) / 60
    if h == 0 { return "\(m) min" }
    let hours = h == 1 ? "1 hr" : "\(h) hrs"
    return m == 0 ? hours : "\(hours), \(m) min"
}

private func short(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    let h = s / 3600, m = (s % 3600) / 60
    return h == 0 ? "\(m)m" : "\(h)h \(m)m"
}

/// The reading activity of the user: snapshot, daily bars, goal, calendar, rhythm, completions, sources and pace.
struct ActivityView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var overview: ActivityOverview?
    @State private var error: String?
    @State private var loading = false
    @State private var section = 0   // 0 = Insights, 1 = Achievements

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            Picker("Section", selection: $section) { Text("Insights").tag(0); Text("Achievements").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            if section == 1 { AchievementsView() } else {
            ScrollView {
                if let o = overview {
                    LazyVStack(spacing: 16) {
                        SnapshotCard(o: o)
                        DailyActivityCard(days: o.dailyActivity.days)
                        GoalCard(goal: o.goal)
                        CalendarCard(initial: o.calendar)
                        RhythmCard(r: o.rhythm)
                        CompletionCard(months: o.completion.months)
                        SourcesCard(s: o.sources)
                        PaceCard(p: o.pace)
                    }.padding()
                }
            }
            .refreshable { await load() }
            .overlay {
                if loading && overview == nil { ProgressView() }
                else if overview == nil { Text(error ?? "No activity yet").foregroundStyle(.secondary).padding() }
            }
            }
        }
        .navigationTitle("Activity")
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { overview = try await api.activityOverview() }
        catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MediaBar: View {
    let totals: ActivityDuration
    var body: some View {
        let total = max(totals.readingSeconds + totals.listeningSeconds, 1)
        VStack(spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(readingColor).frame(width: max(g.size.width * totals.readingSeconds / total, totals.readingSeconds > 0 ? 6 : 0))
                    Capsule().fill(listeningColor).frame(width: g.size.width * totals.listeningSeconds / total)
                    Spacer(minLength: 0)
                }
            }.frame(height: 10)
            HStack {
                Label("Reading \(long(totals.readingSeconds))", systemImage: "book")
                Spacer()
                Label("Listening \(long(totals.listeningSeconds))", systemImage: "headphones")
            }.font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: Weekly snapshot

private struct SnapshotCard: View {
    let o: ActivityOverview
    var body: some View {
        let s = o.snapshot
        Card(title: "Weekly Snapshot", icon: "chart.line.uptrend.xyaxis") {
            HStack {
                stat(short(s.today.totalSeconds), "Today")
                stat(short(s.lastSevenDays.totalSeconds), "Last 7 days")
                stat("\(s.currentStreak)", "Day streak")
            }
            if let change = change { Text(change).font(.headline) }
            MediaBar(totals: s.lastSevenDays)
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) { Text(v).font(.title.weight(.semibold)); Text(l).font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var change: String? {
        let now = o.snapshot.lastSevenDays.totalSeconds, before = o.snapshot.previousSevenDays.totalSeconds
        guard before > 0 else { return nil }
        let pct = Int(((now - before) / before * 100).rounded())
        return pct >= 0 ? "Up \(pct)% vs last week" : "Down \(-pct)% vs last week"
    }
}

// MARK: Daily activity

private struct DailyActivityCard: View {
    let days: [ActivityDay]
    @State private var range = 0   // 0 = 7D, 1 = 30D, 2 = 12W
    @State private var selected: Date?

    private struct Bar: Identifiable { let id: Date; let reading: Double; let listening: Double; let sessions: Int }

    private var bars: [Bar] {
        let sorted = days.compactMap { d in isoDay(d.day).map { ($0, d) } }.sorted { $0.0 < $1.0 }
        if range == 2 {
            let cal = Calendar.current
            var weeks: [Date: (Double, Double, Int)] = [:]
            for (date, d) in sorted.suffix(84) {
                let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                let cur = weeks[start] ?? (0, 0, 0)
                weeks[start] = (cur.0 + d.readingSeconds, cur.1 + d.listeningSeconds, cur.2 + d.sessionsCount)
            }
            return weeks.keys.sorted().map { Bar(id: $0, reading: weeks[$0]!.0, listening: weeks[$0]!.1, sessions: weeks[$0]!.2) }
        }
        return sorted.suffix(range == 0 ? 7 : 30).map { Bar(id: $0.0, reading: $0.1.readingSeconds, listening: $0.1.listeningSeconds, sessions: $0.1.sessionsCount) }
    }

    var body: some View {
        let data = bars
        let total = data.reduce(0) { $0 + $1.reading + $1.listening }
        let active = data.filter { $0.reading + $0.listening > 0 }.count
        Card(title: "Daily Activity", icon: "chart.bar") {
            Picker("Range", selection: $range) { Text("7D").tag(0); Text("30D").tag(1); Text("12W").tag(2) }.pickerStyle(.segmented)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) { Text(long(total)).font(.title2.weight(.semibold)); Text("Total time").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(active > 0 ? long(total / Double(active)) : "–").font(.title3.weight(.semibold))
                    Text(range == 2 ? "Average per active week" : "Average per active day").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(data) { b in
                    BarMark(x: .value("Day", b.id, unit: range == 2 ? .weekOfYear : .day), y: .value("Hours", b.reading / 3600)).foregroundStyle(readingColor)
                    BarMark(x: .value("Day", b.id, unit: range == 2 ? .weekOfYear : .day), y: .value("Hours", b.listening / 3600)).foregroundStyle(listeningColor)
                }
            }
            .chartYAxisLabel("hrs")
            .chartXSelection(value: $selected)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: range == 0 ? 7 : 5)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
            .frame(height: 180)
            HStack(spacing: 14) {
                Label("Reading", systemImage: "circle.fill").foregroundStyle(readingColor)
                Label("Listening", systemImage: "circle.fill").foregroundStyle(listeningColor)
            }.font(.caption).labelStyle(DotLabel())
            if let detail = detail(in: data) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(detail.title).font(.headline); Spacer(); Text(long(detail.total)).font(.headline) }
                    Text("\(detail.sessions) session\(detail.sessions == 1 ? "" : "s"), Reading \(long(detail.reading)), Listening \(long(detail.listening))")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func detail(in data: [Bar]) -> (title: String, total: Double, reading: Double, listening: Double, sessions: Int)? {
        let cal = Calendar.current
        let bar = selected.flatMap { sel in data.first { cal.isDate($0.id, equalTo: sel, toGranularity: range == 2 ? .weekOfYear : .day) } } ?? data.last
        guard let bar else { return nil }
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return ((range == 2 ? "Week of " : "") + f.string(from: bar.id), bar.reading + bar.listening, bar.reading, bar.listening, bar.sessions)
    }
}

private struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 8)); configuration.title.foregroundStyle(.secondary) }
    }
}

// MARK: Annual goal

private struct GoalCard: View {
    let goal: ActivityOverview.Goal
    var body: some View {
        Card(title: "Annual Goal", icon: "scope") {
            if let target = goal.goalBooks, target > 0 {
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 12)
                        Circle().trim(from: 0, to: min(Double(goal.completedBooks) / Double(target), 1)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(goal.completedBooks)/\(target)").font(.title3.weight(.semibold))
                    }.frame(width: 100, height: 100)
                    VStack(alignment: .leading, spacing: 4) {
                        if let status { Label(status.0, systemImage: status.1).font(.title3.weight(.medium)).foregroundStyle(status.2) }
                        Text("Projected: \(String(format: "%.1f", goal.projectedBooks)) books").foregroundStyle(.secondary)
                    }
                }
                Chart {
                    ForEach(goal.points, id: \.month) { p in
                        LineMark(x: .value("Month", p.month), y: .value("Books", p.actualCumulative), series: .value("S", "actual")).foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Month", p.month), y: .value("Books", p.actualCumulative)).foregroundStyle(Color.accentColor)
                        if let t = p.targetCumulative {
                            LineMark(x: .value("Month", p.month), y: .value("Books", t), series: .value("S", "target")).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }.chartXAxis(.hidden).frame(height: 130)
            } else {
                Text("\(goal.completedBooks) read in \(String(goal.year))").font(.title3.weight(.semibold))
                Text("No goal set").foregroundStyle(.secondary)
            }
        }
    }
    private var status: (String, String, Color)? {
        switch goal.status {
        case "ahead": return ("Ahead", "arrow.up.right.circle.fill", .green)
        case "on_pace": return ("On pace", "equal.circle.fill", .blue)
        case "behind": return ("Behind", "arrow.down.right.circle.fill", .orange)
        default: return nil
        }
    }
}

// MARK: Calendar

private struct CalendarCard: View {
    @EnvironmentObject var api: ServerAPI
    let initial: ActivityCalendar
    @State private var calendar: ActivityCalendar?
    @State private var month = Calendar.current.component(.month, from: Date())

    var body: some View {
        let cal = calendar ?? initial
        Card(title: "Reading Calendar", icon: "calendar") {
            HStack {
                Text("Consistency by day").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(cal.availableYears.sorted(by: >), id: \.self) { y in Button(String(y)) { Task { await switchYear(y) } } }
                } label: { Label(String(cal.year), systemImage: "chevron.up.chevron.down").labelStyle(.titleAndIcon) }
            }
            HStack {
                Button { month = max(month - 1, 1) } label: { Image(systemName: "chevron.left") }.disabled(month <= 1)
                Spacer()
                Text(monthTitle(cal.year)).font(.headline)
                Spacer()
                Button { month = min(month + 1, 12) } label: { Image(systemName: "chevron.right") }.disabled(month >= 12)
            }.buttonStyle(.borderless)
            grid(cal)
            legend
        }
    }

    private func monthTitle(_ year: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let d = Calendar.current.date(from: c) else { return "" }
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: d).capitalized
    }

    private func grid(_ cal: ActivityCalendar) -> some View {
        var c = DateComponents(); c.year = cal.year; c.month = month; c.day = 1
        let c0 = Calendar.current
        let first = c0.date(from: c) ?? Date()
        let count = c0.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = c0.component(.weekday, from: first) - 1
        let byDay = Dictionary(cal.days.map { ($0.day.prefix(10).description, $0.totalSeconds) }, uniquingKeysWith: { a, _ in a })
        let cells: [Int?] = Array(repeating: nil, count: offset) + (1...count).map { Optional($0) }
        return VStack(spacing: 6) {
            HStack { ForEach(Array("SMTWTFS".enumerated()), id: \.offset) { _, ch in Text(String(ch)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let key = String(format: "%04d-%02d-%02d", cal.year, month, day)
                        Text("\(day)").font(.callout).frame(maxWidth: .infinity).frame(height: 34)
                            .background(shade(byDay[key] ?? 0), in: RoundedRectangle(cornerRadius: 8))
                    } else { Color.clear.frame(height: 34) }
                }
            }
        }
    }

    private func shade(_ seconds: Double) -> Color {
        switch seconds / 60 {
        case ..<0.5: return Color.secondary.opacity(0.15)
        case ..<15.5: return Color.accentColor.opacity(0.25)
        case ..<30.5: return Color.accentColor.opacity(0.45)
        case ..<60.5: return Color.accentColor.opacity(0.7)
        default: return Color.accentColor
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily time").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach([("No activity", 0.0), ("1 to 15 minutes", 10 * 60.0), ("16 to 30 minutes", 20 * 60.0), ("31 to 60 minutes", 45 * 60.0), ("More than 60 minutes", 90 * 60.0)], id: \.0) { item in
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(shade(item.1)).frame(width: 14, height: 14); Text(item.0).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func switchYear(_ year: Int) async {
        if let c = try? await api.activityCalendar(year: year) { calendar = c; month = year == Calendar.current.component(.year, from: Date()) ? Calendar.current.component(.month, from: Date()) : 1 }
    }
}

// MARK: Rhythm

private struct RhythmCard: View {
    let r: ActivityOverview.Rhythm
    @State private var hours = false
    private let dayNames = Calendar.current.shortWeekdaySymbols
    private let fullDays = Calendar.current.weekdaySymbols

    var body: some View {
        Card(title: "Reading Rhythm", icon: "arrow.triangle.2.circlepath") {
            Picker("Rhythm", selection: $hours) { Text("Days").tag(false); Text("Hours").tag(true) }.pickerStyle(.segmented)
            Chart {
                if hours {
                    ForEach(r.hours, id: \.hour) { h in BarMark(x: .value("Hour", h.hour), y: .value("Minutes", h.totalSeconds / 60)).foregroundStyle(.purple.gradient) }
                } else {
                    ForEach(r.weekdays, id: \.dayOfWeek) { d in BarMark(x: .value("Day", dayNames[min(max(d.dayOfWeek, 0), 6)]), y: .value("Minutes", d.averageSeconds / 60)).foregroundStyle(.purple.gradient) }
                }
            }.chartYAxisLabel("min").frame(height: 180)
            if let day = r.favoriteDayOfWeek {
                Text("\(fullDays[min(max(day, 0), 6)])\(r.peakHour.map { " around \($0)" } ?? "") is your strongest reading window.").font(.headline)
            }
        }
    }
}

// MARK: Completion

private struct CompletionCard: View {
    let months: [ActivityOverview.Completion.Month]
    @State private var range = 0   // 0 = 1Y, 1 = 5Y, 2 = All

    private struct Bar: Identifiable { let id: String; let count: Int }

    private var bars: [Bar] {
        let now = Date(), cal = Calendar.current
        if range == 0 {
            return (0..<12).reversed().compactMap { back -> Bar? in
                guard let d = cal.date(byAdding: .month, value: -back, to: now) else { return nil }
                let y = cal.component(.year, from: d), m = cal.component(.month, from: d)
                let f = DateFormatter(); f.dateFormat = "MMM"
                return Bar(id: "\(y)-\(String(format: "%02d", m)) \(f.string(from: d))", count: months.first { $0.year == y && $0.month == m }?.count ?? 0)
            }
        }
        let year = cal.component(.year, from: now)
        let years = Set(months.map(\.year)).union([year])
        let shown = range == 1 ? (year - 4...year).map { $0 } : Array((years.min() ?? year)...year)
        return shown.map { y in Bar(id: String(y), count: months.filter { $0.year == y }.reduce(0) { $0 + $1.count }) }
    }

    var body: some View {
        let data = bars
        Card(title: "Completion", icon: "checkmark.circle") {
            Picker("Range", selection: $range) { Text("1Y").tag(0); Text("5Y").tag(1); Text("All").tag(2) }.pickerStyle(.segmented)
            HStack {
                Text("Completed").font(.title3.weight(.semibold))
                Spacer()
                if let best = data.max(by: { $0.count < $1.count }), best.count > 0 { Text("Best: \(label(best.id)) · \(best.count)").font(.footnote).foregroundStyle(.secondary) }
            }
            Chart(data) { BarMark(x: .value("Period", label($0.id)), y: .value("Completed", $0.count)).foregroundStyle(Color.green.opacity(0.7)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }.frame(height: 150)
        }
    }
    private func label(_ id: String) -> String { id.split(separator: " ").count > 1 ? String(id.split(separator: " ")[1]) : id }
}

// MARK: Sources

private let sourceInfo: [String: (String, Color)] = [
    "bookorbit": ("BookOrbit", Color(red: 0.45, green: 0.62, blue: 0.85)),
    "ios": ("iOS app", Color(red: 0.45, green: 0.90, blue: 0.50)),
    "watchos": ("Apple Watch", .teal),
    "android": ("Android app", Color(red: 0.90, green: 0.35, blue: 0.95)),
    "koreader": ("KOReader", Color(red: 0.97, green: 0.70, blue: 0.35)),
    "kobo": ("Kobo", .brown),
]

private struct SourcesCard: View {
    let s: ActivityOverview.Sources
    var body: some View {
        let slices = s.slices.filter { $0.totalSeconds > 0 }
        let total = max(slices.reduce(0) { $0 + $1.totalSeconds }, 1)
        Card(title: "Where You Read", icon: "square.stack.3d.up") {
            GeometryReader { g in
                // Slices share the width; tiny ones get a minimum, and everything is scaled back to fit.
                let avail = g.size.width - 2 * CGFloat(max(slices.count - 1, 0))
                let raw = slices.map { max(avail * $0.totalSeconds / total, 6) }
                let scale = avail / max(raw.reduce(0, +), 1)
                HStack(spacing: 2) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, sl in
                        Capsule().fill(sourceInfo[sl.bucket]?.1 ?? .gray).frame(width: raw[i] * scale)
                    }
                }
            }.frame(height: 16)
            ForEach(slices, id: \.bucket) { sl in
                HStack {
                    Circle().fill(sourceInfo[sl.bucket]?.1 ?? .gray).frame(width: 14, height: 14)
                    Text(sourceInfo[sl.bucket]?.0 ?? sl.bucket).foregroundStyle(sourceInfo[sl.bucket]?.1 ?? .primary)
                    Spacer()
                    Text(long(sl.totalSeconds)).foregroundStyle(.secondary)
                    Text("\(Int((sl.totalSeconds / total * 100).rounded()))%").foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                }
            }
            Divider()
            MediaBar(totals: s.totals)
        }
    }
}

// MARK: Pace

private struct PaceCard: View {
    let p: ActivityOverview.Pace
    var body: some View {
        Card(title: "Reading Pace", icon: "gauge.with.dots.needle.33percent") {
            HStack {
                VStack(alignment: .leading) { Text(p.medianDurationSeconds.map { short($0) } ?? "–").font(.title.weight(.semibold)); Text("Typical session").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) { Text(p.medianProgressDelta.map { "\(Int($0.rounded()))%" } ?? "–").font(.title.weight(.semibold)); Text("Median progress").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Based on \(p.eligibleSessions) eligible sessions").foregroundStyle(.secondary)
        }
    }
}
