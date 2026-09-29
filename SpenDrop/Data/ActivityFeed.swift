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

/// One row of the timeline. Built on the fly from Expense and MoneyMovement; never stored.
public enum ActivityItem: Identifiable {
    case expense(Expense)
    case movement(MoneyMovement)

    public var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .movement(let m): return m.id
        }
    }

    public var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .movement(let m): return m.date
        }
    }
}

