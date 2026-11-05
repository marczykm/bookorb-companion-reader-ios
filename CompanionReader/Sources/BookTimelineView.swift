import SwiftUI
import Charts

private let sourceLabels: [String: String] = [
    "bookorbit": "Web reader", "web": "Web reader", "manual": "Added by hand", "ios": "iOS app", "watchos": "Apple Watch",
    "android": "Android app", "koreader": "KOReader", "kobo": "Kobo",
]
private let sourceIcons: [String: String] = [
    "bookorbit": "globe", "web": "globe", "manual": "hand.point.up", "ios": "iphone", "watchos": "applewatch",
    "android": "smartphone", "koreader": "book.closed", "kobo": "book.closed",
]

/// Every reading session of one book: a summary, a chart and the sessions grouped by day.
struct BookTimelineView: View {
    @EnvironmentObject var api: ServerAPI
    let book: BookCard
    let title: String
    let sessions: SessionsPage
    @State private var device: String?        // nil = all devices
    @State private var openRuns: Set<String> = []

    private var items: [SessionsPage.Item] {
        sessions.items.filter { device == nil || bucket($0.source) == device }.sorted { $0.startedAt > $1.startedAt }
    }

    private func bucket(_ source: String?) -> String { (source == nil || source == "web" || source == "manual") ? "bookorbit" : source! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summary
                deviceFilter
                ForEach(days, id: \.day) { day in dayBlock(day) }
                startedRow
                Text("Sessions are recorded on every device you read or listen on, including Kobo and KOReader.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12)
            }.padding(.horizontal).padding(.bottom, 24)
        }
        .navigationTitle("Timeline").navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header and summary

