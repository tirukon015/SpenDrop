import BackgroundTasks
import Foundation
import CryptoKit
import Network
import Observation
import SwiftData
import UIKit

/// Metadata row for one cloud backup (table `public.backups`, protected by Row Level Security).
public struct CloudBackupRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let deviceId: String
    public let deviceName: String
    public let appVersion: String
    public let schemaVersion: String
    public let backupVersion: Int
    public let createdAt: Date
    public let objectPath: String
    public let expensesCount: Int
    public let peopleCount: Int
    public let accountsCount: Int
    public let movementsCount: Int
    public let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case schemaVersion = "schema_version"
        case backupVersion = "backup_version"
        case createdAt = "created_at"
        case objectPath = "object_path"
        case expensesCount = "expenses_count"
        case peopleCount = "people_count"
        case accountsCount = "accounts_count"
        case movementsCount = "movements_count"
        case sizeBytes = "size_bytes"
    }
}

/// Cloud BACKUP + RESTORE (not live sync). Local SwiftData stays the source of truth; the local backup system
/// is unchanged. Backups are append-only files under `backups/<user id>/<device id>/`; nothing in the cloud is
/// ever overwritten, and a restore merges by stable id after saving a local safety copy.
@MainActor
@Observable
public final class CloudBackupService {
    public enum Status: Equatable {
        case notConfigured
        case notSignedIn
        case idle
        case waitingForNetwork
        case uploading
        case upToDate
        case restoring
        case failed(String)

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var title: String {
            switch self {
            case .notConfigured: return "Not set up"
            case .notSignedIn: return "Not signed in"
            case .idle: return "Enabled"
            case .waitingForNetwork: return "Waiting for internet"
            case .uploading: return "Backup in progress…"
            case .upToDate: return "Up to date"
            case .restoring: return "Restoring…"
            case .failed: return "Backup failed"
            }
        }
    }

    public static let bucket = "backups"

    public static let shared = CloudBackupService(
        auth: .shared,
        transport: URLSessionTransport(),
        defaults: .standard,
        device: .current,
        contextProvider: { ExpenseDataContainer.shared.mainContext },
        canUseLocalStore: { ExpenseDataContainer.isPersistentStoreHealthy },
        makeSafetyBackup: { context in CloudBackupService.writeLocalSafetyBackup(from: context) },
        scheduler: ExpenseDataContainer.isUITesting ? NoBackupTaskScheduler() : SystemBackupTaskScheduler()
    )

    public struct Device {
        public let id: String
        public let name: String
        public let appVersion: String

        @MainActor
        public static var current: Device {
            let defaults = UserDefaults.standard
            let key = "SpenDrop.cloudDeviceID"
            let id = defaults.string(forKey: key) ?? {
                let new = UUID().uuidString
                defaults.set(new, forKey: key)
                return new
            }()
            let info = Bundle.main.infoDictionary ?? [:]
            let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
            return Device(id: id, name: UIDevice.current.model, appVersion: version)
        }
    }

    public private(set) var status: Status
    /// What the running backup is doing (shown as non-blocking progress).
    public private(set) var phase: BackupPhase = .idle
    /// Result of the most recent backup attempt (manual or automatic), including screenshot statistics.
    public private(set) var lastReport: BackupReport?
    /// Most recent successful upload of either kind (kept for compatibility).
    public private(set) var lastBackupDate: Date?
    public private(set) var lastManualBackupDate: Date?
    public private(set) var lastAutomaticBackupDate: Date?
    public var isOnline = true {
        didSet {
            if isOnline && !oldValue { Task { await self.runAutomaticBackupIfDue() } }
        }
    }

    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let transport: HTTPTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let device: Device
    @ObservationIgnored private let contextProvider: () -> ModelContext
    @ObservationIgnored private let canUseLocalStore: () -> Bool
    @ObservationIgnored private let makeSafetyBackup: (ModelContext) -> Bool
    @ObservationIgnored let scheduler: BackupTaskScheduling
    @ObservationIgnored private let imageStorage: ImageStorageService
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored var calendar: Calendar
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var monitor: NWPathMonitor?

