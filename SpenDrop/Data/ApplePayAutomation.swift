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

