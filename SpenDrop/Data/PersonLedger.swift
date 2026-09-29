import Foundation

/// Per-person balances and history, always calculated from ExpenseShare, Expense.payer and MoneyMovement.
/// Positive = they owe me; negative = I owe them. Nothing is stored.
public enum PersonLedger {
    public struct Entry: Identifiable {
        public enum Source {
            case expense(Expense)
            case movement(MoneyMovement)
        }

        public let id: UUID
        public let date: Date
        public let title: String
        public let detail: String
        /// Change to "what they owe me" in minor units (0 = recorded but does not affect our balance).
        public let effectMinor: Int
        public let currency: String
        public let source: Source
    }

    public struct Summary: Equatable {
        /// Currency → total others owe me (positive).
        public var owedToMe: [String: Int] = [:]
        /// Currency → total I owe others (positive).
        public var iOwe: [String: Int] = [:]
        /// People with history whose balances are all zero.
        public var settledCount = 0
        public var owingMeCount = 0
        public var iOweCount = 0

        public var isEmpty: Bool { owedToMe.isEmpty && iOwe.isEmpty && settledCount == 0 }
    }

    // MARK: Balances

    private static func relatedExpenses(_ person: PayBookProfile) -> [Expense] {
        var seen = Set<UUID>()
        var expenses: [Expense] = []
        for expense in person.shares.compactMap(\.expense) + person.paidExpenses where seen.insert(expense.id).inserted {
            expenses.append(expense)
        }
        return expenses
    }

    /// Currency → balance with this person. Zero balances are omitted.
    public static func balances(for person: PayBookProfile) -> [String: Int] {
        let expenses = relatedExpenses(person)
        let movements = person.movements
        let currencies = Set(expenses.map(\.currency) + movements.map(\.currency))
        var result: [String: Int] = [:]
        for currency in currencies {
            let value = FinancialCalculator.personBalances(expenses: expenses, movements: movements, currency: currency)[person.id] ?? 0
            if value != 0 { result[currency] = value }
        }
        return result
    }

    public static func hasHistory(_ person: PayBookProfile) -> Bool {
        !person.shares.isEmpty || !person.paidExpenses.isEmpty || !person.movements.isEmpty
    }

    /// Deleting is only allowed when nothing is owed either way. History survives through snapshots.
    public static func canDelete(_ person: PayBookProfile) -> Bool {
        balances(for: person).isEmpty
    }

