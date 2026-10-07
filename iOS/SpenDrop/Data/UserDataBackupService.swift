import Foundation
import SwiftData

/// Manages backup, restore, and automated data rehydration for user accounts and submitted receipts/screenshots.
@MainActor
public final class UserDataBackupService {
    public static let shared = UserDataBackupService()

    public static let defaultAccountName = "Touhidul Islam Rukon"
    public static let defaultAccountEmail = "tirukon015@gmail.com"
    /// Written to `accountName` in exported backups (Android writes the same).
    public static let exportAccountName = "SpenDrop user"
    private static let autoBackupFileName = "SpenDrop_AutoBackup.json"

    // MARK: - Codable DTOs for Persistent Backup

    public struct BackupPayload: Codable {
        /// 1 = expenses + PayBook only. 2 = adds accounts, money movements, splits, payer and account links.
        /// 3 = adds locally learned classification rules.
        /// 4 = adds settlements (which payment paid which expense/loan) and the sample-data register.
        public static let currentVersion = 4
        public static let supportedVersions = 1...currentVersion

        public let version: Int
        public let appName: String
        public let accountName: String
        public let exportDate: Date
        public let expenses: [ExpenseDTO]
        public let paybookProfiles: [PayBookProfileDTO]
        // Version 2 (absent in version 1 files)
        public var accounts: [AccountDTO]? = nil
        public var moneyMovements: [MoneyMovementDTO]? = nil
        // Version 3
        public var classificationRules: [ClassificationRuleDTO]? = nil
        // Version 4
        public var settlementAllocations: [SettlementAllocationDTO]? = nil
        public var sampleRecords: [SampleRecordDTO]? = nil
        // Learned payment channels per merchant + funding account (optional; absent in older version-4 files)
        public var channelRules: [ChannelRuleDTO]? = nil

        public var recordCount: RecordCount {
            RecordCount(expenses: expenses.count, profiles: paybookProfiles.count,
                        accounts: accounts?.count ?? 0, movements: moneyMovements?.count ?? 0,
                        rules: classificationRules?.count ?? 0)
        }

        public init(
            version: Int = 1,
            appName: String = "SpenDrop",
            accountName: String = exportAccountName,
            exportDate: Date = Date(),
            expenses: [ExpenseDTO],
            paybookProfiles: [PayBookProfileDTO]
        ) {
            self.version = version
            self.appName = appName
            self.accountName = accountName
            self.exportDate = exportDate
            self.expenses = expenses
            self.paybookProfiles = paybookProfiles
        }
    }

    public struct RecordCount: Equatable {
        public var expenses: Int
        public var profiles: Int
        public var accounts: Int
        public var movements: Int
        public var rules: Int = 0

        /// True when any kind of record would disappear.
        public func isSmaller(than other: RecordCount) -> Bool {
            expenses < other.expenses || profiles < other.profiles || accounts < other.accounts ||
            movements < other.movements || rules < other.rules
        }
    }

    public struct ExpenseDTO: Codable {
        public let id: UUID
        public let amount: Double
        public let currency: String
        public let merchant: String
        public let categoryRaw: String
        public let paymentSourceRaw: String
        public let underlyingBankRaw: String?
        public let paymentMethodRaw: String?
        public let date: Date
        public let notes: String?
        public let transactionReference: String?
        public let sourceTypeRaw: String
        public let ocrText: String?
        public let isSampleData: Bool
        public let createdAt: Date
        public let paymentChannelRaw: String?
        public let fundingAccount: String?
        public let fundingInstrument: String?
        public let matchingStatusRaw: String?
        // Added in Phase 0 (optional so older backup files still decode)
        public var imageRelativePath: String? = nil
        public var confidence: Double? = nil
        public var externalTransactionId: String? = nil
        public var matchingConfidence: Double? = nil
        public var updatedAt: Date? = nil
        // Version 2: relationships are stored as ids, never as names
        public var accountId: UUID? = nil
        public var paidByMe: Bool? = nil
        public var payerId: UUID? = nil
        public var payerNameSnapshot: String? = nil
        public var splitMethodRaw: String? = nil
        /// Hybrid Split rule (canonical JSON, see split-hybrid.md); nil = a normal split. Omitted from the JSON when
        /// nil, so older backups load unchanged.
        public var splitRule: String? = nil
        public var shares: [ExpenseShareDTO]? = nil

        public init(from expense: Expense) {
            self.id = expense.id
            self.amount = expense.amount
            self.currency = expense.currency
            self.merchant = expense.merchant
            self.categoryRaw = expense.categoryRaw
            self.paymentSourceRaw = expense.paymentSourceRaw
            self.underlyingBankRaw = expense.underlyingBankRaw
            self.paymentMethodRaw = expense.paymentMethodRaw
            self.date = expense.date
            self.notes = expense.notes
            self.transactionReference = expense.transactionReference
            self.sourceTypeRaw = expense.sourceTypeRaw
            self.ocrText = expense.ocrText
            self.isSampleData = expense.isSampleData
            self.createdAt = expense.createdAt
            self.paymentChannelRaw = expense.paymentChannelRaw
            self.fundingAccount = expense.effectiveFundingAccount
            self.fundingInstrument = expense.fundingInstrument
            self.matchingStatusRaw = expense.matchingStatusRaw
            self.imageRelativePath = expense.imageRelativePath
            self.confidence = expense.confidence
            self.externalTransactionId = expense.externalTransactionId
            self.matchingConfidence = expense.matchingConfidence
            self.updatedAt = expense.updatedAt
            self.accountId = expense.account?.id
            self.paidByMe = expense.paidByMe
            self.payerId = expense.payer?.id
            self.payerNameSnapshot = expense.payerNameSnapshot
            self.splitMethodRaw = expense.splitMethodRaw
            self.splitRule = expense.splitRule
            self.shares = expense.shares.sorted { $0.sortIndex < $1.sortIndex }.map { ExpenseShareDTO(from: $0) }
        }

        public init(
            id: UUID = UUID(),
            amount: Double,
            currency: String = "RM",
            merchant: String,
            categoryRaw: String,
            paymentSourceRaw: String,
            underlyingBankRaw: String? = nil,
            paymentMethodRaw: String? = nil,
            date: Date,
            notes: String? = nil,
            transactionReference: String? = nil,
            sourceTypeRaw: String = ExpenseSourceType.screenshot.rawValue,
            ocrText: String? = nil,
            isSampleData: Bool = false,
            createdAt: Date = Date(),
            paymentChannelRaw: String? = nil,
            fundingAccount: String? = nil,
            fundingInstrument: String? = nil,
            matchingStatusRaw: String? = nil
        ) {
            self.id = id
            self.amount = amount
            self.currency = currency
            self.merchant = merchant
            self.categoryRaw = categoryRaw
            self.paymentSourceRaw = paymentSourceRaw
            self.underlyingBankRaw = underlyingBankRaw
            self.paymentMethodRaw = paymentMethodRaw
            self.date = date
            self.notes = notes
            self.transactionReference = transactionReference
            self.sourceTypeRaw = sourceTypeRaw
            self.ocrText = ocrText
            self.isSampleData = isSampleData
            self.createdAt = createdAt
            self.paymentChannelRaw = paymentChannelRaw
            self.fundingAccount = fundingAccount
            self.fundingInstrument = fundingInstrument
            self.matchingStatusRaw = matchingStatusRaw
        }
    }

    public struct PayBookMethodDTO: Codable {
        public let id: UUID
        public let paymentTypeRaw: String
        public let provider: String
        public let customProviderName: String?
        public let accountIdentifier: String
        public let label: String?
        public let notes: String?
        public var createdAt: Date? = nil
        public var updatedAt: Date? = nil

        public init(from method: PayBookPaymentMethod) {
            self.id = method.id
            self.paymentTypeRaw = method.paymentTypeRaw
            self.provider = method.provider
            self.customProviderName = method.customProviderName
            self.accountIdentifier = method.accountIdentifier
            self.label = method.label
            self.notes = method.notes
            self.createdAt = method.createdAt
            self.updatedAt = method.updatedAt
        }

        public init(
            id: UUID = UUID(),
            paymentTypeRaw: String,
            provider: String,
            customProviderName: String? = nil,
            accountIdentifier: String,
            label: String? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.paymentTypeRaw = paymentTypeRaw
            self.provider = provider
            self.customProviderName = customProviderName
            self.accountIdentifier = accountIdentifier
            self.label = label
            self.notes = notes
        }
    }

    public struct PayBookProfileDTO: Codable {
        public let id: UUID
        public let name: String
        public let notes: String?
        public let paymentMethods: [PayBookMethodDTO]
        public var createdAt: Date? = nil
        public var updatedAt: Date? = nil
        public var isFrequent: Bool? = nil
        public var isArchived: Bool? = nil

        public init(from profile: PayBookProfile) {
            self.id = profile.id
            self.name = profile.name
            self.notes = profile.notes
            self.paymentMethods = profile.paymentMethods.map { PayBookMethodDTO(from: $0) }
            self.createdAt = profile.createdAt
            self.updatedAt = profile.updatedAt
            self.isFrequent = profile.isFrequent
            self.isArchived = profile.isArchived
        }

        public init(
            id: UUID = UUID(),
            name: String,
            notes: String? = nil,
            paymentMethods: [PayBookMethodDTO]
        ) {
            self.id = id
            self.name = name
            self.notes = notes
            self.paymentMethods = paymentMethods
        }
    }

    public struct AccountDTO: Codable {
        public let id: UUID
        public let name: String
        public let typeRaw: String
        public let currency: String
        public let icon: String?
        public let isArchived: Bool
        public let createdAt: Date
        public let sortIndex: Int

        public init(from account: Account) {
            self.id = account.id
            self.name = account.name
            self.typeRaw = account.typeRaw
            self.currency = account.currency
            self.icon = account.icon
            self.isArchived = account.isArchived
            self.createdAt = account.createdAt
            self.sortIndex = account.sortIndex
        }
    }

