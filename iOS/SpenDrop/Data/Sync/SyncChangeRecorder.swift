import Foundation
import SwiftData

/// Turns local saves into sync changes without touching any save call site: it observes `ModelContext.willSave`
/// (synchronously, on the saving thread) and reads only the ids of the inserted/changed/deleted objects — no fetches,
/// no encoding, no I/O. After `didSave` the changes are handed to `onChanges` (which enqueues them in the background).
/// A save that fails never posts didSave, so nothing is recorded for it. Saves of excluded contexts (the sync engine
/// applying pulled rows) are ignored, so pulled data never echoes back as local changes.
public final class SyncChangeRecorder: @unchecked Sendable {
    /// A single save deleting more than this many records (e.g. "Clear All Expenses") is held for confirmation.
    public static let massDeleteThreshold = 100

    private let container: ModelContainer
    private let lock = NSLock()
    private var stash: [ObjectIdentifier: [SyncChange]] = [:]
    private var excluded: Set<ObjectIdentifier> = []
    private var observers: [NSObjectProtocol] = []
    private let shouldRecord: @Sendable () -> Bool
    private let onChanges: @Sendable ([SyncChange]) -> Void
    private let clock: @Sendable () -> Date

    public init(container: ModelContainer, shouldRecord: @escaping @Sendable () -> Bool,
                clock: @escaping @Sendable () -> Date = Date.init,
                onChanges: @escaping @Sendable ([SyncChange]) -> Void) {
        self.container = container
        self.shouldRecord = shouldRecord
        self.clock = clock
        self.onChanges = onChanges
    }

    deinit { stop() }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { [weak self] note in
            guard let self, let context = note.object as? ModelContext else { return }
            self.willSave(context)
        })
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            guard let self, let context = note.object as? ModelContext else { return }
            self.didSave(context)
        })
    }

    public func stop() {
        lock.lock()
        let list = observers
        observers = []
        lock.unlock()
        list.forEach(NotificationCenter.default.removeObserver)
    }

    /// Saves of this context are never recorded (the sync engine's own context).
    public func exclude(_ context: ModelContext) {
        lock.lock(); excluded.insert(ObjectIdentifier(context)); lock.unlock()
    }

    private func isWatched(_ context: ModelContext) -> Bool {
        guard context.container === container else { return false }
        lock.lock(); defer { lock.unlock() }
        return !excluded.contains(ObjectIdentifier(context))
    }

    private func willSave(_ context: ModelContext) {
        guard isWatched(context), shouldRecord() else { return }
        let changes = Self.changes(in: context, now: clock())
        lock.lock(); stash[ObjectIdentifier(context)] = changes; lock.unlock()
    }

    private func didSave(_ context: ModelContext) {
        lock.lock()
        let changes = stash.removeValue(forKey: ObjectIdentifier(context))
        lock.unlock()
        if let changes, !changes.isEmpty { onChanges(changes) }
    }

    /// The (table, id, op) of every pending change in `context`. Precedence per record: delete > create > update.
    /// Split shares map to their expense (they're saved together). Sample expenses and non-synced types are skipped.
    static func changes(in context: ModelContext, now: Date) -> [SyncChange] {
        var result: [String: SyncChange] = [:]
        func add(_ table: SyncTable, _ id: UUID, _ op: SyncOpKind) {
            let key = table.rawValue + id.uuidString
            if let existing = result[key] {
                let rank: (SyncOpKind) -> Int = { $0 == .delete ? 2 : ($0 == .create ? 1 : 0) }
                if rank(op) <= rank(existing.op) { return }
            }
            result[key] = SyncChange(table: table, id: id, op: op, changedAt: now)
        }
        func record(_ model: any PersistentModel, _ op: SyncOpKind) {
            switch model {
            case let e as Expense:
                if !e.isSampleData { add(.expenses, e.id, op) }
            case let s as ExpenseShare:
                if let parent = s.expense, !parent.isSampleData { add(.expenses, parent.id, .update) }
            case let a as Account: add(.accounts, a.id, op)
            case let p as PayBookProfile: add(.people, p.id, op)
            case let m as PayBookPaymentMethod: add(.personPaymentMethods, m.id, op)
            case let m as MoneyMovement: add(.moneyMovements, m.id, op)
            case let a as SettlementAllocation: add(.settlementAllocations, a.id, op)
            case let r as ClassificationRule: add(.classificationRules, r.id, op)
            case let r as ChannelRule: add(.channelRules, r.id, op)
            default: break   // PayBookContact (legacy), SampleDataRecord: never synced
            }
        }
        for model in context.insertedModelsArray { record(model, .create) }
        for model in context.changedModelsArray { record(model, .update) }
        for model in context.deletedModelsArray { record(model, .delete) }
        var list = Array(result.values)
        let deletes = list.filter { $0.op == .delete }.count
        if deletes > massDeleteThreshold {
            list = list.map { var c = $0; if c.op == .delete { c.held = true }; return c }
        }
        return list
    }
}
