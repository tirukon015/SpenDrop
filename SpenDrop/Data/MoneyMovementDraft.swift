import Foundation
import SwiftData

/// The record types offered by the Add sheet. Expense stays the default.
public enum TransactionEntryType: String, CaseIterable, Identifiable {
    case expense
    case moneyIn
    case moneyOut
    case transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: return "Expense"
        case .moneyIn: return "Money In"
        case .moneyOut: return "Money Out"
        case .transfer: return "Transfer"
        }
    }

    public var icon: String {
        switch self {
        case .expense: return "cart"
        case .moneyIn: return "arrow.down.circle"
        case .moneyOut: return "arrow.up.right.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }

    /// Kinds offered for this entry type, most common first.
    public var kinds: [MoneyMovementKind] {
        switch self {
        case .expense: return []
        case .moneyIn: return [.income, .repaymentReceived, .loanReceived, .refund, .otherIn]
        case .moneyOut: return [.loanGiven, .repaymentMade, .otherOut]
        case .transfer: return [.ownTransfer]
        }
    }

    public init(kind: MoneyMovementKind) {
        switch kind.direction {
        case .moneyIn: self = .moneyIn
        case .moneyOut: self = .moneyOut
        case .internal: self = .transfer
        }
    }
}

/// Editable, validated form state for a Money In / Money Out / Transfer record.
/// Keeps validation out of the view so it can be tested.
public struct MoneyMovementDraft {
