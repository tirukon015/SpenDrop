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

    @Model
    public final class PayBookContact {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var bankName: String
        public var accountHolderName: String
        public var accountNumber: String
        public var phoneNumber: String?
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
            self.bankName = ""
            self.accountHolderName = ""
            self.accountNumber = ""
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}

// MARK: - Schema V2 (frozen)

/// Adds Account, ExpenseShare, MoneyMovement, the payer/split/account fields on Expense and
/// isFrequent/isArchived on PayBookProfile. Every new field is optional or has a default.
/// Until schema V6 these were the live model types. V6 added a field to Expense, so the V2 models were frozen
/// here as an exact copy of what shipped (V2–V5 stores must keep being recognised). Never edit them: tests check both
/// the V2 fingerprint and the Core Data version hashes of the shipped V5 model.
public enum SpenDropSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Expense.self,
            PayBookProfile.self,
            PayBookPaymentMethod.self,
            PayBookContact.self,
            Account.self,
            ExpenseShare.self,
            MoneyMovement.self
        ]
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
        public var account: Account? = nil
        public var paidByMe: Bool = true
        public var payer: PayBookProfile? = nil
        public var payerNameSnapshot: String? = nil
        public var splitMethodRaw: String? = nil

        @Relationship(deleteRule: .cascade, inverse: \ExpenseShare.expense)
        public var shares: [ExpenseShare] = []

        @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.linkedExpense)
        public var linkedMovements: [MoneyMovement] = []

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

        public var isFrequent: Bool = false
        public var isArchived: Bool = false

        @Relationship(deleteRule: .nullify, inverse: \ExpenseShare.person)
        public var shares: [ExpenseShare] = []

        @Relationship(deleteRule: .nullify, inverse: \Expense.payer)
        public var paidExpenses: [Expense] = []

        @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.person)
        public var movements: [MoneyMovement] = []

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

    @Model
    public final class PayBookContact {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var bankName: String
        public var accountHolderName: String
        public var accountNumber: String
        public var phoneNumber: String?
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
            self.bankName = ""
            self.accountHolderName = ""
            self.accountNumber = ""
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    public final class Account {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var typeRaw: String
        public var currency: String
        public var icon: String?
        public var isArchived: Bool = false
        public var createdAt: Date
        public var sortIndex: Int = 0

        @Relationship(deleteRule: .nullify, inverse: \Expense.account)
        public var expenses: [Expense] = []

        @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.account)
        public var movements: [MoneyMovement] = []

        @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.counterAccount)
        public var incomingTransfers: [MoneyMovement] = []

        public init(id: UUID = UUID(), name: String, typeRaw: String, currency: String, sortIndex: Int) {
            self.id = id
            self.name = name
            self.typeRaw = typeRaw
            self.currency = currency
            self.createdAt = Date()
            self.sortIndex = sortIndex
        }
    }

    @Model
    public final class ExpenseShare {
        @Attribute(.unique) public var id: UUID
        public var expense: Expense?
        public var person: PayBookProfile?
        public var isMe: Bool
        public var nameSnapshot: String
        public var amountMinor: Int
        public var parts: Int?
        public var enteredMinor: Int?
        public var sortIndex: Int

        public init(id: UUID = UUID(), isMe: Bool, nameSnapshot: String, amountMinor: Int, parts: Int? = nil,
                    enteredMinor: Int? = nil, sortIndex: Int) {
            self.id = id
            self.isMe = isMe
            self.nameSnapshot = nameSnapshot
            self.amountMinor = amountMinor
            self.parts = parts
            self.enteredMinor = enteredMinor
            self.sortIndex = sortIndex
        }
    }

    @Model
    public final class MoneyMovement {
        @Attribute(.unique) public var id: UUID
        public var directionRaw: String
        public var kindRaw: String
        public var amountMinor: Int
        public var currency: String
        public var date: Date
        public var person: PayBookProfile?
        public var personNameSnapshot: String?
        public var linkedExpense: Expense?
        public var linkedExpenseSnapshot: String?
        public var account: Account?
        public var counterAccount: Account?
        public var note: String?
        public var transactionReference: String?
        public var sourceTypeRaw: String
        public var paymentChannelRaw: String
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), directionRaw: String, kindRaw: String, amountMinor: Int) {
            self.id = id
            self.directionRaw = directionRaw
            self.kindRaw = kindRaw
            self.amountMinor = amountMinor
            self.currency = "RM"
            self.date = Date()
            self.sourceTypeRaw = "manual"
            self.paymentChannelRaw = "UNKNOWN"
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    /// The V1 -> V2 step's account linking (same rules as `AccountLinker.linkUnlinkedExpenses`), written against the
    /// frozen V2 models because that migration context only knows the V2 model.
    @discardableResult
    static func linkUnlinkedExpenses(in context: ModelContext) -> (accountsCreated: Int, expensesLinked: Int) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
        var accountsByKey: [String: Account] = [:]
        for account in accounts {
            if let key = AccountLinker.normalizedKey(account.name), accountsByKey[key] == nil {
                accountsByKey[key] = account
            }
        }
        var nextSortIndex = (accounts.map(\.sortIndex).max() ?? -1) + 1
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var created = 0
        var linked = 0
        for expense in expenses where expense.account == nil {
            guard let key = AccountLinker.normalizedKey(expense.fundingAccount) else { continue }
            let account: Account
            if let existing = accountsByKey[key] {
                account = existing
            } else {
                let name = expense.fundingAccount.trimmingCharacters(in: .whitespacesAndNewlines)
                account = Account(name: name, typeRaw: AccountLinker.inferredType(forName: name).rawValue, currency: expense.currency,
                                  sortIndex: nextSortIndex)
                context.insert(account)
                accountsByKey[key] = account
                nextSortIndex += 1
                created += 1
            }
            expense.account = account
            linked += 1
        }
        return (created, linked)
    }
}

