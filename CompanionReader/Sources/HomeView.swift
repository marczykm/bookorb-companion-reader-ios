import SwiftUI

private let shelfDefs: [(id: String, type: String)] = [
    ("continue", "continue-reading"), ("next", "up-next-in-series"), ("want", "want-to-read"), ("recent", "recently-added"),
]
private let shelfTitles = ["next": "Up next in series", "want": "Want to read", "recent": "Recently added"]

/// Cover width for an item size: small is about three quarters of medium, large about a third bigger.
private func coverWidth(_ size: String, _ medium: CGFloat) -> CGFloat {
    size == "s" ? medium * 3 / 4 : size == "l" ? medium * 4 / 3 : medium
}

struct HomeView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @EnvironmentObject var app: AppState
    @StateObject private var layout = HomeLayout()
    @State private var shelves: [String: [BookCard]] = [:]
    @State private var widgets: WidgetData = [:]
    @State private var loaded = false
    @State private var selected: BookCard?
    @State private var customizing = false
    @State private var showAbout = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(layout.rows, id: \.first) { row in
                            if row.count == 2 || (row[0] != "hero" && halfWidthItems.contains(row[0]) && layout.sizeOf(row[0]) == "s") {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(row, id: \.self) { id in
                                        WidgetItemView(id: id, data: widgets, hasBook: !(shelves["continue"] ?? []).isEmpty, size: "s")
                                    }
                                    if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                                }.padding(.horizontal)
                            } else {
                                item(row[0])
                            }
                        }
                    }.padding(.vertical)
                }
                .refreshable { await load() }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { customizing = true } label: { Image(systemName: "slider.horizontal.3") }
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                }
            }
            .task { await load() }
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { BookDetailView(book: $0) }
            .sheet(isPresented: $customizing) { CustomizeHomeSheet(layout: layout) }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showSettings) { SettingsView(settings: app.settings) }
        }
    }

    @ViewBuilder private func item(_ id: String) -> some View {
        let size = layout.sizeOf(id)
        let current = shelves["continue"] ?? []
        if id == "hero" {
            if let book = current.first { ContinueCard(book: book, size: size) { selected = book } }
            else if loaded { Text("Nothing in progress. Pick a book from the library.").foregroundStyle(.secondary).padding(.horizontal) }
        } else if id == "shelf:continue" {
            if current.count > 1 { Shelf(title: "Continue reading", books: Array(current.dropFirst()), size: size) { selected = $0 } }
        } else if id.hasPrefix("shelf:") {
            let key = String(id.dropFirst(6))
            if let books = shelves[key], !books.isEmpty { Shelf(title: shelfTitles[key] ?? key, books: books, size: size) { selected = $0 } }
        } else if id == "clock" || !widgets.isEmpty {
            WidgetItemView(id: id, data: widgets, hasBook: !current.isEmpty, size: size).padding(.horizontal)
        }
    }

    private func load() async {
        shelves = await api.shelves(shelfDefs)
        widgets = await api.widgets(widgetTypes)
        loaded = true
        await WidgetSync.publish(api: api, current: shelves["continue"]?.first, widgets: widgets)
    }
}

private struct ContinueCard: View {
    let book: BookCard; let size: String; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                CoverView(book: book).frame(width: coverWidth(size, 110))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue reading").font(.caption.weight(.medium)).foregroundStyle(.tint)
                    Text(book.title ?? "Untitled").font(.title3.weight(.semibold)).lineLimit(3)
                    Text(book.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if let p = book.readingProgress {
                        ProgressView(value: min(max(p / 100, 0), 1)).padding(.top, 8)
                        Text("\(Int(p))%").font(.caption2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).padding(.horizontal)
    }
}

private struct Shelf: View {
    let title: String; let books: [BookCard]; let size: String; let onOpen: (BookCard) -> Void
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(books) { b in
                        Button { onOpen(b) } label: { CoverView(book: b).frame(width: coverWidth(size, 110)) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
        }
    }
}

private struct CustomizeHomeSheet: View {
    @ObservedObject var layout: HomeLayout
    @Environment(\.dismiss) private var dismiss
    private let titles = Dictionary(uniqueKeysWithValues: homeItems.map { ($0.id, $0.title) })

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(layout.order.enumerated()), id: \.element) { index, id in
                    HStack {
                        Toggle("", isOn: Binding(get: { !layout.hidden.contains(id) }, set: { layout.setVisible(id, $0) })).labelsHidden()
                        Text(titles[id] ?? id).frame(maxWidth: .infinity, alignment: .leading)
                        Button(layout.sizeOf(id).uppercased()) { layout.cycleSize(id) }.buttonStyle(.bordered)
                        Button { layout.move(id, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                        Button { layout.move(id, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == layout.order.count - 1)
                    }.buttonStyle(.borderless)
                }
            }
            .navigationTitle("Customize Home").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset", role: .destructive) { layout.reset() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The notice required by BookOrbit's additional license terms for material reused from the project.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Link("Powered by BookOrbit", destination: URL(string: "https://github.com/bookorbit/bookorbit")!).font(.headline)
                    Text("Copyright (C) 2025-2026 neon.")
                    Text("Additional copyright is held by the respective BookOrbit contributors.")
                    Text("Original project: https://github.com/bookorbit/bookorbit")
                    Text("Licensed under the GNU Affero General Public License, version 3 only, with additional terms. This software is provided without warranty. You may redistribute and modify it under those terms.")
                    Text("This is a modified version of BookOrbit and is not an official BookOrbit release. Companion artwork is from the BookOrbit KOReader plugin. EPUB position code is from foliate-js (MIT).")
                        .foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// App settings, as on Android: the gear on Home.
struct SettingsView: View {
    @EnvironmentObject var api: ServerAPI
    @ObservedObject var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    Toggle(isOn: $settings.volumeKeys) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn pages with the volume keys")
                            Text("Volume down goes to the next page and volume up to the previous one while a book is open.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Account") {
                    Button("Sign out", role: .destructive) { Task { await api.logout() } }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
