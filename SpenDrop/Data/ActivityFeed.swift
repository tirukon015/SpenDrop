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

public enum ActivityFeed {
    public static func matches(_ item: ActivityItem, _ filter: ActivityFilter) -> Bool {
        switch (filter, item) {
        case (.all, _): return true
        case (.expenses, .expense): return true
        case (.shared, .expense(let e)): return e.isShared
        case (.moneyIn, .movement(let m)): return m.kind.direction == .moneyIn
        case (.moneyOut, .movement(let m)): return m.kind.direction == .moneyOut
        case (.transfers, .movement(let m)): return m.kind == .ownTransfer
        default: return false
        }
    }

    /// Combined, de-duplicated (by id), sorted timeline.
    public static func items(expenses: [Expense], movements: [MoneyMovement], filter: ActivityFilter, newestFirst: Bool = true) -> [ActivityItem] {
        var seen = Set<UUID>()
        let all = expenses.map(ActivityItem.expense) + movements.map(ActivityItem.movement)
        return all
            .filter { matches($0, filter) && seen.insert($0.id).inserted }
            .sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }
}