    private var header: some View {
        HStack(spacing: 14) {
            CoverView(book: book).frame(width: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .semibold, design: .serif)).lineLimit(2)
                if let last = BookPage.date(sessions.stats.lastSessionAt) { Text("Last read \(BookPage.full.string(from: last))").foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }

    private var summary: some View {
        let st = sessions.stats
        let left = BookPage.secondsLeft(st, progress: st.latestEndProgress)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("THIS READ · SINCE \(sinceText)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(st.totalSessions) sessions").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                bigStat(hm(st.totalSeconds), "this read")
                Divider().frame(height: 44)
                bigStat(left.map { "≈\(hm($0))" } ?? "–", "left at your pace")
                Divider().frame(height: 44)
                bigStat(finish(left).0, finish(left).1)
            }
            chart
            HStack(spacing: 16) {
                Label("Read \(hm(st.totalSeconds))", systemImage: "square.fill").foregroundStyle(Color(red: 0.42, green: 0.62, blue: 0.85))
                Label("Progress", systemImage: "minus").foregroundStyle(.orange)
            }.font(.footnote.weight(.medium)).labelStyle(SmallIcon())
            Divider()
            FlowLayout(spacing: 14) {
                ForEach(st.bySource, id: \.bucket) { sl in
                    HStack(spacing: 6) {
                        Image(systemName: sourceIcons[sl.bucket] ?? "square").foregroundStyle(.secondary)
                        Text(sourceLabels[sl.bucket] ?? sl.bucket).foregroundStyle(.secondary)
                        Text(hm(sl.totalSeconds)).fontWeight(.semibold)
                    }.font(.subheadline)
                }
            }
        }
        .padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
    }

    private var sinceText: String {
        guard let d = BookPage.date(sessions.stats.firstSessionAt) else { return "" }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d).uppercased()
    }

    private func bigStat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) { Text(v).font(.title.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5); Text(l).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day the book would be finished, if reading goes on at the average daily pace so far.
    private func finish(_ left: Double?) -> (String, String) {
        guard let left, left > 0, let first = BookPage.date(sessions.stats.firstSessionAt) else { return ("–", "to finish") }
        let days = max(Date().timeIntervalSince(first) / 86400, 1)
        let perDay = sessions.stats.totalSeconds / days
        guard perDay > 0 else { return ("–", "to finish") }
        let date = Date().addingTimeInterval(left / perDay * 86400)
        let w = DateFormatter(); w.dateFormat = "EEE"; let d = DateFormatter(); d.dateFormat = "d MMM"
        return (w.string(from: date), "to finish, \(d.string(from: date))")
    }

    private var chart: some View {
        let daily = sessions.stats.dailySummary
        let progress = sessions.stats.progressSummary
        let maxMinutes = max(daily.map(\.totalMinutes).max() ?? 1, 1)
        return Chart {
            ForEach(daily, id: \.day) { d in
                BarMark(x: .value("Day", d.day), y: .value("Minutes", d.totalMinutes / maxMinutes)).foregroundStyle(Color(red: 0.42, green: 0.62, blue: 0.85).opacity(0.7))
            }
            ForEach(progress, id: \.day) { p in
                LineMark(x: .value("Day", p.day), y: .value("Progress", p.endProgress / 100)).foregroundStyle(.orange)
                PointMark(x: .value("Day", p.day), y: .value("Progress", p.endProgress / 100)).foregroundStyle(.orange)
            }
        }
        .chartYScale(domain: 0...1.1).chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { v in AxisValueLabel { if let s = v.as(String.self) { Text(Self.shortDay(s)).font(.caption2) } } } }
        .frame(height: 140)
    }

    private static func shortDay(_ s: String) -> String {
        guard let d = HighlightsHubView.parse(s) else { return s }
        if Calendar.current.isDateInToday(d) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
    }

    private var deviceFilter: some View {
        Menu {
            Button("All devices") { device = nil }
            ForEach(sessions.stats.bySource, id: \.bucket) { sl in Button(sourceLabels[sl.bucket] ?? sl.bucket) { device = sl.bucket } }
        } label: {
            Label(device.map { sourceLabels[$0] ?? $0 } ?? "All devices", systemImage: "chevron.down").labelStyle(TrailingChevron())
                .font(.headline).foregroundStyle(.tint).padding(.horizontal, 16).padding(.vertical, 10).background(.quaternary.opacity(0.5), in: Capsule())
        }
    }

    // MARK: Days and sessions

    private enum Row: Identifiable {
        case session(SessionsPage.Item, gap: TimeInterval?)
        case quick(id: String, count: Int, seconds: Double, items: [SessionsPage.Item])
        var id: String {
            switch self { case .session(let s, _): return "s\(s.id)"; case .quick(let id, _, _, _): return id }
        }
    }
    private struct Day { let day: String; let date: Date; let seconds: Double; let count: Int; let rows: [Row] }

    private var days: [Day] {
        let cal = Calendar.current
        let all = items
        // Gap since the previous (earlier) session ended, across the whole list.
        var gap: [Int: TimeInterval] = [:]
        let asc = all.reversed()
        var prevEnd: Date?
        for s in asc {
            if let e = prevEnd, let st = BookPage.date(s.startedAt) { gap[s.id] = max(st.timeIntervalSince(e), 0) }
            prevEnd = BookPage.date(s.endedAt) ?? prevEnd
        }
        var order: [String] = []
        var groups: [String: [SessionsPage.Item]] = [:]
        for s in all {
            guard let d = BookPage.date(s.startedAt) else { continue }
            let key = String(format: "%04d-%02d-%02d", cal.component(.year, from: d), cal.component(.month, from: d), cal.component(.day, from: d))
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        return order.map { key in
            let list = groups[key]!
            var rows: [Row] = []
            var run: [SessionsPage.Item] = []
            func flush() {
                if run.count >= 2 { rows.append(.quick(id: "q\(run[0].id)", count: run.count, seconds: run.reduce(0) { $0 + $1.durationSeconds }, items: run)) }
                else { for r in run { rows.append(.session(r, gap: gap[r.id])) } }
                run = []
            }
            for s in list { if s.durationSeconds < 10 { run.append(s) } else { flush(); rows.append(.session(s, gap: gap[s.id])) } }
            flush()
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return Day(day: key, date: f.date(from: key) ?? Date(), seconds: list.reduce(0) { $0 + $1.durationSeconds }, count: list.count, rows: rows)
        }
    }

    private func dayBlock(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayTitle(day.date)).font(.title3.weight(.semibold))
                Text(dayFull(day.date)).foregroundStyle(.secondary)
                Spacer()
                Label(hm(day.seconds), systemImage: "clock").font(.subheadline.weight(.medium))
                Text("\(day.count)").font(.footnote.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2).background(.quaternary, in: Capsule())
            }
            .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            ForEach(day.rows) { row in
                switch row {
                case .session(let s, let gap): sessionRow(s, gap)
                case .quick(let id, let count, let seconds, let list):
                    VStack(alignment: .leading, spacing: 10) {
                        Button { if openRuns.contains(id) { openRuns.remove(id) } else { openRuns.insert(id) } } label: {
                            HStack(spacing: 12) {
                                timeLabel(list.first!.startedAt)
                                Circle().stroke(.secondary, lineWidth: 1.5).frame(width: 12, height: 12)
                                Text("\(count) quick looks · \(hm(seconds))").foregroundStyle(.secondary)
                                Image(systemName: openRuns.contains(id) ? "chevron.up" : "chevron.down").font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                        if openRuns.contains(id) { ForEach(list) { sessionRow($0, nil) } }
                    }
                }
            }
        }
    }

    private func sessionRow(_ s: SessionsPage.Item, _ gap: TimeInterval?) -> some View {
        let src = bucket(s.source)
        let end = s.endProgress
        let start = end.flatMap { e in s.progressDelta.map { e - $0 } }
        let moved = start.map { abs($0 - (end ?? 0)) >= 0.5 } ?? false
        return HStack(alignment: .top, spacing: 12) {
            timeLabel(s.startedAt)
            Image(systemName: "book").frame(width: 38, height: 38).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Read \(readText(s.durationSeconds))").font(.headline)
                    if s.durationSeconds == (sessions.items.map(\.durationSeconds).max() ?? -1), s.durationSeconds >= 60 {
                        Text("Longest").font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.horizontal, 8).padding(.vertical, 2).background(Color.orange.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if let e = end { Text("\(Int(e.rounded()))%").font(.headline) }
                }
                HStack(spacing: 6) {
                    Image(systemName: sourceIcons[src] ?? "square").font(.caption)
                    Text(sourceLabels[src] ?? src)
                    Text("•")
                    if moved, let a = start, let b = end { Text("\(Int(a.rounded()))% → \(Int(b.rounded()))%") } else if let e = end { Text("at \(Int(e.rounded()))%") }
                }.font(.subheadline).foregroundStyle(.secondary)
                if let e = end {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary).frame(height: 8)
                            if moved, let a = start {
                                Capsule().fill(Color(red: 0.42, green: 0.62, blue: 0.85).opacity(0.6))
                                    .frame(width: max(g.size.width * abs(e - a) / 100, 6), height: 8).offset(x: g.size.width * min(a, e) / 100)
                            }
                            Circle().fill(Color(red: 0.42, green: 0.62, blue: 0.85)).frame(width: 12, height: 12).offset(x: max(g.size.width * e / 100 - 6, 0))
                        }
                    }.frame(height: 12)
                }
                if let gap, gap >= 60 { Label(hm(gap), systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func timeLabel(_ iso: String) -> some View {
        let f = DateFormatter(); f.dateFormat = "H:mm"
        return Text(BookPage.date(iso).map { f.string(from: $0) } ?? "").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .frame(width: 58, height: 30).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    }

    private func readText(_ s: Double) -> String {
        let n = Int(s.rounded())
        if n < 60 { return "\(n) sec" }
        let m = n / 60
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: d)
    }
    private func dayFull(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = (cal.isDateInToday(d) || cal.isDateInYesterday(d)) ? "EEE, d MMM" : "d MMM"; return f.string(from: d)
    }

    @ViewBuilder private var startedRow: some View {
        if let first = items.last {
            let src = bucket(first.source)
            HStack(alignment: .top, spacing: 12) {
                timeLabel(first.startedAt)
                Image(systemName: "flag.fill").foregroundStyle(.orange).frame(width: 38, height: 38).background(Color.orange.opacity(0.2), in: Circle())
                VStack(alignment: .leading) {
                    Text("Started reading").font(.headline).foregroundStyle(.orange)
                    Text("On \(sourceLabels[src] ?? src)").foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SmallIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 9)); configuration.title }
    }
}
private struct TrailingChevron: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { Image(systemName: "iphone"); configuration.title; configuration.icon.font(.footnote) }
    }
}