    public struct ExpenseShareDTO: Codable {
        public let id: UUID
        public let personId: UUID?
        public let isMe: Bool
        public let nameSnapshot: String
        public let amountMinor: Int
        public let parts: Int?
        public let enteredMinor: Int?
        public let sortIndex: Int

        public init(from share: ExpenseShare) {
            self.id = share.id
            self.personId = share.person?.id
            self.isMe = share.isMe
            self.nameSnapshot = share.nameSnapshot
            self.amountMinor = share.amountMinor
            self.parts = share.parts
            self.enteredMinor = share.enteredMinor
            self.sortIndex = share.sortIndex
        }
    }

    public struct MoneyMovementDTO: Codable {
        public let id: UUID
        public let directionRaw: String
        public let kindRaw: String
        public let amountMinor: Int
        public let currency: String
        public let date: Date
        public let personId: UUID?
        public let personNameSnapshot: String?
        public let linkedExpenseId: UUID?
        public let linkedExpenseSnapshot: String?
        public let accountId: UUID?
        public let counterAccountId: UUID?
        public let note: String?
        public let transactionReference: String?
        public let sourceTypeRaw: String
        public let paymentChannelRaw: String
        public let createdAt: Date
        public let updatedAt: Date

        public init(from movement: MoneyMovement) {
            self.id = movement.id
            self.directionRaw = movement.directionRaw
            self.kindRaw = movement.kindRaw
            self.amountMinor = movement.amountMinor
            self.currency = movement.currency
            self.date = movement.date
            self.personId = movement.person?.id
            self.personNameSnapshot = movement.personNameSnapshot
            self.linkedExpenseId = movement.linkedExpense?.id
            self.linkedExpenseSnapshot = movement.linkedExpenseSnapshot
            self.accountId = movement.account?.id
            self.counterAccountId = movement.counterAccount?.id
            self.note = movement.note
            self.transactionReference = movement.transactionReference
            self.sourceTypeRaw = movement.sourceTypeRaw
            self.paymentChannelRaw = movement.paymentChannelRaw
            self.createdAt = movement.createdAt
            self.updatedAt = movement.updatedAt
        }
    }

    public struct SettlementAllocationDTO: Codable, Equatable {
        public let id: UUID
        public let groupID: UUID
        public let kindRaw: String
        public let paymentID: UUID?
        public let expenseID: UUID?
        public let loanID: UUID?
        public let personID: UUID
        public let direction: Int
        public let amountMinor: Int
        public let currency: String
        public let date: Date
        public let createdAt: Date

        public init(from a: SettlementAllocation) {
            id = a.id; groupID = a.groupID; kindRaw = a.kindRaw; paymentID = a.paymentID; expenseID = a.expenseID
            loanID = a.loanID; personID = a.personID; direction = a.direction; amountMinor = a.amountMinor
            currency = a.currency; date = a.date; createdAt = a.createdAt
        }
    }

    public struct SampleRecordDTO: Codable, Equatable {
        public let recordID: UUID
        public let entityRaw: String
        public let createdAt: Date

        public init(from r: SampleDataRecord) {
            recordID = r.recordID; entityRaw = r.entityRaw; createdAt = r.createdAt
        }
    }

    public struct ChannelRuleDTO: Codable {
        public let id: UUID
        public let merchantKey: String
        public let fundingKey: String
        public let channelRaw: String
        public let hitCount: Int
        public let createdAt: Date
        public let updatedAt: Date

        public init(from rule: ChannelRule) {
            id = rule.id; merchantKey = rule.merchantKey; fundingKey = rule.fundingKey; channelRaw = rule.channelRaw
            hitCount = rule.hitCount; createdAt = rule.createdAt; updatedAt = rule.updatedAt
        }
    }

    public struct ClassificationRuleDTO: Codable {
        public let id: UUID
        public let merchantKey: String
        public let categoryRaw: String?
        public let suggestedTypeRaw: String?
        public let accountId: UUID?
        public let hitCount: Int
        public let createdAt: Date
        public let updatedAt: Date

        public init(from rule: ClassificationRule) {
            self.id = rule.id
            self.merchantKey = rule.merchantKey
            self.categoryRaw = rule.categoryRaw
            self.suggestedTypeRaw = rule.suggestedTypeRaw
            self.accountId = rule.accountId
            self.hitCount = rule.hitCount
            self.createdAt = rule.createdAt
            self.updatedAt = rule.updatedAt
        }
    }

    // MARK: - Auto-Backup Storage URLs

