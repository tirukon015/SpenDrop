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
    public static let keepPerDevice = 10

    public static let shared = CloudBackupService(
        auth: .shared,
        transport: URLSessionTransport(),
        defaults: .standard,
        device: .current,
        contextProvider: { ExpenseDataContainer.shared.mainContext },
        canUseLocalStore: { ExpenseDataContainer.isPersistentStoreHealthy },
        makeSafetyBackup: { context in CloudBackupService.writeLocalSafetyBackup(from: context) }
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
    public private(set) var lastBackupDate: Date?
    public var isOnline = true {
        didSet {
            if isOnline && !oldValue && pendingBackup { scheduleBackup(delay: .seconds(2)) }
        }
    }

    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let transport: HTTPTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let device: Device
    @ObservationIgnored private let contextProvider: () -> ModelContext
    @ObservationIgnored private let canUseLocalStore: () -> Bool
    @ObservationIgnored private let makeSafetyBackup: (ModelContext) -> Bool
    @ObservationIgnored private var pendingBackup = false
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private var didSaveObserver: NSObjectProtocol?
    @ObservationIgnored private var monitor: NWPathMonitor?

    private static let lastBackupKey = "SpenDrop.cloudLastBackupDate"
    private static let lastHashKey = "SpenDrop.cloudLastBackupHash"

    public init(auth: AuthService, transport: HTTPTransport, defaults: UserDefaults, device: Device,
                contextProvider: @escaping () -> ModelContext, canUseLocalStore: @escaping () -> Bool,
                makeSafetyBackup: @escaping (ModelContext) -> Bool) {
        self.auth = auth
        self.transport = transport
        self.defaults = defaults
        self.device = device
        self.contextProvider = contextProvider
        self.canUseLocalStore = canUseLocalStore
        self.makeSafetyBackup = makeSafetyBackup
        self.lastBackupDate = defaults.object(forKey: Self.lastBackupKey) as? Date
        self.status = auth.config == nil ? .notConfigured : (auth.currentUser == nil ? .notSignedIn : .idle)
    }

    // MARK: Automatic backups

    /// Backs up (debounced) after local saves and when connectivity returns. Safe to call more than once.
    public func startAutomaticBackups() {
        guard didSaveObserver == nil, auth.config != nil else { return }
        didSaveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleBackup() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "SpenDrop.network"))
        self.monitor = monitor
    }

    /// Coalesces bursts of saves into one upload.
    public func scheduleBackup(delay: Duration = .seconds(20)) {
        guard auth.currentUser != nil else { return }
        pendingBackup = true
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            _ = await self?.backupNow()
        }
    }

    public func refreshStatus() {
        if auth.config == nil { status = .notConfigured }
        else if auth.currentUser == nil { status = .notSignedIn }
        else if status == .notSignedIn || status == .notConfigured { status = .idle }
    }

    // MARK: Backup

    /// Uploads a new backup when local data changed since the last successful one. Never blocks local use:
    /// failures only change `status`.
    @discardableResult
    public func backupNow(force: Bool = false) async -> Bool {
        guard let config = auth.config else { status = .notConfigured; return false }
        guard let user = auth.currentUser else { status = .notSignedIn; return false }
        guard canUseLocalStore() else { status = .failed("Local data isn't available (safe mode)."); return false }
        guard isOnline else { pendingBackup = true; status = .waitingForNetwork; return false }
        guard status != .uploading && status != .restoring else { return false }

        let context = contextProvider()
        let payload = UserDataBackupService.makePayload(from: context)
        let hash = Self.contentHash(payload)
        if !force, hash == defaults.string(forKey: Self.lastHashKey) {
            pendingBackup = false
            status = .upToDate
            return true
        }

        status = .uploading
        do {
            let data = try UserDataBackupService.makeEncoder().encode(payload)
            let token = try await auth.validAccessToken()
            let backupID = UUID()
            let path = "\(user.id)/\(device.id)/\(backupID.uuidString).json"
            try await send(config: config, method: "POST", path: "storage/v1/object/\(Self.bucket)/\(path)", token: token,
                           body: data, headers: ["Content-Type": "application/json", "x-upsert": "false"])
            let record = CloudBackupRecord(
                id: backupID, deviceId: device.id, deviceName: device.name, appVersion: device.appVersion,
                schemaVersion: "\(SpenDropSchemaV3.versionIdentifier)", backupVersion: payload.version, createdAt: Date(),
                objectPath: path, expensesCount: payload.expenses.count, peopleCount: payload.paybookProfiles.count,
                accountsCount: payload.accounts?.count ?? 0, movementsCount: payload.moneyMovements?.count ?? 0, sizeBytes: data.count)
            do {
                try await send(config: config, method: "POST", path: "rest/v1/backups", token: token,
                               body: try CloudJSON.encoder().encode(record), headers: ["Prefer": "return=minimal"])
            } catch {
                // Keep the cloud consistent: remove the file whose metadata could not be recorded.
                _ = try? await deleteObjects([path], config: config, token: token)
                throw error
            }
            defaults.set(hash, forKey: Self.lastHashKey)
            lastBackupDate = record.createdAt
            defaults.set(record.createdAt, forKey: Self.lastBackupKey)
            pendingBackup = false
            status = .upToDate
            await pruneOldBackups(config: config, token: token)
            return true
        } catch CloudError.offline {
            pendingBackup = true
            status = .waitingForNetwork
        } catch CloudError.sessionExpired {
            status = .notSignedIn
        } catch {
            pendingBackup = true
            status = .failed((error as? LocalizedError)?.errorDescription ?? "Cloud backup failed.")
        }
        return false
    }

    /// Stable fingerprint of the backed-up content (ignores export time and fetch order).
    static func contentHash(_ payload: UserDataBackupService.BackupPayload) -> String {
        struct Content: Encodable {
            let expenses: [UserDataBackupService.ExpenseDTO]
            let profiles: [UserDataBackupService.PayBookProfileDTO]
            let accounts: [UserDataBackupService.AccountDTO]
            let movements: [UserDataBackupService.MoneyMovementDTO]
            let rules: [UserDataBackupService.ClassificationRuleDTO]
        }
        let content = Content(
            expenses: payload.expenses.sorted { $0.id.uuidString < $1.id.uuidString },
            profiles: payload.paybookProfiles.sorted { $0.id.uuidString < $1.id.uuidString },
            accounts: (payload.accounts ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            movements: (payload.moneyMovements ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
            rules: (payload.classificationRules ?? []).sorted { $0.id.uuidString < $1.id.uuidString })
        let data = (try? CloudJSON.encoder().encode(content)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func pruneOldBackups(config: SupabaseConfig, token: String) async {
        let query = "rest/v1/backups?select=id,object_path&device_id=eq.\(device.id)&order=created_at.desc&offset=\(Self.keepPerDevice)"
        guard let data = try? await send(config: config, method: "GET", path: query, token: token),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !rows.isEmpty else { return }
        let paths = rows.compactMap { $0["object_path"] as? String }
        let ids = rows.compactMap { $0["id"] as? String }
        _ = try? await deleteObjects(paths, config: config, token: token)
        _ = try? await send(config: config, method: "DELETE", path: "rest/v1/backups?id=in.(\(ids.joined(separator: ",")))", token: token)
    }

    // MARK: Restore

    public func listBackups() async throws -> [CloudBackupRecord] {
        guard let config = auth.config else { throw CloudError.notConfigured }
        let token = try await auth.validAccessToken()
        let data = try await send(config: config, method: "GET", path: "rest/v1/backups?select=*&order=created_at.desc&limit=30", token: token)
        return try CloudJSON.decoder().decode([CloudBackupRecord].self, from: data)
    }

