import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var book: BookCard
    @State private var reading = false
    @State private var downloading = false
    @State private var onDevice = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CoverView(book: book).frame(width: 160)
                    Text(book.title ?? "Untitled").font(.title2.bold()).multilineTextAlignment(.center)
                    if !book.authors.isEmpty { Text(book.authors.joined(separator: ", ")).foregroundStyle(.secondary) }
                    if let s = book.seriesName { Text(s).font(.footnote).foregroundStyle(.secondary) }
                    if let p = book.readingProgress, p > 0 { ProgressView(value: min(p, 100), total: 100).padding(.horizontal) }

                    if let file = book.epubFile() {
                        Button { reading = true } label: { Label(downloading ? "Downloading…" : "Read", systemImage: "book").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Button(onDevice ? "Remove download" : "Download for offline") {
                            if onDevice { api.removeDownload(fileId: file.id); onDevice = false } else { download(file) }
                        }.disabled(downloading)
                    } else {
                        Text("Only EPUB books can be read in this app.").foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                    Picker("Status", selection: Binding(get: { book.readStatus?.status ?? "unread" }, set: setStatus)) {
                        ForEach(bookStatuses, id: \.key) { Text($0.label).tag($0.key) }
                    }
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: Double(i) <= (book.rating ?? 0) ? "star.fill" : "star").foregroundStyle(.yellow)
                                .onTapGesture { setRating(Int(book.rating ?? 0) == i ? nil : i) }
                        }
                    }.font(.title3)
                }.padding()
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { if let f = book.epubFile() { onDevice = api.isOnDevice(f.id) } }
            .fullScreenCover(isPresented: $reading, onDismiss: { if let f = book.epubFile() { onDevice = api.isOnDevice(f.id) } }) {
                if let f = book.epubFile() { ReaderScreen(book: book, file: f) }
            }
        }
    }

    private func download(_ file: BookFileRef) {
        downloading = true; error = nil
        Task {
            do { _ = try await api.downloadFile(fileId: file.id); onDevice = true } catch { self.error = error.localizedDescription }
            downloading = false
        }
    }
    private func setStatus(_ s: String) {
        book.readStatus = StatusInfo(status: s)
        app.outbox.status(bookId: book.id, s); app.syncNow()
    }
    private func setRating(_ r: Int?) {
        book.rating = r.map(Double.init)
        app.outbox.rating(bookId: book.id, r); app.syncNow()
    }
}
