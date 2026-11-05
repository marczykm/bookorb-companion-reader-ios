import Foundation
import UIKit
import CryptoKit

struct AuthError: LocalizedError { var errorDescription: String? { "Session expired" } }
struct HTTPError: LocalizedError {
    let code: Int
    var errorDescription: String? { "Server returned HTTP \(code)" }
}

final class ServerAPI: ObservableObject {
    let session: Session
    var outbox: Outbox!
    /// False while the last read had to fall back to saved data.
    @Published var online = true
    /// True while a (non-cover) request is in flight.
    @Published var syncing = false

    private var inFlight = 0
    private let urlSession = URLSession(configuration: .default)
    private let enc: JSONEncoder = { let e = JSONEncoder(); return e }()
    private let dec = JSONDecoder()
    private let refreshGate = AsyncGate()
    private let fm = FileManager.default
    private let dataDir: URL
    let booksDir: URL
    private let coverDir: URL
    private let coverCache = NSCache<NSNumber, UIImage>()

    init(session: Session) {
        self.session = session
        let docs = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dataDir = docs.appendingPathComponent("data"); booksDir = docs.appendingPathComponent("books")
        coverDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers")
        for d in [dataDir, booksDir, coverDir] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    }

    private func setSyncing(_ on: Bool) {
        DispatchQueue.main.async {
            self.inFlight += on ? 1 : -1
            if on { self.syncing = true }
            else if self.inFlight == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if self.inFlight == 0 { self.syncing = false } }
            }
        }
    }
    private func setOnline(_ v: Bool) { DispatchQueue.main.async { if self.online != v { self.online = v } } }

    private func url(_ path: String, _ query: [String: String] = [:], base: String? = nil) -> URL {
        var c = URLComponents(string: (base ?? session.serverUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1" + path)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }

    // MARK: Requests

    private func raw(_ method: String, _ url: URL, body: Data? = nil, authed: Bool = true, counted: Bool = true) async throws -> (Data, Int) {
        var retried = false
        while true {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 20
            if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let sent = session.accessToken
            if authed, let sent { req.setValue("Bearer \(sent)", forHTTPHeaderField: "Authorization") }
            if counted { setSyncing(true) }
            defer { if counted { setSyncing(false) } }
            // Run in its own task: SwiftUI cancels a pull-to-refresh as soon as the view updates, and that
            // must not abort the request (it would look like an unreachable server).
            let (data, resp) = try await Task { try await urlSession.data(for: req) }.value
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401, authed, !retried {
                retried = true
                if try await refresh(failedWith: sent) { continue }
                throw AuthError()
            }
            return (data, code)
        }
    }

    private func refresh(failedWith sent: String?) async throws -> Bool {
        try await refreshGate.run {
            // Another request may already have refreshed while we waited.
            if let now = session.accessToken, now != sent { return true }
            guard let rt = session.refreshToken else { return false }
            let body = try enc.encode(["refreshToken": rt])
            let (data, code) = try await raw("POST", url("/auth/refresh"), body: body, authed: false)
            if code == 401 { session.clearTokens(); return false }
            guard (200..<300).contains(code) else { throw HTTPError(code: code) }
            let auth = try dec.decode(AuthResponse.self, from: data)
            session.accessToken = auth.accessToken; session.refreshToken = auth.refreshToken
            return true
        }
    }

    private func text(_ method: String, _ url: URL, body: Data? = nil) async throws -> Data {
        let (data, code) = try await raw(method, url, body: body)
        if code == 401 { throw AuthError() }
        guard (200..<300).contains(code) else { throw HTTPError(code: code) }
        return data
    }

    private func cacheFile(_ key: String) -> URL {
        let hash = Insecure.SHA1.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dataDir.appendingPathComponent(hash + ".json")
    }

    /// Fetches and keeps a copy; answers from that copy when the server can't be reached.
    private func cached<T: Decodable>(_ key: String, _ type: T.Type, fetch: () async throws -> Data) async throws -> T {
        let file = cacheFile(key)
        do {
            let data = try await fetch()
            let value = try dec.decode(T.self, from: data)
            try? data.write(to: file, options: .atomic)
            setOnline(true)
            return value
        } catch let e as AuthError {
            throw e
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch let e as URLError {
            setOnline(false)
            guard let d = try? Data(contentsOf: file) else { throw e }
            return try dec.decode(T.self, from: d)
        }
    }

    // MARK: Auth

    /// A server typed without a scheme is tried over https first, then http (typical for a home server).
    func login(server: String, username: String, password: String) async throws {
        let rawServer = server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidates = rawServer.hasPrefix("http://") || rawServer.hasPrefix("https://") ? [rawServer] : ["https://" + rawServer, "http://" + rawServer]
        var failure: Error = URLError(.cannotConnectToHost)
        for base in candidates {
            guard URL(string: base)?.host != nil else { throw URLError(.badURL) }
            do {
                struct Body: Encodable { let username, password, clientKind, deviceLabel: String }
                let body = try enc.encode(Body(username: username, password: password, clientKind: "native", deviceLabel: "iOS"))
                let (data, code) = try await raw("POST", url("/auth/login", base: base), body: body, authed: false)
                if code == 401 { throw LoginError.wrongCredentials }
                guard (200..<300).contains(code) else { throw HTTPError(code: code) }
                let auth = try dec.decode(AuthResponse.self, from: data)
                session.serverUrl = base
                session.accessToken = auth.accessToken; session.refreshToken = auth.refreshToken
                session.markLoggedIn()
                return
            } catch let e as LoginError { throw e } catch { failure = error }
        }
        throw failure
    }

    func logout() async {
        if let rt = session.refreshToken, let body = try? enc.encode(["refreshToken": rt]) {
            _ = try? await raw("POST", url("/auth/logout"), body: body, authed: false)
        }
        session.clearTokens()
    }

    // MARK: Reads

    private func withPending(_ b: BookCard) -> BookCard {
        var out = b
        for op in outbox.pendingOps() where op.bookId == b.id {
            if op.type == "status", let s = op.status { out.readStatus = StatusInfo(status: s) }
            if op.type == "rating" { out.rating = op.rating.map(Double.init) }
        }
        return out
    }
    private func pending(_ p: BooksPage) -> BooksPage { var p = p; p.items = p.items.map(withPending); return p }

    func books(query: String?, page: Int, size: Int = 40, libraryId: Int? = nil, status: String? = nil) async throws -> BooksPage {
        let q = query?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        var body: [String: Any] = [
            "sort": [["field": q == nil ? "addedAt" : "relevance", "dir": "desc"]],
            "pagination": ["page": page, "size": size],
        ]
        if let q { body["q"] = q }
        if let status {
            body["filter"] = ["type": "group", "join": "AND", "rules": [["type": "rule", "field": "readStatus", "operator": "includesAny", "value": [status]]]]
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        let path = libraryId.map { "/libraries/\($0)/books" } ?? "/books/query"
        let key = "books:\(libraryId.map(String.init) ?? "nil"):\(String(decoding: data, as: UTF8.self))"
        return pending(try await cached(key, BooksPage.self) { try await text("POST", url(path), body: data) })
    }

    func libraries() async -> [Library] {
        (try? await cached("libraries", [Library].self) { try await text("GET", url("/libraries")) }) ?? []
    }

    func shelves(_ shelves: [(id: String, type: String)], limit: Int = 20) async -> [String: [BookCard]] {
        let items = shelves.map { ["id": $0.id, "type": $0.type, "limit": limit] as [String: Any] }
        guard let body = try? JSONSerialization.data(withJSONObject: ["items": items], options: .sortedKeys),
              let r = try? await cached("shelves", ScrollerBatchResponse.self, fetch: { try await text("POST", url("/dashboard/scrollers/batch"), body: body) })
        else { return [:] }
        return Dictionary(r.items.map { ($0.id, $0.books.map(withPending)) }, uniquingKeysWith: { a, _ in a })
    }

    func getProgress(fileId: Int) async -> Double {
        guard let (d, code) = try? await raw("GET", url("/books/files/\(fileId)/progress")), (200..<300).contains(code),
              let p = try? dec.decode(FileProgress.self, from: d) else { return 0 }
        return p.percentage
    }

    func annotations(bookId: Int, fileId: Int) async -> [Annotation]? {
        try? await cached("get:/books/\(bookId)/annotations?readerFileId=\(fileId)", [Annotation].self) {
            try await text("GET", url("/books/\(bookId)/annotations", ["readerFileId": String(fileId)]))
        }
    }

    /// Dashboard widget payloads by widget type; widgets that failed or have no data are left out.
    func widgets(_ types: [String]) async -> [String: [String: Any]] {
        guard let body = try? JSONSerialization.data(withJSONObject: ["widgets": types], options: .sortedKeys) else { return [:] }
        let file = cacheFile("widgets")
        var data: Data?
        do {
            data = try await text("POST", url("/dashboard/widgets/batch"), body: body)
            try? data?.write(to: file, options: .atomic)
            setOnline(true)
        } catch is AuthError {
            return [:]
        } catch let e as URLError where e.code == .cancelled {
            return [:]
        } catch {
            setOnline(false)
            data = try? Data(contentsOf: file)
        }
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [:] }
        var out: [String: [String: Any]] = [:]
        for item in items {
            if let type = item["type"] as? String, let d = item["data"] as? [String: Any] { out[type] = d }
        }
        return out
    }

    // MARK: Browse

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], as type: T.Type) async throws -> T {
        let u = url(path, query)
        return try await cached("get:\(u.path)?\(u.query ?? "")", type) { try await text("GET", u) }
    }

    private func paging(_ query: String?, _ page: Int, size: Int = 50) -> [String: String] {
        var q = ["page": String(page), "size": String(size)]
        if let t = query?.trimmingCharacters(in: .whitespaces).nilIfEmpty { q["q"] = t }
        return q
    }

    func series(query: String?, page: Int) async throws -> SeriesPage { try await get("/series", paging(query, page), as: SeriesPage.self) }
    func authors(query: String?, page: Int) async throws -> AuthorsPage { try await get("/authors", paging(query, page), as: AuthorsPage.self) }
    /// The user's SmartScopes (saved filters); the server returns them all at once.
    func smartScopes() async throws -> [SmartScopeItem] { try await get("/smart-scopes", as: [SmartScopeItem].self) }

    func seriesBooks(id: Int, page: Int) async throws -> BooksPage { pending(try await get("/series/\(id)/books", paging(nil, page), as: BooksPage.self)) }
    func authorBooks(id: Int, page: Int) async throws -> BooksPage { pending(try await get("/authors/\(id)/books", paging(nil, page), as: BooksPage.self)) }
    func smartScopeBooks(id: Int, page: Int) async throws -> BooksPage { pending(try await get("/smart-scopes/\(id)/books", paging(nil, page), as: BooksPage.self)) }

    // MARK: Reading history

    /// A page of finished reads. `year` nil means all time.
    func history(year: Int?, search: String?, offset: Int, limit: Int = 50) async throws -> HistoryPage {
        var q = ["outcomes": "completed,skimmed,abandoned", "sort": "newest", "offset": String(offset), "limit": String(limit)]
        if let year { q["year"] = String(year) }
        if let t = search?.trimmingCharacters(in: .whitespaces).nilIfEmpty { q["search"] = t }
        return try await get("/reading-history", q, as: HistoryPage.self)
    }

    func historySummary(year: Int?) async throws -> HistorySummary {
        try await get("/reading-history/summary", year.map { ["year": String($0)] } ?? [:], as: HistorySummary.self)
    }

    // MARK: Files

    func localFile(_ fileId: Int) -> URL { booksDir.appendingPathComponent("\(fileId).epub") }
    func isOnDevice(_ fileId: Int) -> Bool { fm.fileExists(atPath: localFile(fileId).path) }

    /// Downloads the book file once and returns its path.
    func downloadFile(fileId: Int) async throws -> URL {
        let target = localFile(fileId)
        if isOnDevice(fileId) { return target }
        var req = URLRequest(url: url("/books/files/\(fileId)/serve"))
        if let t = session.accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        setSyncing(true); defer { setSyncing(false) }
        var (tmp, resp) = try await urlSession.download(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401, try await refresh(failedWith: nil) {
            if let t = session.accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            (tmp, resp) = try await urlSession.download(for: req)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HTTPError(code: code) }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: tmp, to: target)
        return target
    }

    func removeDownload(fileId: Int) { try? fm.removeItem(at: localFile(fileId)) }

    func cover(bookId: Int) async -> UIImage? {
        if let i = coverCache.object(forKey: bookId as NSNumber) { return i }
        let file = coverDir.appendingPathComponent("\(bookId).img")
        if let d = try? Data(contentsOf: file), let i = UIImage(data: d) { coverCache.setObject(i, forKey: bookId as NSNumber); return i }
        guard let (d, code) = try? await raw("GET", url("/books/\(bookId)/thumbnail"), counted: false), (200..<300).contains(code),
              let i = UIImage(data: d) else { return nil }
        try? d.write(to: file)
        coverCache.setObject(i, forKey: bookId as NSNumber)
        return i
    }

    // MARK: Outbox delivery

    func send(_ op: Op) async -> Sent {
        let request: (String, URL, Data?)?
        switch op.type {
        case "progress":
            let p = min(max(op.percentage ?? 0, 0), 100)
            request = ("POST", url("/books/files/\(op.fileId ?? 0)/progress"), try? JSONSerialization.data(withJSONObject: ["percentage": p]))
        case "session":
            request = ("POST", url("/books/files/\(op.fileId ?? 0)/sessions"), op.session.flatMap { try? enc.encode($0) })
        case "status":
            request = ("PATCH", url("/books/\(op.bookId ?? 0)/status"), try? enc.encode(["status": op.status ?? ""]))
        case "rating":
            var body: [String: Any] = ["bookIds": [op.bookId ?? 0]]
            body["rating"] = op.rating.map { $0 as Any } ?? NSNull()
            request = ("POST", url("/books/bulk-set-rating"), try? JSONSerialization.data(withJSONObject: body))
        case "ann_create":
            let b: [String: Any] = ["cfi": op.cfi ?? "", "bookFileId": op.fileId ?? 0, "text": op.text ?? "", "color": op.color ?? "yellow", "style": "highlight"]
            request = ("POST", url("/books/\(op.bookId ?? 0)/annotations"), try? JSONSerialization.data(withJSONObject: b))
        case "ann_color":
            request = ("PATCH", url("/books/\(op.bookId ?? 0)/annotations/\(op.annId ?? 0)"), try? enc.encode(["color": op.color ?? "yellow"]))
        case "ann_delete":
            request = ("DELETE", url("/books/\(op.bookId ?? 0)/annotations/\(op.annId ?? 0)"), nil)
        default: request = nil
        }
        guard let (method, url, body) = request else { return Sent(outcome: .drop) }
        do {
            let (data, code) = try await raw(method, url, body: body)
            switch code {
            case 200..<300:
                let created = op.type == "ann_create" ? (try? dec.decode(Annotation.self, from: data))?.id : nil
                return Sent(outcome: .ok, createdId: created)
            case 401, 408, 429, 500...: return Sent(outcome: .retry)
            default: return Sent(outcome: .drop)
            }
        } catch { return Sent(outcome: .retry) }
    }
}

enum LoginError: LocalizedError {
    case wrongCredentials
    var errorDescription: String? { "Wrong username or password" }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
