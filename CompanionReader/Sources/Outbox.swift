import Foundation

enum Outcome { case ok, retry, drop }

/// One change waiting to reach the server. `key` lets a newer change replace an older one.
struct Op: Codable {
    var id: Int
    var type: String            // progress | session | status | rating
    var key: String?
    var bookId: Int?
    var fileId: Int?
    var percentage: Double?
    var session: ReadingSession?
    var status: String?
    var rating: Int?
    var annId: Int?
    var cfi: String?
    var text: String?
    var color: String?
}

struct Sent {
    let outcome: Outcome
    var createdId: Int?
}

private struct OutboxState: Codable { var ops: [Op] = []; var nextId = 1; var idMap: [Int: Int] = [:] }

/// Everything changed while reading (progress, reading time, status, rating) goes here first and is sent
/// whenever the server is reachable. Kept on disk, so it survives the app being closed.
final class Outbox {
    private let url: URL
    private let lock = NSRecursiveLock()
    private var state = OutboxState()
    private let flushGate = AsyncGate()

    init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(OutboxState.self, from: d) { state = s }
    }

    private func persist() { try? JSONEncoder().encode(state).write(to: url, options: .atomic) }
    func pendingOps() -> [Op] { lock.withLock { state.ops } }
    var isEmpty: Bool { lock.withLock { state.ops.isEmpty } }

    private func add(_ type: String, key: String?, _ fill: (inout Op) -> Void) {
        lock.withLock {
            if let key { state.ops.removeAll { $0.key == key } }
            var op = Op(id: state.nextId, type: type, key: key)
            state.nextId += 1
            fill(&op)
            state.ops.append(op)
            persist()
        }
    }

    func progress(fileId: Int, percentage: Double) {
        add("progress", key: "progress:\(fileId)") { $0.fileId = fileId; $0.percentage = percentage }
    }
    func session(fileId: Int, _ s: ReadingSession) {
        add("session", key: "session:\(s.sessionId)") { $0.fileId = fileId; $0.session = s }
    }
    func status(bookId: Int, _ status: String) {
        add("status", key: "status:\(bookId)") { $0.bookId = bookId; $0.status = status }
    }
    func rating(bookId: Int, _ rating: Int?) {
        add("rating", key: "rating:\(bookId)") { $0.bookId = bookId; $0.rating = rating }
    }

    /// Returns the temporary (negative) id the highlight is known by until the server assigns one.
    func createAnnotation(bookId: Int, fileId: Int, cfi: String, text: String, color: String) -> Int {
        lock.withLock {
            let id = state.nextId // the op takes this id, so the temporary annotation id is its negation
            add("ann_create", key: nil) { $0.bookId = bookId; $0.fileId = fileId; $0.cfi = cfi; $0.text = text; $0.color = color }
            return -id
        }
    }

    private func realId(_ annId: Int) -> Int { annId < 0 ? (state.idMap[annId] ?? annId) : annId }

    func recolorAnnotation(bookId: Int, annId: Int, color: String) {
        lock.withLock {
            let id = realId(annId)
            if id < 0 {
                // Not on the server yet: change the colour it will be created with.
                if let i = state.ops.firstIndex(where: { $0.id == -id && $0.type == "ann_create" }) { state.ops[i].color = color; persist() }
            } else {
                add("ann_color", key: "ann_color:\(bookId):\(id)") { $0.bookId = bookId; $0.annId = id; $0.color = color }
            }
        }
    }

    func deleteAnnotation(bookId: Int, annId: Int) {
        lock.withLock {
            let id = realId(annId)
            if id < 0 {
                state.ops.removeAll { $0.id == -id && $0.type == "ann_create" }
                persist()
            } else {
                state.ops.removeAll { $0.key == "ann_color:\(bookId):\(id)" }
                add("ann_delete", key: "ann_delete:\(bookId):\(id)") { $0.bookId = bookId; $0.annId = id }
            }
        }
    }

    /// Sends queued changes oldest first, stopping at the first that can't be delivered. True when the queue is empty.
    func flush(api: ServerAPI) async -> Bool {
        let done = try? await flushGate.run {
            while true {
                guard let op = self.lock.withLock({ self.state.ops.first }) else { return true }
                let sent = await api.send(op)
                if sent.outcome == .retry { return false }
                self.lock.withLock {
                    if sent.outcome == .ok, op.type == "ann_create", let created = sent.createdId { self.state.idMap[-op.id] = created }
                    self.state.ops.removeAll { $0.id == op.id }
                    self.persist()
                }
            }
        }
        return done ?? false
    }
}

/// Serialises async work so two flushes never run at once.
actor AsyncGate {
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func run<T>(_ work: () async throws -> T) async throws -> T {
        if running { await withCheckedContinuation { waiters.append($0) } }
        running = true
        defer {
            running = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await work()
    }
}

/// Decides when reading progress should be queued: every `pagesPerSync` page turns.
struct ProgressSyncCounter {
    let pagesPerSync: Int
    private var since = 0
    private var lastSeen: Double?
    init(pagesPerSync: Int) { self.pagesPerSync = pagesPerSync }

    mutating func onPosition(_ progress: Double, moved: Bool) -> Bool {
        let previous = lastSeen
        lastSeen = progress
        guard moved, let previous, progress != previous else { return false }
        since += 1
        if since < pagesPerSync { return false }
        since = 0
        return true
    }
}
