import Foundation

/// Type filter for the unified Transactions timeline.
public enum ActivityFilter: String, CaseIterable, Identifiable {
    case all, expenses, moneyIn, moneyOut, shared, transfers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .expenses: return "Expenses"
        case .moneyIn: return "Money In"
        case .moneyOut: return "Money Out"
        case .shared: return "Shared"
        case .transfers: return "Transfers"
        }
    }
}