    private static let lastBackupKey = "SpenDrop.cloudLastBackupDate"
    private static let lastManualKey = "SpenDrop.cloudLastManualBackupDate"
    private static let lastAutomaticKey = "SpenDrop.cloudLastAutomaticBackupDate"
    private static let lastHashKey = "SpenDrop.cloudLastBackupHash"
    /// Consent: "Cloud Backup" switch (per user).
    private static let autoBackupKey = "SpenDrop.cloudAutoBackupEnabled."
    private static let dailyEnabledKey = "SpenDrop.cloudDailyBackupEnabled."
    private static let dailyTimeKey = "SpenDrop.cloudDailyBackupMinutes."
    public static let defaultDailyBackupMinutes = 3 * 60  // 3:00 AM

    public init(auth: AuthService, transport: HTTPTransport, defaults: UserDefaults, device: Device,
                contextProvider: @escaping () -> ModelContext, canUseLocalStore: @escaping () -> Bool,
                makeSafetyBackup: @escaping (ModelContext) -> Bool,
                scheduler: BackupTaskScheduling = NoBackupTaskScheduler(),
                imageStorage: ImageStorageService = .shared,
                clock: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.auth = auth
        self.transport = transport
        self.defaults = defaults
        self.device = device
        self.contextProvider = contextProvider
        self.canUseLocalStore = canUseLocalStore
        self.makeSafetyBackup = makeSafetyBackup
        self.scheduler = scheduler
        self.imageStorage = imageStorage
        self.clock = clock
        self.calendar = calendar
        self.lastBackupDate = defaults.object(forKey: Self.lastBackupKey) as? Date
        self.lastManualBackupDate = defaults.object(forKey: Self.lastManualKey) as? Date
        self.lastAutomaticBackupDate = defaults.object(forKey: Self.lastAutomaticKey) as? Date
        self.status = auth.config == nil ? .notConfigured : (auth.currentUser == nil ? .notSignedIn : .idle)
    }

    // MARK: Settings (per signed-in user)

    /// The "Cloud Backup" switch: explicit consent, off by default. Signing in alone never uploads anything.
    /// Use `enableCloudBackup()` to turn it on (first backup + schedule) and `disableCloudBackup()` to turn it off.
    public private(set) var automaticBackupsEnabled: Bool {
        get {
            access(keyPath: \.automaticBackupsEnabled)
            guard let id = auth.currentUser?.id else { return false }
            return defaults.bool(forKey: Self.autoBackupKey + id)
        }
        set {
            guard let id = auth.currentUser?.id else { return }
            withMutation(keyPath: \.automaticBackupsEnabled) {
                defaults.set(newValue, forKey: Self.autoBackupKey + id)
            }
        }
    }

    public var cloudBackupEnabled: Bool { automaticBackupsEnabled }

    /// True while a backup (screenshots, snapshot, upload, verification) is running.
    public var isBackupRunning: Bool { phase != .idle || status == .uploading }

    /// "Automatic Daily Backup" (on by default once Cloud Backup is on).
    public var dailyBackupEnabled: Bool {
        get {
            access(keyPath: \.dailyBackupEnabled)
            guard let id = auth.currentUser?.id else { return false }
            return (defaults.object(forKey: Self.dailyEnabledKey + id) as? Bool) ?? true
        }
        set {
            guard let id = auth.currentUser?.id else { return }
            withMutation(keyPath: \.dailyBackupEnabled) { defaults.set(newValue, forKey: Self.dailyEnabledKey + id) }
            rescheduleDailyBackup()
        }
    }

