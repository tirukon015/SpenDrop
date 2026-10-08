import Foundation
import SwiftData

/// In-memory stand-in for the Supabase REST API used by live sync (the 9 record tables, the save RPC, PATCH
/// tombstones). Enforces owner-only access by token like RLS, sets server_updated_at on every write and keeps the
/// RPC's last-writer-wins guard. Thread-safe (expense RPCs run a few at a time).
final class FakeSyncServer: HTTPTransport, @unchecked Sendable {
    struct Logged { let method: String; let path: String; let query: [String: String]; let token: String; let body: Data? }
    private let lock = NSLock()
    var tokens: [String: String] = [:]                    // token -> user id
    var tables: [String: [String: [String: Any]]] = [:]   // table -> id -> row
    var log: [Logged] = []
    var offline = false
    var badIds: Set<String> = []                           // rows the server rejects (400)
    var failNext: [(match: String, status: Int, afterApply: Bool)] = []
    private var tick = 0

    func nextStamp() -> String {
        tick += 1
        return String(format: "2026-10-08T%02d:%02d:%02d.%06d+00:00", 10 + tick / 3600, (tick / 60) % 60, tick % 60, tick)
    }

    func rows(_ table: String, user: String) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return (tables[table] ?? [:]).values.filter { ($0["user_id"] as? String) == user }
    }

    func row(_ table: String, _ id: UUID) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return tables[table]?[id.uuidString.lowercased()]
    }

    /// Simulates a write by another device (Web/Android): stamps server_updated_at.
    func put(_ table: String, user: String, _ row: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        var r = row
        r["user_id"] = user
        r["server_updated_at"] = nextStamp()
        tables[table, default: [:]][(r["id"] as! String)] = r
    }

    var writes: [Logged] { lock.lock(); defer { lock.unlock() }; return log.filter { $0.method != "GET" } }
    func count(_ method: String, _ pathSuffix: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return log.filter { $0.method == method && $0.path.hasSuffix(pathSuffix) }.count
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handle(request)
    }

    private func handle(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        if offline { throw CloudError.offline }
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let token = (request.value(forHTTPHeaderField: "Authorization") ?? "").replacingOccurrences(of: "Bearer ", with: "")
        log.append(Logged(method: method, path: url.path, query: query, token: token, body: request.httpBody))
        guard let user = tokens[token] else { return respond(401, ["message": "JWT expired"]) }
        var afterApplyStatus: Int?
        if let i = failNext.firstIndex(where: { "\(method) \(url.path)".contains($0.match) }) {
            let f = failNext.remove(at: i)
            if f.afterApply { afterApplyStatus = f.status } else { return respond(f.status, ["message": "Injected \(f.status)"]) }
        }
        let table = url.path.replacingOccurrences(of: "/rest/v1/", with: "")
        let result: (Data, HTTPURLResponse)
        switch method {
        case "GET": result = select(table, user: user, query: query)
        case "POST" where table == "rpc/save_expense_with_shares": result = rpc(user: user, body: request.httpBody)
        case "POST": result = upsert(table, user: user, body: request.httpBody)
        case "PATCH": result = patch(table, user: user, query: query, body: request.httpBody)
        default: result = respond(404, [:])
        }
        if let afterApplyStatus { return respond(afterApplyStatus, ["message": "Response lost"]) }
        return result
    }

    private func select(_ table: String, user: String, query: [String: String]) -> (Data, HTTPURLResponse) {
        var list = (tables[table] ?? [:]).values.filter { ($0["user_id"] as? String) == user }
        if let or = query["or"] {
            let parts = or.components(separatedBy: "\"")   // (sua.gt."C",and(sua.eq."C",id.gt.I))
            let cursor = parts.count > 1 ? parts[1] : ""
            let lastId = or.components(separatedBy: "id.gt.").last.map { String($0.dropLast(2)) } ?? ""
            list = list.filter {
                let s = $0["server_updated_at"] as! String
                return s > cursor || (s == cursor && ($0["id"] as! String) > lastId)
            }
        }
        list.sort { ($0["server_updated_at"] as! String, $0["id"] as! String) < ($1["server_updated_at"] as! String, $1["id"] as! String) }
        let limit = Int(query["limit"] ?? "") ?? list.count
        return respondArray(Array(list.prefix(limit)))
    }

    private func upsert(_ table: String, user: String, body: Data?) -> (Data, HTTPURLResponse) {
        guard let rows = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [[String: Any]] else { return respond(400, [:]) }
        if rows.contains(where: { badIds.contains($0["id"] as? String ?? "") }) { return respond(400, ["message": "violates check constraint"]) }
        for var row in rows {
            let id = row["id"] as! String
            if let existing = tables[table]?[id], (existing["user_id"] as? String) != user { return respond(403, ["message": "row-level security"]) }
            row["user_id"] = user
            row["server_updated_at"] = nextStamp()
            tables[table, default: [:]][id] = row
        }
        return respond(201, [:])
    }

    private func rpc(user: String, body: Data?) -> (Data, HTTPURLResponse) {
        guard let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any],
              var expense = json["p_expense"] as? [String: Any], let shares = json["p_shares"] as? [[String: Any]] else { return respond(400, [:]) }
        let id = expense["id"] as! String
        if badIds.contains(id) { return respond(400, ["message": "split shares must add up to the expense amount"]) }
        let updated = CloudJSON.parseDate(expense["updated_at"] as! String)!
        if let existing = tables["expenses"]?[id], let at = CloudJSON.parseDate(existing["updated_at"] as? String ?? ""), at > updated {
            return respond(204, [:])   // a newer version already exists (server LWW)
        }
        if expense["split_rule"] == nil { expense["split_rule"] = tables["expenses"]?[id]?["split_rule"] ?? NSNull() }
        expense["user_id"] = user
        expense["server_updated_at"] = nextStamp()
        tables["expenses", default: [:]][id] = expense
        let keep = Set(shares.map { $0["id"] as! String })
        for (sid, var s) in tables["expense_shares"] ?? [:] where (s["expense_id"] as? String) == id && !keep.contains(sid) && s["deleted_at"] is NSNull {
            s["deleted_at"] = expense["updated_at"]; s["updated_at"] = expense["updated_at"]; s["server_updated_at"] = nextStamp()
            tables["expense_shares"]![sid] = s
        }
        for var s in shares {
            s["expense_id"] = id; s["user_id"] = user; s["updated_at"] = expense["updated_at"]; s["deleted_at"] = NSNull()
            s["server_updated_at"] = nextStamp()
            tables["expense_shares", default: [:]][s["id"] as! String] = s
        }
        return respond(204, [:])
    }

    private func patch(_ table: String, user: String, query: [String: String], body: Data?) -> (Data, HTTPURLResponse) {
        guard let fields = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] else { return respond(400, [:]) }
        let key = query["id"] != nil ? "id" : "expense_id"
        let ids = Set((query[key] ?? "").dropFirst(4).dropLast().split(separator: ",").map(String.init))
        let before = query["updated_at"].flatMap { CloudJSON.parseDate(String($0.dropFirst(3))) }
        for (rid, var row) in tables[table] ?? [:] where (row["user_id"] as? String) == user && ids.contains(row[key] as? String ?? "") {
            if query["deleted_at"] == "is.null", !(row["deleted_at"] is NSNull) { continue }
            if let before, let at = CloudJSON.parseDate(row["updated_at"] as? String ?? ""), at >= before { continue }
            for (k, v) in fields { row[k] = v }
            row["server_updated_at"] = nextStamp()
            tables[table]![rid] = row
        }
        return respond(204, [:])
    }

    private func respond(_ status: Int, _ body: [String: Any]) -> (Data, HTTPURLResponse) {
        ((try? JSONSerialization.data(withJSONObject: body)) ?? Data(),
         HTTPURLResponse(url: URL(string: "https://fake.supabase.co")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func respondArray(_ body: [[String: Any]]) -> (Data, HTTPURLResponse) {
        ((try? JSONSerialization.data(withJSONObject: body)) ?? Data(),
         HTTPURLResponse(url: URL(string: "https://fake.supabase.co")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class FakeSyncAuth: SyncAuthProviding, @unchecked Sendable {
    var current: SyncSession?
    var refreshedToken: String?
    var refreshCount = 0
    init(_ session: SyncSession?) { current = session }
    func session(forceRefresh: Bool) async throws -> SyncSession? {
        if forceRefresh {
            refreshCount += 1
            if let token = refreshedToken, let user = current?.userId { current = SyncSession(userId: user, token: token) }
        }
        return current
    }
}

/// Collects what the recorder saw (tests enqueue explicitly so they can await it).
final class ChangeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SyncChange] = []
    func append(_ c: [SyncChange]) { lock.lock(); items += c; lock.unlock() }
    func take() -> [SyncChange] { lock.lock(); defer { items = []; lock.unlock() }; return items }
}

/// Live sync tests. `--run-sync-tests`
@MainActor
public struct SyncTests {
    static let config = SupabaseConfig(url: URL(string: "https://fake.supabase.co")!, anonKey: "anon")
    static let userA = "aaaaaaaa-0000-0000-0000-00000000000a"
    static let userB = "bbbbbbbb-0000-0000-0000-00000000000b"

    @MainActor
    final class Harness {
        let container: ModelContainer
        let outboxContainer: ModelContainer
        let server: FakeSyncServer
        let auth: FakeSyncAuth
        let settings: SyncSettings
        let box: ChangeBox
        let recorder: SyncChangeRecorder
        let engine: SyncEngine
        let ui: ModelContext

        init(user: String = SyncTests.userA, owner: String? = SyncTests.userA, outboxURL: URL? = nil) {
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config])
            let outboxContainer = try! SyncOutboxStore.makeContainer(url: outboxURL, inMemory: outboxURL == nil)
            let server = FakeSyncServer()
            server.tokens = ["token-a": SyncTests.userA, "token-b": SyncTests.userB]
            let auth = FakeSyncAuth(SyncSession(userId: user, token: user == SyncTests.userA ? "token-a" : "token-b"))
            let settings = SyncSettings(defaults: UserDefaults(suiteName: "SpenDropSyncTests-\(UUID().uuidString)")!)
            settings.ownerUserId = owner
            let box = ChangeBox()
            let recorder = SyncChangeRecorder(container: container, shouldRecord: { true }) { box.append($0) }
            recorder.start()
            self.engine = SyncEngine(container: container, outboxContainer: outboxContainer, transport: server, config: SyncTests.config,
                                     auth: auth, settings: settings, recorder: recorder, jitter: { 1 })
            self.container = container
            self.outboxContainer = outboxContainer
            self.server = server
            self.auth = auth
            self.settings = settings
            self.box = box
            self.recorder = recorder
            let ui = ModelContext(container)
            ui.autosaveEnabled = false
            self.ui = ui
        }

        /// Save like the app does, then enqueue what the recorder captured (the app does this on a utility task).
        func save() async {
            try? ui.save()
            await engine.enqueue(box.take(), userId: settings.ownerUserId ?? SyncTests.userA)
        }

        func fresh() -> ModelContext { ModelContext(container) }
        func ops() async -> [(table: String, id: UUID, op: String, status: String, retry: Int)] { await engine.operations() }
        func finish() { recorder.stop() }
    }

    static func expenseRow(_ id: UUID, amountMinor: Int, merchant: String, updatedAt: Date, deleted: Date? = nil) -> [String: Any] {
        ["id": id.uuidString.lowercased(), "amount_minor": amountMinor, "currency": "RM", "merchant": merchant, "category": "Food",
         "payment_channel": "CARD", "funding_account": "Maybank", "funding_instrument": NSNull(), "account_id": NSNull(),
         "payment_source": "Unknown", "date": SyncDates.string(updatedAt), "notes": NSNull(), "transaction_reference": NSNull(),
         "source_type": "manual", "paid_by_me": true, "payer_id": NSNull(), "payer_name_snapshot": NSNull(), "split_method": NSNull(),
         "receipt_path": NSNull(), "is_sample_data": false, "created_at": SyncDates.string(updatedAt),
         "updated_at": SyncDates.string(updatedAt), "deleted_at": deleted.map { SyncDates.string($0) as Any } ?? NSNull()]
    }

    static func localExpense(_ ctx: ModelContext, _ id: UUID) -> Expense? {
        try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
    }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Sync") { results.append($0) }

        // 1. Local save works offline and creates exactly one outbox op; nothing touches the network.
        do {
            let h = Harness()
            h.server.offline = true
            let e = Expense(amount: 12.5, merchant: "Kopi")
            h.ui.insert(e)
            await h.save()
            let ops = await h.ops()
            t.check("Offline save is stored locally", localExpense(h.fresh(), e.id) != nil, expected: "expense saved", actual: localExpense(h.fresh(), e.id) == nil ? "missing" : "saved")
            t.check("Offline save creates one CREATE op", ops.count == 1 && ops[0].op == "create" && ops[0].table == "expenses",
                    expected: "1 create on expenses", actual: "\(ops.map { "\($0.op) \($0.table)" })")
            let result = await h.engine.sync(full: false)
            let after = await h.ops()
            t.check("Offline sync keeps the op pending (no retry burned)", result.snapshot.state == .offline && after.count == 1 && after[0].retry == 0,
                    expected: "offline, 1 pending, retry 0", actual: "\(result.snapshot.state), \(after.count), retry \(after.first?.retry ?? -1)")
            // 4. Reconnect: the next sync pushes it.
            h.server.offline = false
            _ = await h.engine.sync(full: false)
            let pushed = await h.ops()
            t.check("Back online: the queued save is pushed", pushed.isEmpty && h.server.row("expenses", e.id)?["amount_minor"] as? Int == 1250,
                    expected: "0 ops, server 1250", actual: "\(pushed.count) ops, server \(h.server.row("expenses", e.id)?["amount_minor"] ?? "none")")
            h.finish()
        }

        // 2. The outbox survives a restart (new container on the same store file).
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropSyncTest-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("SpenDropSync.store")
            var h: Harness? = Harness(outboxURL: url)
            let id = UUID()
            await h!.engine.enqueue([SyncChange(table: .expenses, id: id, op: .create, changedAt: Date())], userId: userA)
            h!.finish()
            h = nil
            let reopened = try? SyncOutboxStore.makeContainer(url: url)
            let ops = (try? ModelContext(reopened!).fetch(FetchDescriptor<SyncOperation>())) ?? []
            t.check("Outbox survives restart", ops.count == 1 && ops[0].entityId == id && ops[0].operation == .create,
                    expected: "1 create op after reopening", actual: "\(ops.count) ops")
            try? FileManager.default.removeItem(at: dir)
        }

        // 3 + 6. Rapid CREATE + UPDATE×3 → exactly one RPC with the final state; success removes the op.
        do {
            let h = Harness()
            let e = Expense(amount: 10, merchant: "Burst")
            h.ui.insert(e)
            await h.save()
            for amount in [11.0, 12.0, 13.45] { e.amount = amount; e.updatedAt = Date(); await h.save() }
            let queued = await h.ops()
            _ = await h.engine.sync(full: false)
            let rpcs = h.server.count("POST", "rpc/save_expense_with_shares")
            t.check("Burst coalesces to one op", queued.count == 1 && queued[0].op == "create", expected: "1 create", actual: "\(queued.map(\.op))")
            t.check("Burst sends exactly one upsert with the final state", rpcs == 1 && h.server.row("expenses", e.id)?["amount_minor"] as? Int == 1345,
                    expected: "1 RPC, 1345", actual: "\(rpcs) RPC, \(h.server.row("expenses", e.id)?["amount_minor"] ?? "none")")
            let ops = await h.ops()
            t.check("Successful push removes the op", ops.isEmpty, expected: "0 ops", actual: "\(ops.count)")
            h.finish()
        }

        // 5. Retried op is idempotent: response lost after the server applied it → retry → still one row, same id.
        do {
            let h = Harness()
            let e = Expense(amount: 5, merchant: "Retry")
            h.ui.insert(e)
            await h.save()
            h.server.failNext = [("rpc/save_expense_with_shares", 503, true)]
            _ = await h.engine.sync(full: false)
            let afterFail = await h.ops()
            await h.engine.makeAllDue()
            _ = await h.engine.sync(full: false)
            let bodies = h.server.log.filter { $0.path.hasSuffix("save_expense_with_shares") }.compactMap { $0.body }
                .compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }.compactMap { ($0["p_expense"] as? [String: Any])?["id"] as? String }
            let rows = h.server.rows("expenses", user: userA).count
            t.check("5xx → retried with backoff", afterFail.count == 1 && afterFail[0].retry == 1, expected: "1 op, retry 1", actual: "\(afterFail.count), retry \(afterFail.first?.retry ?? -1)")
            t.check("Retry is idempotent (same id, one server row)", bodies.count == 2 && Set(bodies).count == 1 && rows == 1,
                    expected: "2 sends of 1 id, 1 row", actual: "\(bodies.count) sends of \(Set(bodies).count) id, \(rows) rows")
            h.finish()
        }

        // 7. CREATE then DELETE before sync: dropped locally, nothing is sent.
        do {
            let h = Harness()
            let e = Expense(amount: 3, merchant: "Oops")
            h.ui.insert(e)
            await h.save()
            h.ui.delete(e)
            await h.save()
            let ops = await h.ops()
            _ = await h.engine.sync(full: false)
            t.check("Create+delete before sync drops both", ops.isEmpty && h.server.writes.isEmpty,
                    expected: "0 ops, 0 writes", actual: "\(ops.count) ops, \(h.server.writes.count) writes")
            h.finish()
        }

        // 9b. Delete of a synced record → tombstone (deleted_at), shares too; never a hard delete.
        do {
            let h = Harness()
            let e = Expense(amount: 20, merchant: "Shared")
            h.ui.insert(e)
            let me = ExpenseShare(expense: e, isMe: true, nameSnapshot: "Me", amountMinor: 1000, sortIndex: 0)
            let other = ExpenseShare(expense: e, nameSnapshot: "Ali", amountMinor: 1000, sortIndex: 1)
            h.ui.insert(me); h.ui.insert(other)
            e.splitMethodRaw = "equal"
            await h.save()
            _ = await h.engine.sync(full: false)
            let shares = h.server.rows("expense_shares", user: userA)
            t.check("Expense with split goes through the RPC with its shares", shares.count == 2 && shares.reduce(0) { $0 + ($1["amount_minor"] as? Int ?? 0) } == 2000,
                    expected: "2 shares = 2000", actual: "\(shares.count) shares")
            h.ui.delete(e)
            await h.save()
            _ = await h.engine.sync(full: false)
            let row = h.server.row("expenses", e.id)
            let liveShares = h.server.rows("expense_shares", user: userA).filter { $0["deleted_at"] is NSNull }
            t.check("Delete is sent as a tombstone", row?["deleted_at"] is String && liveShares.isEmpty,
                    expected: "deleted_at set, 0 live shares", actual: "deleted_at \(row?["deleted_at"] ?? "nil"), \(liveShares.count) live shares")
            h.finish()
        }

        // 8. Conflict: the server copy is newer → it's applied locally, the local op is dropped, nothing lost.
        do {
            let h = Harness()
            let e = Expense(amount: 10, merchant: "Conflict")
            h.ui.insert(e)
            await h.save()
            _ = await h.engine.sync(full: true)
            e.amount = 20; e.updatedAt = Date()
            await h.save()
            h.server.put("expenses", user: userA, expenseRow(e.id, amountMinor: 9900, merchant: "Edited on Web", updatedAt: Date().addingTimeInterval(60)))
            let result = await h.engine.sync(full: false)
            let local = localExpense(h.fresh(), e.id)
            t.check("Newer server copy wins locally", local?.amount == 99 && local?.merchant == "Edited on Web",
                    expected: "99, Edited on Web", actual: "\(local?.amount ?? -1), \(local?.merchant ?? "nil")")
            t.check("Server keeps the newer copy; conflict counted", h.server.row("expenses", e.id)?["amount_minor"] as? Int == 9900 && result.snapshot.conflicts == 1,
                    expected: "server 9900, 1 conflict", actual: "server \(h.server.row("expenses", e.id)?["amount_minor"] ?? "nil"), \(result.snapshot.conflicts)")
            h.finish()
        }

        // 14. A pending local edit is not clobbered by an older server row; it is pushed.
        do {
            let h = Harness()
            let e = Expense(amount: 10, merchant: "Mine")
            h.ui.insert(e)
            await h.save()
            _ = await h.engine.sync(full: true)
            e.amount = 42; e.updatedAt = Date()
            await h.save()
            h.server.put("expenses", user: userA, expenseRow(e.id, amountMinor: 100, merchant: "Old web edit", updatedAt: Date().addingTimeInterval(-3600)))
            _ = await h.engine.sync(full: true)
            let local = localExpense(h.fresh(), e.id)
            t.check("Pull keeps the pending local edit", local?.amount == 42 && local?.merchant == "Mine", expected: "42, Mine", actual: "\(local?.amount ?? -1), \(local?.merchant ?? "nil")")
            t.check("…and pushes it over the older server row", h.server.row("expenses", e.id)?["amount_minor"] as? Int == 4200,
                    expected: "server 4200", actual: "server \(h.server.row("expenses", e.id)?["amount_minor"] ?? "nil")")
            h.finish()
        }

        // 9. 401 → refresh once and retry; still 401 → pause, ops kept, no loop.
        do {
            let h = Harness()
            h.auth.current = SyncSession(userId: userA, token: "expired")
            h.auth.refreshedToken = "token-a"
            let a = Account(name: "Maybank", type: .bank)
            h.ui.insert(a)
            await h.save()
            _ = await h.engine.sync(full: false)
            let ops = await h.ops()
            t.check("401 → token refreshed once, request retried", h.auth.refreshCount == 1 && ops.isEmpty && h.server.row("accounts", a.id) != nil,
                    expected: "1 refresh, pushed", actual: "\(h.auth.refreshCount) refresh, \(ops.count) ops")
            h.auth.current = SyncSession(userId: userA, token: "revoked")
            h.auth.refreshedToken = "still-bad"
            a.name = "Maybank 2"
            await h.save()
            let before = h.server.log.count
            let result = await h.engine.sync(full: false)
            let kept = await h.ops()
            t.check("Persistent 401 pauses sync and keeps the op", result.snapshot.state == .authRequired && kept.count == 1 && h.server.log.count - before <= 3,
                    expected: "authRequired, 1 op, ≤3 requests", actual: "\(result.snapshot.state), \(kept.count) op, \(h.server.log.count - before) requests")
            h.finish()
        }

        // 10. 4xx validation → failed, not retried forever; a bad row doesn't block the others; local data kept.
        do {
            let h = Harness()
            let e = Expense(amount: 7, merchant: "Rejected")
            h.ui.insert(e)
            let accounts = (0..<3).map { Account(name: "Acc \($0)") }
            accounts.forEach { h.ui.insert($0) }
            await h.save()
            h.server.badIds = [e.id.uuidString.lowercased(), accounts[1].id.uuidString.lowercased()]
            _ = await h.engine.sync(full: false)
            let rpcBefore = h.server.count("POST", "rpc/save_expense_with_shares")
            await h.engine.makeAllDue()
            let result = await h.engine.sync(full: false)
            let rpcAfter = h.server.count("POST", "rpc/save_expense_with_shares")
            let ops = await h.ops()
            t.check("4xx marks the op failed and doesn't loop", rpcBefore == 1 && rpcAfter == 1 && ops.filter { $0.status == "failed" }.count == 2 && result.snapshot.state == .failed,
                    expected: "1 RPC total, 2 failed", actual: "\(rpcBefore)→\(rpcAfter) RPC, \(ops.map(\.status)), \(result.snapshot.state)")
            t.check("A bad row doesn't block the rest of its batch", h.server.row("accounts", accounts[0].id) != nil && h.server.row("accounts", accounts[2].id) != nil && h.server.row("accounts", accounts[1].id) == nil,
                    expected: "2 of 3 accounts uploaded", actual: "\(h.server.rows("accounts", user: userA).count)")
            t.check("Rejected record stays on the iPhone", localExpense(h.fresh(), e.id) != nil, expected: "kept", actual: localExpense(h.fresh(), e.id) == nil ? "missing" : "kept")
            h.finish()
        }

        // 11. User switch isolation: A's ops are never sent with B's token; B's ops never with A's.
        do {
            let h = Harness(user: userB, owner: userA)
            let e = Expense(amount: 9, merchant: "Owned by A")
            h.ui.insert(e)
            await h.save()   // recorded for the owner (A)
            let result = await h.engine.sync(full: true)
            let ops = await h.ops()
            t.check("Signed in as B: A's queue is held, nothing sent", result.snapshot.state == .otherAccount && h.server.log.isEmpty && ops.count == 1,
                    expected: "otherAccount, 0 requests, 1 op kept", actual: "\(result.snapshot.state), \(h.server.log.count) requests, \(ops.count) ops")
            h.auth.current = SyncSession(userId: userA, token: "token-a")
            await h.engine.enqueue([SyncChange(table: .accounts, id: UUID(), op: .create, changedAt: Date())], userId: userB)
            _ = await h.engine.sync(full: false)
            let left = await h.ops()
            let tokens = Set(h.server.log.map(\.token))
            t.check("Back as A: only A's ops are sent, only with A's token", tokens == ["token-a"] && h.server.rows("expenses", user: userA).count == 1 && left.count == 1 && h.server.rows("accounts", user: userA).isEmpty,
                    expected: "token-a only, B's op untouched", actual: "\(tokens), \(left.count) left")
            h.finish()
        }

        // 12. Pull: remote changes incl. tombstones, paginated (1203 rows → 3 pages), applied in the background.
        do {
            let h = Harness()
            let base = Date().addingTimeInterval(-7200)
            var ids: [UUID] = []
            for i in 0..<1203 {
                let id = UUID()
                ids.append(id)
                h.server.put("expenses", user: userA, expenseRow(id, amountMinor: 100 + i, merchant: "Web \(i)", updatedAt: base))
            }
            h.server.put("expenses", user: userB, expenseRow(UUID(), amountMinor: 1, merchant: "Someone else", updatedAt: base))
            let personId = UUID()
            h.server.put("people", user: userA, ["id": personId.uuidString.lowercased(), "name": "Siti", "notes": NSNull(), "is_frequent": true,
                                                 "is_archived": false, "created_at": SyncDates.string(base), "updated_at": SyncDates.string(base), "deleted_at": NSNull()])
            _ = await h.engine.sync(full: true)
            let pages = h.server.log.filter { $0.method == "GET" && $0.path.hasSuffix("/expenses") }.count
            let count = TestKit.count(Expense.self, in: h.fresh())
            let people = TestKit.fetch(PayBookProfile.self, in: h.fresh())
            t.check("Pull is paginated and complete", count == 1203 && pages == 3, expected: "1203 expenses in 3 pages (500+500+203)", actual: "\(count) in \(pages) requests")
            t.check("Pulled person applied", people.count == 1 && people[0].name == "Siti" && people[0].isFrequent, expected: "Siti", actual: "\(people.map(\.name))")
            for id in ids.prefix(2) { h.server.put("expenses", user: userA, expenseRow(id, amountMinor: 100, merchant: "x", updatedAt: Date(), deleted: Date())) }
            h.server.put("expenses", user: userA, expenseRow(UUID(), amountMinor: 1, merchant: "never here", updatedAt: Date(), deleted: Date()))
            let before = h.server.log.count
            _ = await h.engine.sync(full: true)
            let afterCount = TestKit.count(Expense.self, in: h.fresh())
            let gets = h.server.log[before...].filter { $0.path.hasSuffix("/expenses") }.count
            t.check("Tombstones delete locally; unknown tombstone ignored; only new rows fetched", afterCount == 1201 && gets == 1,
                    expected: "1201, 1 request", actual: "\(afterCount), \(gets) requests")
            let echoed = h.box.take().count
            t.check("Applying pulled rows records no local changes (no echo)", echoed == 0, expected: "0", actual: "\(echoed)")
            h.finish()
        }

        // Own echo: a pushed record coming back on the next pull doesn't rewrite local-only data.
        do {
            let h = Harness()
            let long = String(repeating: "n", count: 5000)
            let e = Expense(amount: 8, merchant: "Echo", notes: long)
            h.ui.insert(e)
            await h.save()
            _ = await h.engine.sync(full: false)
            h.server.put("expenses", user: userA, h.server.row("expenses", e.id)!)   // re-stamped, same updated_at
            _ = await h.engine.sync(full: true)
            let local = localExpense(h.fresh(), e.id)
            t.check("Own echo is skipped (local 5000-char note kept; cloud copy capped at 4000)",
                    local?.notes?.count == 5000 && (h.server.row("expenses", e.id)?["notes"] as? String)?.count == 4000,
                    expected: "5000 local / 4000 cloud", actual: "\(local?.notes?.count ?? -1) / \((h.server.row("expenses", e.id)?["notes"] as? String)?.count ?? -1)")
            h.finish()
        }

        // Mass delete is held until confirmed.
        do {
            let h = Harness()
            let accounts = (0..<(SyncChangeRecorder.massDeleteThreshold + 1)).map { Account(name: "A\($0)") }
            accounts.forEach { h.ui.insert($0) }
            await h.save()
            _ = await h.engine.sync(full: false)
            accounts.forEach { h.ui.delete($0) }
            await h.save()
            let result = await h.engine.sync(full: false)
            let patchesBefore = h.server.count("PATCH", "/accounts")
            await h.engine.releaseHeld(userId: userA)
            _ = await h.engine.sync(full: false)
            let tombstoned = h.server.rows("accounts", user: userA).filter { $0["deleted_at"] is String }.count
            t.check("Mass delete held (not sent) until confirmed", result.snapshot.held == accounts.count && patchesBefore == 0 && tombstoned == accounts.count,
                    expected: "\(accounts.count) held, 0 PATCH, then \(accounts.count) tombstones", actual: "\(result.snapshot.held) held, \(patchesBefore) PATCH, \(tombstoned) tombstones")
            h.finish()
        }

        // Bootstrap: existing local data queued once (sample data excluded).
        do {
            let h = Harness()
            h.ui.insert(Expense(amount: 1, merchant: "Old 1"))
            h.ui.insert(Expense(amount: 2, merchant: "Old 2"))
            h.ui.insert(Expense(amount: 3, merchant: "Demo", isSampleData: true))
            h.ui.insert(Account(name: "Cash", type: .cash))
            try? h.ui.save()
            _ = h.box.take()
            await h.engine.bootstrap(userId: userA)
            let ops = await h.ops()
            _ = await h.engine.sync(full: true)
            t.check("Bootstrap queues existing records, skips sample data", ops.count == 3 && h.server.rows("expenses", user: userA).count == 2,
                    expected: "3 ops, 2 expenses uploaded", actual: "\(ops.count) ops, \(h.server.rows("expenses", user: userA).count) uploaded")
            h.finish()
        }

        // Coordinator: reconnect triggers a sync (no polling).
        do {
            let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema,
                                                configurations: [ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)])
            let server = FakeSyncServer()
            server.tokens = ["token-a": userA]
            let defaults = UserDefaults(suiteName: "SpenDropSyncTests-\(UUID().uuidString)")!
            let coordinator = SyncCoordinator(container: container, outboxContainer: try! SyncOutboxStore.makeContainer(inMemory: true),
                                              transport: server, config: config, auth: nil,
                                              authProvider: FakeSyncAuth(SyncSession(userId: userA, token: "token-a")), defaults: defaults)
            coordinator.settings.ownerUserId = userA
            coordinator.networkChanged(online: false)
            let id = UUID()
            await coordinator.engine.enqueue([SyncChange(table: .accounts, id: id, op: .create, changedAt: Date())], userId: userA)
            let ctx = ModelContext(container)
            ctx.insert(Account(id: id, name: "Touch 'n Go", type: .eWallet))
            try? ctx.save()
            coordinator.networkChanged(online: true)
            for _ in 0..<250 where server.row("accounts", id) == nil { try? await Task.sleep(for: .milliseconds(20)) }
            t.check("Reconnect triggers one sync", server.row("accounts", id) != nil, expected: "pushed after reconnect", actual: server.row("accounts", id) == nil ? "not pushed" : "pushed")
            coordinator.recorder.stop()
        }

        // Benchmark: save latency with sync on vs off (the save never includes network), and requests for a burst.
        do {
            func medianSave(recording: Bool) async -> (Double, Int) {
                let h = Harness()
                if !recording { h.recorder.stop() }
                var times: [Double] = []
                for i in 0..<100 {
                    h.ui.insert(Expense(amount: Double(i + 1), merchant: "Bench \(i)"))
                    let start = DispatchTime.now().uptimeNanoseconds
                    try? h.ui.save()
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                }
                let requests = h.server.log.count
                await h.engine.enqueue(h.box.take(), userId: userA)
                h.finish()
                return (times.sorted()[times.count / 2], requests)
            }
            let (off, _) = await medianSave(recording: false)
            let (on, requestsDuringSaves) = await medianSave(recording: true)
            t.check("Save latency with sync on stays local (no network in save)", requestsDuringSaves == 0 && on < 10,
                    expected: "0 requests, median < 10 ms", actual: String(format: "median %.3f ms on vs %.3f ms off, %d requests", on, off, requestsDuringSaves))

            let h = Harness()
            let expenses = (0..<5).map { Expense(amount: Double($0 + 1), merchant: "Burst \($0)") }
            expenses.forEach { h.ui.insert($0) }
            await h.save()
            for round in 0..<4 { for e in expenses { e.amount += 1; e.notes = "edit \(round)"; e.updatedAt = Date() }; await h.save() }
            _ = await h.engine.sync(full: false)
            let writes = h.server.writes.count
            let total = h.server.log.count
            t.check("Burst of 25 saves on 5 expenses → 5 upserts", writes == 5,
                    expected: "5 writes", actual: "\(writes) writes, \(total) requests total (incl. \(total - writes) pull GETs)")
            h.finish()
        }

        return results
    }
}
