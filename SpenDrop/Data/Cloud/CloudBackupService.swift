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