    /// Minutes after local midnight (default 180 = 3:00 AM). Changing it reschedules the single pending request.
    public var dailyBackupMinutes: Int {
        get {
            access(keyPath: \.dailyBackupMinutes)
            guard let id = auth.currentUser?.id else { return Self.defaultDailyBackupMinutes }
            return (defaults.object(forKey: Self.dailyTimeKey + id) as? Int) ?? Self.defaultDailyBackupMinutes
        }
        set {
            guard let id = auth.currentUser?.id else { return }
            let clamped = min(max(newValue, 0), 24 * 60 - 1)
            withMutation(keyPath: \.dailyBackupMinutes) { defaults.set(clamped, forKey: Self.dailyTimeKey + id) }
            rescheduleDailyBackup()
        }
    }

    /// Turns Cloud Backup on after the user confirmed, runs the first full backup immediately (screenshots are
    /// optimized first), then schedules the daily backup. If the first backup fails Cloud Backup stays on and the
    /// failure is reported; "Back Up Now" and the daily backup retry later.
    @discardableResult
    public func enableCloudBackup() async -> BackupReport? {
        guard auth.currentUser != nil else { return nil }
        automaticBackupsEnabled = true
        let report = await runBackup(kind: .manual)
        rescheduleDailyBackup()
        return report
    }

    /// Stops future automatic backups. Existing cloud backups are kept.
    public func disableCloudBackup() {
        automaticBackupsEnabled = false
        scheduler.cancelDailyBackup()
    }

    // MARK: Daily schedule

