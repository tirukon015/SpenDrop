import Foundation
import SwiftData

// Live sync with the SpenDrop cloud records (Docs/IOS-Sync-Design.md). This file: the cloud tables, the change
// records produced by local saves, and the persistent outbox. The outbox lives in its OWN SwiftData store
// ("SpenDropSync.store"), so the user's main store/schema (V6) is not changed by sync at all.

/// Cloud tables (Supabase/supabase/migrations/20261007000000_spendrop_cloud_records.sql).
public enum SyncTable: String, CaseIterable, Sendable, Codable {
    case accounts
    case people
    case personPaymentMethods = "person_payment_methods"
    case expenses
    case expenseShares = "expense_shares"
    case moneyMovements = "money_movements"
    case settlementAllocations = "settlement_allocations"
    case classificationRules = "classification_rules"
    case channelRules = "channel_rules"

    /// Foreign-key-safe push order. Shares are pushed with their expense (save_expense_with_shares).
    public static let pushOrder: [SyncTable] = [.accounts, .people, .personPaymentMethods, .expenses, .moneyMovements,
                                                .settlementAllocations, .classificationRules, .channelRules]
    /// Pull order: parents before children so references resolve.
    public static let pullOrder: [SyncTable] = [.accounts, .people, .personPaymentMethods, .expenses, .expenseShares,
                                                .moneyMovements, .settlementAllocations, .classificationRules, .channelRules]
}

public enum SyncOpKind: String, Sendable, Codable {
    case create, update, delete

    var isUpsert: Bool { self != .delete }
}

/// One local change, as recorded from a save (ids only; the payload is read at send time).
public struct SyncChange: Sendable, Hashable {
    public let table: SyncTable
    public let id: UUID
    public let op: SyncOpKind
    public let changedAt: Date
    /// Part of a mass delete: recorded, but not sent until the user confirms.
    public var held: Bool = false

    public init(table: SyncTable, id: UUID, op: SyncOpKind, changedAt: Date, held: Bool = false) {
        self.table = table
        self.id = id
        self.op = op
        self.changedAt = changedAt
        self.held = held
    }
}

// MARK: - Outbox store models

/// One pending change of one record, coalesced per (user, table, id). Removed only after the server confirmed it.
@Model
public final class SyncOperation {
    @Attribute(.unique) public var key: String
    public var userId: String
    public var tableRaw: String
    public var entityId: UUID
    /// create | update | delete
    public var operationRaw: String
    /// pending | failed | held
    public var statusRaw: String
    public var retryCount: Int
    public var nextAttemptAt: Date
    public var createdAt: Date
    /// Time of the latest local change (the LWW time of this op).
    public var changedAt: Date
    public var lastError: String?
    /// An upsert of this record was sent at least once (the server may have seen it).
    public var attempted: Bool

    public init(userId: String, table: SyncTable, entityId: UUID, operation: SyncOpKind, status: String = "pending",
                changedAt: Date, now: Date) {
        self.key = SyncOperation.key(userId: userId, table: table, id: entityId)
        self.userId = userId
        self.tableRaw = table.rawValue
        self.entityId = entityId
        self.operationRaw = operation.rawValue
        self.statusRaw = status
        self.retryCount = 0
        self.nextAttemptAt = now
        self.createdAt = now
        self.changedAt = changedAt
        self.lastError = nil
        self.attempted = false
    }

    public static func key(userId: String, table: SyncTable, id: UUID) -> String {
        "\(userId)|\(table.rawValue)|\(id.uuidString.lowercased())"
    }

    public var table: SyncTable? { SyncTable(rawValue: tableRaw) }
    public var operation: SyncOpKind { SyncOpKind(rawValue: operationRaw) ?? .update }
}

/// Pull cursor per (user, table): keyset (server_updated_at, id), stored exactly as the server sent it.
@Model
public final class SyncCursor {
    @Attribute(.unique) public var key: String
    public var serverUpdatedAt: String
    public var lastId: String

    public init(key: String, serverUpdatedAt: String, lastId: String) {
        self.key = key
        self.serverUpdatedAt = serverUpdatedAt
        self.lastId = lastId
    }
}

