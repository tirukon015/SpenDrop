import Foundation
import SwiftData

public enum PayBookPaymentType: String, CaseIterable, Identifiable, Codable {
    case bankAccount = "Bank Account"
    case eWallet = "E-Wallet"
    case paymentId = "Payment ID"
    case other = "Other"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .bankAccount: return "building.columns.fill"
        case .eWallet: return "iphone"
        case .paymentId: return "qrcode"
        case .other: return "creditcard.fill"
        }
    }

    public var identifierFieldLabel: String {
        switch self {
        case .bankAccount: return "Account Number"
        case .eWallet: return "Phone Number / Wallet ID"
        case .paymentId: return "Payment ID"
        case .other: return "Payment Identifier"
        }
    }
}

public struct PayBookProviders {
    public static let common: [String] = [
        "CIMB Bank",
        "Maybank",
        "RHB Bank",
        "Affin Bank",
        "Public Bank",
        "Hong Leong Bank",
        "AmBank",
        "Bank Islam",
        "Bank Rakyat",
        "OCBC Bank",
        "UOB",
        "HSBC",
        "Standard Chartered",
        "Touch 'n Go",
        "GrabPay",
        "DuitNow",
        "Other"
    ]
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

    public init(
        id: UUID = UUID(),
        paymentType: PayBookPaymentType = .bankAccount,
        provider: String,
        customProviderName: String? = nil,
        accountIdentifier: String,
        label: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        profile: PayBookProfile? = nil
    ) {
        self.id = id
        self.paymentTypeRaw = paymentType.rawValue
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustom = customProviderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customProviderName = (trimmedCustom?.isEmpty == true) ? nil : trimmedCustom
        self.accountIdentifier = accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = (trimmedLabel?.isEmpty == true) ? nil : trimmedLabel
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profile = profile
    }

    public var paymentType: PayBookPaymentType {
        get { PayBookPaymentType(rawValue: paymentTypeRaw) ?? .bankAccount }
        set { paymentTypeRaw = newValue.rawValue }
    }

    public var displayProvider: String {
        if provider.lowercased() == "other", let custom = customProviderName, !custom.isEmpty {
            return custom
        }
        return provider
    }

    public var identifierLabel: String {
        paymentType.identifierFieldLabel
    }

    public var maskedIdentifier: String {
        let clean = accountIdentifier.filter { $0.isNumber || $0.isLetter }
        if clean.count > 4 {
            let lastFour = String(clean.suffix(4))
            return "••••\(lastFour)"
        }
        return accountIdentifier
    }

    /// Normalized alphanumeric string for duplicate checks
    public var normalizedIdentifier: String {
        accountIdentifier.filter { $0.isNumber || $0.isLetter }.lowercased()
    }

    /// Subtitle display e.g. "Account Number: ••••7890 • Personal"
    public var displaySubtitle: String {
        var parts: [String] = [maskedIdentifier]
        if let lbl = label, !lbl.isEmpty {
            parts.append(lbl)
        }
        return parts.joined(separator: " • ")
    }
}
