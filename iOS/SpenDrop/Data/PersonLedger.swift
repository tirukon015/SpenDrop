import Foundation
import SwiftData

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

/// PayBook's "They Owe Me / I Owe Them" filter. Who belongs where is decided only by the net balance from
/// `PersonLedger.balances(for:)` (i.e. `FinancialCalculator.personBalances`), never by stored labels.
public enum PayBookBalanceFilter: String, CaseIterable, Identifiable {
    case all, theyOweMe, iOweThem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .theyOweMe: return "They Owe Me"
        case .iOweThem: return "I Owe Them"
        }
    }
}

public extension PersonLedger {
    /// One person in an outstanding list: the amount is always positive; `direction` says who owes whom.
    struct OutstandingPerson: Identifiable {
        public let person: PayBookProfile
        public let amountMinor: Int
        public let currency: String
        public let lastActivity: Date
        public var id: UUID { person.id }
    }

    /// People with a positive (They Owe Me) or negative (I Owe Them) net balance, largest amount first; ties are
    /// broken by the most recent activity, then by name. Settled people (exactly 0) are in neither list.
    /// When someone has balances in more than one currency, their largest balance in that direction is used.
    static func outstanding(_ people: [PayBookProfile], filter: PayBookBalanceFilter) -> [OutstandingPerson] {
        guard filter != .all else { return [] }
        let sign = filter == .theyOweMe ? 1 : -1
        return people.compactMap { person -> OutstandingPerson? in
            let matching = balances(for: person).filter { $0.value * sign > 0 }
            guard let largest = matching.max(by: { abs($0.value) < abs($1.value) }) else { return nil }
            let last = entries(for: person).map(\.date).max() ?? person.updatedAt
            return OutstandingPerson(person: person, amountMinor: abs(largest.value), currency: largest.key, lastActivity: last)
        }
        .sorted { a, b in
            if a.amountMinor != b.amountMinor { return a.amountMinor > b.amountMinor }
            if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
            return a.person.name.localizedCaseInsensitiveCompare(b.person.name) == .orderedAscending
        }
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

// MARK: - Debts (per transaction) and settlements

/// One debt between me and one person, coming from one transaction. Nothing is stored: the original amount comes
/// from the expense/loan, what has been paid comes from `SettlementAllocation`s. The original transaction and its
/// shares are never changed by a settlement.
public struct Debt: Identifiable, Equatable {
    public enum Source: Equatable {
        case expense(UUID)
        case loan(UUID)
    }

    public let id: String
    public let source: Source
    public let personID: UUID
    public let personName: String
    public let date: Date
    public let title: String
    public let currency: String
    /// +1: the person owes me. -1: I owe the person.
    public let direction: Int
    /// The share/loan amount this debt came from, in minor units.
    public let originalMinor: Int
    /// Paid towards this debt so far (all settlements), in minor units.
    public let settledMinor: Int
    /// e.g. "You paid · their share RM 6.99"
    public let detail: String
    public let expense: Expense?
    public let loan: MoneyMovement?

    public var outstandingMinor: Int { max(0, originalMinor - settledMinor) }
    public var isSettled: Bool { outstandingMinor == 0 }
    public var isPartiallyPaid: Bool { settledMinor > 0 && !isSettled }
    /// Positive when they owe me, negative when I owe them.
    public var signedOutstandingMinor: Int { direction * outstandingMinor }

    public var expenseID: UUID? { if case .expense(let id) = source { return id }; return nil }
    public var loanID: UUID? { if case .loan(let id) = source { return id }; return nil }

    /// "Bijoy owes you RM 6.99" / "You owe Bijoy RM 20.00" / "Settled"
    public var statusText: String {
        isSettled ? "Settled" : PersonLedger.directionText(name: personName, balanceMinor: signedOutstandingMinor, currency: currency)
    }

    public static func == (lhs: Debt, rhs: Debt) -> Bool {
        lhs.id == rhs.id && lhs.originalMinor == rhs.originalMinor && lhs.settledMinor == rhs.settledMinor &&
        lhs.direction == rhs.direction && lhs.currency == rhs.currency
    }
}

/// The single place that turns expenses, loans and settlements into per-transaction debts.
/// The net balance with a person stays `FinancialCalculator.personBalances` (unchanged); debts explain it.
public enum DebtLedger {
    /// Every allocation in the store (one fetch).
    public static func allocations(in context: ModelContext?) -> [SettlementAllocation] {
        guard let context else { return [] }
        return (try? context.fetch(FetchDescriptor<SettlementAllocation>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    /// Allocations that still count: offsets always; payments/assignments only while their payment exists.
    static func active(_ allocations: [SettlementAllocation], paymentIDs: Set<UUID>) -> [SettlementAllocation] {
        allocations.filter { $0.kind == .offset || ($0.paymentID.map(paymentIDs.contains) ?? false) }
    }

    private static func paymentIDs(in context: ModelContext?) -> Set<UUID> {
        guard let context else { return [] }
        let movements = (try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []
        return Set(movements.filter { $0.kind == .repaymentReceived || $0.kind == .repaymentMade }.map(\.id))
    }

    /// The debt between me and `person` created by `expense`, if any.
    static func expenseDebt(_ expense: Expense, person: PayBookProfile, allocations: [SettlementAllocation]) -> Debt? {
        let direction: Int
        let original: Int
        let detail: String
        if expense.paidByMe {
            guard let share = expense.shares.first(where: { !$0.isMe && $0.person?.id == person.id }) else { return nil }
            direction = 1
            original = share.amountMinor
            detail = "You paid · their share \(PersonLedger.format(original, expense.currency))"
        } else if expense.payer?.id == person.id {
            direction = -1
            original = expense.myShareMinor
            detail = "\(person.name) paid · your share \(PersonLedger.format(original, expense.currency))"
        } else {
            return nil
        }
        guard original > 0 else { return nil }
        let settled = allocations.filter { $0.expenseID == expense.id && $0.personID == person.id && $0.direction == direction }
            .reduce(0) { $0 + $1.amountMinor }
        return Debt(id: "expense:\(expense.id.uuidString):\(person.id.uuidString)", source: .expense(expense.id), personID: person.id,
                    personName: person.name, date: expense.date, title: expense.merchant, currency: expense.currency,
                    direction: direction, originalMinor: original, settledMinor: settled, detail: detail, expense: expense, loan: nil)
    }

    /// A loan given (they owe me) or received (I owe them) is a debt too.
    static func loanDebt(_ loan: MoneyMovement, person: PayBookProfile, allocations: [SettlementAllocation]) -> Debt? {
        let direction: Int
        switch loan.kind {
        case .loanGiven: direction = 1
        case .loanReceived: direction = -1
        default: return nil
        }
        guard loan.amountMinor > 0 else { return nil }
        let settled = allocations.filter { $0.loanID == loan.id && $0.direction == direction }.reduce(0) { $0 + $1.amountMinor }
        let title = loan.note?.isEmpty == false ? loan.note! : (direction > 0 ? "Money you gave" : "Money you received")
        return Debt(id: "loan:\(loan.id.uuidString)", source: .loan(loan.id), personID: person.id, personName: person.name,
                    date: loan.date, title: title, currency: loan.currency, direction: direction, originalMinor: loan.amountMinor,
                    settledMinor: settled, detail: direction > 0 ? "You gave money" : "\(person.name) gave you money",
                    expense: nil, loan: loan)
    }

    /// Every debt with this person (settled and outstanding), oldest first.
    public static func debts(for person: PayBookProfile) -> [Debt] {
        let context = person.modelContext
        let active = active(allocations(in: context).filter { $0.personID == person.id }, paymentIDs: paymentIDs(in: context))
        var seen = Set<UUID>()
        var result: [Debt] = []
        for expense in person.shares.compactMap(\.expense) + person.paidExpenses where seen.insert(expense.id).inserted {
            if let debt = expenseDebt(expense, person: person, allocations: active) { result.append(debt) }
        }
        for loan in person.movements {
            if let debt = loanDebt(loan, person: person, allocations: active) { result.append(debt) }
        }
        return result.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// The debts an expense created (one per person involved with me).
    public static func debts(for expense: Expense) -> [Debt] {
        let context = expense.modelContext
        let active = active(allocations(in: context).filter { $0.expenseID == expense.id }, paymentIDs: paymentIDs(in: context))
        let people: [PayBookProfile] = expense.paidByMe ? expense.shares.compactMap { $0.isMe ? nil : $0.person } : [expense.payer].compactMap { $0 }
        return people.compactMap { expenseDebt(expense, person: $0, allocations: active) }
    }

    /// Payments (or parts of payments) not linked to any transaction, signed like balances (positive = credit
    /// that reduces what they owe me… expressed so that `net == Σ signedOutstanding + unassigned`).
    public static func unassignedMinor(for person: PayBookProfile, currency: String) -> Int {
        let net = PersonLedger.balances(for: person)[currency] ?? 0
        let outstanding = debts(for: person).filter { $0.currency == currency }.reduce(0) { $0 + $1.signedOutstandingMinor }
        return net - outstanding
    }

    /// One repayment and how much of it is applied to transactions. `unallocatedMinor` is credit.
    public struct PaymentUse: Identifiable {
        public let payment: MoneyMovement
        public let allocatedMinor: Int
        public var id: UUID { payment.id }
        /// +1 they paid me, -1 I paid them.
        public var direction: Int { payment.kind == .repaymentReceived ? 1 : -1 }
        public var unallocatedMinor: Int { max(0, payment.amountMinor - allocatedMinor) }
    }

    /// Every repayment with this person and how much of it is applied (payment = applied + credit).
    public static func paymentUses(for person: PayBookProfile) -> [PaymentUse] {
        let payments = person.movements.filter { $0.kind == .repaymentReceived || $0.kind == .repaymentMade }
        let active = active(allocations(in: person.modelContext).filter { $0.personID == person.id }, paymentIDs: Set(payments.map(\.id)))
        return payments.sorted { $0.date < $1.date }.map { payment in
            PaymentUse(payment: payment, allocatedMinor: active.filter { $0.paymentID == payment.id }.reduce(0) { $0 + $1.amountMinor })
        }
    }

    /// Credit: repayments (or parts of them) not applied to any transaction, in one direction.
    /// direction +1 = money they paid me that isn't linked yet; -1 = money I paid them that isn't linked yet.
    public static func creditMinor(for person: PayBookProfile, currency: String, direction: Int) -> Int {
        paymentUses(for: person).filter { $0.payment.currency == currency && $0.direction == direction }.reduce(0) { $0 + $1.unallocatedMinor }
    }

    /// Settlement actions (payments, assignments, settle-all) involving a person or an expense, newest first.
    public struct SettlementGroup: Identifiable {
        public let id: UUID
        public let date: Date
        public let allocations: [SettlementAllocation]
        public let payment: MoneyMovement?
        public var totalMinor: Int { allocations.filter { $0.kind != .offset }.reduce(0) { $0 + $1.amountMinor } }
        public var offsetMinor: Int { allocations.filter { $0.kind == .offset && $0.direction > 0 }.reduce(0) { $0 + $1.amountMinor } }
        public var currency: String { allocations.first?.currency ?? payment?.currency ?? "RM" }
        /// +1 money came to me, -1 I paid, 0 offset only.
        public var direction: Int { allocations.first { $0.kind != .offset }?.direction ?? 0 }
    }

    public static func settlementGroups(personID: UUID? = nil, expenseID: UUID? = nil, loanID: UUID? = nil,
                                        in context: ModelContext?) -> [SettlementGroup] {
        guard let context else { return [] }
        let movements = (try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []
        let byID = Dictionary(movements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let all = active(allocations(in: context), paymentIDs: Set(byID.keys))
        let matching = all.filter { a in
            (personID == nil || a.personID == personID) && (expenseID == nil || a.expenseID == expenseID) && (loanID == nil || a.loanID == loanID)
        }
        let groupIDs = Set(matching.map(\.groupID))
        return groupIDs.map { gid in
            let items = all.filter { $0.groupID == gid }
            let shown = items.filter { a in matching.contains { $0.id == a.id } }
            let payment = items.compactMap { $0.kind == .payment ? $0.paymentID : nil }.first.flatMap { byID[$0] }
            return SettlementGroup(id: gid, date: shown.map(\.date).max() ?? Date(), allocations: shown, payment: payment)
        }
        .sorted { $0.date > $1.date }
    }
}

/// Records settlements. Every action is one group that can be undone as a whole. Original expenses, shares and
/// loans are never modified; payments are normal Repayment Received / Repayment Made records.
public enum SettlementService {
    public enum SettlementError: Error, Equatable, LocalizedError {
        case invalidAmount
        case exceedsOutstanding(debtTitle: String)
        case allocationExceedsPayment
        case mixedPeopleOrDirections
        case nothingToSettle
        case notEnoughCredit(availableMinor: Int, currency: String)

        public var errorDescription: String? {
            switch self {
            case .invalidAmount: return "Enter an amount greater than zero."
            case .exceedsOutstanding(let title): return "That's more than what's left on \(title)."
            case .allocationExceedsPayment: return "The amounts applied are more than the payment."
            case .mixedPeopleOrDirections: return "These transactions can't be paid together."
            case .nothingToSettle: return "Nothing is outstanding."
            case .notEnoughCredit(let available, let currency):
                return "Only \(PersonLedger.format(available, currency)) of credit is available. Apply less, or record a new payment."
            }
        }
    }

    /// "Mark as Paid": one payment for exactly what's left on this debt. No amount to type.
    @discardableResult
    public static func markPaid(_ debt: Debt, person: PayBookProfile, date: Date = Date(), account: Account? = nil,
                                in context: ModelContext) throws -> UUID {
        guard debt.outstandingMinor > 0 else { throw SettlementError.nothingToSettle }
        return try recordPayment(person: person, direction: debt.direction, amountMinor: debt.outstandingMinor,
                                 allocations: [(debt, debt.outstandingMinor)], currency: debt.currency, date: date,
                                 account: account, note: "Settled: \(debt.title)", in: context)
    }

    /// One real payment between me and `person`, applied to the chosen debts. Any part not applied stays as a
    /// payment without a transaction (it still counts in the net balance). Validated before anything is written.
    @discardableResult
    public static func recordPayment(person: PayBookProfile, direction: Int, amountMinor: Int, allocations: [(Debt, Int)],
                                     currency: String, date: Date = Date(), account: Account? = nil, note: String? = nil,
                                     in context: ModelContext) throws -> UUID {
        guard amountMinor > 0, direction == 1 || direction == -1 else { throw SettlementError.invalidAmount }
        let applied = allocations.filter { $0.1 > 0 }
        for (debt, amount) in applied {
            guard debt.personID == person.id, debt.direction == direction, debt.currency == currency else { throw SettlementError.mixedPeopleOrDirections }
            guard amount <= debt.outstandingMinor else { throw SettlementError.exceedsOutstanding(debtTitle: debt.title) }
        }
        guard applied.reduce(0, { $0 + $1.1 }) <= amountMinor else { throw SettlementError.allocationExceedsPayment }

        let group = UUID()
        let payment = MoneyMovement(kind: direction > 0 ? .repaymentReceived : .repaymentMade, amountMinor: amountMinor,
                                    currency: currency, date: date, person: person, account: account, note: note,
                                    sourceType: .manual)
        context.insert(payment)
        for (debt, amount) in applied {
            context.insert(SettlementAllocation(groupID: group, kind: .payment, paymentID: payment.id, expenseID: debt.expenseID,
                                                loanID: debt.loanID, personID: person.id, direction: direction,
                                                amountMinor: amount, currency: currency, date: date))
        }
        try context.save()
        return group
    }

    /// Applies existing credit (unlinked parts of earlier repayments, oldest first) to the chosen debts. No new money
    /// moves; undo removes only these allocations and the repayments stay. Validated before anything is written.
    @discardableResult
    public static func applyCredit(person: PayBookProfile, direction: Int, allocations: [(Debt, Int)], currency: String,
                                   date: Date = Date(), in context: ModelContext) throws -> UUID {
        let applied = allocations.filter { $0.1 > 0 }
        guard !applied.isEmpty else { throw SettlementError.invalidAmount }
        for (debt, amount) in applied {
            guard debt.personID == person.id, debt.direction == direction, debt.currency == currency else { throw SettlementError.mixedPeopleOrDirections }
            guard amount <= debt.outstandingMinor else { throw SettlementError.exceedsOutstanding(debtTitle: debt.title) }
        }
        let available = DebtLedger.creditMinor(for: person, currency: currency, direction: direction)
        let wanted = applied.reduce(0) { $0 + $1.1 }
        guard wanted <= available else { throw SettlementError.notEnoughCredit(availableMinor: available, currency: currency) }

        let group = UUID()
        var sources = DebtLedger.paymentUses(for: person)
            .filter { $0.payment.currency == currency && $0.direction == direction && $0.unallocatedMinor > 0 }
            .map { ($0.payment.id, $0.unallocatedMinor) }
        var index = 0
        for (debt, amount) in applied {
            var left = amount
            while left > 0 && index < sources.count {
                let take = min(left, sources[index].1)
                context.insert(SettlementAllocation(groupID: group, kind: .assign, paymentID: sources[index].0, expenseID: debt.expenseID,
                                                    loanID: debt.loanID, personID: person.id, direction: direction,
                                                    amountMinor: take, currency: currency, date: date))
                sources[index].1 -= take
                left -= take
                if sources[index].1 == 0 { index += 1 }
            }
        }
        try context.save()
        return group
    }

    /// Oldest first: fills each debt before moving to the next. Shown to the user before anything is recorded.
    public static func autoAllocate(amountMinor: Int, to debts: [Debt]) -> [(Debt, Int)] {
        var left = amountMinor
        var plan: [(Debt, Int)] = []
        for debt in debts.filter({ $0.outstandingMinor > 0 }).sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }) where left > 0 {
            let amount = min(left, debt.outstandingMinor)
            plan.append((debt, amount))
            left -= amount
        }
        return plan
    }

    /// Settles everything with a person in one currency:
    /// 1. earlier payments not linked to a transaction are applied to the oldest debts in their direction;
    /// 2. debts in opposite directions cancel each other (no money moves);
    /// 3. one payment for what remains, in the net direction.
    /// Everything is one group, so Undo restores the previous state exactly.
    @discardableResult
    public static func settleAll(person: PayBookProfile, currency: String, date: Date = Date(), account: Account? = nil,
                                 in context: ModelContext) throws -> UUID {
        let group = UUID()
        var debts = DebtLedger.debts(for: person).filter { $0.currency == currency && $0.outstandingMinor > 0 }
        guard !debts.isEmpty else { throw SettlementError.nothingToSettle }
        var outstanding = Dictionary(debts.map { ($0.id, $0.outstandingMinor) }, uniquingKeysWith: { a, _ in a })
        func add(_ debt: Debt, _ amount: Int, kind: SettlementAllocation.Kind, paymentID: UUID?) {
            guard amount > 0 else { return }
            context.insert(SettlementAllocation(groupID: group, kind: kind, paymentID: paymentID, expenseID: debt.expenseID,
                                                loanID: debt.loanID, personID: person.id, direction: debt.direction,
                                                amountMinor: amount, currency: currency, date: date))
            outstanding[debt.id, default: 0] -= amount
        }
        debts.sort { ($0.date, $0.id) < ($1.date, $1.id) }

        // 1. Earlier unlinked payments.
        let existing = DebtLedger.active(DebtLedger.allocations(in: context), paymentIDs: Set(person.movements.map(\.id)))
        for payment in person.movements.sorted(by: { $0.date < $1.date }) where payment.currency == currency {
            let direction: Int
            switch payment.kind {
            case .repaymentReceived: direction = 1
            case .repaymentMade: direction = -1
            default: continue
            }
            var free = payment.amountMinor - existing.filter { $0.paymentID == payment.id }.reduce(0) { $0 + $1.amountMinor }
            for debt in debts where debt.direction == direction && free > 0 {
                let amount = min(free, outstanding[debt.id] ?? 0)
                add(debt, amount, kind: .assign, paymentID: payment.id)
                free -= amount
            }
        }

        // 2. Offsets.
        func total(_ direction: Int) -> Int { debts.filter { $0.direction == direction }.reduce(0) { $0 + (outstanding[$1.id] ?? 0) } }
        var offset = min(total(1), total(-1))
        if offset > 0 {
            for direction in [1, -1] {
                var left = offset
                for debt in debts where debt.direction == direction && left > 0 {
                    let amount = min(left, outstanding[debt.id] ?? 0)
                    add(debt, amount, kind: .offset, paymentID: nil)
                    left -= amount
                }
            }
            offset = 0
        }

        // 3. One payment for the rest.
        for direction in [1, -1] {
            let rest = total(direction)
            guard rest > 0 else { continue }
            let payment = MoneyMovement(kind: direction > 0 ? .repaymentReceived : .repaymentMade, amountMinor: rest,
                                        currency: currency, date: date, person: person, account: account,
                                        note: "Settled all with \(person.name)", sourceType: .manual)
            context.insert(payment)
            for debt in debts where debt.direction == direction {
                add(debt, outstanding[debt.id] ?? 0, kind: .payment, paymentID: payment.id)
            }
        }
        try context.save()
        return group
    }

    /// Reverses one settlement action: its allocations are removed and a payment it created is deleted.
    /// Earlier payments that were only assigned stay recorded. The original transactions are untouched.
    public static func undo(groupID: UUID, in context: ModelContext) throws {
        let items = DebtLedger.allocations(in: context).filter { $0.groupID == groupID }
        let createdPayments = Set(items.filter { $0.kind == .payment }.compactMap(\.paymentID))
        let movements = (try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []
        for movement in movements where createdPayments.contains(movement.id) {
            context.delete(movement)
        }
        for item in items { context.delete(item) }
        try context.save()
    }
}
