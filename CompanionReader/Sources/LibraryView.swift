import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var books: [BookCard] = []
    @State private var libraries: [Library] = []
    @State private var libraryId: Int?
    @State private var status: String?
    @State private var query = ""
    @State private var grid = true
    @State private var total = 0
    @State private var page = 0
    @State private var loading = false
    @State private var error: String?
    @State private var selected: BookCard?
    @State private var showHighlights = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                if let error, books.isEmpty { Text(error).foregroundStyle(.secondary).padding() }
                ScrollView {
                    if grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                            ForEach(books) { b in
                                Button { selected = b } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        CoverView(book: b)
                                        Text(b.title ?? "Untitled").font(.caption).lineLimit(2)
                                    }
                                }.buttonStyle(.plain).onAppear { more(b) }
                            }
                        }.padding()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(books) { b in
                                Button { selected = b } label: {
                                    HStack(spacing: 12) {
                                        CoverView(book: b).frame(width: 56)
                                        VStack(alignment: .leading) {
                                            Text(b.title ?? "Untitled").font(.headline).lineLimit(2)
                                            Text(b.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                            if let s = b.seriesName { Text(s).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                    }
                                }.buttonStyle(.plain).onAppear { more(b) }
                            }
                        }.padding()
                    }
                }
                .refreshable { await load(reset: true) }
            }
            .navigationTitle("Library (\(total))")
            .searchable(text: $query, prompt: "Search books")
            .navigationDestination(isPresented: $showHighlights) { HighlightsHubView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHighlights = true } label: { Image(systemName: "highlighter") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Library", selection: $libraryId) {
                            Text("All libraries").tag(Int?.none)
                            ForEach(libraries) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        Picker("Status", selection: $status) {
                            Text("Any status").tag(String?.none)
                            ForEach(bookStatuses, id: \.key) { Text($0.label).tag(String?.some($0.key)) }
                        }
                        Button(grid ? "List view" : "Grid view", systemImage: grid ? "list.bullet" : "square.grid.2x2") { grid.toggle() }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { Task { await api.logout() } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .task(id: "\(query)|\(libraryId ?? -1)|\(status ?? "")") {
                if !query.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
                guard !Task.isCancelled else { return }
                await load(reset: true)
            }
            .task { libraries = await api.libraries() }
            .sheet(item: $selected) { BookDetailView(book: $0) }
        }
    }

    private func more(_ b: BookCard) {
        guard b.id == books.last?.id, books.count < total, !loading else { return }
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true; error = nil
        defer { loading = false }
        let target = reset ? 0 : page + 1
        do {
            let r = try await api.books(query: query, page: target, libraryId: libraryId, status: status)
            if reset { books = r.items } else { books += r.items }
            total = r.total; page = target
        } catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}
