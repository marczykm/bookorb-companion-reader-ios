import SwiftUI

/// A series, author or SmartScope that was opened to see its books.
struct Opened: Hashable {
    enum Kind { case series, author, smartScope }
    let kind: Kind
    let id: Int
    let title: String
}

struct BrowseView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @EnvironmentObject var router: AppRouter
    private var mode: Int { router.browseMode }   // 0 all books, 1 series, 2 authors, 3 SmartScopes
    @State private var query = ""
    @State private var series: [SeriesItem] = []
    @State private var authors: [AuthorItem] = []
    @State private var scopes: [SmartScopeItem] = []
    @State private var total = 0
    @State private var page = 0
    @State private var loading = false
    @State private var error: String?

    private var count: Int { mode == 0 ? 0 : [series.count, authors.count, scopes.count][mode - 1] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                Picker("Browse", selection: $router.browseMode) {
                    Text("All").tag(0); Text("Series").tag(1); Text("Authors").tag(2); Text("SmartScopes").tag(3)
                }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)
                if mode == 0 { LibraryContent(query: $query) } else {
                List {
                    switch mode {
                    case 1:
                        ForEach(series) { s in
                            NavigationLink(value: Opened(kind: .series, id: s.id, title: s.name)) {
                                BrowseRow(coverBookId: s.coverBookIds.first, title: s.name, round: false,
                                          subtitle: "\(s.readCount)/\(s.bookCount) read" + (s.authors.isEmpty ? "" : " · " + s.authors.joined(separator: ", ")))
                            }.onAppear { more(s.id == series.last?.id) }
                        }
                    case 2:
                        ForEach(authors) { a in
                            NavigationLink(value: Opened(kind: .author, id: a.id, title: a.name)) {
                                BrowseRow(coverBookId: a.coverBookId, title: a.name, round: true, subtitle: "\(a.bookCount) book\(a.bookCount == 1 ? "" : "s")")
                            }.onAppear { more(a.id == authors.last?.id) }
                        }
                    default:
                        ForEach(scopes) { sc in
                            NavigationLink(value: Opened(kind: .smartScope, id: sc.id, title: sc.name)) {
                                BrowseRow(coverBookId: nil, title: sc.name, round: false,
                                          subtitle: sc.bookCount.map { "\($0) book\($0 == 1 ? "" : "s")" } ?? "SmartScope")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if loading && count == 0 { ProgressView() }
                    else if !loading && count == 0 { Text(error ?? "Nothing found").foregroundStyle(.secondary).padding() }
                }
                .refreshable { await load(reset: true) }
                }
            }
            .navigationTitle("Browse")
            .searchable(text: $query, prompt: ["Search books", "Search series", "Search authors", "Search SmartScopes"][mode])
            .navigationDestination(for: Opened.self) { PagedBooksView(opened: $0) }
            .task(id: "\(mode)|\(query)") {
                guard mode != 0 else { return }   // All loads its own books
                if !query.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
                guard !Task.isCancelled else { return }
                await load(reset: true)
            }
        }
    }

    private func more(_ isLast: Bool) {
        guard isLast, count < total, !loading else { return }
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true; error = nil
        defer { loading = false }
        let target = reset ? 0 : page + 1
        do {
            switch mode {
            case 0: return
            case 1:
                let r = try await api.series(query: query, page: target)
                series = reset ? r.items : series + r.items; total = r.total
            case 2:
                let r = try await api.authors(query: query, page: target)
                authors = reset ? r.items : authors + r.items; total = r.total
            default:
                // SmartScopes come back in one piece; the search box filters them here.
                let q = query.trimmingCharacters(in: .whitespaces)
                scopes = try await api.smartScopes().filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
                total = scopes.count
            }
            page = target
        } catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private struct BrowseRow: View {
    let coverBookId: Int?
    let title: String
    let round: Bool
    let subtitle: String
    @EnvironmentObject var api: ServerAPI
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { ZStack { Color.accentColor.opacity(0.15); Text(String(title.prefix(1)).uppercased()).font(.title2) } }
            }
            .frame(width: 56, height: round ? 56 : 84)
            .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .task(id: coverBookId) { if let id = coverBookId { image = await api.cover(bookId: id) } }
    }
}

/// The books of a series, author or SmartScope, loaded a page at a time.
struct PagedBooksView: View {
    let opened: Opened
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var books: [BookCard] = []
    @State private var total = 0
    @State private var page = 0
    @State private var loading = false
    @State private var error: String?
    @State private var selected: BookCard?

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            ScrollView {
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
            }
            .refreshable { await load(reset: true) }
            .overlay {
                if loading && books.isEmpty { ProgressView() }
                else if !loading && books.isEmpty { Text(error ?? "No books").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(opened.title).navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
        .sheet(item: $selected, onDismiss: { Task { await load(reset: true) } }) { BookDetailView(book: $0) }
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
            let r: BooksPage
            switch opened.kind {
            case .series: r = try await api.seriesBooks(id: opened.id, page: target)
            case .author: r = try await api.authorBooks(id: opened.id, page: target)
            case .smartScope: r = try await api.smartScopeBooks(id: opened.id, page: target)
            }
            books = reset ? r.items : books + r.items
            total = r.total; page = target
        } catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}
