import Foundation
import SwiftData

/// What the status line shows. Produced by the engine after each step; the UI model copies it only on change.
public struct SyncSnapshot: Sendable, Equatable {
    public enum State: String, Sendable {
        case off, synced, pending, syncing, offline, failed, conflict, authRequired, otherAccount
    }
    public var state: State = .off
    public var pending = 0
    public var failed = 0
    public var held = 0
    public var conflicts = 0
    public var lastSyncDate: Date?
    public var lastError: String?
}

public struct SyncCycleResult: Sendable {
    public let snapshot: SyncSnapshot
    /// Earliest time a backed-off op becomes due (the coordinator sets one timer for it).
    public let nextWake: Date?
}

enum SyncFailure: Error, Equatable {
    case offline
    case unauthorized
    case permanent(Int, String)
    case transient(Int, String)
}

extension Array {
    func syncChunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// The background sync engine (never on the main actor). It owns:
/// - a ModelContext on the user's main store (reads records to push, applies pulled rows; excluded from recording),
/// - a ModelContext on the outbox store (operations, cursors, record meta).
/// One cycle runs at a time; requests during a cycle collapse into one follow-up cycle.
public actor SyncEngine: ModelActor {
    nonisolated public let modelExecutor: any ModelExecutor
    nonisolated public let modelContainer: ModelContainer

    public static let pageSize = 500
    public static let chunkSize = 100
    public static let rpcConcurrency = 4
    public static let maxBackoff: TimeInterval = 15 * 60
    /// After a push, the other tables are pulled too, at most this often (Web/Android edits arrive without realtime).
    public static let fullPullInterval: TimeInterval = 60

    private let outbox: ModelContext
    private let transport: HTTPTransport
    private let config: SupabaseConfig
    private let auth: SyncAuthProviding
    public let settings: SyncSettings
    private let clock: @Sendable () -> Date
    private let jitter: @Sendable () -> Double

    private var running = false
    private var rerun = false
    private var rerunFull = false
    private var token = ""
    private var userId = ""
    private var sampleIDs: Set<UUID> = []
    private var conflictsTotal = 0
    private var conflictsThisCycle = 0
    private var lastError: String?
    /// Requests sent (for tests and the benchmark).
    public private(set) var requestCount = 0

    public init(container: ModelContainer, outboxContainer: ModelContainer, transport: HTTPTransport, config: SupabaseConfig,
                auth: SyncAuthProviding, settings: SyncSettings, recorder: SyncChangeRecorder? = nil,
                clock: @escaping @Sendable () -> Date = Date.init,
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        recorder?.exclude(context)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = container
        let outboxContext = ModelContext(outboxContainer)
        outboxContext.autosaveEnabled = false
        self.outbox = outboxContext
        self.transport = transport
        self.config = config
        self.auth = auth
        self.settings = settings
        self.clock = clock
        self.jitter = jitter
    }

    // MARK: - Outbox

    /// Persists local changes for `userId`, coalesced per record. Cheap; never touches the network.
    public func enqueue(_ changes: [SyncChange], userId: String) {
        let now = clock()
        for chunk in changes.syncChunks(of: 200) {
            let keys = chunk.map { SyncOperation.key(userId: userId, table: $0.table, id: $0.id) }
            var existing = Dictionary(((try? outbox.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { keys.contains($0.key) }))) ?? [])
                .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            for change in chunk {
                let key = SyncOperation.key(userId: userId, table: change.table, id: change.id)
                if let op = existing[key] {
                    if change.op == .delete {
                        if op.operation == .create && !op.attempted {
                            // Created and deleted before the server ever saw it: nothing to send.
                            outbox.delete(op)
                            existing[key] = nil
                            continue
                        }
                        op.operationRaw = SyncOpKind.delete.rawValue
                        op.statusRaw = change.held ? "held" : "pending"
                    } else {
                        if op.operation == .delete { op.operationRaw = SyncOpKind.update.rawValue }
                        op.statusRaw = "pending"
                    }
                    op.changedAt = max(op.changedAt, change.changedAt)
                    op.retryCount = 0
                    op.nextAttemptAt = now
                    op.lastError = nil
                } else {
                    let op = SyncOperation(userId: userId, table: change.table, entityId: change.id, operation: change.op,
                                           status: change.held && change.op == .delete ? "held" : "pending",
                                           changedAt: change.changedAt, now: now)
                    outbox.insert(op)
                    existing[key] = op
                }
            }
        }
        try? outbox.save()
    }

