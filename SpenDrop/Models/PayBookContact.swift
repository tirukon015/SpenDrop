import Foundation
import SwiftData

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

    public init(
        id: UUID = UUID(),
        name: String,
        bankName: String,
        accountHolderName: String,
        accountNumber: String,
        phoneNumber: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bankName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountHolderName = accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountNumber = accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.phoneNumber = (trimmedPhone?.isEmpty == true) ? nil : trimmedPhone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Partially masked account number for list view (e.g. "••••7890" or full if short)
    public var maskedAccountNumber: String {
        let clean = accountNumber.filter { $0.isNumber || $0.isLetter }
        if clean.count > 4 {
            let lastFour = String(clean.suffix(4))
            return "••••\(lastFour)"
        }
        return accountNumber
    }

    /// Plain text subtitle for the contact list: e.g. "Maybank ••••7890" or "Maybank • 1234"
    public var displaySubtitle: String {
        if maskedAccountNumber.isEmpty {
            return bankName
        }
        if maskedAccountNumber.hasPrefix("•") {
            return "\(bankName) \(maskedAccountNumber)"
        } else {
            return "\(bankName) • \(maskedAccountNumber)"
        }
    }
}
