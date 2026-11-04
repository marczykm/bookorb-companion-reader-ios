import SwiftUI

@main
struct CompanionReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Gate()
            .environmentObject(app)
            .environmentObject(app.api)
            .environmentObject(app.session)
            .environmentObject(AppRouter.shared)
            .onOpenURL { url in if url.scheme == "bookorb", url.host == "continue" { AppRouter.shared.handle("app.bookorb.companion.continue") } }
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

/// Which tab is showing and which book to open, driven by the Home Screen quick actions.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab = 0
    @Published var openBook: BookCard?
    /// An action that arrived before the UI was ready (e.g. a cold start); handled once signed in.
    @Published var pending: String?

    func handle(_ type: String) {
        switch type {
        case "app.bookorb.companion.library": pending = nil; tab = 1
        case "app.bookorb.companion.browse": pending = nil; tab = 2
        case "app.bookorb.companion.continue": tab = 0; pending = type
        default: break
        }
    }
}

/// Receives the quick actions from the app icon's long-press menu.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { AppRouter.shared.handle(item.type) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        AppRouter.shared.handle(shortcutItem.type)
        completionHandler(true)
    }
}
