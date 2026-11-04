import SwiftUI

@main
struct CompanionReaderApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Gate()
            .environmentObject(app)
            .environmentObject(app.api)
            .environmentObject(app.session)
            .onReceive(app.session.$loggedIn) { if $0 { app.syncNow() } }
            .onChange(of: phase) { _, p in if p == .active { app.syncNow() } }
            .onChange(of: app.api.online) { _, on in if on { app.syncNow() } }
        }
    }
}

private struct Gate: View {
    @EnvironmentObject var session: Session
    var body: some View { if session.loggedIn { RootView() } else { LoginView() } }
}

final class AppState: ObservableObject {
    let session = Session()
    let api: ServerAPI
    let outbox: Outbox
    let settings = ReaderSettings()
    private var retry: Task<Void, Never>?

    init() {
        api = ServerAPI(session: session)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        outbox = Outbox(url: dir.appendingPathComponent("outbox.json"))
        api.outbox = outbox
    }

    /// Tries to send the queue now; if the server isn't reachable, tries again in a while.
    func syncNow() {
        guard session.refreshToken != nil, !outbox.isEmpty else { return }
        retry?.cancel()
        retry = Task { [api, outbox] in
            var delay: UInt64 = 30
            while !Task.isCancelled {
                if await outbox.flush(api: api) { return }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 600)
            }
        }
    }
}
