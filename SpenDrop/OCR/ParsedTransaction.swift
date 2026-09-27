import UIKit

public enum ParsingConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    public var isConfident: Bool {
        self == .high || self == .medium
    }
}

public struct ParsedTransaction: Identifiable {
    public let id: UUID
    public var amount: Double?
    public var amountConfidence: Double
    public var currency: String
    public var merchant: String?
    public var date: Date?
    public var dateString: String?
    public var timeString: String?
    public var paymentSource: PaymentSource?
    public var provider: String
    public var providerConfidence: Double
    public var paymentMethod: String?
    public var paymentChannel: PaymentChannel
    public var fundingAccount: String?
    public var underlyingBank: PaymentSource?
    public var underlyingBankNormalizedId: String?
    public var suggestedRemark: String?
    public var category: ExpenseCategory?
    public var transactionReference: String?
    public var transactionStatus: String?
    public var confidence: ParsingConfidence
    public var rawOCRText: String
    public var detectedLines: [String]
    public var amountCandidates: [MonetaryCandidate]
    public var originalImage: UIImage?

    // Contextual flags
    public var isCompletedTransaction: Bool
    public var isFailedTransaction: Bool
    public var isBalanceOrLimitOnly: Bool

    public init(
        id: UUID = UUID(),
        amount: Double? = nil,
        amountConfidence: Double = 0.5,
        currency: String = "RM",
        merchant: String? = nil,
        date: Date? = nil,
        dateString: String? = nil,
        timeString: String? = nil,
        paymentSource: PaymentSource? = nil,
        provider: String = "unknown",
        providerConfidence: Double = 0.0,
        paymentMethod: String? = nil,
        paymentChannel: PaymentChannel = .unknown,
        fundingAccount: String? = nil,
        underlyingBank: PaymentSource? = nil,
        underlyingBankNormalizedId: String? = nil,
        suggestedRemark: String? = nil,
        category: ExpenseCategory? = nil,
        transactionReference: String? = nil,
        transactionStatus: String? = nil,
        confidence: ParsingConfidence = .low,
        rawOCRText: String = "",
        detectedLines: [String] = [],
        amountCandidates: [MonetaryCandidate] = [],
        originalImage: UIImage? = nil,
        isCompletedTransaction: Bool = false,
        isFailedTransaction: Bool = false,
        isBalanceOrLimitOnly: Bool = false
    ) {
        self.id = id
        self.amount = amount
        self.amountConfidence = amountConfidence
        self.currency = currency
        self.merchant = merchant
        self.date = date
        self.dateString = dateString
        self.timeString = timeString
        self.paymentSource = paymentSource
        self.provider = provider
        self.providerConfidence = providerConfidence
        self.paymentMethod = paymentMethod
        self.paymentChannel = paymentChannel
        self.fundingAccount = fundingAccount
        self.underlyingBank = underlyingBank
        self.underlyingBankNormalizedId = underlyingBankNormalizedId
        self.suggestedRemark = suggestedRemark
        self.category = category
        self.transactionReference = transactionReference
        self.transactionStatus = transactionStatus
        self.confidence = confidence
        self.rawOCRText = rawOCRText
        self.detectedLines = detectedLines
        self.amountCandidates = amountCandidates
        self.originalImage = originalImage
        self.isCompletedTransaction = isCompletedTransaction
        self.isFailedTransaction = isFailedTransaction
        self.isBalanceOrLimitOnly = isBalanceOrLimitOnly
    }

    /// Normalized Transaction Dictionary representation (Issue 4, 6)
    public func toNormalizedDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "paymentProvider": provider,
            "provider": provider, // Backward-compatible alias
            "providerConfidence": providerConfidence,
            "paymentMethod": paymentMethod ?? "unknown",
            "currency": currency == "RM" ? "MYR" : currency,
            "status": transactionStatus?.lowercased() ?? "unknown"
        ]
        if let bankId = underlyingBankNormalizedId {
            dict["underlyingBank"] = bankId
        } else {
            dict["underlyingBank"] = NSNull()
        }
        if let amt = amount {
            dict["amount"] = amt
            dict["amountConfidence"] = amountConfidence
        }
        if let m = merchant {
            dict["merchant"] = m
        }
        if let d = dateString {
            dict["date"] = d
        }
        if let t = timeString {
            dict["time"] = t
        }
        return dict
    }

    public var displayMerchant: String {
        merchant ?? "Unknown Merchant"
    }

    public var displayPaymentSource: PaymentSource {
        paymentSource ?? .unknown
    }

    public var displayCategory: ExpenseCategory {
        category ?? .other
    }

    public var displayDate: Date {
        date ?? Date()
    }

    public var displayFundingAccount: String {
        if let fa = fundingAccount, !fa.isEmpty, fa != "Unknown" {
            return fa
        }
        if let bank = underlyingBank, bank != .unknown {
            return bank.rawValue
        }
        if let src = paymentSource, src != .applePay, src != .qrPayment, src != .bankTransfer, src != .physicalCard, src != .unknown {
            return src.rawValue
        }
        return "Unknown"
    }
}
