import SwiftUI

struct RootView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView(selection: Binding(get: { router.tab }, set: { new in
            // Choosing More, from another tab or while on it, always lands on its list.
            if new == 2 { router.morePath = [] }
            router.tab = new
        })) {
            HomeView().tabItem { Label("Home", systemImage: "house") }.tag(0)
            BrowseView().tabItem { Label("Library", systemImage: "books.vertical") }.tag(1)
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }.tag(2)
        }
        .fullScreenCover(item: $router.openBook) { book in
            if let file = book.epubFile() { ReaderScreen(book: book, file: file) }
        }
        .task(id: router.pending) { await continueReading() }
    }

    /// "Continue reading" from the icon menu: opens the book that is in progress.
    private func continueReading() async {
        guard router.pending == "app.bookorb.companion.continue" else { return }
        router.pending = nil
        let shelves = await api.shelves([("continue", "continue-reading")], limit: 1)
        if let book = shelves["continue"]?.first(where: { $0.epubFile() != nil }) { router.openBook = book }
    }
}

struct CoverView: View {
    @EnvironmentObject var api: ServerAPI
    let book: BookCard
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "book.closed").foregroundStyle(.secondary) }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) {
            if let p = book.readingProgress, p > 0, p < 100 {
                GeometryReader { g in
                    Rectangle().fill(.tint).frame(width: g.size.width * p / 100, height: 3).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .task(id: book.id) { if book.hasCover { image = await api.cover(bookId: book.id) } }
    }
}

struct OfflineBanner: View {
    @EnvironmentObject var api: ServerAPI
    var body: some View {
        if !api.online {
            Label("Server unreachable – showing saved data", systemImage: "wifi.slash")
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.yellow.opacity(0.25))
        }
    }
}

/// History, Activity and Highlights, which no longer have a tab of their own.
struct MoreView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.morePath) {
            List {
                row("History", "Finished reads by month", "clock.arrow.circlepath", .history)
                row("Activity", "Reading insights and achievements", "chart.bar.xaxis", .activity)
                row("Highlights", "Everything you have highlighted", "highlighter", .highlights)
            }
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .history: HistoryView()
                case .activity: ActivityView()
                case .highlights: HighlightsHubView()
                }
            }
        }
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, _ destination: MoreDestination) -> some View {
        NavigationLink(value: destination) {
            Label {
                VStack(alignment: .leading, spacing: 2) { Text(title); Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            } icon: { Image(systemName: icon) }
        }
    }
}
