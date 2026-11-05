import SwiftUI

/// Finished reads, newest first, grouped by month, with a summary of the year.
struct HistoryView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var year: Int? = Calendar.current.component(.year, from: Date())   // nil = all time
    @State private var query = ""
    @State private var covers = false
    @State private var summary: HistorySummary?
    @State private var items: [HistoryItem] = []
    @State private var months: [HistoryMonth] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            List {
                Section {
                    Picker("View", selection: $covers) { Text("List").tag(false); Text("Covers").tag(true) }.pickerStyle(.segmented)
                    yearChips
                }.listRowSeparator(.hidden)
                if let summary { Section { NumbersCard(summary: summary, year: year) }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                if covers { coverWall } else { monthList }
                if items.count < total {
                    Color.clear.frame(height: 1).onAppear { Task { await load(reset: false) } }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && items.isEmpty { ProgressView() }
                else if loaded && items.isEmpty { Text(error ?? "No reads yet").foregroundStyle(.secondary) }
            }
            .refreshable { await load(reset: true) }
        }
        .navigationTitle("History")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search books")
        .task(id: "\(year.map(String.init) ?? "all")|\(query)") {
            if !query.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    // MARK: Pieces

    private var yearChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(summary?.years ?? [], id: \.year) { y in
                    chip("\(String(y.year)) \(y.reads)", selected: year == y.year) { year = y.year }
                }
                chip("All time", selected: year == nil) { year = nil }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.accentColor : .clear))
        }.buttonStyle(.plain)
    }

    /// Rows are split into the server's months by count, in order, as the web client does.
    private var sections: [(month: HistoryMonth, rows: [HistoryItem])] {
        var out: [(HistoryMonth, [HistoryItem])] = []
        var index = 0
        for m in months {
            let rows = Array(items[min(index, items.count)..<min(index + m.reads, items.count)])
            index += m.reads
            if !rows.isEmpty { out.append((m, rows)) }
        }
        return out
    }

    @ViewBuilder private var monthList: some View {
        ForEach(sections, id: \.month.month) { section in
            Section {
                ForEach(section.rows) { HistoryRow(item: $0) }
            } header: { MonthHeader(month: section.month) }
        }
    }

    @ViewBuilder private var coverWall: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 12) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HistoryCover(bookId: item.bookId)
                        Text(item.title ?? "Untitled").font(.caption2).lineLimit(2)
                    }
                }
            }.listRowSeparator(.hidden)
        }
    }

    // MARK: Loading

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            if reset { summary = try await api.historySummary(year: year) }
            let page = try await api.history(year: year, search: query, offset: reset ? 0 : items.count)
            if reset { items = page.items; months = page.months ?? [] } else { items += page.items }
            total = page.total
        } catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private struct MonthHeader: View {
    let month: HistoryMonth
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(month.reads) read\(month.reads == 1 ? "" : "s")\(month.seconds > 0 ? " · " + duration(month.seconds) : "")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .textCase(nil).padding(.vertical, 4)
    }
    private var title: String {
        if month.month == "undated" { return "Undated" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: month.month) else { return month.month }
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HistoryCover(bookId: item.bookId).frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Untitled").font(.headline).lineLimit(2)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    if let f = item.format { Badge(text: f.uppercased(), color: .green) }
                    if item.outcome != "completed" {
                        Badge(text: item.outcome == "abandoned" ? "Abandoned" : "Skimmed", color: .orange)
                    }
                    if let r = item.readNumber, r > 1 { Badge(text: "Read \(r)", color: .blue) }
                    if item.highlightCount > 0 { Label("\(item.highlightCount)", systemImage: "highlighter").font(.caption).foregroundStyle(.secondary) }
                    if let rating = item.rating, rating > 0 {
                        Label(String(format: "%g", rating), systemImage: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
            }
            Spacer(minLength: 4)
            if let d = shortDate { Text(d).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing) }
        }.padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts = [item.authors.joined(separator: ", ")].filter { !$0.isEmpty }
        if let s = item.seriesName { parts.append(s + (item.seriesIndex.map { " #\($0)" } ?? "")) }
        return parts.joined(separator: " · ")
    }

    private var shortDate: String? {
        guard let s = item.endedOn else { return nil }
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: String(s.prefix(10))) else { return nil }
        let out = DateFormatter(); out.dateFormat = "d MMM\nEEE"
        return out.string(from: d)
    }
}

private struct Badge: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

private struct HistoryCover: View {
    let bookId: Int?
    @EnvironmentObject var api: ServerAPI
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "book.closed").foregroundStyle(.secondary) }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: bookId) { if let id = bookId { image = await api.cover(bookId: id) } }
    }
}

/// "2026 in numbers": totals, a bar per month and the reading goal.
private struct NumbersCard: View {
    let summary: HistorySummary
    let year: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(year.map(String.init) ?? "All time") in numbers", systemImage: "chart.xyaxis.line").font(.headline)
            HStack {
                stat(summary.reads, "reads"); stat(summary.books, "books"); stat(summary.rereads, "rereads")
            }
            if year != nil, !summary.months.isEmpty { bars }
            if let g = summary.goal {
                Label(goalText(g), systemImage: g.reached >= g.target ? "checkmark" : "target").font(.subheadline.weight(.medium))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 4)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading) { Text("\(n)").font(.title.weight(.semibold)); Text(label).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bars: some View {
        let maxReads = max(summary.months.map(\.reads).max() ?? 0, 1)
        let current = Calendar.current.component(.month, from: Date())
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(summary.months, id: \.month) { m in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(m.reads > 0 ? (m.month == current && year == Calendar.current.component(.year, from: Date()) ? Color.accentColor : Color.accentColor.opacity(0.45)) : Color.secondary.opacity(0.3))
                        .frame(height: m.reads > 0 ? max(54 * CGFloat(m.reads) / CGFloat(maxReads), 8) : 2)
                    Text(String(Calendar.current.veryShortMonthSymbols[max(min(m.month, 12), 1) - 1])).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 76, alignment: .bottom)
    }

    private func goalText(_ g: HistorySummary.Goal) -> String {
        if g.reached >= g.target {
            if let met = g.metOn, let d = ISO8601DateFormatter().date(from: met) ?? shortDate(met) {
                let f = DateFormatter(); f.dateFormat = "d MMM"
                return "Goal of \(g.target) met on \(f.string(from: d))"
            }
            return "Goal of \(g.target) met"
        }
        return "\(g.reached) of \(g.target) toward your goal"
    }

    private func shortDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(s.prefix(10)))
    }
}

func duration(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return h > 0 ? "\(h)h" : "\(max(m, 1))m"
}