    private static var localAutoBackupURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(autoBackupFileName)
    }

    private static var appGroupAutoBackupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ExpenseDataContainer.appGroupIdentifier)?
            .appendingPathComponent("Library/Application Support/\(autoBackupFileName)")
    }

    // MARK: - Primary Restore / Rehydrate Account Data

    /// Restores user transactions from verified screenshots, historical expenses, and PayBook accounts
    @discardableResult
    public static func restoreAccountData(into context: ModelContext, force: Bool = false) -> (expensesCount: Int, profilesCount: Int) {
        print("[SpenDrop][BackupService] Starting account data restoration (force=\(force))...")

        // 1. Restore PayBook Profiles
        let restoredProfilesCount = restorePayBookProfiles(into: context, force: force)

        // 2. Restore Expenses (Screenshots & Receipts)
        let restoredExpensesCount = restoreScreenshotExpenses(into: context, force: force)

        try? context.save()

        // 3. Save snapshot to persistent auto-backup
        saveAutoBackup(from: context)

        print("[SpenDrop][BackupService] Data restoration finished: \(restoredExpensesCount) expenses, \(restoredProfilesCount) profiles restored.")
        return (restoredExpensesCount, restoredProfilesCount)
    }

    // MARK: - Screenshot & User Expense Dataset

    private static func restoreScreenshotExpenses(into context: ModelContext, force: Bool) -> Int {
        let existingExpenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        var existingRefs = Set<String>()
        var existingSignatures = Set<String>()

        for exp in existingExpenses {
            if let ref = exp.transactionReference, !ref.isEmpty {
                existingRefs.insert(ref)
            }
            let sig = "\(exp.merchant.lowercased())_\(exp.amount)_\(Calendar.current.component(.day, from: exp.date))"
            existingSignatures.insert(sig)
        }

        let now = Date()
        let calendar = Calendar.current

        func makeDate(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let comp = calendar.dateComponents([.year, .month, .day], from: now)
            if let dateWithoutTime = calendar.date(from: comp),
               let offsetDate = calendar.date(byAdding: .day, value: -daysAgo, to: dateWithoutTime) {
                var newComp = calendar.dateComponents([.year, .month, .day], from: offsetDate)
                newComp.hour = hour
                newComp.minute = minute
                newComp.second = 0
                return calendar.date(from: newComp) ?? now
            }
            return now
        }

        // Built-in demo dataset (from screenshots used during development). Tagged as sample data so it never
        // counts as the user's own records and "Remove Sample Transactions" can take it out again.
        let userRecords: [ExpenseDTO] = [
            // 1. TNG Transfer to RANA SOHEL (Verified User Screenshot: RM22.00 vs RM450 Ad)
            ExpenseDTO(
                amount: 22.00,
                merchant: "RANA SOHEL",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "ewallet",
                date: makeDate(daysAgo: 12, hour: 13, minute: 49),
                notes: "Touch 'n Go eWallet transfer to Rana Sohel (verified from screenshot)",
                transactionReference: "TNG-20260915-RANA",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Touch 'n Go eWallet\nTransferred\nReceiver: RANA SOHEL\nRM22.00\n15/09/2026 13:49:06",
                isSampleData: true
            ),

            // 2. CIMB FPX Payment to IPAY88 (Verified User Screenshot Alert: RM932.46)
            ExpenseDTO(
                amount: 932.46,
                merchant: "IPAY88",
                categoryRaw: ExpenseCategory.bills.rawValue,
                paymentSourceRaw: PaymentSource.cimb.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "bank_transfer",
                date: makeDate(daysAgo: 22, hour: 23, minute: 13),
                notes: "CIMB FPX payment to IPAY88 (M) SDN BHD accepted (verified from screenshot)",
                transactionReference: "CIMB-FPX-20260806",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Transaction Alert\nCIMB: FPX Payment RM932.46 to IPAY88 (M) SDN BHD accepted on 06-Aug-2026, 23:13:56.",
                isSampleData: true
            ),

            // 3. TNG Transfer to BARAKAT MD ABUL (Verified User Screenshot: -RM12.00)
            ExpenseDTO(
                amount: 12.00,
                merchant: "BARAKAT MD ABUL",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "ewallet",
                date: makeDate(daysAgo: 25, hour: 13, minute: 7),
                notes: "Touch 'n Go eWallet transfer to Barakat Md Abul (verified from screenshot)",
                transactionReference: "2026080211121700010100171897968925005",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Details\n-RM12.00\nTransaction Type\nTransfer to Wallet\nTransfer To\nBARAKAT MD ABUL\n02/08/2026 13:07:14",
                isSampleData: true
            ),

            // 4. CIMB DuitNow to TOUHIDUL ISLAM RUKON (Maybank) (Verified Screenshot: RM1.00)
            ExpenseDTO(
                amount: 1.00,
                merchant: "TOUHIDUL ISLAM RUKON",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.cimb.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 9, hour: 14, minute: 18),
                notes: "CIMB DuitNow transfer to Maybank 168603292644 (verified from screenshot)",
                transactionReference: "283550902",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Transaction Summary\nMYR 1.00\nTOUHIDUL ISLAM RUKON\nMaybank 168603292644\nSAVINGS ACCT-i PLUS 7658174175",
                isSampleData: true
            ),

            // 5. CIMB OCTO QR Payment to RUKON TOUHIDUL ISLAM (Verified Screenshot: RM0.01)
            ExpenseDTO(
                amount: 0.01,
                merchant: "RUKON TOUHIDUL ISLAM",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.cimb.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "duitnow_qr",
                date: makeDate(daysAgo: 9, hour: 14, minute: 17),
                notes: "CIMB OCTO QR Payment (verified from screenshot)",
                transactionReference: "OCTO-283547681",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Transaction Summary\nMYR 0.01\nRUKON TOUHIDUL ISLAM\nSAVINGS ACCT-i PLUS 7658174175",
                isSampleData: true
            ),

            // 6. Maybank Interbank to TOUHIDUL ISLAM RUKON (RHB) (Verified Screenshot: RM0.01)
            ExpenseDTO(
                amount: 0.01,
                merchant: "TOUHIDUL ISLAM RUKON",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.maybank.rawValue,
                underlyingBankRaw: PaymentSource.maybank.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 9, hour: 14, minute: 16),
                notes: "Maybank DuitNow transfer to RHB 2160 1100 0364 06 (verified from screenshot)",
                transactionReference: "035649071M",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Maybank\nDuitNow Transfer\nBeneficiary: TOUHIDUL ISLAM RUKON\nRHB BANK 2160 1100 0364 06\nRM 0.01",
                isSampleData: true
            ),

            // 7. Maybank Scan & Pay Receipt to RUKONTOUHIDULISLAM (Verified Screenshot: RM0.01)
            ExpenseDTO(
                amount: 0.01,
                merchant: "RUKONTOUHIDULISLAM",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.maybank.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "duitnow_qr",
                date: makeDate(daysAgo: 9, hour: 14, minute: 15),
                notes: "Maybank Scan & Pay QR (verified from receipt screenshot)",
                transactionReference: "QR70737488",
                sourceTypeRaw: ExpenseSourceType.receipt.rawValue,
                ocrText: "Maybank Scan & Pay\nBeneficiary: RUKONTOUHIDULISLAM\nRM 0.01\nQR70737488",
                isSampleData: true
            ),

            // 8. RHB Interbank to TOUHIDUL ISLAM RUKON (CIMB) (Verified Screenshot: RM1.00)
            ExpenseDTO(
                amount: 1.00,
                merchant: "TOUHIDUL ISLAM RUKON",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.rhb.rawValue,
                underlyingBankRaw: PaymentSource.rhb.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 9, hour: 14, minute: 21),
                notes: "RHB Smart Account DuitNow to CIMB 7658174175 (verified from screenshot)",
                transactionReference: "17897124619260845",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Status Successful\nMYR 1.00\nFrom RHB Smart Account 21601100036406\nTo TOUHIDUL ISLAM RUKON CIMB 7658174175",
                isSampleData: true
            ),

            // 9. RHB DuitNow QR Transfer to RUKONTOUHIDULISLAM (Verified Screenshot: RM0.01)
            ExpenseDTO(
                amount: 0.01,
                merchant: "RUKONTOUHIDULISLAM",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.rhb.rawValue,
                underlyingBankRaw: PaymentSource.rhb.rawValue,
                paymentMethodRaw: "duitnow_qr",
                date: makeDate(daysAgo: 9, hour: 14, minute: 19),
                notes: "RHB Smart Account DuitNow QR P2P (verified from screenshot)",
                transactionReference: "20260918RHBBMYKL0400QR59060146",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "MYR 0.01\nDuitNow QR\nFrom RHB Smart Account 21601100036406\nTo RUKONTOUHIDULISLAM",
                isSampleData: true
            ),

            // 10. TNG Interbank to TOUHIDUL ISLAM RUKON (Maybank) (Verified Screenshot: RM1.00)
            ExpenseDTO(
                amount: 1.00,
                merchant: "TOUHIDUL ISLAM RUKON",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 9, hour: 14, minute: 12),
                notes: "TNG DuitNow transfer to Maybank 168603292644 (verified from screenshot)",
                transactionReference: "20260918TNGDMYNB010ORM42680415",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "RM 1.00 Transferred\nReceiver: TOUHIDUL ISLAM RUKON\nRecipient Bank: Maybank 168603292644",
                isSampleData: true
            ),

            // 11. TNG QR to RIYAD MD TANVIR ISLAM (Verified Screenshot: RM0.01)
            ExpenseDTO(
                amount: 0.01,
                merchant: "RIYAD MD TANVIR ISLAM",
                categoryRaw: ExpenseCategory.personal.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "ewallet",
                date: makeDate(daysAgo: 9, hour: 14, minute: 13),
                notes: "Touch 'n Go fund transfer to Riyad Md Tanvir Islam (verified from screenshot)",
                transactionReference: "TNG-QR-20260918-01",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "RM 0.01 Transferred\nReceiver: RIYAD MD TANVIR ISLAM\nFund Transfer",
                isSampleData: true
            ),

            // 12. Starbucks Coffee (Apple Pay + CIMB Debit *8821)
            ExpenseDTO(
                amount: 25.90,
                merchant: "Starbucks Coffee",
                categoryRaw: ExpenseCategory.food.rawValue,
                paymentSourceRaw: PaymentSource.applePay.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "digital_wallet",
                date: makeDate(daysAgo: 1, hour: 14, minute: 2),
                notes: "Starbucks Coffee via Apple Pay CIMB Debit *8821",
                transactionReference: "APL-SBC-771829",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Starbucks Coffee\nTotal: RM 25.90\nPayment Method: Apple Pay\nCard: CIMB Bank Debit *8821",
                isSampleData: true
            ),

            // 13. Uniqlo Mid Valley (Apple Pay + Maybank Visa Signature)
            ExpenseDTO(
                amount: 149.90,
                merchant: "Uniqlo Mid Valley",
                categoryRaw: ExpenseCategory.shopping.rawValue,
                paymentSourceRaw: PaymentSource.applePay.rawValue,
                underlyingBankRaw: PaymentSource.maybank.rawValue,
                paymentMethodRaw: "digital_wallet",
                date: makeDate(daysAgo: 2, hour: 16, minute: 20),
                notes: "Uniqlo Mid Valley via Apple Pay Maybank Visa Signature",
                transactionReference: "APL-MBB-992819",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Uniqlo Mid Valley\nTotal: RM 149.90\nPaid using Apple Pay\nFunding: Maybank Visa Signature",
                isSampleData: true
            ),

            // 14. Shell Petrol (CIMB) - Today
            ExpenseDTO(
                amount: 50.00,
                merchant: "Shell",
                categoryRaw: ExpenseCategory.transport.rawValue,
                paymentSourceRaw: PaymentSource.cimb.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 0, hour: 10, minute: 30),
                notes: "Fuel refill RON95 Shell",
                transactionReference: "CIMB-SHL-481902",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "CIMB OCTO\nDuitNow Transfer Successful\nRM50.00\nPaid to: Shell",
                isSampleData: true
            ),

            // 15. MYDIN Groceries (Maybank) - Today
            ExpenseDTO(
                amount: 42.90,
                merchant: "MYDIN",
                categoryRaw: ExpenseCategory.groceries.rawValue,
                paymentSourceRaw: PaymentSource.maybank.rawValue,
                underlyingBankRaw: PaymentSource.maybank.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 0, hour: 12, minute: 45),
                notes: "Weekly pantry and fresh groceries",
                transactionReference: "MBB-MYD-983102",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Maybank2u\nTransfer Successful\nAmount: RM42.90\nRecipient: MYDIN",
                isSampleData: true
            ),

            // 16. McDonald's (Touch 'n Go) - This Week
            ExpenseDTO(
                amount: 18.50,
                merchant: "McDonald's",
                categoryRaw: ExpenseCategory.food.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "ewallet",
                date: makeDate(daysAgo: 1, hour: 20, minute: 15),
                notes: "Dinner set at McDonald's",
                transactionReference: "TNG-MCD-992837",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "Touch 'n Go eWallet\nPayment Successful\nRM18.50\nPaid to: McDonald's",
                isSampleData: true
            ),

            // 17. Grab Ride (RHB) - This Week
            ExpenseDTO(
                amount: 14.80,
                merchant: "Grab",
                categoryRaw: ExpenseCategory.transport.rawValue,
                paymentSourceRaw: PaymentSource.rhb.rawValue,
                underlyingBankRaw: PaymentSource.rhb.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 3, hour: 9, minute: 10),
                notes: "Grab ride to office meeting",
                transactionReference: "RHB-GRB-551029",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: "RHB Now\nPayment Successful\nAmount: RM14.80\nPaid to: Grab",
                isSampleData: true
            ),

            // 18. Kopitiam Ah Kow (Cash) - Today
            ExpenseDTO(
                amount: 12.50,
                merchant: "Kopitiam Ah Kow",
                categoryRaw: ExpenseCategory.food.rawValue,
                paymentSourceRaw: PaymentSource.cash.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "cash",
                date: makeDate(daysAgo: 0, hour: 8, minute: 30),
                notes: "Breakfast kopi and kaya toast",
                transactionReference: "RCP-48291",
                sourceTypeRaw: ExpenseSourceType.receipt.rawValue,
                ocrText: "Kopitiam Ah Kow\nRM 12.50\nReceipt #48291",
                isSampleData: true
            ),

            // 19. 7-Eleven Snacks - Today
            ExpenseDTO(
                amount: 11.50,
                merchant: "7-Eleven",
                categoryRaw: ExpenseCategory.groceries.rawValue,
                paymentSourceRaw: PaymentSource.cash.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "cash",
                date: makeDate(daysAgo: 0, hour: 15, minute: 20),
                notes: "Snacks and mineral water",
                transactionReference: "RCP-711-20260927",
                sourceTypeRaw: ExpenseSourceType.manual.rawValue,
                ocrText: nil,
                isSampleData: true
            ),

            // 20. GrabFood Nasi Lemak - This Week
            ExpenseDTO(
                amount: 22.40,
                merchant: "GrabFood",
                categoryRaw: ExpenseCategory.food.rawValue,
                paymentSourceRaw: PaymentSource.touchNGo.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "ewallet",
                date: makeDate(daysAgo: 2, hour: 19, minute: 40),
                notes: "Nasi lemak delivery",
                transactionReference: "TNG-GF-330192",
                sourceTypeRaw: ExpenseSourceType.shareExtension.rawValue,
                ocrText: nil,
                isSampleData: true
            ),

            // 21. Shopee Gadget Order - This Month
            ExpenseDTO(
                amount: 89.90,
                merchant: "Shopee",
                categoryRaw: ExpenseCategory.shopping.rawValue,
                paymentSourceRaw: PaymentSource.maybank.rawValue,
                underlyingBankRaw: PaymentSource.maybank.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 8, hour: 16, minute: 15),
                notes: "USB hub & desk organizer",
                transactionReference: "MBB-SHP-662910",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: nil,
                isSampleData: true
            ),

            // 22. Netflix Subscription - This Month
            ExpenseDTO(
                amount: 17.00,
                merchant: "Netflix",
                categoryRaw: ExpenseCategory.subscription.rawValue,
                paymentSourceRaw: PaymentSource.cimb.rawValue,
                underlyingBankRaw: PaymentSource.cimb.rawValue,
                paymentMethodRaw: "duitnow",
                date: makeDate(daysAgo: 16, hour: 5, minute: 0),
                notes: "Monthly subscription auto-debit",
                transactionReference: "CIMB-NTF-129034",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: nil,
                isSampleData: true
            ),

            // 23. TNB Electricity Bill - This Month
            ExpenseDTO(
                amount: 75.30,
                merchant: "Electricity",
                categoryRaw: ExpenseCategory.bills.rawValue,
                paymentSourceRaw: PaymentSource.bankTransfer.rawValue,
                underlyingBankRaw: nil,
                paymentMethodRaw: "bank_transfer",
                date: makeDate(daysAgo: 20, hour: 11, minute: 20),
                notes: "TNB electricity monthly bill payment",
                transactionReference: "FPX-TNB-881920",
                sourceTypeRaw: ExpenseSourceType.screenshot.rawValue,
                ocrText: nil,
                isSampleData: true
            )
        ]

        var insertedCount = 0
        for dto in userRecords {
            if !force {
                if let ref = dto.transactionReference, existingRefs.contains(ref) {
                    continue
                }
                let sig = "\(dto.merchant.lowercased())_\(dto.amount)_\(calendar.component(.day, from: dto.date))"
                if existingSignatures.contains(sig) {
                    continue
                }
            }

            let cat = ExpenseCategory(rawValue: dto.categoryRaw) ?? .personal
            let src = PaymentSource(rawValue: dto.paymentSourceRaw) ?? .touchNGo
            let bank = dto.underlyingBankRaw != nil ? PaymentSource(rawValue: dto.underlyingBankRaw!) : nil
            let sType = ExpenseSourceType(rawValue: dto.sourceTypeRaw) ?? .screenshot
            let channel = dto.paymentChannelRaw != nil ? (PaymentChannel(rawValue: dto.paymentChannelRaw!) ?? .unknown) : .unknown
            let funding = dto.fundingAccount ?? bank?.rawValue ?? (src != .applePay && src != .qrPayment && src != .bankTransfer && src != .physicalCard && src != .unknown ? src.rawValue : "Unknown")
            let matching = dto.matchingStatusRaw ?? "UNMATCHED"

            let expense = Expense(
                id: dto.id,
                amount: dto.amount,
                currency: dto.currency,
                merchant: dto.merchant,
                category: cat,
                paymentSource: src,
                underlyingBank: bank,
                paymentMethod: dto.paymentMethodRaw,
                date: dto.date,
                notes: dto.notes,
                transactionReference: dto.transactionReference,
                sourceType: sType,
                ocrText: dto.ocrText,
                isSampleData: dto.isSampleData,
                paymentChannel: channel,
                fundingAccount: funding,
                matchingStatus: matching
            )
            context.insert(expense)
            insertedCount += 1
        }

        return insertedCount
    }

    // MARK: - PayBook Profile Dataset

    private static func restorePayBookProfiles(into context: ModelContext, force: Bool) -> Int {
        let existingProfiles = (try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []
        var existingNames = Set(existingProfiles.map { $0.name.lowercased() })

        var addedProfilesCount = 0

        // 1. Touhidul Islam Rukon (User's Main Account)
        if force || !existingNames.contains(defaultAccountName.lowercased()) {
            let rukon = PayBookProfile(
                name: defaultAccountName,
                notes: "Primary account holder (My Accounts & Cards)"
            )
            context.insert(rukon)

            let mCimb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "CIMB Bank",
                accountIdentifier: "7658174175",
                label: "SAVINGS ACCT-i PLUS",
                notes: "Primary CIMB account",
                profile: rukon
            )
            let mMaybank = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "Maybank",
                accountIdentifier: "168603292644",
                label: "Personal Savings",
                notes: "Maybank2u account",
                profile: rukon
            )
            let mRhb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "RHB Bank",
                accountIdentifier: "21601100036406",
                label: "RHB Smart Account",
                notes: "Smart Account",
                profile: rukon
            )
            let mTng = PayBookPaymentMethod(
                paymentType: .eWallet,
                provider: "Touch 'n Go",
                accountIdentifier: "0123456789",
                label: "Primary eWallet",
                profile: rukon
            )
            let mDuitNow = PayBookPaymentMethod(
                paymentType: .paymentId,
                provider: "DuitNow",
                accountIdentifier: defaultAccountEmail,
                label: "DuitNow ID (Email)",
                profile: rukon
            )

            rukon.paymentMethods.append(contentsOf: [mCimb, mMaybank, mRhb, mTng, mDuitNow])
            existingNames.insert(defaultAccountName.lowercased())
            addedProfilesCount += 1
        }

        // 2. Rahim
        if force || !existingNames.contains("rahim") {
            let rahim = PayBookProfile(name: "Rahim", notes: "Frequent contractor & utility transfers")
            context.insert(rahim)

            let rMbb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "Maybank",
                accountIdentifier: "1234567890",
                label: "Personal",
                profile: rahim
            )
            let rCimb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "CIMB Bank",
                accountIdentifier: "9876543210",
                label: "Business",
                profile: rahim
            )
            let rTng = PayBookPaymentMethod(
                paymentType: .eWallet,
                provider: "Touch 'n Go",
                accountIdentifier: "0123456789",
                profile: rahim
            )
            rahim.paymentMethods.append(contentsOf: [rMbb, rCimb, rTng])
            existingNames.insert("rahim")
            addedProfilesCount += 1
        }

        // 3. Karim
        if force || !existingNames.contains("karim") {
            let karim = PayBookProfile(name: "Karim", notes: "Family transfer")
            context.insert(karim)

            let kMbb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "Maybank",
                accountIdentifier: "999999999",
                label: "Main Account",
                profile: karim
            )
            let kAffin = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "Affin Bank",
                accountIdentifier: "555566667777",
                profile: karim
            )
            karim.paymentMethods.append(contentsOf: [kMbb, kAffin])
            existingNames.insert("karim")
            addedProfilesCount += 1
        }

        // 4. Siti Nurhaliza
        if force || !existingNames.contains("siti nurhaliza") {
            let siti = PayBookProfile(name: "Siti Nurhaliza", notes: "Siti Nurhaliza Binti Tarudin")
            context.insert(siti)

            let sRhb = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: "RHB Bank",
                accountIdentifier: "21415600192837",
                profile: siti
            )
            let sDuitNow = PayBookPaymentMethod(
                paymentType: .paymentId,
                provider: "DuitNow",
                accountIdentifier: "siti@email.com",
                profile: siti
            )
            siti.paymentMethods.append(contentsOf: [sRhb, sDuitNow])
            existingNames.insert("siti nurhaliza")
            addedProfilesCount += 1
        }

        // 5. Rana Sohel
        if force || !existingNames.contains("rana sohel") {
            let rana = PayBookProfile(name: "Rana Sohel", notes: "Touch 'n Go transfer contact")
            context.insert(rana)

            let rTng = PayBookPaymentMethod(
                paymentType: .eWallet,
                provider: "Touch 'n Go",
                accountIdentifier: "0112345678",
                profile: rana
            )
            rana.paymentMethods.append(rTng)
            existingNames.insert("rana sohel")
            addedProfilesCount += 1
        }

        // 6. Barakat Md Abul
        if force || !existingNames.contains("barakat md abul") {
            let barakat = PayBookProfile(name: "Barakat Md Abul", notes: "Touch 'n Go contact")
            context.insert(barakat)

            let bTng = PayBookPaymentMethod(
                paymentType: .eWallet,
                provider: "Touch 'n Go",
                accountIdentifier: "0179876543",
                profile: barakat
            )
            barakat.paymentMethods.append(bTng)
            existingNames.insert("barakat md abul")
            addedProfilesCount += 1
        }

        return addedProfilesCount
    }

    // MARK: - Auto-Backup Management

    private static let backupHistoryFolderName = "SpenDropBackupHistory"
    private static let maxDailyHistoryFiles = 7
    private static let maxShrinkHistoryFiles = 5
    private static var didSaveObserver: NSObjectProtocol?
    private static var pendingAutoBackup: Task<Void, Never>?

    /// Refreshes the auto-backup shortly after any SwiftData save (manual entry, edits, deletes, imports).
    public static func startAutomaticBackups(for container: ModelContainer) {
        guard didSaveObserver == nil else { return }
        didSaveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in
                scheduleAutoBackup(from: container.mainContext)
            }
        }
    }

    /// Debounced backup so a burst of saves produces one write.
    public static func scheduleAutoBackup(from context: ModelContext, delay: Duration = .seconds(2)) {
        pendingAutoBackup?.cancel()
        pendingAutoBackup = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            saveAutoBackup(from: context)
        }
    }

    /// Writes a backup snapshot to the local Documents directory and App Group.
    /// Skipped in safe mode and for in-memory stores so a temporary store can never overwrite a real backup.
    /// Before overwriting, the previous file is kept in `SpenDropBackupHistory/` (one per day, plus a copy
    /// whenever the new backup contains fewer records than the old one).
    @discardableResult
    public static func saveAutoBackup(from context: ModelContext) -> Bool {
        let isInMemory = context.container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        guard !isInMemory, ExpenseDataContainer.isPersistentStoreHealthy, !ExpenseDataContainer.isUITesting else {
            print("[SpenDrop][BackupService] Auto-backup skipped (in-memory or safe-mode store).")
            return false
        }

        let payload = makePayload(from: context)
        guard !payload.expenses.isEmpty || !payload.paybookProfiles.isEmpty || !(payload.moneyMovements ?? []).isEmpty else { return false }

        guard let data = try? makeEncoder().encode(payload) else { return false }

        var wroteAny = false
        for url in [localAutoBackupURL, appGroupAutoBackupURL].compactMap({ $0 }) {
            do {
                try writeBackupData(data, to: url)
                wroteAny = true
                print("[SpenDrop][BackupService] Saved auto-backup to: \(url.path)")
            } catch {
                print("[SpenDrop][BackupService] Failed to write auto-backup to \(url.path): \(error)")
            }
        }
        return wroteAny
    }

    /// Builds a complete version-2 backup of everything in the store.
    static func makePayload(from context: ModelContext) -> BackupPayload {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let movements = (try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []
        let rules = (try? context.fetch(FetchDescriptor<ClassificationRule>())) ?? []
        let allocations = (try? context.fetch(FetchDescriptor<SettlementAllocation>())) ?? []
        let sampleRecords = (try? context.fetch(FetchDescriptor<SampleDataRecord>())) ?? []
        let channelRules = (try? context.fetch(FetchDescriptor<ChannelRule>())) ?? []

        var payload = BackupPayload(
            version: BackupPayload.currentVersion,
            appName: "SpenDrop",
            // Never the developer's name in a user's backup (same as Android).
            accountName: exportAccountName,
            exportDate: Date(),
            expenses: expenses.map { ExpenseDTO(from: $0) },
            paybookProfiles: profiles.map { PayBookProfileDTO(from: $0) }
        )
        payload.accounts = accounts.map { AccountDTO(from: $0) }
        payload.moneyMovements = movements.map { MoneyMovementDTO(from: $0) }
        payload.classificationRules = rules.map { ClassificationRuleDTO(from: $0) }
        payload.settlementAllocations = allocations.map { SettlementAllocationDTO(from: $0) }
        payload.sampleRecords = sampleRecords.map { SampleRecordDTO(from: $0) }
        payload.channelRules = channelRules.map { ChannelRuleDTO(from: $0) }
        return payload
    }

    /// Writes `data` to `url`, first preserving the file it replaces in the history folder next to it.
    static func writeBackupData(_ data: Data, to url: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: url.path) {
            let historyDir = dir.appendingPathComponent(backupHistoryFolderName, isDirectory: true)
            try fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
            let baseName = url.deletingPathExtension().lastPathComponent

            // One copy per day, named after the day the old file was written.
            let oldDate = ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? now
            let dailyURL = historyDir.appendingPathComponent("\(baseName)_\(dayString(oldDate)).json")
            if !fm.fileExists(atPath: dailyURL.path) {
                try fm.copyItem(at: url, to: dailyURL)
            }

            // Extra copy whenever records would disappear from the backup.
            if let oldPayload = decodePayload(at: url), let newPayload = try? makeDecoder().decode(BackupPayload.self, from: data),
               newPayload.recordCount.isSmaller(than: oldPayload.recordCount) {
                let shrinkURL = historyDir.appendingPathComponent("\(baseName)_before-shrink_\(ExpenseDataContainer.timestampString(now)).json")
                try fm.copyItem(at: url, to: shrinkURL)
                print("[SpenDrop][BackupService] Backup shrinks (\(oldPayload.expenses.count) -> \(newPayload.expenses.count) expenses). Kept previous copy at \(shrinkURL.lastPathComponent)")
            }

            pruneHistory(in: historyDir, prefix: "\(baseName)_before-shrink_", keep: maxShrinkHistoryFiles)
            pruneHistory(in: historyDir, prefix: "\(baseName)_2", keep: maxDailyHistoryFiles)
        }

        try data.write(to: url, options: .atomic)
    }

    private static func pruneHistory(in dir: URL, prefix: String, keep: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names.filter({ $0.hasPrefix(prefix) }).sorted().dropLast(keep) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decodePayload(at url: URL) -> BackupPayload? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? makeDecoder().decode(BackupPayload.self, from: data) else { return nil }
        guard BackupPayload.supportedVersions.contains(payload.version) else {
            print("[SpenDrop][BackupService] Ignoring backup \(url.lastPathComponent): version \(payload.version) is not supported.")
            return nil
        }
        return payload
    }

    /// The newest readable local backup (auto-backup file, then the most recent history copy), if any.
    /// Never called at launch: restoring is always an explicit user action.
    public static func latestLocalBackup() -> BackupPayload? {
        // UI tests never read the device's real backup files.
        if ExpenseDataContainer.isUITesting {
            return ProcessInfo.processInfo.arguments.contains("--ui-testing-backup-fixture") ? uiTestBackupFixture() : nil
        }
        let candidateURLs = [localAutoBackupURL, appGroupAutoBackupURL].compactMap { $0 } + historyBackupURLsNewestFirst()
        for url in candidateURLs {
            if let payload = decodePayload(at: url) {
                return payload
            }
        }
        return nil
    }


    private static func historyBackupURLsNewestFirst() -> [URL] {
        let fm = FileManager.default
        let dirs = [localAutoBackupURL, appGroupAutoBackupURL].compactMap {
            $0?.deletingLastPathComponent().appendingPathComponent(backupHistoryFolderName, isDirectory: true)
        }
        let files = dirs.flatMap { dir -> [URL] in
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.filter { $0.hasSuffix(".json") }.map { dir.appendingPathComponent($0) }
        }
        return files.sorted {
            let a = ((try? fm.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date) ?? .distantPast
            let b = ((try? fm.attributesOfItem(atPath: $1.path))?[.modificationDate] as? Date) ?? .distantPast
            return a > b
        }
    }

    // MARK: - Export and Import JSON

    /// Creates an exportable JSON file and returns its URL for ShareSheet / saving
    public static func generateExportJSONFile(from context: ModelContext) -> URL? {
        guard let data = try? makeEncoder().encode(makePayload(from: context)) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "SpenDrop_Backup_\(timestamp).json"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("[SpenDrop][BackupService] Failed to export JSON: \(error)")
            return nil
        }
    }

    /// Result of applying a backup file. Records are matched by `id` only.
    public struct ImportSummary: Equatable {
        public var expensesAdded = 0
        public var expensesUpdated = 0
        public var expensesKeptNewer = 0
        public var possibleDuplicateExpenses = 0
        public var profilesAdded = 0
        public var profilesUpdated = 0
        public var profilesKeptNewer = 0
        public var profilesSharingName = 0
        public var methodsAdded = 0
        public var methodsUpdated = 0
        public var accountsAdded = 0
        public var accountsMatchedByName = 0
        public var sharesRestored = 0
        public var movementsAdded = 0
        public var movementsUpdated = 0
        public var movementsKeptNewer = 0
        public var rulesRestored = 0
        public var settlementsRestored = 0
        /// Relationship ids in the backup that point to records missing from both the backup and this device.
        /// The link is left empty; name snapshots keep the history readable.
        public var missingReferences = 0

        public var message: String {
            var lines = [
                "Expenses: \(expensesAdded) added, \(expensesUpdated) updated.",
                "PayBook people: \(profilesAdded) added, \(profilesUpdated) updated."
            ]
            if movementsAdded + movementsUpdated > 0 {
                lines.append("Money movements: \(movementsAdded) added, \(movementsUpdated) updated.")
            }
            if accountsAdded > 0 {
                lines.append("Accounts: \(accountsAdded) added.")
            }
            let keptNewer = expensesKeptNewer + profilesKeptNewer + movementsKeptNewer
            if keptNewer > 0 {
                lines.append("\(keptNewer) records on this device were newer and were kept.")
            }
            if possibleDuplicateExpenses > 0 {
                lines.append("\(possibleDuplicateExpenses) imported expenses look similar to existing ones. They were imported, not skipped. Please review them.")
            }
            if profilesSharingName > 0 {
                lines.append("\(profilesSharingName) imported people share a name with an existing person. They were kept separate.")
            }
            if missingReferences > 0 {
                lines.append("\(missingReferences) links pointed to records that no longer exist and were left empty.")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Imports backup JSON file from an external URL (e.g. from Files picker)
    @discardableResult
    public static func importFromJSON(at url: URL, into context: ModelContext) throws -> ImportSummary {
        let targetIsInMemory = context.container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        guard !(ExpenseDataContainer.didFailToOpenStore && targetIsInMemory) else {
            throw NSError(domain: "SpenDropBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "SpenDrop is in safe mode because your database could not be opened. Import is disabled so nothing is lost."])
        }
        guard url.startAccessingSecurityScopedResource() || true else {
            throw NSError(domain: "SpenDropBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied accessing backup file"])
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let payload = try makeDecoder().decode(BackupPayload.self, from: data)
        guard BackupPayload.supportedVersions.contains(payload.version) else {
            throw NSError(domain: "SpenDropBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "This backup was made by a newer version of SpenDrop (format \(payload.version)). Please update the app before importing it. Nothing was imported."])
        }
        let result = applyBackupPayload(payload, into: context)
        try context.save()
        saveAutoBackup(from: context)
        return result
    }

    /// Applies a backup using `id` as the only identity:
    /// - existing id: the record is updated from the backup (unless the device copy is newer)
    /// - new id: the record is imported, even if it looks like an existing one (reported, never skipped)
    /// - people are never merged because their names match
    /// - accounts are matched by id, then by name (one "Maybank" account per user)
    /// - version-2 fields are only applied from version-2 files; a version-1 file never clears them
    @discardableResult
    static func applyBackupPayload(_ payload: BackupPayload, into context: ModelContext) -> ImportSummary {
        var summary = ImportSummary()
        let isV2 = payload.version >= 2

        // 1. Accounts
        let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var accountsById = Dictionary(existingAccounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var accountsByKey: [String: Account] = [:]
        for account in existingAccounts {
            if let key = account.nameKey, accountsByKey[key] == nil { accountsByKey[key] = account }
        }
        for aDTO in payload.accounts ?? [] {
            if let found = accountsById[aDTO.id] {
                found.name = aDTO.name
                found.typeRaw = aDTO.typeRaw
                found.currency = aDTO.currency
                found.icon = aDTO.icon
                found.isArchived = aDTO.isArchived
                found.sortIndex = aDTO.sortIndex
            } else if let key = AccountLinker.normalizedKey(aDTO.name), let sameName = accountsByKey[key] {
                accountsById[aDTO.id] = sameName
                summary.accountsMatchedByName += 1
            } else {
                let account = Account(id: aDTO.id, name: aDTO.name, type: AccountType(rawValue: aDTO.typeRaw) ?? .other,
                                      currency: aDTO.currency, icon: aDTO.icon, isArchived: aDTO.isArchived,
                                      createdAt: aDTO.createdAt, sortIndex: aDTO.sortIndex)
                context.insert(account)
                accountsById[aDTO.id] = account
                if let key = account.nameKey { accountsByKey[key] = account }
                summary.accountsAdded += 1
            }
        }
        func account(_ id: UUID?) -> Account? {
            guard let id else { return nil }
            if let found = accountsById[id] { return found }
            summary.missingReferences += 1
            return nil
        }

        // 2. People and their payment methods
        let existingProfiles = (try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []
        var profilesById = Dictionary(existingProfiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingNames = Set(existingProfiles.map { $0.name.lowercased() })
        let existingMethods = (try? context.fetch(FetchDescriptor<PayBookPaymentMethod>())) ?? []
        var methodsById = Dictionary(existingMethods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for pDTO in payload.paybookProfiles {
            let prof: PayBookProfile
            if let found = profilesById[pDTO.id] {
                prof = found
                if let backupDate = pDTO.updatedAt, found.updatedAt > backupDate {
                    summary.profilesKeptNewer += 1
                } else {
                    found.name = pDTO.name
                    found.notes = pDTO.notes
                    if let frequent = pDTO.isFrequent { found.isFrequent = frequent }
                    if let archived = pDTO.isArchived { found.isArchived = archived }
                    if let updated = pDTO.updatedAt { found.updatedAt = updated }
                    summary.profilesUpdated += 1
                }
            } else {
                if existingNames.contains(pDTO.name.lowercased()) {
                    summary.profilesSharingName += 1
                }
                prof = PayBookProfile(
                    id: pDTO.id,
                    name: pDTO.name,
                    notes: pDTO.notes,
                    createdAt: pDTO.createdAt ?? Date(),
                    updatedAt: pDTO.updatedAt ?? Date()
                )
                prof.isFrequent = pDTO.isFrequent ?? false
                prof.isArchived = pDTO.isArchived ?? false
                context.insert(prof)
                profilesById[pDTO.id] = prof
                summary.profilesAdded += 1
            }

            for mDTO in pDTO.paymentMethods {
                let pType = PayBookPaymentType(rawValue: mDTO.paymentTypeRaw) ?? .bankAccount
                if let method = methodsById[mDTO.id] {
                    if let backupDate = mDTO.updatedAt, method.updatedAt > backupDate { continue }
                    method.paymentType = pType
                    method.provider = mDTO.provider
                    method.customProviderName = mDTO.customProviderName
                    method.accountIdentifier = mDTO.accountIdentifier
                    method.label = mDTO.label
                    method.notes = mDTO.notes
                    if let updated = mDTO.updatedAt { method.updatedAt = updated }
                    if method.profile?.id != prof.id {
                        method.profile?.paymentMethods.removeAll { $0.id == method.id }
                        method.profile = prof
                        prof.paymentMethods.append(method)
                    }
                    summary.methodsUpdated += 1
                } else {
                    let method = PayBookPaymentMethod(
                        id: mDTO.id,
                        paymentType: pType,
                        provider: mDTO.provider,
                        customProviderName: mDTO.customProviderName,
                        accountIdentifier: mDTO.accountIdentifier,
                        label: mDTO.label,
                        notes: mDTO.notes,
                        createdAt: mDTO.createdAt ?? Date(),
                        updatedAt: mDTO.updatedAt ?? Date(),
                        profile: prof
                    )
                    context.insert(method)
                    prof.paymentMethods.append(method)
                    methodsById[mDTO.id] = method
                    summary.methodsAdded += 1
                }
            }
        }
        func person(_ id: UUID?) -> PayBookProfile? {
            guard let id else { return nil }
            if let found = profilesById[id] { return found }
            summary.missingReferences += 1
            return nil
        }

        // 3. Expenses, with account, payer and split
        let existingExpenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        var expensesById = Dictionary(existingExpenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var existingRefs = Set<String>()
        var existingSignatures = Set<String>()
        for exp in existingExpenses {
            if let ref = exp.transactionReference, !ref.isEmpty { existingRefs.insert(ref) }
            existingSignatures.insert(expenseSignature(merchant: exp.merchant, amount: exp.amount, date: exp.date))
        }
        let existingShares = (try? context.fetch(FetchDescriptor<ExpenseShare>())) ?? []
        var sharesById = Dictionary(existingShares.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for dto in payload.expenses {
            let expense: Expense
            if let existing = expensesById[dto.id] {
                if let backupDate = dto.updatedAt, existing.updatedAt > backupDate {
                    summary.expensesKeptNewer += 1
                    continue
                }
                apply(dto, to: existing)
                expense = existing
                summary.expensesUpdated += 1
            } else {
                let sameRef = dto.transactionReference.map { !$0.isEmpty && existingRefs.contains($0) } ?? false
                if sameRef || existingSignatures.contains(expenseSignature(merchant: dto.merchant, amount: dto.amount, date: dto.date)) {
                    summary.possibleDuplicateExpenses += 1
                }
                expense = makeExpense(from: dto)
                context.insert(expense)
                expensesById[dto.id] = expense
                summary.expensesAdded += 1
            }

            guard isV2 else { continue }
            expense.account = account(dto.accountId)
            expense.paidByMe = dto.paidByMe ?? true
            expense.payer = person(dto.payerId)
            expense.payerNameSnapshot = dto.payerNameSnapshot
            expense.splitMethodRaw = dto.splitMethodRaw
            expense.splitRule = dto.splitRule

            // The backup's share list is the truth for this expense: update/insert by id, remove the rest.
            let backupShares = dto.shares ?? []
            let keepIds = Set(backupShares.map(\.id))
            for stale in expense.shares where !keepIds.contains(stale.id) {
                context.delete(stale)
            }
            for sDTO in backupShares {
                let share = sharesById[sDTO.id] ?? {
                    let created = ExpenseShare(id: sDTO.id, nameSnapshot: sDTO.nameSnapshot, amountMinor: sDTO.amountMinor)
                    context.insert(created)
                    sharesById[sDTO.id] = created
                    return created
                }()
                share.expense = expense
                share.person = sDTO.isMe ? nil : person(sDTO.personId)
                share.isMe = sDTO.isMe
                share.nameSnapshot = sDTO.nameSnapshot
                share.amountMinor = sDTO.amountMinor
                share.parts = sDTO.parts
                share.enteredMinor = sDTO.enteredMinor
                share.sortIndex = sDTO.sortIndex
                summary.sharesRestored += 1
            }
        }

        // 4. Money movements
        let existingMovements = (try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []
        var movementsById = Dictionary(existingMovements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for mDTO in payload.moneyMovements ?? [] {
            let movement: MoneyMovement
            if let found = movementsById[mDTO.id] {
                if found.updatedAt > mDTO.updatedAt {
                    summary.movementsKeptNewer += 1
                    continue
                }
                movement = found
                summary.movementsUpdated += 1
            } else {
                movement = MoneyMovement(id: mDTO.id, kind: MoneyMovementKind(rawValue: mDTO.kindRaw) ?? .otherOut, amountMinor: mDTO.amountMinor)
                context.insert(movement)
                movementsById[mDTO.id] = movement
                summary.movementsAdded += 1
            }
            movement.directionRaw = mDTO.directionRaw
            movement.kindRaw = mDTO.kindRaw
            movement.amountMinor = mDTO.amountMinor
            movement.currency = mDTO.currency
            movement.date = mDTO.date
            movement.person = person(mDTO.personId)
            movement.personNameSnapshot = mDTO.personNameSnapshot
            if let expenseId = mDTO.linkedExpenseId {
                movement.linkedExpense = expensesById[expenseId]
                if movement.linkedExpense == nil { summary.missingReferences += 1 }
            } else {
                movement.linkedExpense = nil
            }
            movement.linkedExpenseSnapshot = mDTO.linkedExpenseSnapshot
            movement.account = account(mDTO.accountId)
            movement.counterAccount = account(mDTO.counterAccountId)
            movement.note = mDTO.note
            movement.transactionReference = mDTO.transactionReference
            movement.sourceTypeRaw = mDTO.sourceTypeRaw
            movement.paymentChannelRaw = mDTO.paymentChannelRaw
            movement.createdAt = mDTO.createdAt
            movement.updatedAt = mDTO.updatedAt
        }

        // 5. Learned classification rules (version 3): by id, then by merchant key (one rule per merchant)
        let existingRules = (try? context.fetch(FetchDescriptor<ClassificationRule>())) ?? []
        var rulesById = Dictionary(existingRules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rulesByKey = Dictionary(existingRules.map { ($0.merchantKey, $0) }, uniquingKeysWith: { first, _ in first })
        for rDTO in payload.classificationRules ?? [] {
            let rule = rulesById[rDTO.id] ?? rulesByKey[rDTO.merchantKey]
            if let rule {
                guard rDTO.updatedAt >= rule.updatedAt else { continue }
                rule.categoryRaw = rDTO.categoryRaw
                rule.suggestedTypeRaw = rDTO.suggestedTypeRaw
                rule.accountId = rDTO.accountId
                rule.hitCount = rDTO.hitCount
                rule.updatedAt = rDTO.updatedAt
            } else {
                let created = ClassificationRule(id: rDTO.id, merchantKey: rDTO.merchantKey, categoryRaw: rDTO.categoryRaw,
                                                 suggestedTypeRaw: rDTO.suggestedTypeRaw, accountId: rDTO.accountId,
                                                 hitCount: rDTO.hitCount, createdAt: rDTO.createdAt, updatedAt: rDTO.updatedAt)
                context.insert(created)
                rulesById[rDTO.id] = created
                rulesByKey[rDTO.merchantKey] = created
            }
            summary.rulesRestored += 1
        }

        // 6. Learned payment channels: by id, then by merchant + funding account (one rule per pair). Newer wins.
        let existingChannelRules = (try? context.fetch(FetchDescriptor<ChannelRule>())) ?? []
        var channelRulesById = Dictionary(existingChannelRules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var channelRulesByKey = Dictionary(existingChannelRules.map { ($0.merchantKey + "|" + $0.fundingKey, $0) }, uniquingKeysWith: { first, _ in first })
        for cDTO in payload.channelRules ?? [] {
            let key = cDTO.merchantKey + "|" + cDTO.fundingKey
            if let rule = channelRulesById[cDTO.id] ?? channelRulesByKey[key] {
                guard cDTO.updatedAt >= rule.updatedAt else { continue }
                rule.channelRaw = cDTO.channelRaw
                rule.hitCount = cDTO.hitCount
                rule.updatedAt = cDTO.updatedAt
            } else {
                let created = ChannelRule(id: cDTO.id, merchantKey: cDTO.merchantKey, fundingKey: cDTO.fundingKey, channelRaw: cDTO.channelRaw,
                                          hitCount: cDTO.hitCount, createdAt: cDTO.createdAt, updatedAt: cDTO.updatedAt)
                context.insert(created)
                channelRulesById[cDTO.id] = created
                channelRulesByKey[key] = created
            }
        }

        // 7. Settlements and the sample-data register (version 4). Matched by id; nothing on the device is removed.
        let existingAllocations = (try? context.fetch(FetchDescriptor<SettlementAllocation>())) ?? []
        let allocationIDs = Set(existingAllocations.map(\.id))
        for a in payload.settlementAllocations ?? [] where !allocationIDs.contains(a.id) {
            context.insert(SettlementAllocation(id: a.id, groupID: a.groupID, kind: SettlementAllocation.Kind(rawValue: a.kindRaw) ?? .payment,
                                                paymentID: a.paymentID, expenseID: a.expenseID, loanID: a.loanID, personID: a.personID,
                                                direction: a.direction, amountMinor: a.amountMinor, currency: a.currency, date: a.date,
                                                createdAt: a.createdAt))
            summary.settlementsRestored += 1
        }
        let existingSample = Set(((try? context.fetch(FetchDescriptor<SampleDataRecord>())) ?? []).map(\.recordID))
        for r in payload.sampleRecords ?? [] where !existingSample.contains(r.recordID) {
            if let entity = SampleDataRecord.Entity(rawValue: r.entityRaw) {
                context.insert(SampleDataRecord(recordID: r.recordID, entity: entity, createdAt: r.createdAt))
            }
        }

        return summary
    }

    private static func expenseSignature(merchant: String, amount: Double, date: Date) -> String {
        "\(merchant.lowercased())_\(amount)_\(Calendar.current.component(.day, from: date))"
    }

    private static func makeExpense(from dto: ExpenseDTO) -> Expense {
        let cat = ExpenseCategory(rawValue: dto.categoryRaw) ?? .personal
        let src = PaymentSource(rawValue: dto.paymentSourceRaw) ?? .touchNGo
        let bank = dto.underlyingBankRaw != nil ? PaymentSource(rawValue: dto.underlyingBankRaw!) : nil
        let sType = ExpenseSourceType(rawValue: dto.sourceTypeRaw) ?? .screenshot
        let channel = dto.paymentChannelRaw != nil ? (PaymentChannel(rawValue: dto.paymentChannelRaw!) ?? .unknown) : .unknown
        let funding = dto.fundingAccount ?? bank?.rawValue ?? (src != .applePay && src != .qrPayment && src != .bankTransfer && src != .physicalCard && src != .unknown ? src.rawValue : "Unknown")
        let matching = dto.matchingStatusRaw ?? "UNMATCHED"

        return Expense(
            id: dto.id,
            amount: dto.amount,
            currency: dto.currency,
            merchant: dto.merchant,
            category: cat,
            paymentSource: src,
            underlyingBank: bank,
            paymentMethod: dto.paymentMethodRaw,
            date: dto.date,
            notes: dto.notes,
            transactionReference: dto.transactionReference,
            imageRelativePath: dto.imageRelativePath,
            sourceType: sType,
            ocrText: dto.ocrText,
            confidence: dto.confidence,
            isSampleData: dto.isSampleData,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt ?? dto.createdAt,
            paymentChannel: channel,
            fundingAccount: funding,
            fundingInstrument: dto.fundingInstrument,
            externalTransactionId: dto.externalTransactionId,
            matchingStatus: matching,
            matchingConfidence: dto.matchingConfidence
        )
    }

    /// Updates an existing expense from a backup record. Fields added after backup version 1 are only
    /// applied when the backup contains them, so an older file never clears newer data.
    private static func apply(_ dto: ExpenseDTO, to expense: Expense) {
        expense.amount = dto.amount
        expense.currency = dto.currency
        expense.merchant = dto.merchant
        expense.categoryRaw = dto.categoryRaw
        expense.paymentSourceRaw = dto.paymentSourceRaw
        expense.underlyingBankRaw = dto.underlyingBankRaw
        expense.paymentMethodRaw = dto.paymentMethodRaw
        expense.date = dto.date
        expense.notes = dto.notes
        expense.transactionReference = dto.transactionReference
        expense.sourceTypeRaw = dto.sourceTypeRaw
        expense.ocrText = dto.ocrText
        expense.isSampleData = dto.isSampleData
        expense.createdAt = dto.createdAt
        if let channel = dto.paymentChannelRaw { expense.paymentChannelRaw = channel }
        if let funding = dto.fundingAccount { expense.fundingAccount = funding }
        expense.fundingInstrument = dto.fundingInstrument
        if let matching = dto.matchingStatusRaw { expense.matchingStatusRaw = matching }
        if let path = dto.imageRelativePath { expense.imageRelativePath = path }
        if let confidence = dto.confidence { expense.confidence = confidence }
        if let externalId = dto.externalTransactionId { expense.externalTransactionId = externalId }
        if let matchingConfidence = dto.matchingConfidence { expense.matchingConfidence = matchingConfidence }
        if let updated = dto.updatedAt { expense.updatedAt = updated }
    }
}

extension UserDataBackupService {
    /// A local backup for UI tests, made "now": 7 expenses spread so that each restore range finds a different
    /// number (7 days: 3, 30 days: 4, 2 months: 5, 3 months: 6, everything: 7). Dated relative to today so the
    /// restored expenses also appear in the app's own "Last 7 Days" view.
    static func uiTestBackupFixture() -> BackupPayload? {
        guard let container = try? ModelContainer(for: ExpenseDataContainer.currentSchema,
                                                  configurations: [ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)]) else { return nil }
        let context = ModelContext(container)
        let reference = Date()
        let maybank = Account(name: "Maybank", type: .bank)
        context.insert(maybank)
        for (merchant, daysAgo) in [("Fixture Today", 0), ("Fixture Two Days", 2), ("Fixture Six Days", 6), ("Fixture Twenty Days", 20),
                                    ("Fixture Fifty Days", 50), ("Fixture Eighty Days", 80), ("Fixture Old", 200)] {
            let expense = Expense(amount: 10, merchant: merchant, paymentSource: .maybank,
                                  date: reference.addingTimeInterval(TimeInterval(-daysAgo * 86_400)), fundingAccount: "Maybank")
            if daysAgo == 0 { expense.account = maybank }
            context.insert(expense)
        }
        try? context.save()
        let built = makePayload(from: context)
        var payload = BackupPayload(version: built.version, appName: built.appName, accountName: built.accountName,
                                    exportDate: reference, expenses: built.expenses, paybookProfiles: built.paybookProfiles)
        payload.accounts = built.accounts
        payload.moneyMovements = built.moneyMovements
        payload.classificationRules = built.classificationRules
        return payload
    }
}

// MARK: - Restore with a date range (full snapshot in, filtered merge out)

/// Which part of a full backup to restore. Ranges are whole calendar days ending on the backup's own day,
/// so the same backup always gives the same range no matter when the restore runs.
public enum RestoreRange: Hashable {
    case everything
    case lastDays(Int)
    case lastMonths(Int)
    /// Inclusive start and end days (time of day is ignored).
    case custom(start: Date, end: Date)

    public static let last7Days = RestoreRange.lastDays(7)
    public static let last30Days = RestoreRange.lastDays(30)
    public static let last2Months = RestoreRange.lastMonths(2)
    public static let last3Months = RestoreRange.lastMonths(3)

    public var title: String {
        switch self {
        case .everything: return "Everything"
        case .lastDays(let n): return "Last \(n) days"
        case .lastMonths(let n): return "Last \(n) months"
        case .custom: return "Custom range"
        }
    }

    /// Half-open interval [start, end) covering whole days in `calendar`'s time zone; nil means no date filter.
    /// - Last N days: the backup day and the N − 1 days before it (7 days from 5 Oct = 29 Sep – 5 Oct).
    /// - Last N months: from the day after the same date N calendar months earlier (2 months from 5 Oct = 6 Aug – 5 Oct;
    ///   from 31 Mar = 1 Feb – 31 Mar, because Calendar clamps 31 Jan correctly and leap days are respected).
    public func interval(reference: Date, calendar: Calendar) -> DateInterval? {
        let referenceDay = calendar.startOfDay(for: reference)
        guard let afterReferenceDay = calendar.date(byAdding: .day, value: 1, to: referenceDay) else { return nil }
        switch self {
        case .everything:
            return nil
        case .lastDays(let n):
            guard let start = calendar.date(byAdding: .day, value: -(max(n, 1) - 1), to: referenceDay) else { return nil }
            return DateInterval(start: start, end: afterReferenceDay)
        case .lastMonths(let n):
            guard let sameDate = calendar.date(byAdding: .month, value: -max(n, 1), to: referenceDay),
                  let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: sameDate)) else { return nil }
            return DateInterval(start: start, end: afterReferenceDay)
        case .custom(let startDate, let endDate):
            let start = calendar.startOfDay(for: startDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)), start < end else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// Custom ranges: start must not be after end. Other ranges are always valid.
    public func validationProblem(calendar: Calendar) -> String? {
        guard case .custom(let start, let end) = self else { return nil }
        if calendar.startOfDay(for: start) > calendar.startOfDay(for: end) { return "The start date must be on or before the end date." }
        return nil
    }
}

public extension DateInterval {
    /// Membership for half-open day intervals built by `RestoreRange` (the end instant belongs to the next day).
    func containsRestoreDate(_ date: Date) -> Bool { date >= start && date < end }

    /// "29 Sep 2026 – 5 Oct 2026" (the last included day, not the exclusive end).
    func restoreDescription(calendar: Calendar) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = calendar.timeZone
        return "\(start.formatted(style)) – \(lastDay.formatted(style))"
    }
}

extension UserDataBackupService {
    /// Ids already on this device, fetched once per type (no per-record queries).
    public struct LocalRecordIDs {
        public var expenses = Set<UUID>()
        public var accounts = Set<UUID>()
        public var accountNames = Set<String>()
        public var movements = Set<UUID>()
        public var profiles = Set<UUID>()

        public init() {}

        public static func fetch(from context: ModelContext) -> LocalRecordIDs {
            var ids = LocalRecordIDs()
            ids.expenses = Set(((try? context.fetch(FetchDescriptor<Expense>())) ?? []).map(\.id))
            let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            ids.accounts = Set(accounts.map(\.id))
            ids.accountNames = Set(accounts.compactMap(\.nameKey))
            ids.movements = Set(((try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []).map(\.id))
            ids.profiles = Set(((try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []).map(\.id))
            return ids
        }
    }

    public struct RecordCounts: Equatable {
        public var expenses = 0
        public var accounts = 0
        public var movements = 0
        public var profiles = 0
        public var rules = 0
        public var total: Int { expenses + accounts + movements + profiles + rules }
    }

    /// What a restore will write, computed before anything is written.
    public struct RestorePlan {
        public let range: RestoreRange
        public let interval: DateInterval?
        /// The filtered backup handed to the existing id-based merge.
        public let payload: BackupPayload
        /// Records in `payload`.
        public let counts: RecordCounts
        /// Of those, records whose id (or, for accounts, name) is already on this device: merged, never duplicated.
        public let alreadyOnDevice: RecordCounts
        /// Money records in the range that point to an expense outside it (the link stays empty unless that expense
        /// is already on this device; the name snapshot keeps the record readable).
        public let linksOutsideRange: Int
        public var isEmpty: Bool { counts.total == 0 }
    }

    public struct RestoreResult {
        public let plan: RestorePlan
        public let summary: ImportSummary
        /// New records written to this device.
        public var added: RecordCounts {
            RecordCounts(expenses: summary.expensesAdded, accounts: summary.accountsAdded, movements: summary.movementsAdded,
                         profiles: summary.profilesAdded, rules: summary.rulesRestored)
        }
    }

    /// Builds the plan. Expenses and money records are filtered by their own date; everything they depend on
    /// (funding accounts by id or name, payers and split people, money-record people and accounts, learned
    /// categories for the restored merchants) comes along whatever its own creation date.
    public static func makeRestorePlan(from backup: BackupPayload, range: RestoreRange, calendar: Calendar = .current,
                                       localIDs: LocalRecordIDs = LocalRecordIDs()) -> RestorePlan {
        let interval = range.interval(reference: backup.exportDate, calendar: calendar)
        let payload: BackupPayload
        var linksOutside = 0

        if range == .everything {
            payload = backup
        } else if let interval {
            let expenses = backup.expenses.filter { interval.containsRestoreDate($0.date) }
            let movements = (backup.moneyMovements ?? []).filter { interval.containsRestoreDate($0.date) }
            let expenseIDs = Set(expenses.map(\.id))
            linksOutside = movements.filter { $0.linkedExpenseId.map { !expenseIDs.contains($0) } ?? false }.count

            var accountIDs = Set(expenses.compactMap(\.accountId))
            accountIDs.formUnion(movements.compactMap(\.accountId))
            accountIDs.formUnion(movements.compactMap(\.counterAccountId))
            let fundingNames = Set(expenses.compactMap { AccountLinker.normalizedKey($0.fundingAccount) })

            // Rules are stored under the recognised merchant's name or the merchant text itself.
            let merchantKeys = Set(expenses.flatMap { [TransactionClassifier.ruleKey($0.merchant), TransactionClassifier.merchantKey($0.merchant)].compactMap { $0 } })
            let rules = (backup.classificationRules ?? []).filter { merchantKeys.contains($0.merchantKey) }
            accountIDs.formUnion(rules.compactMap(\.accountId))

            let accounts = (backup.accounts ?? []).filter {
                accountIDs.contains($0.id) || (AccountLinker.normalizedKey($0.name).map(fundingNames.contains) ?? false)
            }

            var personIDs = Set(expenses.compactMap(\.payerId))
            personIDs.formUnion(expenses.flatMap { ($0.shares ?? []).compactMap(\.personId) })
            personIDs.formUnion(movements.compactMap(\.personId))
            let profiles = backup.paybookProfiles.filter { personIDs.contains($0.id) }

            var filtered = BackupPayload(version: backup.version, appName: backup.appName, accountName: backup.accountName,
                                         exportDate: backup.exportDate, expenses: expenses, paybookProfiles: profiles)
            filtered.accounts = backup.accounts == nil ? nil : accounts
            filtered.moneyMovements = backup.moneyMovements == nil ? nil : movements
            filtered.classificationRules = backup.classificationRules == nil ? nil : rules
            filtered.channelRules = backup.channelRules?.filter { merchantKeys.contains($0.merchantKey) }
            let movementIDs = Set(movements.map(\.id))
            filtered.settlementAllocations = backup.settlementAllocations?.filter { a in
                a.paymentID.map(movementIDs.contains) ?? ((a.expenseID.map(expenseIDs.contains) ?? false) || (a.loanID.map(movementIDs.contains) ?? false))
            }
            var keptIDs = expenseIDs.union(movementIDs).union(accounts.map(\.id)).union(profiles.map(\.id)).union(rules.map(\.id))
            keptIDs.formUnion(filtered.settlementAllocations?.map(\.id) ?? [])
            filtered.sampleRecords = backup.sampleRecords?.filter { keptIDs.contains($0.recordID) }
            payload = filtered
        } else {
            // Invalid custom range: restore nothing.
            payload = BackupPayload(version: backup.version, appName: backup.appName, accountName: backup.accountName,
                                    exportDate: backup.exportDate, expenses: [], paybookProfiles: [])
        }

        let counts = RecordCounts(expenses: payload.expenses.count, accounts: payload.accounts?.count ?? 0,
                                  movements: payload.moneyMovements?.count ?? 0, profiles: payload.paybookProfiles.count,
                                  rules: payload.classificationRules?.count ?? 0)
        let existing = RecordCounts(
            expenses: payload.expenses.filter { localIDs.expenses.contains($0.id) }.count,
            accounts: (payload.accounts ?? []).filter {
                localIDs.accounts.contains($0.id) || (AccountLinker.normalizedKey($0.name).map(localIDs.accountNames.contains) ?? false)
            }.count,
            movements: (payload.moneyMovements ?? []).filter { localIDs.movements.contains($0.id) }.count,
            profiles: payload.paybookProfiles.filter { localIDs.profiles.contains($0.id) }.count,
            rules: 0)
        return RestorePlan(range: range, interval: interval, payload: payload, counts: counts,
                           alreadyOnDevice: existing, linksOutsideRange: linksOutside)
    }

    /// Merges the plan with the existing id-based merge, then saves once. Nothing is ever deleted: records outside
    /// the range and records only on this device are untouched. If saving fails, every pending change is rolled
    /// back so the store is left exactly as it was.
    @MainActor
    public static func applyRestorePlan(_ plan: RestorePlan, into context: ModelContext) throws -> RestoreResult {
        guard BackupPayload.supportedVersions.contains(plan.payload.version) else {
            throw NSError(domain: "SpenDropBackup", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "This backup was made by a newer version of SpenDrop (format \(plan.payload.version)). Update the app to restore it. Nothing was restored."])
        }
        let summary = applyBackupPayload(plan.payload, into: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return RestoreResult(plan: plan, summary: summary)
    }
}
