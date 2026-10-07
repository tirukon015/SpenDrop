import Foundation
import SwiftData

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

    // MARK: - Transaction Intelligence V1 (Channels & Funding Accounts)
    public var paymentChannelRaw: String = PaymentChannel.unknown.rawValue
    public var fundingAccount: String = "Unknown"
    public var fundingInstrument: String? = nil
    public var externalTransactionId: String? = nil
    public var matchingStatusRaw: String = "UNMATCHED"
    public var matchingConfidence: Double? = nil

    // MARK: - Financial Architecture V2 (Accounts, Payer, Splits)
    // The text fields above (fundingAccount, paymentSourceRaw, underlyingBankRaw) are kept as historical snapshots.
    public var account: Account? = nil
    /// false when another person paid the whole bill (`payer`).
    public var paidByMe: Bool = true
    public var payer: PayBookProfile? = nil
    public var payerNameSnapshot: String? = nil
    /// nil = not shared. See `SplitMethod`.
    public var splitMethodRaw: String? = nil
    /// Hybrid Split (schema V6): the rule as canonical JSON (Common/BusinessRules/split-hybrid.md); nil = a normal
    /// split. The shares are always stored as plain Custom Amounts, so nothing else depends on this.
    public var splitRule: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \ExpenseShare.expense)
    public var shares: [ExpenseShare] = []

    /// Money movements that reference this expense (e.g. refunds). They are kept if the expense is deleted.
    @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.linkedExpense)
    public var linkedMovements: [MoneyMovement] = []

    public init(
        id: UUID = UUID(),
        amount: Double,
        currency: String = "RM",
        merchant: String = "Unknown",
        category: ExpenseCategory = .other,
        paymentSource: PaymentSource = .unknown,
        underlyingBank: PaymentSource? = nil,
        paymentMethod: String? = nil,
        date: Date = Date(),
        notes: String? = nil,
        transactionReference: String? = nil,
        imageRelativePath: String? = nil,
        sourceType: ExpenseSourceType = .manual,
        ocrText: String? = nil,
        confidence: Double? = nil,
        isSampleData: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        paymentChannel: PaymentChannel = .unknown,
        fundingAccount: String? = nil,
        fundingInstrument: String? = nil,
        externalTransactionId: String? = nil,
        matchingStatus: String = "UNMATCHED",
        matchingConfidence: Double? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : merchant
        self.categoryRaw = category.rawValue
        self.paymentSourceRaw = paymentSource.rawValue
        self.underlyingBankRaw = underlyingBank?.rawValue
        self.paymentMethodRaw = paymentMethod ?? paymentSource.defaultPaymentMethod
        self.date = date
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : notes
        self.transactionReference = transactionReference
        self.imageRelativePath = imageRelativePath
        self.sourceTypeRaw = sourceType.rawValue
        self.ocrText = ocrText
        self.confidence = confidence
        self.isSampleData = isSampleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        // Funding Account derivation
        if let explicitFunding = fundingAccount, !explicitFunding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.fundingAccount = explicitFunding
        } else if let bank = underlyingBank, bank != .unknown {
            self.fundingAccount = bank.rawValue
        } else if paymentSource != .applePay && paymentSource != .qrPayment &&
                    paymentSource != .bankTransfer && paymentSource != .physicalCard &&
                    paymentSource != .unknown && paymentSource != .other {
            self.fundingAccount = paymentSource.rawValue
        } else {
            self.fundingAccount = "Unknown"
        }

        // Payment Channel derivation (Never guesses: uses unknown if not confirmed)
        if paymentChannel != .unknown {
            self.paymentChannelRaw = paymentChannel.rawValue
        } else if paymentSource == .applePay {
            self.paymentChannelRaw = PaymentChannel.applePay.rawValue
        } else if paymentSource == .qrPayment || paymentMethod == "duitnow_qr" {
            self.paymentChannelRaw = PaymentChannel.qrPayment.rawValue
        } else if paymentSource == .bankTransfer || paymentMethod == "bank_transfer" {
            self.paymentChannelRaw = PaymentChannel.bankTransfer.rawValue
        } else if paymentSource == .physicalCard || paymentMethod == "card" {
            self.paymentChannelRaw = PaymentChannel.card.rawValue
        } else if paymentSource == .cash || paymentMethod == "cash" {
            self.paymentChannelRaw = PaymentChannel.cash.rawValue
        } else {
            self.paymentChannelRaw = PaymentChannel.unknown.rawValue
        }

        self.fundingInstrument = fundingInstrument
        self.externalTransactionId = externalTransactionId
        self.matchingStatusRaw = matchingStatus
        self.matchingConfidence = matchingConfidence
    }

    public var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    public var paymentSource: PaymentSource {
        get { PaymentSource(rawValue: paymentSourceRaw) ?? .unknown }
        set { paymentSourceRaw = newValue.rawValue }
    }

    public var underlyingBank: PaymentSource? {
        get {
            guard let raw = underlyingBankRaw else { return nil }
            return PaymentSource(rawValue: raw)
        }
        set {
            underlyingBankRaw = newValue?.rawValue
        }
    }

    public var paymentMethod: String {
        get { paymentMethodRaw ?? paymentSource.defaultPaymentMethod }
        set { paymentMethodRaw = newValue }
    }

    public var paymentChannel: PaymentChannel {
        get {
            if let channel = PaymentChannel(rawValue: paymentChannelRaw) {
                return channel
            }
            // Conservative fallback for older records without raw channel stored
            if paymentSourceRaw == PaymentSource.applePay.rawValue || paymentMethodRaw == "digital_wallet" {
                return .applePay
            } else if paymentSourceRaw == PaymentSource.qrPayment.rawValue || paymentMethodRaw == "duitnow_qr" {
                return .qrPayment
            } else if paymentSourceRaw == PaymentSource.bankTransfer.rawValue || paymentMethodRaw == "bank_transfer" {
                return .bankTransfer
            } else if paymentSourceRaw == PaymentSource.physicalCard.rawValue || paymentMethodRaw == "card" {
                return .card
            } else if paymentSourceRaw == PaymentSource.cash.rawValue && (paymentMethodRaw == "cash" || fundingAccount == "Cash") {
                return .cash
            }
            return .unknown
        }
        set {
            paymentChannelRaw = newValue.rawValue
        }
    }

    public var effectiveFundingAccount: String {
        let trimmed = fundingAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "Unknown" {
            return trimmed
        }
        if let bank = underlyingBankRaw, !bank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, bank != "Unknown" {
            return bank
        }
        if paymentSourceRaw != PaymentSource.applePay.rawValue &&
           paymentSourceRaw != PaymentSource.qrPayment.rawValue &&
           paymentSourceRaw != PaymentSource.bankTransfer.rawValue &&
           paymentSourceRaw != PaymentSource.physicalCard.rawValue &&
           paymentSourceRaw != PaymentSource.unknown.rawValue &&
           paymentSourceRaw != PaymentSource.other.rawValue &&
           !paymentSourceRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return paymentSourceRaw
        }
        return "Unknown"
    }

    public var displayFundingAndChannel: String {
        let funding = effectiveFundingAccount
        let channel = paymentChannel
        if funding == "Unknown" && channel == .unknown {
            return "Unknown"
        }
        return "\(funding) • \(channel.displayName)"
    }

    public var displayPaymentTitle: String {
        displayFundingAndChannel
    }

    public var isReconciled: Bool {
        matchingStatusRaw == "RECONCILED" || matchingStatusRaw == "MATCHED"
    }

    public var sourceType: ExpenseSourceType {
        get { ExpenseSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    public var splitMethod: SplitMethod? {
        get { splitMethodRaw.flatMap(SplitMethod.init(rawValue:)) }
        set { splitMethodRaw = newValue?.rawValue }
    }

    /// Marks another person as the payer and records their current name for history. Pass nil for "I paid".
    public func setPayer(_ person: PayBookProfile?) {
        payer = person
        paidByMe = (person == nil)
        payerNameSnapshot = person?.name
    }

    public var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.isEmpty ? "RM" : "\(currency) "
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }
}
