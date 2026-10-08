import BackgroundTasks
import Foundation
import Network
import Observation
import SwiftData

/// Lightweight sync status for the Account screen. Every property is assigned only when its value changed, so
/// observers re-render only on real changes. Expense lists never observe it.
@MainActor
@Observable
public final class SyncStatusModel {
    public private(set) var state: SyncSnapshot.State = .off
    public private(set) var pendingCount = 0
    public private(set) var failedCount = 0
    public private(set) var heldDeletes = 0
    public private(set) var conflicts = 0
    public private(set) var lastSyncDate: Date?
    public private(set) var lastError: String?

    public init() {}

    func apply(_ s: SyncSnapshot) {
        if state != s.state { state = s.state }
        if pendingCount != s.pending { pendingCount = s.pending }
        if failedCount != s.failed { failedCount = s.failed }
        if heldDeletes != s.held { heldDeletes = s.held }
        if conflicts != s.conflicts { conflicts = s.conflicts }
        if lastSyncDate != s.lastSyncDate { lastSyncDate = s.lastSyncDate }
        if lastError != s.lastError { lastError = s.lastError }
    }

    public var title: String {
        switch state {
        case .off: return "Off"
        case .synced: return "Up to date"
        case .pending: return pendingCount == 1 ? "1 change waiting" : "\(pendingCount) changes waiting"
        case .syncing: return "Syncing…"
        case .offline: return "Waiting for internet"
        case .failed: return failedCount == 1 ? "1 record couldn't sync" : "\(failedCount) records couldn't sync"
        case .conflict: return "Up to date (newer cloud copy kept)"
        case .authRequired: return "Sign in again to sync"
        case .otherAccount: return "This iPhone's data is linked to another account"
        }
    }
}

/// Decides WHEN to sync (never blocks the UI): debounce after local saves, network changes, launch/foreground,
/// background refresh and a one-shot backoff timer. The work itself runs in `SyncEngine` (a background actor).
@MainActor
public final class SyncCoordinator {
    public static let debounce: Duration = .milliseconds(1500)
    public static let backgroundTaskIdentifier = "com.spendrop.SpenDrop.sync"

    public static let shared: SyncCoordinator? = {
        guard !ExpenseDataContainer.isUITesting, let config = AuthService.shared.config,
              let outbox = try? SyncOutboxStore.makeContainer() else { return nil }
        return SyncCoordinator(container: ExpenseDataContainer.shared, outboxContainer: outbox, transport: URLSessionTransport(),
                               config: config, auth: AuthService.shared, defaults: .standard)
    }()

    public let status = SyncStatusModel()
    public let engine: SyncEngine
    public let settings: SyncSettings
    let recorder: SyncChangeRecorder
    private let auth: AuthService?
    private var monitor: NWPathMonitor?
    private var debounceTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var started = false
    public private(set) var isOnline = true

    /// `auth` nil = tests (they drive the engine directly).
    init(container: ModelContainer, outboxContainer: ModelContainer, transport: HTTPTransport, config: SupabaseConfig,
         auth: AuthService?, authProvider: SyncAuthProviding? = nil, defaults: UserDefaults) {
        let settings = SyncSettings(defaults: defaults)
        self.settings = settings
        self.auth = auth
        // The recorder needs the engine and the engine needs the recorder (to exclude its context): late-bound box.
        let box = EngineBox()
        let recorder = SyncChangeRecorder(container: container, shouldRecord: { settings.ownerUserId != nil }) { changes in
            Task { @MainActor in await box.coordinator?.record(changes) }
        }
        self.recorder = recorder
        self.engine = SyncEngine(container: container, outboxContainer: outboxContainer, transport: transport, config: config,
                                 auth: authProvider ?? AuthServiceSyncProvider(auth: auth ?? AuthService.shared),
                                 settings: settings, recorder: recorder)
        box.coordinator = self
    }

    private final class EngineBox: @unchecked Sendable {
        @MainActor weak var coordinator: SyncCoordinator?
    }

    // MARK: Lifecycle

