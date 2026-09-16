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
    public var date: Date
    public var notes: String?
    public var transactionReference: String?
    public var imageRelativePath: String?
    public var sourceTypeRaw: String
    public var ocrText: String?
    public var confidence: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        amount: Double,
        currency: String = "RM",
        merchant: String = "Unknown",
        category: ExpenseCategory = .other,
        paymentSource: PaymentSource = .cash,
        date: Date = Date(),
        notes: String? = nil,
        transactionReference: String? = nil,
        imageRelativePath: String? = nil,
        sourceType: ExpenseSourceType = .manual,
        ocrText: String? = nil,
        confidence: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : merchant
        self.categoryRaw = category.rawValue
        self.paymentSourceRaw = paymentSource.rawValue
        self.date = date
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : notes
        self.transactionReference = transactionReference
        self.imageRelativePath = imageRelativePath
        self.sourceTypeRaw = sourceType.rawValue
        self.ocrText = ocrText
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    public var paymentSource: PaymentSource {
        get { PaymentSource(rawValue: paymentSourceRaw) ?? .unknown }
        set { paymentSourceRaw = newValue.rawValue }
    }

    public var sourceType: ExpenseSourceType {
        get { ExpenseSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
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
