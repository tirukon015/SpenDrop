import Foundation
import SwiftData

public enum MoneyDirection: String, Codable {
    case moneyIn = "in"
    case moneyOut = "out"
    /// Between the user's own accounts. Never counted as spending, money in or money out.
    case `internal` = "internal"
}

public enum MoneyMovementKind: String, CaseIterable, Codable, Identifiable {
    // Money In
    case income = "income"
    case loanReceived = "loanReceived"
    case repaymentReceived = "repaymentReceived"
    case refund = "refund"
    case otherIn = "otherIn"
    // Money Out
    case loanGiven = "loanGiven"
    case repaymentMade = "repaymentMade"
    case otherOut = "otherOut"
    // Internal
    case ownTransfer = "ownTransfer"

    public var id: String { rawValue }

    public var direction: MoneyDirection {
        switch self {
        case .income, .loanReceived, .repaymentReceived, .refund, .otherIn: return .moneyIn
        case .loanGiven, .repaymentMade, .otherOut: return .moneyOut
        case .ownTransfer: return .internal
        }
    }

    /// Effect on "what this person owes me" per unit of amount: +1 they owe me more, -1 they owe me less.
    /// Kinds that do not involve a debt between me and a person return 0.
    public var personBalanceSign: Int {
        switch self {
        case .loanGiven, .repaymentMade: return 1
        case .loanReceived, .repaymentReceived: return -1
        case .income, .refund, .otherIn, .otherOut, .ownTransfer: return 0
        }
    }

    public var requiresPerson: Bool { personBalanceSign != 0 }
}

public extension MoneyMovementKind {
    var displayName: String {
        switch self {
        case .income: return "Income"
        case .loanReceived: return "Loan received"
        case .repaymentReceived: return "Repayment received"
        case .refund: return "Refund"
        case .otherIn: return "Other money in"
        case .loanGiven: return "Loan given"
        case .repaymentMade: return "Repayment made"
        case .otherOut: return "Other money out"
        case .ownTransfer: return "Own transfer"
        }
    }
}