// MARK: - Schema V3

/// V2 + ClassificationRule (a new, standalone table for locally learned suggestions). No V2 table changes.
public enum SpenDropSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SpenDropSchemaV2.models + [ClassificationRule.self]
    }
}

// MARK: - Schema V4

/// V3 + SettlementAllocation (which payment settled which expense/loan) and SampleDataRecord (which records are
/// demo data). Two new standalone tables that refer to existing records by id; no existing table changes.
public enum SpenDropSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SpenDropSchemaV3.models + [SettlementAllocation.self, SampleDataRecord.self]
    }
}

// MARK: - Schema V5

/// V4 + ChannelRule (learned payment channel per merchant and funding account). One new standalone table;
/// no existing table changes.
public enum SpenDropSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SpenDropSchemaV4.models + [ChannelRule.self]
    }
}

// MARK: - Schema V6 (current)

/// V5 with one optional field on Expense: `splitRule` (the Hybrid Split rule as JSON; nil for every existing expense).
/// Lists the live model types; the V2 tables up to V5 are the frozen copies in `SpenDropSchemaV2`.
/// A future change to any live type must first freeze a copy, exactly as V2 does.
public enum SpenDropSchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Expense.self,
            PayBookProfile.self,
            PayBookPaymentMethod.self,
            PayBookContact.self,
            Account.self,
            ExpenseShare.self,
            MoneyMovement.self,
            ClassificationRule.self,
            SettlementAllocation.self,
            SampleDataRecord.self,
            ChannelRule.self
        ]
    }
}

// MARK: - Migration Plan

public enum SpenDropMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SpenDropSchemaV1.self, SpenDropSchemaV2.self, SpenDropSchemaV3.self, SpenDropSchemaV4.self, SpenDropSchemaV5.self,
         SpenDropSchemaV6.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    /// Only adds the optional Expense.splitRule column (nil for every existing expense); existing data is untouched.
    static let migrateV5toV6 = MigrationStage.lightweight(fromVersion: SpenDropSchemaV5.self, toVersion: SpenDropSchemaV6.self)

    /// Only adds the ChannelRule table; existing data is untouched.
    static let migrateV4toV5 = MigrationStage.lightweight(fromVersion: SpenDropSchemaV4.self, toVersion: SpenDropSchemaV5.self)

    /// Only adds the SettlementAllocation and SampleDataRecord tables; existing data is untouched.
    static let migrateV3toV4 = MigrationStage.lightweight(fromVersion: SpenDropSchemaV3.self, toVersion: SpenDropSchemaV4.self)

    /// Only adds the ClassificationRule table; existing data is untouched.
    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: SpenDropSchemaV2.self, toVersion: SpenDropSchemaV3.self)

    /// Adds the new tables/columns (no existing column is removed or changed), then creates one Account per
    /// distinct meaningful `fundingAccount` value and links existing expenses to it. The text is not modified.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SpenDropSchemaV1.self,
        toVersion: SpenDropSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let result = SpenDropSchemaV2.linkUnlinkedExpenses(in: context)
            try context.save()
            print("[SpenDropMigration] V1 -> V2 complete: \(result.accountsCreated) accounts created, \(result.expensesLinked) expenses linked.")
        }
    )
}
