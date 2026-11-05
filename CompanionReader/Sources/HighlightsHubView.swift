import SwiftUI

/// All the user's highlights across the library, newest first and grouped by month, with search and filters.
struct HighlightsHubView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var overview: HubOverview?
    @State private var items: [HubHighlight] = []
    @State private var total = 0
    @State private var page = 0
    @State private var query = ""
    @State private var colors: Set<String> = []
    @State private var onlyNotes = false
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            List {
                if let o = overview { Section { header(o) }.listRowSeparator(.hidden).listRowBackground(Color.clear) }
                ForEach(sections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.rows) { HighlightRow(item: $0) }
                    }
                }
                if items.count < total {
                    Color.clear.frame(height: 1).onAppear { Task { await load(reset: false) } }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && items.isEmpty { ProgressView() }
                else if loaded && items.isEmpty { Text(error ?? "No highlights").foregroundStyle(.secondary).padding() }
            }
            .refreshable { await load(reset: true) }
        }
        .navigationTitle("Highlights").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search highlights")
        .task(id: "\(query)|\(colors.sorted().joined(separator: ","))|\(onlyNotes)") {
            if !query.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    // MARK: Header with the counts and filters

    @ViewBuilder private func header(_ o: HubOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stat(o.total, "highlights"); stat(o.books, "books"); stat(o.withNotes, "with notes")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(selected: onlyNotes) { onlyNotes.toggle() } label: { Label("With notes", systemImage: "note.text") }
                    ForEach(o.colorBreakdown, id: \.color) { c in
                        chip(selected: colors.contains(c.color)) {
                            if colors.contains(c.color) { colors.remove(c.color) } else { colors.insert(c.color) }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(HighlightSync.tint(c.color))).frame(width: 12, height: 12)
                                Text("\(c.count)")
                            }
                        }
                    }
                }
            }
        }
        .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading) { Text("\(n)").font(.title2.weight(.semibold)); Text(label).font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label().font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.accentColor : .clear))
        }.buttonStyle(.plain)
    }

    // MARK: Month sections

    private struct MonthSection { let key: String; let title: String; let rows: [HubHighlight] }

    private var sections: [MonthSection] {
        let cal = Calendar.current
        var order: [String] = []
        var groups: [String: [HubHighlight]] = [:]
        for it in items {
            let d = Self.parse(it.highlightedAt ?? it.createdAt)
            let key = d.map { String(format: "%04d-%02d", cal.component(.year, from: $0), cal.component(.month, from: $0)) } ?? "undated"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(it)
        }
        return order.map { key in
            let title: String
            if key == "undated" { title = "Undated" } else {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                let d = f.date(from: key) ?? Date()
                f.dateFormat = "LLLL yyyy"; title = f.string(from: d).capitalized
            }
            return MonthSection(key: key, title: title, rows: groups[key]!)
        }
    }

    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: iso) { return d }
        if let d = ISO8601DateFormatter().date(from: iso) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(iso.prefix(10)))
    }

    // MARK: Loading

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        let target = reset ? 1 : page + 1
        do {
            if reset && overview == nil { overview = try await api.hubOverview() }
            let r = try await api.hubHighlights(page: target, search: query, colors: colors.sorted(), hasNote: onlyNotes)
            items = reset ? r.items : items + r.items
            total = r.total; page = target
        } catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private struct HighlightRow: View {
    let item: HubHighlight
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(HighlightSync.tint(item.color))).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text).font(.body).lineLimit(expanded ? nil : 6)
                if let note = item.note, !note.isEmpty {
                    Label(note, systemImage: "note.text").font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 3)
                }
                HStack(spacing: 6) {
                    if item.starredAt != nil { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                    Text(footer).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    if item.origin != "web" { Text(item.origin.capitalized).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).overlay(Capsule().stroke(.secondary.opacity(0.5))) }
                }
            }
        }
        .padding(.vertical, 4).contentShape(Rectangle()).onTapGesture { expanded.toggle() }
        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text } }
    }

    private var footer: String {
        var parts = [item.bookTitle ?? "Unknown book"]
        if let a = item.author, !a.isEmpty { parts.append(a) }
        if let c = item.chapterTitle, !c.isEmpty { parts.append(c) }
        if let d = HighlightsHubView.parse(item.highlightedAt ?? item.createdAt) { let f = DateFormatter(); f.dateFormat = "d MMM"; parts.append(f.string(from: d)) }
        return parts.joined(separator: " · ")
    }
}