/// What this device last sent for a record (to recognise its own echo on the next pull) and cloud-only fields that
/// iOS doesn't store but must not wipe (an expense's Web receipt path).
@Model
public final class SyncRecordMeta {
    @Attribute(.unique) public var key: String
    public var lastSentUpdatedAt: Date?
    public var receiptPath: String?

    public init(key: String) {
        self.key = key
    }
}

public enum SyncOutboxStore {
    public static let schema = Schema([SyncOperation.self, SyncCursor.self, SyncRecordMeta.self])

    /// The outbox store next to the main store (App Group), or the given file / memory (tests).
    public static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration("SpenDropSync", schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration("SpenDropSync", schema: schema, url: url ?? defaultURL())
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: ExpenseDataContainer.appGroupIdentifier)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("SpenDropSync.store")
    }
}

// MARK: - Settings (UserDefaults; thread-safe)

/// Which account this iPhone's data is linked to, the per-user "Sync across devices" switch and a few marks.
public final class SyncSettings: @unchecked Sendable {
    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static let ownerKey = "SpenDrop.sync.ownerUserId"
    private static let enabledKey = "SpenDrop.sync.enabled."
    private static let lastSyncKey = "SpenDrop.sync.lastSyncDate."
    private static let lastFullPullKey = "SpenDrop.sync.lastFullPull."
    private static let catchUpKey = "SpenDrop.sync.catchUpMark"
    /// Written by the Share Extension process after it saved (the app then catches up on launch/foreground).
    public static let extensionSaveKey = "SpenDrop.sync.extensionLastSave"

    /// The account this iPhone's data belongs to (set when sync is first enabled). Ops are recorded for it.
    public var ownerUserId: String? {
        get { defaults.string(forKey: Self.ownerKey) }
        set { defaults.set(newValue, forKey: Self.ownerKey) }
    }

    /// "Sync across devices": on by default for a signed-in user.
    public func isEnabled(for userId: String) -> Bool {
        (defaults.object(forKey: Self.enabledKey + userId) as? Bool) ?? true
    }

    public func setEnabled(_ on: Bool, for userId: String) {
        defaults.set(on, forKey: Self.enabledKey + userId)
    }

    public func lastSyncDate(for userId: String) -> Date? { defaults.object(forKey: Self.lastSyncKey + userId) as? Date }
    public func setLastSyncDate(_ date: Date, for userId: String) { defaults.set(date, forKey: Self.lastSyncKey + userId) }
    public func lastFullPull(for userId: String) -> Date? { defaults.object(forKey: Self.lastFullPullKey + userId) as? Date }
    public func setLastFullPull(_ date: Date?, for userId: String) { defaults.set(date, forKey: Self.lastFullPullKey + userId) }

    public var catchUpMark: Date? {
        get { defaults.object(forKey: Self.catchUpKey) as? Date }
        set { defaults.set(newValue, forKey: Self.catchUpKey) }
    }

    /// Records with changes newer than this are re-checked on launch (Share Extension saves happen in another process).
    public static func noteExtensionSave(now: Date = Date()) {
        UserDefaults(suiteName: ExpenseDataContainer.appGroupIdentifier)?.set(now, forKey: extensionSaveKey)
    }

    public var extensionLastSave: Date? {
        (UserDefaults(suiteName: ExpenseDataContainer.appGroupIdentifier) ?? defaults).object(forKey: Self.extensionSaveKey) as? Date
    }
}

// MARK: - Auth for sync

public struct SyncSession: Sendable, Equatable {
    public let userId: String
    public let token: String

    public init(userId: String, token: String) {
        self.userId = userId
        self.token = token
    }
}

/// The signed-in user and a valid access token (nil when signed out).
public protocol SyncAuthProviding: AnyObject, Sendable {
    func session(forceRefresh: Bool) async throws -> SyncSession?
}

/// Uses the app's AuthService (Keychain session, token refresh).
public final class AuthServiceSyncProvider: SyncAuthProviding, @unchecked Sendable {
    private let auth: AuthService

    public init(auth: AuthService) {
        self.auth = auth
    }

    public func session(forceRefresh: Bool) async throws -> SyncSession? {
        guard let user = await auth.currentUser else { return nil }
        let token = try await auth.validAccessToken(forceRefresh: forceRefresh)
        guard let current = await auth.currentUser, current.id == user.id else { return nil }
        return SyncSession(userId: user.id, token: token)
    }
}
