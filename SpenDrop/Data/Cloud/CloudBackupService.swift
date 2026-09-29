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

