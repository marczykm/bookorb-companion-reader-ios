import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house") }
            LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
            BrowseView().tabItem { Label("Browse", systemImage: "square.stack") }
        }
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
