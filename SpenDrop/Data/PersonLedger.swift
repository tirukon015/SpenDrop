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

    public static func summary(of people: [PayBookProfile]) -> Summary {
        var summary = Summary()
        for person in people {
            let balances = balances(for: person)
            if balances.isEmpty {
                if hasHistory(person) { summary.settledCount += 1 }
                continue
            }
            if balances.values.contains(where: { $0 > 0 }) { summary.owingMeCount += 1 }
            if balances.values.contains(where: { $0 < 0 }) { summary.iOweCount += 1 }
            for (currency, value) in balances {
                if value > 0 { summary.owedToMe[currency, default: 0] += value }
                if value < 0 { summary.iOwe[currency, default: 0] += -value }
            }
        }
        return summary
    }

    // MARK: History

    public static func entries(for person: PayBookProfile) -> [Entry] {
        var entries: [Entry] = []
        for expense in relatedExpenses(person) {
            let theirShare = expense.shares.first { $0.person?.id == person.id }
            let effect: Int
            let detail: String
            if expense.paidByMe {
                effect = theirShare?.amountMinor ?? 0
                detail = "You paid · their share \(format(effect, expense.currency))"
            } else if expense.payer?.id == person.id {
                effect = -expense.myShareMinor
                detail = "\(person.name) paid · your share \(format(expense.myShareMinor, expense.currency))"
            } else {
                effect = 0
                detail = "Paid by \(expense.payer?.name ?? expense.payerNameSnapshot ?? "someone else") · not between you"
            }
            entries.append(Entry(id: expense.id, date: expense.date, title: expense.merchant, detail: detail,
                                 effectMinor: effect, currency: expense.currency, source: .expense(expense)))
        }
        for movement in person.movements {
            entries.append(Entry(id: movement.id, date: movement.date, title: movement.kind.displayName,
                                 detail: movement.note ?? (movement.account?.name ?? ""),
                                 effectMinor: movement.kind.personBalanceSign * movement.amountMinor,
                                 currency: movement.currency, source: .movement(movement)))
        }
        return entries.sorted { $0.date > $1.date }
    }

    // MARK: Record payment

    /// Prefilled repayment for settling a balance: Repayment Received when they owe me, Repayment Made when I owe them.
    public static func repaymentDraft(for person: PayBookProfile, currency: String) -> MoneyMovementDraft? {
        guard let balance = balances(for: person)[currency], balance != 0 else { return nil }
        var draft = MoneyMovementDraft(entryType: balance > 0 ? .moneyIn : .moneyOut)
        draft.kind = balance > 0 ? .repaymentReceived : .repaymentMade
        draft.person = person
        draft.currency = currency
        draft.amountText = String(format: "%.2f", Money.majorAmount(fromMinor: abs(balance)))
        return draft
    }

    /// Human sentence with explicit direction, e.g. "Shadin owes you RM 100.00" / "You owe Bijoy RM 7.50".
    public static func directionText(name: String, balanceMinor: Int, currency: String) -> String {
        if balanceMinor > 0 { return "\(name) owes you \(format(balanceMinor, currency))" }
        if balanceMinor < 0 { return "You owe \(name) \(format(-balanceMinor, currency))" }
        return "Settled with \(name)"
    }

    static func format(_ minor: Int, _ currency: String) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
    }
}

/// How PayBook groups people: Frequent, Other People, Archived.
public enum PayBookGrouping {
    public static func groups(_ people: [PayBookProfile]) -> (frequent: [PayBookProfile], other: [PayBookProfile], archived: [PayBookProfile]) {
        (people.filter { $0.isFrequent && !$0.isArchived },
         people.filter { !$0.isFrequent && !$0.isArchived },
         people.filter(\.isArchived))
    }
}
