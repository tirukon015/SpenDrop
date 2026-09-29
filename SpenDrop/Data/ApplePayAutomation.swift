import Foundation
import SwiftData

/// Records an Apple Pay purchase handed over by the Shortcuts Wallet "Transaction" automation.
/// Supported Apple path only (App Intent). It does NOT see bank-app, QR or other card-issuer notifications.
public enum ApplePayAutomation {
    public enum Outcome: Equatable {
        case saved(UUID)
        case duplicate
        case invalid(String)

        public var message: String {
            switch self {
            case .saved: return "Saved to SpenDrop."
            case .duplicate: return "This purchase is already in SpenDrop, so it was not added again."
            case .invalid(let reason): return reason
            }
        }
    }

    /// Automations can fire twice for one tap; the same amount at the same merchant within this window is skipped.
    public static let repeatWindow: TimeInterval = 10 * 60

    /// "Maybank Visa Debit" → .maybank. Unknown cards stay Unknown (never guessed).
    public static func bank(fromCardName card: String?) -> PaymentSource? {
        guard let lower = card?.lowercased(), !lower.isEmpty else { return nil }
        let banks: [PaymentSource] = [.maybank, .cimb, .rhb, .publicBank, .bankIslam, .wise, .touchNGo, .grabPay, .boost]
        return banks.first { lower.contains($0.rawValue.lowercased()) || lower.contains($0.shortName.lowercased()) }
    }

    @MainActor
    @discardableResult
    public static func record(amount: Double, merchant: String?, card: String?, date: Date = Date(), in context: ModelContext) -> Outcome {
        guard amount.isFinite, amount > 0 else { return .invalid("The amount must be above zero.") }
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalMerchant = name.isEmpty ? "Apple Pay purchase" : name

        let amountMinor = Money.minorUnits(from: amount)
        let existing = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        if existing.contains(where: {
            $0.amountMinor == amountMinor && $0.merchant.caseInsensitiveCompare(finalMerchant) == .orderedSame &&
            abs($0.date.timeIntervalSince(date)) < repeatWindow
        }) {
            return .duplicate
        }

        let bank = bank(fromCardName: card)
        let category = TransactionClassifier.suggestCategory(merchant: finalMerchant, deterministic: nil, in: context).category
        let expense = Expense(
            amount: Money.majorAmount(fromMinor: amountMinor),
            merchant: finalMerchant,
            category: category,
            paymentSource: .applePay,
            underlyingBank: bank,
            date: date,
            notes: "Recorded by Apple Pay automation",
            sourceType: .appleWallet,
            paymentChannel: .applePay,
            fundingAccount: bank?.rawValue
        )
        context.insert(expense)
        AccountLinker.relink(expense, in: context)
        try? context.save()
        return .saved(expense.id)
    }
}
