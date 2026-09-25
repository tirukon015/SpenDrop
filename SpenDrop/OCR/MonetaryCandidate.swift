import Foundation
import CoreGraphics

public enum MonetarySemanticType: String, Codable, CaseIterable {
    case transactionAmount = "transaction_amount"
    case total = "total"
    case fee = "fee"
    case balance = "balance"
    case cashback = "cashback"
    case discount = "discount"
    case promotion = "promotion"
    case advertisement = "advertisement"
    case productPrice = "product_price"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .transactionAmount: return "Transaction Amount"
        case .total: return "Total"
        case .fee: return "Fee"
        case .balance: return "Balance"
        case .cashback: return "Cashback"
        case .discount: return "Discount"
        case .promotion: return "Promotion"
        case .advertisement: return "Advertisement"
        case .productPrice: return "Product Price"
        case .unknown: return "Unknown"
        }
    }

    public var isExcludedFromTransactionAmount: Bool {
        switch self {
        case .fee, .balance, .cashback, .discount, .promotion, .advertisement, .productPrice:
            return true
        default:
            return false
        }
    }
}

public struct MonetaryCandidate: Identifiable {
    public let id: UUID
    public let amount: Double
    public let currency: String
    public let rawString: String
    public let lineIndex: Int
    public let lineText: String
    public let boundingBox: CGRect
    public var semanticType: MonetarySemanticType
    public var confidenceScore: Double // 0.0 to 1.0
    public var reasoning: String

    public init(
        id: UUID = UUID(),
        amount: Double,
        currency: String = "RM",
        rawString: String,
        lineIndex: Int,
        lineText: String,
        boundingBox: CGRect = .zero,
        semanticType: MonetarySemanticType = .unknown,
        confidenceScore: Double = 0.5,
        reasoning: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.rawString = rawString
        self.lineIndex = lineIndex
        self.lineText = lineText
        self.boundingBox = boundingBox
        self.semanticType = semanticType
        self.confidenceScore = confidenceScore
        self.reasoning = reasoning
    }
}
