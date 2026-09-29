import Foundation
import SwiftData

// MARK: - Schema V1 (frozen)

/// The database schema exactly as shipped before Financial Architecture V2.
/// These nested models are a FROZEN copy of the old model shapes so SwiftData can recognise existing stores.
/// Never edit them: any change here makes existing databases unrecognisable.
public enum SpenDropSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self]
    }

