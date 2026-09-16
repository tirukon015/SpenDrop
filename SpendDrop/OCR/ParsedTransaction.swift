import UIKit

public enum ParsingConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    public var isConfident: Bool {
        self == .high || self == .medium
    }
}

public struct ParsedTransaction {
    public var amount: Double?
    public var currency: String
    public var merchant: String?
    public var date: Date?
    public var paymentSource: PaymentSource?
    public var category: ExpenseCategory?
    public var transactionReference: String?
    public var transactionStatus: String?
    public var confidence: ParsingConfidence
    public var rawOCRText: String
    public var detectedLines: [String]
    public var originalImage: UIImage?

    // Contextual flags
    public var isCompletedTransaction: Bool
    public var isFailedTransaction: Bool
    public var isBalanceOrLimitOnly: Bool

    public init(
        amount: Double? = nil,
        currency: String = "RM",
        merchant: String? = nil,
        date: Date? = nil,
        paymentSource: PaymentSource? = nil,
        category: ExpenseCategory? = nil,
        transactionReference: String? = nil,
        transactionStatus: String? = nil,
        confidence: ParsingConfidence = .low,
        rawOCRText: String = "",
        detectedLines: [String] = [],
        originalImage: UIImage? = nil,
        isCompletedTransaction: Bool = false,
        isFailedTransaction: Bool = false,
        isBalanceOrLimitOnly: Bool = false
    ) {
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.date = date
        self.paymentSource = paymentSource
        self.category = category
        self.transactionReference = transactionReference
        self.transactionStatus = transactionStatus
        self.confidence = confidence
        self.rawOCRText = rawOCRText
        self.detectedLines = detectedLines
        self.originalImage = originalImage
        self.isCompletedTransaction = isCompletedTransaction
        self.isFailedTransaction = isFailedTransaction
        self.isBalanceOrLimitOnly = isBalanceOrLimitOnly
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
}