    /// Called after the first frame (root view `.task`). Everything heavy runs on a utility task.
    public func start() {
        // Safe mode (temporary in-memory store): never link, bootstrap or pull into a store that isn't the user's.
        guard !started, ExpenseDataContainer.isPersistentStoreHealthy else { return }
        started = true
        recorder.start()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "SpenDrop.sync.network", qos: .utility))
        self.monitor = monitor
        Task(priority: .utility) { await self.prepareAndSync(full: true) }
    }

    public func appBecameActive() {
        guard started else { return }
        Task(priority: .utility) { await self.prepareAndSync(full: true) }
    }

    func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { Task(priority: .utility) { await self.run(full: true) } }
        if !online { status.apply(withState(.offline)) }
    }

    private func withState(_ state: SyncSnapshot.State) -> SyncSnapshot {
        var s = SyncSnapshot()
        s.state = state
        s.pending = status.pendingCount
        s.failed = status.failedCount
        s.held = status.heldDeletes
        s.conflicts = status.conflicts
        s.lastSyncDate = status.lastSyncDate
        s.lastError = status.lastError
        return s
    }

    /// Links this iPhone's data to the signed-in account the first time (default ON), bootstraps the queue once,
    /// catches up on Share Extension saves, then syncs.
    func prepareAndSync(full: Bool) async {
        guard let user = auth?.currentUser else { status.apply(SyncSnapshot()); return }
        if settings.ownerUserId == nil, settings.isEnabled(for: user.id) {
            settings.ownerUserId = user.id
            settings.catchUpMark = Date()
            await engine.bootstrap(userId: user.id)
        }
        if let owner = settings.ownerUserId, owner == user.id,
           let mark = settings.catchUpMark, let ext = settings.extensionLastSave, ext > mark {
            settings.catchUpMark = Date()
            await engine.catchUp(userId: owner, since: mark)
        }
        await run(full: full)
    }

    // MARK: Triggers

    func record(_ changes: [SyncChange]) async {
        guard let owner = settings.ownerUserId else { return }
        await engine.enqueue(changes, userId: owner)
        scheduleDebounced()
    }

    /// Each new change restarts the short debounce, so a burst of saves becomes one sync.
    public func scheduleDebounced() {
        debounceTask?.cancel()
        debounceTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.run(full: false)
        }
    }

    public func syncNow() {
        Task(priority: .userInitiated) {
            if let owner = settings.ownerUserId { await engine.retryFailed(userId: owner) }
            await prepareAndSync(full: true)
        }
    }

    public func applyHeldDeletions() {
        guard let owner = settings.ownerUserId else { return }
        Task(priority: .utility) {
            await engine.releaseHeld(userId: owner)
            await run(full: false)
        }
    }

    public var isEnabledForCurrentUser: Bool {
        guard let user = auth?.currentUser else { return false }
        return settings.isEnabled(for: user.id)
    }

    public func setEnabled(_ on: Bool) {
        guard let user = auth?.currentUser else { return }
        settings.setEnabled(on, for: user.id)
        if on { Task(priority: .utility) { await prepareAndSync(full: true) } } else { status.apply(SyncSnapshot()) }
    }

    /// The cloud account was deleted: drop its queue and cursors and unlink this iPhone (local data untouched).
    public func forgetAccount(userId: String) {
        if settings.ownerUserId == userId { settings.ownerUserId = nil }
        Task(priority: .utility) { await engine.forget(userId: userId) }
        status.apply(SyncSnapshot())
    }

    @discardableResult
    func run(full: Bool) async -> SyncCycleResult? {
        guard isOnline else {
            let owner = settings.ownerUserId
            status.apply(await engine.snapshot(userId: owner, state: owner == nil ? .off : .offline))
            return nil
        }
        if status.pendingCount > 0 || full { status.apply(withState(.syncing)) }
        let result = await engine.sync(full: full)
        status.apply(result.snapshot)
        scheduleWake(result.nextWake)
        return result
    }

    /// One timer to the earliest backed-off op (no polling).
    private func scheduleWake(_ date: Date?) {
        wakeTask?.cancel()
        guard let date else { return }
        let delay = max(1, date.timeIntervalSinceNow)
        wakeTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.run(full: false)
        }
    }

    // MARK: Background refresh

    nonisolated public static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            let work = Task { @MainActor in
                guard let coordinator = SyncCoordinator.shared else { task.setTaskCompleted(success: true); return }
                let result = await coordinator.run(full: true)
                SyncCoordinator.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: result?.snapshot.state != .failed)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    public static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