    /// Starts network monitoring and (re)schedules the daily backup. Safe to call more than once.
    public func startAutomaticBackups() {
        rescheduleDailyBackup()
        guard monitor == nil, auth.config != nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "SpenDrop.network"))
        self.monitor = monitor
    }

    /// True when an automatic backup already succeeded on `date`'s local calendar day.
    public func hasSuccessfulAutomaticBackup(on date: Date) -> Bool {
        guard let last = lastAutomaticBackupDate else { return false }
        return calendar.isDate(last, inSameDayAs: date)
    }

    /// Today's scheduled time on `date`'s local day.
    public func scheduledTime(onDayOf date: Date) -> Date? {
        let minutes = dailyBackupMinutes
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)
    }

    /// The next time the daily backup should run: today's time if it's still ahead and today's backup hasn't
    /// succeeded, otherwise tomorrow's. DST gaps move forward to the next valid time.
    public func nextDailyBackupDate(after now: Date) -> Date? {
        let minutes = dailyBackupMinutes
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0)
        if !hasSuccessfulAutomaticBackup(on: now), let today = scheduledTime(onDayOf: now), today > now {
            return today
        }
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.nextDate(after: startOfTomorrow.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTime)
    }

    /// Replaces the single pending background request (never more than one), or cancels it when the daily
    /// backup shouldn't run.
    public func rescheduleDailyBackup() {
        scheduler.cancelDailyBackup()
        guard auth.config != nil, auth.currentUser != nil, cloudBackupEnabled, dailyBackupEnabled,
              let next = nextDailyBackupDate(after: clock()) else { return }
        scheduler.submitDailyBackup(earliestBeginDate: next)
    }

    /// Runs the automatic backup when it is due: Cloud Backup and the daily backup are on, today's scheduled
    /// time has passed and no automatic backup has succeeded today. Called by the background task, when the
    /// app becomes active, and when the network returns. Failures are not recorded as success, so a later
    /// opportunity retries. Always reschedules.
    @discardableResult
    public func runAutomaticBackupIfDue() async -> BackupReport? {
        defer { rescheduleDailyBackup() }
        let now = clock()
        guard auth.currentUser != nil, cloudBackupEnabled, dailyBackupEnabled, !hasSuccessfulAutomaticBackup(on: now),
              let due = scheduledTime(onDayOf: now), now >= due else { return nil }
        return await runBackup(kind: .automatic)
    }

    // MARK: Backup pipeline

    /// The single backup pipeline used by "Back Up Now", the first backup and the daily backup:
    /// optimize screenshots → full snapshot → upload → verify → record success.
    /// Only one runs at a time. Success is recorded only after the upload was verified.
    @discardableResult
    public func runBackup(kind: BackupKind) async -> BackupReport? {
        guard auth.config != nil else { status = .notConfigured; return nil }
        guard auth.currentUser != nil else { status = .notSignedIn; return nil }
        guard !isRunning, status != .restoring else { return nil }
        guard canUseLocalStore() else { status = .failed("Your data isn't available right now, so nothing was backed up."); return nil }
        guard isOnline else {
            status = .waitingForNetwork
            let report = BackupReport(kind: kind, date: clock(), outcome: .offline, screenshots: .init())
            lastReport = report
            return report
        }
        isRunning = true
        defer { isRunning = false; phase = .idle }

        // 1. Screenshots first (one at a time; originals kept until each copy is saved and verified).
        let context = contextProvider()
        phase = .optimizing(done: 0, total: 0)
        let screenshots = await ScreenshotStorageMigrator.optimizeExisting(in: context, storage: imageStorage) { [weak self] done, total in
            self?.phase = .optimizing(done: done, total: total)
        }
        if Task.isCancelled {
            let report = BackupReport(kind: kind, date: clock(), outcome: .failed("The backup was interrupted. It will be retried."), screenshots: screenshots)
            lastReport = report
            return report
        }

        // 2–4. Snapshot, upload, verify. Manual backups always upload; an automatic backup with no changes
        // since the last verified upload counts as done (the latest cloud backup already matches).
        let uploaded = await backupNow(force: kind == .manual)
        let now = clock()
        let outcome: BackupReport.Outcome
        if uploaded {
            outcome = status == .upToDate ? .succeeded : .failed("Backup failed.")
            if kind == .manual {
                lastManualBackupDate = now
                defaults.set(now, forKey: Self.lastManualKey)
            } else {
                lastAutomaticBackupDate = now
                defaults.set(now, forKey: Self.lastAutomaticKey)
            }
        } else if status == .waitingForNetwork {
            outcome = .offline
        } else if case .failed(let reason) = status {
            outcome = .failed(reason)
        } else {
            outcome = .failed("Backup failed.")
        }
        let report = BackupReport(kind: kind, date: now, outcome: outcome, screenshots: screenshots)
        lastReport = report
        return report
    }

    public func refreshStatus() {
        if auth.config == nil { status = .notConfigured }
        else if auth.currentUser == nil { status = .notSignedIn }
        else if status == .notSignedIn || status == .notConfigured { status = .idle }
    }

    // MARK: Upload

    /// Builds the full snapshot, uploads it, then verifies it (metadata row present, downloaded file identical)
    /// before recording success. Older backups are pruned only after that. Never touches local data.
    /// Used by `runBackup`, which optimizes screenshots first; call `runBackup` for user-facing backups.
    @discardableResult
    func backupNow(force: Bool = false) async -> Bool {
        guard let config = auth.config else { status = .notConfigured; return false }
        guard let user = auth.currentUser else { status = .notSignedIn; return false }
        guard canUseLocalStore() else { status = .failed("Local data isn't available (safe mode)."); return false }
        guard isOnline else { status = .waitingForNetwork; return false }
        guard status != .uploading && status != .restoring else { return false }

        phase = .creating
        let context = contextProvider()
        let payload = UserDataBackupService.makePayload(from: context)
        let hash = Self.contentHash(payload)
        if !force, hash == defaults.string(forKey: Self.lastHashKey) {
            status = .upToDate
            return true
        }

        status = .uploading
        var uploadedPath: String?
        var recordID: UUID?
        do {
            let data = try UserDataBackupService.makeEncoder().encode(payload)
            let token = try await auth.validAccessToken()
            let backupID = UUID()
            let path = "\(user.id)/\(device.id)/\(backupID.uuidString).json"
            phase = .uploading
            try await send(config: config, method: "POST", path: "storage/v1/object/\(Self.bucket)/\(path)", token: token,
                           body: data, headers: ["Content-Type": "application/json", "x-upsert": "false"])
            uploadedPath = path
            let record = CloudBackupRecord(
                id: backupID, deviceId: device.id, deviceName: device.name, appVersion: device.appVersion,
                schemaVersion: "\(SpenDropSchemaV5.versionIdentifier)", backupVersion: payload.version, createdAt: clock(),
                objectPath: path, expensesCount: payload.expenses.count, peopleCount: payload.paybookProfiles.count,
                accountsCount: payload.accounts?.count ?? 0, movementsCount: payload.moneyMovements?.count ?? 0, sizeBytes: data.count)
            try await send(config: config, method: "POST", path: "rest/v1/backups", token: token,
                           body: try CloudJSON.encoder().encode(record), headers: ["Prefer": "return=minimal"])
            recordID = backupID

            phase = .verifying
            try await verifyUpload(id: backupID, path: path, expected: data, config: config, token: token)

            defaults.set(hash, forKey: Self.lastHashKey)
            lastBackupDate = record.createdAt
            defaults.set(record.createdAt, forKey: Self.lastBackupKey)
            withMutation(keyPath: \.lastBackupSizeBytes) { defaults.set(data.count, forKey: Self.lastSizeKey) }
            status = .upToDate
            await pruneOldBackups(keeping: backupID, config: config, token: token)
            return true
        } catch {
            // Remove an upload that couldn't be completed or verified so it is never offered for restore.
            // Earlier verified backups are untouched.
            if uploadedPath != nil || recordID != nil, let token = try? await auth.validAccessToken() {
                if let uploadedPath { _ = try? await deleteObjects([uploadedPath], config: config, token: token) }
                if let recordID { _ = try? await send(config: config, method: "DELETE", path: "rest/v1/backups?id=eq.\(recordID.uuidString)", token: token) }
            }
            switch error {
            case CloudError.offline: status = .waitingForNetwork
            case CloudError.sessionExpired: status = .notSignedIn
            default: status = .failed(Self.friendlyMessage(error))
            }
            return false
        }
    }

    /// The upload counts only if its metadata row is readable and the stored file is byte-for-byte what was sent.
    private func verifyUpload(id: UUID, path: String, expected: Data, config: SupabaseConfig, token: String) async throws {
        let rows = try await send(config: config, method: "GET", path: "rest/v1/backups?select=id,object_path&id=eq.\(id.uuidString)", token: token)
        let list = (try? JSONSerialization.jsonObject(with: rows) as? [[String: Any]]) ?? []
        guard list.contains(where: { ($0["id"] as? String)?.lowercased() == id.uuidString.lowercased() && ($0["object_path"] as? String) == path }) else {
            throw CloudError.server(status: 0, message: "The backup couldn't be verified. It will be retried.")
        }
        let stored = try await send(config: config, method: "GET", path: "storage/v1/object/authenticated/\(Self.bucket)/\(path)", token: token)
        guard stored == expected else {
            throw CloudError.server(status: 0, message: "The backup couldn't be verified. It will be retried.")
        }
        // Restorable: the stored file reads back as a supported backup.
        guard let payload = try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: stored),
              UserDataBackupService.BackupPayload.supportedVersions.contains(payload.version) else {
            throw CloudError.server(status: 0, message: "The backup couldn't be verified. It will be retried.")
        }
    }

    static func friendlyMessage(_ error: Error) -> String {
        if case CloudError.server(let status, let message) = error, status == 0 { return message }
        if let cloud = error as? CloudError, cloud != .invalidResponse { return cloud.errorDescription ?? "Backup failed. It will be retried." }
        return "Backup failed. Your data on this iPhone is safe; it will be retried."
    }

    /// Stable fingerprint of the backed-up content (ignores export time and fetch order).
    static func contentHash(_ payload: UserDataBackupService.BackupPayload) -> String {
        struct Content: Encodable {
            let expenses: [UserDataBackupService.ExpenseDTO]
            let profiles: [UserDataBackupService.PayBookProfileDTO]
            let accounts: [UserDataBackupService.AccountDTO]
            let movements: [UserDataBackupService.MoneyMovementDTO]
            let rules: [UserDataBackupService.ClassificationRuleDTO]
            let settlements: [UserDataBackupService.SettlementAllocationDTO]
            let sample: [UserDataBackupService.SampleRecordDTO]
            let channelRules: [UserDataBackupService.ChannelRuleDTO]?   // nil when none, so older hashes are unchanged
        }
        let content = Content(
            expenses: payload.expenses.sorted { $0.id.uuidString < $1.id.uuidString },
            profiles: payload.paybookProfiles.sorted { $0.id.uuidString < $1.id.uuidString },
            accounts: (payload.accounts ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            movements: (payload.moneyMovements ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            rules: (payload.classificationRules ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            settlements: (payload.settlementAllocations ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            sample: (payload.sampleRecords ?? []).sorted { $0.recordID.uuidString < $1.recordID.uuidString },
            channelRules: (payload.channelRules ?? []).isEmpty ? nil : payload.channelRules!.sorted { $0.id.uuidString < $1.id.uuidString })
        let data = (try? CloudJSON.encoder().encode(content)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Removes this device's backup snapshots older than the retention period. Runs only after a new backup was
    /// uploaded AND verified; that newest backup is never removed, and a snapshot whose date can't be read is kept.
    /// Only cloud snapshot files are affected: transactions on the iPhone (the full history) are never touched.
    private func pruneOldBackups(keeping newestID: UUID, config: SupabaseConfig, token: String) async {
        let query = "rest/v1/backups?select=id,object_path,created_at&device_id=eq.\(device.id)&order=created_at.desc"
        guard let data = try? await send(config: config, method: "GET", path: query, token: token),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let cutoff = clock().addingTimeInterval(-Double(backupRetentionDays) * 86_400)
        let expired = rows.filter { row in
            guard let id = row["id"] as? String, id.lowercased() != newestID.uuidString.lowercased(),
                  let text = row["created_at"] as? String, let created = CloudJSON.parseDate(text) else { return false }
            return created < cutoff
        }
        guard !expired.isEmpty else { return }
        let paths = expired.compactMap { $0["object_path"] as? String }
        let ids = expired.compactMap { $0["id"] as? String }
        _ = try? await deleteObjects(paths, config: config, token: token)
        _ = try? await send(config: config, method: "DELETE", path: "rest/v1/backups?id=in.(\(ids.joined(separator: ",")))", token: token)
    }

    /// How long cloud backup snapshots are kept (30 or 90 days). This is snapshot retention only, never data retention.
    public static let retentionChoices = [30, 90]
    private static let retentionKey = "SpenDrop.cloudBackupRetentionDays"
    private static let lastSizeKey = "SpenDrop.cloudLastBackupSizeBytes"

    public var backupRetentionDays: Int {
        get {
            access(keyPath: \.backupRetentionDays)
            let stored = defaults.integer(forKey: Self.retentionKey)
            return Self.retentionChoices.contains(stored) ? stored : 30
        }
        set {
            guard Self.retentionChoices.contains(newValue) else { return }
            withMutation(keyPath: \.backupRetentionDays) { defaults.set(newValue, forKey: Self.retentionKey) }
        }
    }

    /// Size of the most recent verified backup file, in bytes.
    public var lastBackupSizeBytes: Int {
        access(keyPath: \.lastBackupSizeBytes)
        return defaults.integer(forKey: Self.lastSizeKey)
    }

    // MARK: Restore

    public func listBackups() async throws -> [CloudBackupRecord] {
        guard let config = auth.config else { throw CloudError.notConfigured }
        let token = try await auth.validAccessToken()
        let data = try await send(config: config, method: "GET", path: "rest/v1/backups?select=*&order=created_at.desc&limit=30", token: token)
        return try CloudJSON.decoder().decode([CloudBackupRecord].self, from: data)
    }

    /// Downloads and validates one of the signed-in user's backups. Writes nothing.
    public func downloadBackup(_ record: CloudBackupRecord) async throws -> UserDataBackupService.BackupPayload {
        guard let config = auth.config else { throw CloudError.notConfigured }
        guard isOnline else { throw CloudError.offline }
        let token = try await auth.validAccessToken()
        let data = try await send(config: config, method: "GET", path: "storage/v1/object/authenticated/\(Self.bucket)/\(record.objectPath)", token: token)
        let payload: UserDataBackupService.BackupPayload
        do {
            payload = try UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: data)
        } catch {
            throw CloudError.invalidResponse
        }
        guard UserDataBackupService.BackupPayload.supportedVersions.contains(payload.version) else {
            throw CloudError.unsupportedBackup(payload.version)
        }
        return payload
    }

    /// Plans a restore of `range` from a downloaded backup against this device's current records (writes nothing).
    public func makeRestorePlan(_ payload: UserDataBackupService.BackupPayload, range: RestoreRange,
                                calendar: Calendar = .current) -> UserDataBackupService.RestorePlan {
        UserDataBackupService.makeRestorePlan(from: payload, range: range, calendar: calendar,
                                              localIDs: .fetch(from: contextProvider()))
    }

    /// Applies a confirmed plan: saves a LOCAL safety copy first, then merges by stable id and saves once
    /// (rolled back if the save fails). Never deletes local records.
    public func restore(_ plan: UserDataBackupService.RestorePlan) throws -> UserDataBackupService.RestoreResult {
        guard canUseLocalStore() else { throw CloudError.safetyBackupFailed }
        guard !isBackupRunning, status != .restoring else {
            throw CloudError.server(status: 0, message: "A backup is running. Try again when it has finished.")
        }
        status = .restoring
        defer { if status == .restoring { status = .idle } }
        let context = contextProvider()
        guard makeSafetyBackup(context) else { throw CloudError.safetyBackupFailed }
        return try UserDataBackupService.applyRestorePlan(plan, into: context)
    }

    /// Downloads, validates, saves a LOCAL safety copy, then merges the whole backup by stable id.
    /// Nothing is applied if any step before the merge fails.
    public func restore(_ record: CloudBackupRecord) async throws -> UserDataBackupService.ImportSummary {
        guard canUseLocalStore() else { throw CloudError.safetyBackupFailed }
        let payload = try await downloadBackup(record)
        return try restore(makeRestorePlan(payload, range: .everything)).summary
    }

    /// Removes every cloud backup of this user (files first, then metadata). Used by account deletion.
    public func deleteAllCloudData() async throws {
        guard let config = auth.config else { throw CloudError.notConfigured }
        let token = try await auth.validAccessToken()
        let data = try await send(config: config, method: "GET", path: "rest/v1/backups?select=id,object_path", token: token)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let paths = rows.compactMap { $0["object_path"] as? String }
        if !paths.isEmpty {
            try await deleteObjects(paths, config: config, token: token)
        }
        try await send(config: config, method: "DELETE", path: "rest/v1/backups?id=not.is.null", token: token)
        defaults.removeObject(forKey: Self.lastHashKey)
        defaults.removeObject(forKey: Self.lastBackupKey)
        lastBackupDate = nil
        status = .notSignedIn
    }

    // MARK: Local safety copy

    /// Writes the current local data to the backup history before a cloud restore. Returns false on failure.
    static func writeLocalSafetyBackup(from context: ModelContext) -> Bool {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SpenDropBackupHistory", isDirectory: true),
              let data = try? UserDataBackupService.makeEncoder().encode(UserDataBackupService.makePayload(from: context)) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("SpenDrop_AutoBackup_before-cloud-restore_\(ExpenseDataContainer.timestampString(Date())).json")
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: HTTP

    @discardableResult
    private func send(config: SupabaseConfig, method: String, path: String, token: String, body: Data? = nil,
                      headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.url.appendingPathComponent("")) else { throw CloudError.invalidResponse }
        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil && headers["Content-Type"] == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw CloudJSON.error(status: response.statusCode, data: data) }
        return data
    }

    private func deleteObjects(_ paths: [String], config: SupabaseConfig, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["prefixes": paths])
        try await send(config: config, method: "DELETE", path: "storage/v1/object/\(Self.bucket)", token: token, body: body)
    }
}


// MARK: - Backup kinds, reports and scheduling

public enum BackupKind: String, Equatable {
    case manual, automatic
}

public enum BackupPhase: Equatable {
    case idle
    case optimizing(done: Int, total: Int)
    case creating
    case uploading
    case verifying

    public var title: String? {
        switch self {
        case .idle: return nil
        case .optimizing(let done, let total): return total == 0 ? "Preparing backup…" : "Optimizing receipts: \(done) / \(total)"
        case .creating: return "Creating backup…"
        case .uploading: return "Uploading backup…"
        case .verifying: return "Checking backup…"
        }
    }
}

public struct BackupReport: Equatable {
    public enum Outcome: Equatable {
        case succeeded
        case offline
        case failed(String)
    }
    public let kind: BackupKind
    public let date: Date
    public let outcome: Outcome
    public let screenshots: ScreenshotStorageMigrator.Report

    public var succeeded: Bool { outcome == .succeeded }

    /// "42 receipts checked · 18 optimized · 24 already optimized · 0 failed"
    public var screenshotSummary: String {
        let s = screenshots
        var parts = ["\(s.checked) receipts checked", "\(s.optimized) optimized", "\(s.alreadySmall) already optimized", "\(s.keptOriginal) failed"]
        if s.missing > 0 { parts.append("\(s.missing) missing") }
        return parts.joined(separator: " · ")
    }

    public var message: String {
        switch outcome {
        case .succeeded: return "Backup complete"
        case .offline: return "You're offline. The backup will run when you're back online."
        case .failed(let reason): return reason
        }
    }
}

/// Schedules the one daily background request. Abstracted so tests can check rescheduling without iOS.
@MainActor
public protocol BackupTaskScheduling: AnyObject {
    func cancelDailyBackup()
    func submitDailyBackup(earliestBeginDate: Date)
}

/// Used where no background scheduling is wanted (tests, previews).
@MainActor
public final class NoBackupTaskScheduler: BackupTaskScheduling {
    nonisolated public init() {}
    public func cancelDailyBackup() {}
    public func submitDailyBackup(earliestBeginDate: Date) {}
}

/// iOS background processing task for the daily backup. One request with a fixed identifier: submitting
/// replaces any pending one, and it is cancelled first, so there is never more than one.
@MainActor
public final class SystemBackupTaskScheduler: BackupTaskScheduling {
    public static let identifier = "com.spendrop.SpenDrop.dailyBackup"

    public init() {}

    public func cancelDailyBackup() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
    }

    public func submitDailyBackup(earliestBeginDate: Date) {
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = earliestBeginDate  // iOS decides the actual time ("around")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[SpenDrop][CloudBackup] Daily backup could not be scheduled: \(error.localizedDescription)")
        }
    }

    /// Registers the handler (call once, before launch finishes). The handler runs the backup only if it is due,
    /// stops cleanly if iOS ends the task early (nothing is marked successful then), and always reschedules.
    nonisolated public static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task { @MainActor in
                let report = await CloudBackupService.shared.runAutomaticBackupIfDue()
                task.setTaskCompleted(success: report.map(\.succeeded) ?? true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
}
