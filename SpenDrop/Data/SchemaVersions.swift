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

    @Model
    public final class Expense {
        @Attribute(.unique) public var id: UUID
        public var amount: Double
        public var currency: String
        public var merchant: String
        public var categoryRaw: String
        public var paymentSourceRaw: String
        public var underlyingBankRaw: String?
        public var paymentMethodRaw: String?
        public var date: Date
        public var notes: String?
        public var transactionReference: String?
        public var imageRelativePath: String?
        public var sourceTypeRaw: String
        public var ocrText: String?
        public var confidence: Double?
        public var isSampleData: Bool
        public var createdAt: Date
        public var updatedAt: Date
        public var paymentChannelRaw: String = "UNKNOWN"
        public var fundingAccount: String = "Unknown"
        public var fundingInstrument: String? = nil
        public var externalTransactionId: String? = nil
        public var matchingStatusRaw: String = "UNMATCHED"
        public var matchingConfidence: Double? = nil

        public init(id: UUID = UUID(), amount: Double, merchant: String, fundingAccount: String = "Unknown", date: Date = Date()) {
            self.id = id
            self.amount = amount
            self.currency = "RM"
            self.merchant = merchant
            self.categoryRaw = "Other"
            self.paymentSourceRaw = "Unknown"
            self.date = date
            self.sourceTypeRaw = "manual"
            self.isSampleData = false
            self.createdAt = Date()
            self.updatedAt = Date()
            self.fundingAccount = fundingAccount
        }
    }

    @Model
    public final class PayBookProfile {
        @Attribute(.unique) public var id: UUID
        public var name: String
        @Attribute(.externalStorage) public var photoData: Data?
        public var notes: String?
        public var createdAt: Date
        public var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \PayBookPaymentMethod.profile)
        public var paymentMethods: [PayBookPaymentMethod] = []

        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    public final class PayBookPaymentMethod {
        @Attribute(.unique) public var id: UUID
        public var paymentTypeRaw: String
        public var provider: String
        public var customProviderName: String?
        public var accountIdentifier: String
        public var label: String?
        public var notes: String?
        public var createdAt: Date
        public var updatedAt: Date

        public var profile: PayBookProfile?

        public init(id: UUID = UUID(), provider: String, accountIdentifier: String, profile: PayBookProfile? = nil) {
            self.id = id
            self.paymentTypeRaw = "Bank Account"
            self.provider = provider
            self.accountIdentifier = accountIdentifier
            self.createdAt = Date()
            self.updatedAt = Date()
            self.profile = profile
        }
    }

