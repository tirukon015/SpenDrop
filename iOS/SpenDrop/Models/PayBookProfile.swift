import Foundation
import SwiftData

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

    // MARK: - People & Balances (Financial Architecture V2)
    public var isFrequent: Bool = false
    public var isArchived: Bool = false

    /// Deleting a person keeps these records; their name snapshots keep history readable.
    @Relationship(deleteRule: .nullify, inverse: \ExpenseShare.person)
    public var shares: [ExpenseShare] = []

    @Relationship(deleteRule: .nullify, inverse: \Expense.payer)
    public var paidExpenses: [Expense] = []

    @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.person)
    public var movements: [MoneyMovement] = []

    public init(
        id: UUID = UUID(),
        name: String,
        photoData: Data? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        paymentMethods: [PayBookPaymentMethod] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photoData = photoData
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paymentMethods = paymentMethods
    }

    /// Initials used for default avatar when no photo is provided
    public var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let last = parts[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    /// Human-readable count of saved payment methods
    public var paymentMethodCountText: String {
        let count = paymentMethods.count
        if count == 1 {
            return "1 payment method"
        }
        return "\(count) payment methods"
    }

    /// Comma-separated summary of providers (e.g. "CIMB, Maybank, TNG")
    public var providersSummary: String {
        guard !paymentMethods.isEmpty else {
            return "No payment methods"
        }
        let names = paymentMethods.map { $0.displayProvider }
        return names.joined(separator: ", ")
    }
}