    /// First sync of this iPhone for `userId`: every live local record is queued once (ids only, in chunks), with
    /// its own edit time so a newer copy already in the cloud still wins.
    public func bootstrap(userId: String) {
        let ctx = modelContext
        let sample = SyncFetch.sampleIDs(ctx)
        var changes: [SyncChange] = []
        func flush() { enqueue(changes, userId: userId); changes.removeAll(keepingCapacity: true) }
        func page<T: PersistentModel>(_ type: T.Type, _ make: (T) -> SyncChange?) {
            var offset = 0
            while true {
                var d = FetchDescriptor<T>()
                d.fetchLimit = 500
                d.fetchOffset = offset
                let items = (try? ctx.fetch(d)) ?? []
                for item in items { if let c = make(item) { changes.append(c) } }
                flush()
                if items.count < 500 { break }
                offset += 500
            }
        }
        page(Account.self) { sample.contains($0.id) ? nil : SyncChange(table: .accounts, id: $0.id, op: .update, changedAt: $0.createdAt) }
        page(PayBookProfile.self) { sample.contains($0.id) ? nil : SyncChange(table: .people, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        page(PayBookPaymentMethod.self) { sample.contains($0.id) ? nil : SyncChange(table: .personPaymentMethods, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        page(Expense.self) { ($0.isSampleData || sample.contains($0.id)) ? nil : SyncChange(table: .expenses, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        page(MoneyMovement.self) { sample.contains($0.id) ? nil : SyncChange(table: .moneyMovements, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        page(SettlementAllocation.self) { sample.contains($0.id) ? nil : SyncChange(table: .settlementAllocations, id: $0.id, op: .update, changedAt: $0.createdAt) }
        page(ClassificationRule.self) { SyncChange(table: .classificationRules, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        page(ChannelRule.self) { SyncChange(table: .channelRules, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        modelContext.rollback()
    }

    /// The Share Extension saves in another process (no recorder there): queue what it changed since `since`.
    public func catchUp(userId: String, since: Date) {
        let ctx = modelContext
        var changes: [SyncChange] = []
        let expenses = (try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.updatedAt > since || $0.createdAt > since }))) ?? []
        changes += expenses.filter { !$0.isSampleData }.map { SyncChange(table: .expenses, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        let movements = (try? ctx.fetch(FetchDescriptor<MoneyMovement>(predicate: #Predicate { $0.updatedAt > since || $0.createdAt > since }))) ?? []
        changes += movements.map { SyncChange(table: .moneyMovements, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.createdAt > since }))) ?? []
        changes += accounts.map { SyncChange(table: .accounts, id: $0.id, op: .update, changedAt: $0.createdAt) }
        let rules = (try? ctx.fetch(FetchDescriptor<ClassificationRule>(predicate: #Predicate { $0.updatedAt > since }))) ?? []
        changes += rules.map { SyncChange(table: .classificationRules, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        let channelRules = (try? ctx.fetch(FetchDescriptor<ChannelRule>(predicate: #Predicate { $0.updatedAt > since }))) ?? []
        changes += channelRules.map { SyncChange(table: .channelRules, id: $0.id, op: .update, changedAt: $0.updatedAt) }
        if !changes.isEmpty { enqueue(changes, userId: userId) }
    }

    /// "Retry": failed ops become pending again (once; they fail again if the record still can't be uploaded).
    public func retryFailed(userId: String) {
        let ops = (try? outbox.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "failed" }))) ?? []
        for op in ops { op.statusRaw = "pending"; op.nextAttemptAt = clock(); op.retryCount = 0 }
        try? outbox.save()
    }

    /// The user confirmed a mass delete: send the held tombstones.
    public func releaseHeld(userId: String) {
        let ops = (try? outbox.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "held" }))) ?? []
        for op in ops { op.statusRaw = "pending"; op.nextAttemptAt = clock() }
        try? outbox.save()
    }

    /// The cloud account was deleted: its queue and cursors are meaningless (local data is untouched).
    public func forget(userId: String) {
        let ops = (try? outbox.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId }))) ?? []
        ops.forEach(outbox.delete)
        let prefix = userId + "|"
        let cursors = (try? outbox.fetch(FetchDescriptor<SyncCursor>(predicate: #Predicate { $0.key.starts(with: prefix) }))) ?? []
        cursors.forEach(outbox.delete)
        let metas = (try? outbox.fetch(FetchDescriptor<SyncRecordMeta>(predicate: #Predicate { $0.key.starts(with: prefix) }))) ?? []
        metas.forEach(outbox.delete)
        try? outbox.save()
    }

    public func operations(userId: String? = nil) -> [(table: String, id: UUID, op: String, status: String, retry: Int)] {
        let all = (try? outbox.fetch(FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { userId == nil || $0.userId == userId }
            .map { ($0.tableRaw, $0.entityId, $0.operationRaw, $0.statusRaw, $0.retryCount) }
    }

    /// Lets tests make backed-off ops due without waiting.
    public func makeAllDue() {
        let ops = (try? outbox.fetch(FetchDescriptor<SyncOperation>())) ?? []
        for op in ops where op.statusRaw == "pending" { op.nextAttemptAt = .distantPast }
        try? outbox.save()
    }

    public func snapshot(userId: String?, state: SyncSnapshot.State? = nil) -> SyncSnapshot {
        var s = SyncSnapshot()
        s.conflicts = conflictsTotal
        s.lastError = lastError
        guard let userId else { s.state = state ?? .off; return s }
        s.pending = (try? outbox.fetchCount(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "pending" }))) ?? 0
        s.failed = (try? outbox.fetchCount(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "failed" }))) ?? 0
        s.held = (try? outbox.fetchCount(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "held" }))) ?? 0
        s.lastSyncDate = settings.lastSyncDate(for: userId)
        if let state { s.state = state }
        else if s.failed > 0 { s.state = .failed }
        else if s.pending > 0 { s.state = .pending }
        else if conflictsThisCycle > 0 { s.state = .conflict }
        else { s.state = .synced }
        return s
    }

    private func nextWake(userId: String) -> Date? {
        let now = clock()
        var d = FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == userId && $0.statusRaw == "pending" && $0.nextAttemptAt > now },
                                               sortBy: [SortDescriptor(\.nextAttemptAt)])
        d.fetchLimit = 1
        return (try? outbox.fetch(d))?.first?.nextAttemptAt
    }

    // MARK: - Cycle

    /// One sync: (pull) → push → (throttled full pull). `full` pulls every table first (launch, foreground,
    /// reconnect, BG refresh, Sync Now); otherwise only the tables about to be pushed are pulled first (LWW guard).
    public func sync(full: Bool) async -> SyncCycleResult {
        if running {
            rerun = true
            rerunFull = rerunFull || full
            return SyncCycleResult(snapshot: snapshot(userId: settings.ownerUserId, state: .syncing), nextWake: nil)
        }
        running = true
        defer { running = false }
        var result = await cycle(full: full)
        var extra = 0
        while rerun && extra < 3 {
            let nextFull = rerunFull
            rerun = false
            rerunFull = false
            result = await cycle(full: nextFull)
            extra += 1
        }
        return result
    }

    private func cycle(full: Bool) async -> SyncCycleResult {
        conflictsThisCycle = 0
        let owner = settings.ownerUserId
        let session: SyncSession?
        do {
            session = try await auth.session(forceRefresh: false)
        } catch CloudError.offline {
            return SyncCycleResult(snapshot: snapshot(userId: owner, state: .offline), nextWake: nil)
        } catch {
            return SyncCycleResult(snapshot: snapshot(userId: owner, state: .authRequired), nextWake: nil)
        }
        guard let session else { return SyncCycleResult(snapshot: snapshot(userId: owner, state: .off), nextWake: nil) }
        guard let owner, owner == session.userId else {
            // Ops of the account this iPhone is linked to are never sent with another account's token.
            return SyncCycleResult(snapshot: snapshot(userId: nil, state: owner == nil ? .off : .otherAccount), nextWake: nil)
        }
        guard settings.isEnabled(for: owner) else { return SyncCycleResult(snapshot: snapshot(userId: owner, state: .off), nextWake: nil) }
        userId = session.userId
        token = session.token
        sampleIDs = SyncFetch.sampleIDs(modelContext)

        do {
            var pulled = Set<SyncTable>()
            let pullFirst: [SyncTable]
            if full {
                pullFirst = SyncTable.pullOrder
            } else {
                let due = dueOperations(limit: 500)
                var tables = Set(due.compactMap(\.table))
                if tables.contains(.expenses) { tables.insert(.expenseShares) }
                pullFirst = SyncTable.pullOrder.filter(tables.contains)
            }
            for table in pullFirst { try await pull(table) ; pulled.insert(table) }
            if full { settings.setLastFullPull(clock(), for: userId) }

            try await push()

            let lastFull = settings.lastFullPull(for: userId) ?? .distantPast
            if !full, clock().timeIntervalSince(lastFull) >= Self.fullPullInterval {
                for table in SyncTable.pullOrder where !pulled.contains(table) { try await pull(table) }
                settings.setLastFullPull(clock(), for: userId)
            }
            settings.setLastSyncDate(clock(), for: userId)
            lastError = nil
            return SyncCycleResult(snapshot: snapshot(userId: userId), nextWake: nextWake(userId: userId))
        } catch SyncFailure.offline {
            try? outbox.save()
            return SyncCycleResult(snapshot: snapshot(userId: userId, state: .offline), nextWake: nil)
        } catch SyncFailure.unauthorized {
            try? outbox.save()
            lastError = "Sign in again to continue syncing."
            return SyncCycleResult(snapshot: snapshot(userId: userId, state: .authRequired), nextWake: nil)
        } catch {
            try? outbox.save()
            lastError = Self.message(error)
            return SyncCycleResult(snapshot: snapshot(userId: userId), nextWake: nextWake(userId: userId))
        }
    }

    private func dueOperations(limit: Int) -> [SyncOperation] {
        let user = userId
        let now = clock()
        var d = FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.userId == user && $0.statusRaw == "pending" && $0.nextAttemptAt <= now },
                                               sortBy: [SortDescriptor(\.createdAt)])
        d.fetchLimit = limit
        return (try? outbox.fetch(d)) ?? []
    }

    static func message(_ error: Error) -> String {
        switch error {
        case SyncFailure.permanent(let status, let message), SyncFailure.transient(let status, let message):
            return message.isEmpty ? "Server error (\(status))" : message
        case SyncFailure.offline: return "Offline"
        case SyncFailure.unauthorized: return "Sign in again to continue syncing."
        default: return error.localizedDescription
        }
    }

    // MARK: - HTTP

    private static let allowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return set
    }()

    private func makeRequest(method: String, path: String, query: [(String, String)], body: Data?, prefer: String?) -> URLRequest {
        var url = config.url.appendingPathComponent(path)
        if !query.isEmpty {
            let q = query.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? $0.1)" }.joined(separator: "&")
            url = URL(string: url.absoluteString + "?" + q)!
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        return request
    }

    /// Sends with the current token. 401 → refresh the token once (same user only) and retry; still 401 → unauthorized.
    @discardableResult
    private func perform(method: String, path: String, query: [(String, String)] = [], body: Data? = nil, prefer: String? = nil) async throws -> Data {
        var refreshed = false
        while true {
            let request = makeRequest(method: method, path: path, query: query, body: body, prefer: prefer)
            requestCount += 1
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch CloudError.offline {
                throw SyncFailure.offline
            } catch let CloudError.server(status, message) {
                throw SyncFailure.transient(status, message)
            } catch {
                throw SyncFailure.transient(0, error.localizedDescription)
            }
            let status = response.statusCode
            if (200..<300).contains(status) { return data }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let message = (body["message"] as? String) ?? (body["msg"] as? String) ?? ""
            if status == 401 {
                guard !refreshed else { throw SyncFailure.unauthorized }
                refreshed = true
                let fresh: SyncSession?
                do { fresh = try await auth.session(forceRefresh: true) } catch CloudError.offline { throw SyncFailure.offline } catch { throw SyncFailure.unauthorized }
                guard let fresh, fresh.userId == userId else { throw SyncFailure.unauthorized }
                token = fresh.token
                continue
            }
            if status == 408 || status == 429 || status >= 500 { throw SyncFailure.transient(status, message) }
            throw SyncFailure.permanent(status, message)
        }
    }

    // MARK: - Pull

    private func cursorKey(_ table: SyncTable) -> String { "\(userId)|\(table.rawValue)" }

    private func pull(_ table: SyncTable) async throws {
        let key = cursorKey(table)
        while true {
            let cursor = try? outbox.fetch(FetchDescriptor<SyncCursor>(predicate: #Predicate { $0.key == key })).first
            var query: [(String, String)] = [("select", "*"), ("order", "server_updated_at.asc,id.asc"), ("limit", "\(Self.pageSize)")]
            if let cursor {
                let c = cursor.serverUpdatedAt
                query.append(("or", "(server_updated_at.gt.\"\(c)\",and(server_updated_at.eq.\"\(c)\",id.gt.\(cursor.lastId)))"))
            }
            let data = try await perform(method: "GET", path: "rest/v1/\(table.rawValue)", query: query)
            guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                throw SyncFailure.transient(0, "Unexpected response")
            }
            if rows.isEmpty { return }
            applyPage(table, rows)
            do { try modelContext.save() } catch { modelContext.rollback(); throw SyncFailure.transient(0, "Couldn't save pulled data") }
            // The cursor moves only after the page is safely written.
            if let last = rows.last, let at = last["server_updated_at"] as? String, let id = last["id"] as? String {
                if let cursor { cursor.serverUpdatedAt = at; cursor.lastId = id } else { outbox.insert(SyncCursor(key: key, serverUpdatedAt: at, lastId: id)) }
            }
            try? outbox.save()
            if rows.count < Self.pageSize { return }
        }
    }

    /// Applies one page of pulled rows in the background context (last-writer-wins on updated_at; pending local
    /// edits are kept unless the cloud copy is newer; tombstones delete locally; own echoes are skipped).
    private func applyPage(_ table: SyncTable, _ rows: [[String: Any]]) {
        let ctx = modelContext
        let user = userId
        let opTable: SyncTable = table == .expenseShares ? .expenses : table
        let ids = rows.compactMap { SyncRows.uuid($0["id"]) }
        let opIds: [UUID] = table == .expenseShares ? rows.compactMap { SyncRows.uuid($0["expense_id"]) } : ids
        let opKeys = opIds.map { SyncOperation.key(userId: user, table: opTable, id: $0) }
        let ops = Dictionary(((try? outbox.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { opKeys.contains($0.key) }))) ?? [])
            .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let metaKeys = ids.map { SyncOperation.key(userId: user, table: table, id: $0) }
        var metas = Dictionary(((try? outbox.fetch(FetchDescriptor<SyncRecordMeta>(predicate: #Predicate { metaKeys.contains($0.key) }))) ?? [])
            .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var localNewer: [SyncChange] = []

        /// true = apply the row. Handles pending ops (conflict → server wins only if newer) and own echoes.
        func decide(id: UUID, opId: UUID, updated: Date) -> Bool {
            let key = SyncOperation.key(userId: user, table: opTable, id: opId)
            if let op = ops[key], !op.isDeleted {
                guard table != .expenseShares else { return false }   // the expense decides for its split
                if SyncDates.newer(updated, than: op.changedAt) {
                    outbox.delete(op)   // the cloud copy is newer: it wins everywhere
                    conflictsThisCycle += 1
                    conflictsTotal += 1
                    return true
                }
                return false
            }
            if let sent = metas[SyncOperation.key(userId: user, table: table, id: id)]?.lastSentUpdatedAt, SyncDates.same(sent, updated) {
                return false   // our own write coming back
            }
            return true
        }
        /// For types with updatedAt: a local copy edited later than the cloud's (and not queued) is pushed instead.
        func localWins(_ localUpdated: Date?, _ updated: Date, table: SyncTable, id: UUID) -> Bool {
            guard let localUpdated else { return false }
            if SyncDates.same(localUpdated, updated) { return true }
            if localUpdated > updated {
                localNewer.append(SyncChange(table: table, id: id, op: .update, changedAt: localUpdated))
                return true
            }
            return false
        }

        switch table {
        case .expenses:
            let local = SyncFetch.expenses(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let metaKey = SyncOperation.key(userId: user, table: .expenses, id: id)
                let meta = metas[metaKey] ?? { let m = SyncRecordMeta(key: metaKey); outbox.insert(m); metas[metaKey] = m; return m }()
                if meta.receiptPath != (row["receipt_path"] as? String) { meta.receiptPath = row["receipt_path"] as? String }
                let hadOp = ops[metaKey] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                let existing = local[id]
                if !hadOp, let existing, localWins(existing.updatedAt, updated, table: .expenses, id: id) { continue }
                if row["deleted_at"] is String {
                    if let existing { ctx.delete(existing) }   // tombstone: same as deleting on this iPhone
                    continue
                }
                _ = SyncApply.expense(row, into: existing, ctx: ctx)
            }
        case .expenseShares:
            let local = SyncFetch.shares(ids, ctx)
            let parents = SyncFetch.expenses(opIds, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]), let parentId = SyncRows.uuid(row["expense_id"]) else { continue }
                guard decide(id: id, opId: parentId, updated: SyncDates.parse(row["updated_at"]) ?? .distantPast) else { continue }
                if row["deleted_at"] is String {
                    if let existing = local[id] { ctx.delete(existing) }
                    continue
                }
                guard let parent = parents[parentId] else { continue }
                _ = SyncApply.share(row, into: local[id], expense: parent, ctx: ctx)
            }
        case .accounts:
            let local = SyncFetch.accounts(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]), decide(id: id, opId: id, updated: SyncDates.parse(row["updated_at"]) ?? .distantPast) else { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                _ = SyncApply.account(row, into: local[id], ctx: ctx)
            }
        case .people:
            let local = SyncFetch.people(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let hadOp = ops[SyncOperation.key(userId: user, table: .people, id: id)] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                if !hadOp, let existing = local[id], localWins(existing.updatedAt, updated, table: .people, id: id) { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                _ = SyncApply.person(row, into: local[id], ctx: ctx)
            }
        case .personPaymentMethods:
            let local = SyncFetch.methods(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let hadOp = ops[SyncOperation.key(userId: user, table: .personPaymentMethods, id: id)] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                if !hadOp, let existing = local[id], localWins(existing.updatedAt, updated, table: .personPaymentMethods, id: id) { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                _ = SyncApply.method(row, into: local[id], ctx: ctx)
            }
        case .moneyMovements:
            let local = SyncFetch.movements(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let hadOp = ops[SyncOperation.key(userId: user, table: .moneyMovements, id: id)] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                if !hadOp, let existing = local[id], localWins(existing.updatedAt, updated, table: .moneyMovements, id: id) { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                _ = SyncApply.movement(row, into: local[id], ctx: ctx)
            }
        case .settlementAllocations:
            let local = SyncFetch.allocations(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]), decide(id: id, opId: id, updated: SyncDates.parse(row["updated_at"]) ?? .distantPast) else { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                _ = SyncApply.allocation(row, into: local[id], ctx: ctx)
            }
        case .classificationRules:
            let local = SyncFetch.classificationRules(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let hadOp = ops[SyncOperation.key(userId: user, table: .classificationRules, id: id)] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                if !hadOp, let existing = local[id], localWins(existing.updatedAt, updated, table: .classificationRules, id: id) { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                if local[id] == nil, let key = row["merchant_key"] as? String {
                    // One rule per merchant key (as on the server): the cloud's rule replaces a local one with another id.
                    let same = (try? ctx.fetch(FetchDescriptor<ClassificationRule>(predicate: #Predicate { $0.merchantKey == key }))) ?? []
                    for rule in same where rule.id != id { ctx.delete(rule) }
                }
                _ = SyncApply.classificationRule(row, into: local[id], ctx: ctx)
            }
        case .channelRules:
            let local = SyncFetch.channelRules(ids, ctx)
            for row in rows {
                guard let id = SyncRows.uuid(row["id"]) else { continue }
                let updated = SyncDates.parse(row["updated_at"]) ?? .distantPast
                let hadOp = ops[SyncOperation.key(userId: user, table: .channelRules, id: id)] != nil
                guard decide(id: id, opId: id, updated: updated) else { continue }
                if !hadOp, let existing = local[id], localWins(existing.updatedAt, updated, table: .channelRules, id: id) { continue }
                if row["deleted_at"] is String { if let existing = local[id] { ctx.delete(existing) }; continue }
                if local[id] == nil, let key = row["merchant_key"] as? String {
                    let funding = (row["funding_key"] as? String) ?? ""
                    let same = (try? ctx.fetch(FetchDescriptor<ChannelRule>(predicate: #Predicate { $0.merchantKey == key && $0.fundingKey == funding }))) ?? []
                    for rule in same where rule.id != id { ctx.delete(rule) }
                }
                _ = SyncApply.channelRule(row, into: local[id], ctx: ctx)
            }
        }
        if !localNewer.isEmpty { enqueue(localNewer, userId: user) }
    }

    // MARK: - Push

    private func push() async throws {
        for _ in 0..<20 {   // bounded: each round removes or reschedules every op it takes
            let due = dueOperations(limit: 500)
            if due.isEmpty { return }
            let byTable = Dictionary(grouping: due) { $0.table ?? .accounts }
            for table in SyncTable.pushOrder {
                guard let ops = byTable[table] else { continue }
                let upserts = ops.filter { $0.operation.isUpsert }
                let deletes = ops.filter { !$0.operation.isUpsert }
                if table == .expenses { try await pushExpenses(upserts) } else { try await pushRows(table, upserts) }
                try await pushDeletes(table, deletes)
            }
            try? outbox.save()
            if due.count < 500 { return }
        }
    }

    /// Captured state of an op when its payload was built: a change that arrives while the request is in flight
    /// (same actor, between awaits) must not be lost when the response comes back.
    private struct Sent {
        let op: SyncOperation
        let changedAt: Date
        let operation: String
        let updatedAt: Date
    }

    private func succeeded(_ sent: Sent, table: SyncTable) {
        let op = sent.op
        if !op.isDeleted {
            if op.changedAt == sent.changedAt && op.operationRaw == sent.operation {
                outbox.delete(op)
            }   // else: changed again meanwhile → stays queued (already `attempted`)
        }
        guard sent.operation != SyncOpKind.delete.rawValue else { return }
        let key = SyncOperation.key(userId: userId, table: table, id: op.entityId)
        let metas = (try? outbox.fetch(FetchDescriptor<SyncRecordMeta>(predicate: #Predicate { $0.key == key }))) ?? []
        let meta = metas.first ?? { let m = SyncRecordMeta(key: key); outbox.insert(m); return m }()
        meta.lastSentUpdatedAt = sent.updatedAt
    }

    private func failed(_ op: SyncOperation, _ message: String) {
        guard !op.isDeleted else { return }
        op.statusRaw = "failed"
        op.retryCount += 1
        op.lastError = message.isEmpty ? "The cloud didn't accept this record." : message
        lastError = op.lastError
    }

    private func backoff(_ op: SyncOperation, _ message: String) {
        guard !op.isDeleted else { return }
        op.retryCount += 1
        let delay = min(2 * pow(2, Double(op.retryCount - 1)), Self.maxBackoff) * jitter()
        op.nextAttemptAt = clock().addingTimeInterval(delay)
        op.lastError = message
        lastError = message
    }

    private func updatedAt(_ local: Date?, _ op: SyncOperation) -> Date {
        guard let local else { return op.changedAt }
        return max(local, op.changedAt)
    }

    /// Builds rows for plain tables (fetching locals by id in chunks).
    private func buildRows(_ table: SyncTable, _ ops: [SyncOperation]) -> [(Sent, [String: Any])] {
        let ctx = modelContext
        let ids = ops.map(\.entityId)
        var out: [(Sent, [String: Any])] = []
        func handle(_ op: SyncOperation, _ result: SyncRowResult?, _ updated: Date) {
            switch result {
            case .row(let row)?:
                op.attempted = true
                out.append((Sent(op: op, changedAt: op.changedAt, operation: op.operationRaw, updatedAt: updated), row))
            case .invalid(let reason)?:
                failed(op, reason)
            case .drop?, nil:
                outbox.delete(op)   // sample data, or the record no longer exists (its delete op handles the cloud)
            }
        }
        switch table {
        case .accounts:
            let local = SyncFetch.accounts(ids, ctx)
            for op in ops {
                let a = local[op.entityId]
                let u = updatedAt(nil, op)
                handle(op, a.map { sampleIDs.contains($0.id) ? .drop : SyncRows.row($0, updatedAt: u) }, u)
            }
        case .people:
            let local = SyncFetch.people(ids, ctx)
            for op in ops {
                let p = local[op.entityId]
                let u = updatedAt(p?.updatedAt, op)
                handle(op, p.map { sampleIDs.contains($0.id) ? .drop : SyncRows.row($0, updatedAt: u) }, u)
            }
        case .personPaymentMethods:
            let local = SyncFetch.methods(ids, ctx)
            for op in ops {
                let m = local[op.entityId]
                let u = updatedAt(m?.updatedAt, op)
                handle(op, m.map { sampleIDs.contains($0.id) ? .drop : SyncRows.row($0, updatedAt: u, sample: sampleIDs) }, u)
            }
        case .moneyMovements:
            let local = SyncFetch.movements(ids, ctx)
            for op in ops {
                let m = local[op.entityId]
                let u = updatedAt(m?.updatedAt, op)
                handle(op, m.map { sampleIDs.contains($0.id) ? .drop : SyncRows.row($0, updatedAt: u, sample: sampleIDs) }, u)
            }
        case .settlementAllocations:
            let local = SyncFetch.allocations(ids, ctx)
            for op in ops {
                let a = local[op.entityId]
                let u = updatedAt(nil, op)
                handle(op, a.map { sampleIDs.contains($0.id) ? .drop : SyncRows.row($0, updatedAt: u, sample: sampleIDs) }, u)
            }
        case .classificationRules:
            let local = SyncFetch.classificationRules(ids, ctx)
            for op in ops {
                let r = local[op.entityId]
                let u = updatedAt(r?.updatedAt, op)
                handle(op, r.map { SyncRows.row($0, updatedAt: u) }, u)
            }
        case .channelRules:
            let local = SyncFetch.channelRules(ids, ctx)
            for op in ops {
                let r = local[op.entityId]
                let u = updatedAt(r?.updatedAt, op)
                handle(op, r.map { SyncRows.row($0, updatedAt: u) }, u)
            }
        case .expenses, .expenseShares:
            break
        }
        return out
    }

    private func pushRows(_ table: SyncTable, _ ops: [SyncOperation]) async throws {
        for chunk in ops.syncChunks(of: Self.chunkSize) {
            let built = buildRows(table, chunk)
            try? outbox.save()   // `attempted` is durable before the request goes out
            guard !built.isEmpty else { continue }
            let path = "rest/v1/\(table.rawValue)"
            let query = [("on_conflict", "id")]
            let prefer = "resolution=merge-duplicates,return=minimal"
            do {
                let body = try JSONSerialization.data(withJSONObject: built.map(\.1))
                try await perform(method: "POST", path: path, query: query, body: body, prefer: prefer)
                built.forEach { succeeded($0.0, table: table) }
            } catch SyncFailure.permanent(let status, let message) {
                if built.count == 1 { failed(built[0].0.op, message.isEmpty ? "Rejected (\(status))" : message); continue }
                // Isolate the bad row(s) so they can't block the others (same as Android).
                for (sent, row) in built {
                    do {
                        let body = try JSONSerialization.data(withJSONObject: [row])
                        try await perform(method: "POST", path: path, query: query, body: body, prefer: prefer)
                        succeeded(sent, table: table)
                    } catch SyncFailure.permanent(let s, let m) {
                        failed(sent.op, m.isEmpty ? "Rejected (\(s))" : m)
                    } catch SyncFailure.transient(_, let m) {
                        backoff(sent.op, m)
                    }
                }
            } catch SyncFailure.transient(_, let message) {
                built.forEach { backoff($0.0.op, message) }
            }
            try? outbox.save()
        }
    }

    private func pushExpenses(_ ops: [SyncOperation]) async throws {
        let ctx = modelContext
        for chunk in ops.syncChunks(of: Self.chunkSize) {
            let ids = chunk.map(\.entityId)
            let local = SyncFetch.expenses(ids, ctx)
            let metaKeys = ids.map { SyncOperation.key(userId: userId, table: .expenses, id: $0) }
            let metas = Dictionary(((try? outbox.fetch(FetchDescriptor<SyncRecordMeta>(predicate: #Predicate { metaKeys.contains($0.key) }))) ?? [])
                .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            var built: [(Sent, Data)] = []
            for op in chunk {
                guard let e = local[op.entityId], !e.isSampleData, !sampleIDs.contains(e.id) else { outbox.delete(op); continue }
                let u = updatedAt(e.updatedAt, op)
                let receipt = metas[SyncOperation.key(userId: userId, table: .expenses, id: e.id)]?.receiptPath
                switch SyncRows.rpcBody(e, updatedAt: u, sample: sampleIDs, receiptPath: receipt) {
                case .row(let body):
                    guard let data = try? JSONSerialization.data(withJSONObject: body) else { failed(op, "Couldn't prepare this expense"); continue }
                    op.attempted = true
                    built.append((Sent(op: op, changedAt: op.changedAt, operation: op.operationRaw, updatedAt: u), data))
                case .invalid(let reason): failed(op, reason)
                case .drop: outbox.delete(op)
                }
            }
            try? outbox.save()
            // A few RPCs in flight at once; results are applied in order afterwards.
            var results: [Int: SyncFailure?] = [:]
            for window in Array(built.indices).syncChunks(of: Self.rpcConcurrency) {
                await withTaskGroup(of: (Int, SyncFailure?).self) { group in
                    for index in window {
                        let body = built[index].1
                        group.addTask {
                            do {
                                try await self.perform(method: "POST", path: "rest/v1/rpc/save_expense_with_shares", body: body)
                                return (index, nil)
                            } catch let failure as SyncFailure {
                                return (index, failure)
                            } catch {
                                return (index, SyncFailure.transient(0, error.localizedDescription))
                            }
                        }
                    }
                    for await (index, failure) in group { results.updateValue(failure, forKey: index) }
                }
                if results.values.contains(where: { $0 == .offline || $0 == .unauthorized }) { break }
            }
            var stop: SyncFailure?
            for (index, (sent, _)) in built.enumerated() {
                guard let outcome = results[index] else { continue }   // not sent (stopped early): stays pending
                switch outcome {
                case nil: succeeded(sent, table: .expenses)
                case .permanent(let s, let m)?: failed(sent.op, m.isEmpty ? "Rejected (\(s))" : m)
                case .transient(_, let m)?: backoff(sent.op, m)
                case .offline?, .unauthorized?: stop = outcome
                }
            }
            try? outbox.save()
            if let stop { throw stop }
        }
    }

    /// Tombstones by id (works after the local object is gone). `updated_at=lt.T` never tombstones a newer edit.
    private func pushDeletes(_ table: SyncTable, _ ops: [SyncOperation]) async throws {
        guard !ops.isEmpty else { return }
        let groups = Dictionary(grouping: ops) { SyncDates.string($0.changedAt) }
        for (time, group) in groups.sorted(by: { $0.key < $1.key }) {
            for chunk in group.syncChunks(of: Self.chunkSize) {
                let sent = chunk.map { Sent(op: $0, changedAt: $0.changedAt, operation: $0.operationRaw, updatedAt: $0.changedAt) }
                let list = "(" + chunk.map { SyncRows.id($0.entityId) }.joined(separator: ",") + ")"
                let body = try JSONSerialization.data(withJSONObject: ["deleted_at": time, "updated_at": time])
                do {
                    try await perform(method: "PATCH", path: "rest/v1/\(table.rawValue)",
                                      query: [("id", "in.\(list)"), ("updated_at", "lt.\(time)")], body: body, prefer: "return=minimal")
                    if table == .expenses {
                        try await perform(method: "PATCH", path: "rest/v1/expense_shares",
                                          query: [("expense_id", "in.\(list)"), ("deleted_at", "is.null"), ("updated_at", "lt.\(time)")],
                                          body: body, prefer: "return=minimal")
                    }
                    sent.forEach { succeeded($0, table: table) }
                } catch SyncFailure.permanent(let status, let message) {
                    chunk.forEach { failed($0, message.isEmpty ? "Rejected (\(status))" : message) }
                } catch SyncFailure.transient(_, let message) {
                    chunk.forEach { backoff($0, message) }
                }
                try? outbox.save()
            }
        }
    }
}
