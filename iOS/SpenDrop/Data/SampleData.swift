import Foundation
import SwiftData

/// Optional demo data ("Load Sample Data" in Settings). A fresh install is always empty; nothing here runs unless
/// the user confirms. Every record created is listed in `SampleDataRecord` (and sample expenses also carry
/// `isSampleData`), so removal deletes exactly those records and never anything identified by name, amount or date.
/// All people, accounts and amounts are fictional.
public struct SampleData {
    /// People and accounts are named so they can never be mistaken for (or merged with) real ones.
    static let peopleNames = ["Aiman (Sample)", "Mei Ling (Sample)", "Ravi (Sample)"]
    static let bankName = "Demo Bank (Sample)"
    static let walletName = "Demo Wallet (Sample)"

    public struct RemovalReport: Equatable {
        public var expensesRemoved = 0
        public var peopleRemoved = 0
        /// Sample people kept because real records now use them (they become normal people).
        public var peopleKept = 0
        public var movementsRemoved = 0
        public var settlementsRemoved = 0
        public var accountsRemoved = 0
        public var paymentMethodsRemoved = 0
        public var total: Int { expensesRemoved + peopleRemoved + movementsRemoved + settlementsRemoved + accountsRemoved + paymentMethodsRemoved }
    }

    // MARK: State

    /// True while any sample record exists (registered records or flagged expenses).
    public static func isLoaded(in context: ModelContext) -> Bool {
        var registered = FetchDescriptor<SampleDataRecord>()
        registered.fetchLimit = 1
        if ((try? context.fetchCount(registered)) ?? 0) > 0 { return true }
        return count(in: context) > 0
    }

    /// Number of sample expenses currently stored.
    public static func count(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate<Expense> { $0.isSampleData == true })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: Load

    /// Kept for existing callers: loads the sample data set once.
    public static func seed(into context: ModelContext) {
        _ = load(into: context)
    }

    /// Adds the demo data set. Returns false (and adds nothing) when sample data is already loaded.
    /// Nothing existing is read for changing: sample records only point at other sample records.
    @discardableResult
    public static func load(into context: ModelContext, now: Date = Date()) -> Bool {
        guard !isLoaded(in: context) else { return false }
        func register(_ id: UUID, _ entity: SampleDataRecord.Entity) { context.insert(SampleDataRecord(recordID: id, entity: entity)) }
        func day(_ daysAgo: Int, _ hour: Int = 12) -> Date {
            let start = Calendar.current.startOfDay(for: now)
            return Calendar.current.date(byAdding: .hour, value: hour - daysAgo * 24, to: start) ?? now
        }

        // People and a payment method
        let people = peopleNames.map { PayBookProfile(name: $0, notes: "Example person added by Load Sample Data") }
        for person in people { context.insert(person); register(person.id, .person) }
        let (aiman, meiLing, ravi) = (people[0], people[1], people[2])
        aiman.isFrequent = true
        let method = PayBookPaymentMethod(paymentType: .eWallet, provider: "Touch 'n Go", accountIdentifier: "0123456789", label: "Sample")
        context.insert(method)
        method.profile = aiman
        register(method.id, .paymentMethod)

        // Funding accounts used only by the samples (so real expenses are never linked to them)
        let bank = Account(name: bankName, type: .bank, sortIndex: 900)
        let wallet = Account(name: walletName, type: .eWallet, sortIndex: 901)
        for account in [bank, wallet] { context.insert(account); register(account.id, .account) }

        func expense(_ merchant: String, _ minor: Int, _ category: ExpenseCategory, _ date: Date, account: Account,
                     channel: PaymentChannel, notes: String) -> Expense {
            let e = Expense(amount: Money.majorAmount(fromMinor: minor), merchant: merchant, category: category, date: date,
                            notes: notes + " [Sample]", sourceType: .manual, isSampleData: true, paymentChannel: channel,
                            fundingAccount: account.name)
            context.insert(e)
            e.account = account
            register(e.id, .expense)
            return e
        }
        func share(_ e: Expense, _ person: PayBookProfile?, _ minor: Int, _ index: Int, parts: Int? = nil, entered: Int? = nil) {
            let s = ExpenseShare(person: person, isMe: person == nil, nameSnapshot: person?.name ?? "Me", amountMinor: minor,
                                 parts: parts, enteredMinor: entered, sortIndex: index)
            context.insert(s)
            s.expense = e
        }

        // 1. Normal expense (not shared)
        _ = expense("Grocer (Sample)", 4590, .groceries, day(1, 18), account: bank, channel: .qrPayment, notes: "Normal expense")

        // 2. Equal split, I paid: RM120 / 3 → Aiman and Mei Ling owe RM40 each
        let dinner = expense("Team Dinner (Sample)", 12000, .food, day(6, 20), account: bank, channel: .card, notes: "Equal split")
        share(dinner, nil, 4000, 0); share(dinner, aiman, 4000, 1); share(dinner, meiLing, 4000, 2)
        dinner.splitMethod = .equal

        // 3. Parts split, I paid: RM300, Me 1 part, Ravi 2 parts → Ravi owes RM200
        let villa = expense("Holiday Villa (Sample)", 30000, .entertainment, day(20, 15), account: bank, channel: .bankTransfer, notes: "Parts split")
        share(villa, nil, 10000, 0, parts: 1); share(villa, ravi, 20000, 1, parts: 2)
        villa.splitMethod = .parts

        // 4. Amount split with Auto Calculate: RM7.00, Me RM0.01 → Aiman RM6.99 (calculated)
        let coffee = expense("Coffee Run (Sample)", 700, .food, day(3, 9), account: wallet, channel: .qrPayment, notes: "Amounts, Auto Calculate")
        share(coffee, nil, 1, 0, entered: 1); share(coffee, aiman, 699, 1, entered: 699)
        coffee.splitMethod = .amounts

        // 5. Paid for someone: I paid RM150 for Ravi (my share is an automatic 0)
        let ticket = expense("Concert Ticket for Ravi (Sample)", 15000, .entertainment, day(10, 19), account: bank, channel: .applePay, notes: "Paid for someone")
        share(ticket, nil, 0, 0); share(ticket, ravi, 15000, 1)
        ticket.splitMethod = .equal

        // 6. Someone paid for me: Mei Ling paid RM25 for my taxi → I owe her RM25
        let taxi = expense("Taxi paid by Mei Ling (Sample)", 2500, .transport, day(4, 23), account: wallet, channel: .unknown, notes: "Someone paid for me")
        share(taxi, nil, 2500, 0)
        taxi.splitMethod = .equal
        taxi.setPayer(meiLing)

        // 7. Two identical transactions (both legitimate): parking RM10 for Aiman, twice
        for hour in [9, 17] {
            let parking = expense("Parking (Sample)", 1000, .transport, day(2, hour), account: wallet, channel: .qrPayment, notes: "Same amount, separate payment")
            share(parking, nil, 0, 0); share(parking, aiman, 1000, 1)
            parking.splitMethod = .equal
        }

        // 8. Direct transfer: I gave Aiman RM60 (a loan, not an expense)
        let loan = MoneyMovement(kind: .loanGiven, amountMinor: 6000, date: day(15, 11), person: aiman, account: bank,
                                 note: "Lent for books (Sample)", sourceType: .manual)
        context.insert(loan)
        register(loan.id, .movement)

        // Settlements: one payment can go to one or several transactions; any extra stays as credit.
        func payment(_ person: PayBookProfile, _ minor: Int, _ date: Date, note: String, _ allocations: [(Expense?, MoneyMovement?, Int)]) {
            let p = MoneyMovement(kind: .repaymentReceived, amountMinor: minor, date: date, person: person, account: bank,
                                  note: note + " (Sample)", sourceType: .manual)
            context.insert(p)
            register(p.id, .movement)
            let group = UUID()
            for (e, l, amount) in allocations {
                let a = SettlementAllocation(groupID: group, kind: .payment, paymentID: p.id, expenseID: e?.id, loanID: l?.id,
                                             personID: person.id, direction: 1, amountMinor: amount, currency: "RM", date: date)
                context.insert(a)
                register(a.id, .allocation)
            }
        }
        // 9. Partial settlement: Ravi paid RM100 towards the villa (RM200) → RM100 left
        payment(ravi, 10000, day(12, 10), note: "Part of the villa", [(villa, nil, 10000)])
        // 10. Full settlement: Aiman paid the coffee (RM6.99) → settled
        payment(aiman, 699, day(2, 12), note: "Coffee", [(coffee, nil, 699)])
        // 11. Payment larger than the debt: Mei Ling paid RM50 for the dinner (RM40) → RM10 credit
        payment(meiLing, 5000, day(5, 21), note: "Dinner, rounded up", [(dinner, nil, 4000)])

        try? context.save()
        return true
    }

    // MARK: Remove

    /// Deletes exactly the registered sample records (and expenses flagged `isSampleData`). Real expenses, people,
    /// repayments, settlements and accounts are never deleted. A sample person (or account) that real records now
    /// use is kept and becomes a normal record, so no real relationship breaks.
    @discardableResult
    public static func remove(from context: ModelContext) -> RemovalReport {
        var report = RemovalReport()
        let records = (try? context.fetch(FetchDescriptor<SampleDataRecord>())) ?? []
        func ids(_ entity: SampleDataRecord.Entity) -> Set<UUID> { Set(records.filter { $0.entity == entity }.map(\.recordID)) }

        // Expenses: registered ones plus any flagged as sample (older demo data); never an unflagged, unregistered one.
        let sampleExpenseIDs = ids(.expense)
        let expenses = ((try? context.fetch(FetchDescriptor<Expense>())) ?? []).filter { $0.isSampleData || sampleExpenseIDs.contains($0.id) }
        let removedExpenseIDs = Set(expenses.map(\.id))
        let flaggedAccounts = expenses.compactMap(\.account)
        let firstFlagged = expenses.map(\.createdAt).min()
        for expense in expenses { context.delete(expense) }
        report.expensesRemoved = expenses.count

        // Money records (sample repayments and loans)
        let movementIDs = ids(.movement)
        let movements = ((try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []).filter { movementIDs.contains($0.id) }
        let removedMovementIDs = Set(movements.map(\.id))
        for movement in movements { context.delete(movement) }
        report.movementsRemoved = movements.count

        // Settlements: registered ones, and any that only pointed at removed sample records (they'd be orphans).
        let allocationIDs = ids(.allocation)
        let allocations = ((try? context.fetch(FetchDescriptor<SettlementAllocation>())) ?? []).filter { a in
            allocationIDs.contains(a.id) ||
            (a.paymentID.map(removedMovementIDs.contains) ?? false) ||
            (a.expenseID.map(removedExpenseIDs.contains) ?? false) ||
            (a.loanID.map(removedMovementIDs.contains) ?? false)
        }
        for allocation in allocations { context.delete(allocation) }
        report.settlementsRemoved = allocations.count
        try? context.save()

        // Payment methods
        let methodIDs = ids(.paymentMethod)
        let methods = ((try? context.fetch(FetchDescriptor<PayBookPaymentMethod>())) ?? []).filter { methodIDs.contains($0.id) }
        for method in methods { context.delete(method) }
        report.paymentMethodsRemoved = methods.count
        try? context.save()

        // People: removed only when nothing real refers to them any more.
        let personIDs = ids(.person)
        for person in ((try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []) where personIDs.contains(person.id) {
            let inUse = !person.shares.isEmpty || !person.paidExpenses.isEmpty || !person.movements.isEmpty || !person.paymentMethods.isEmpty
            if inUse {
                report.peopleKept += 1
            } else {
                context.delete(person)
                report.peopleRemoved += 1
            }
        }

        // Accounts: registered ones without real records; plus (older demo data) accounts that only ever held flagged samples.
        let accountIDs = ids(.account)
        var accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).filter { accountIDs.contains($0.id) }
        if let firstFlagged {
            accounts += flaggedAccounts.filter { !accountIDs.contains($0.id) && $0.createdAt >= firstFlagged }
        }
        var seenAccounts = Set<PersistentIdentifier>()
        for account in accounts where seenAccounts.insert(account.persistentModelID).inserted {
            let inUse = !account.expenses.isEmpty || !account.movements.isEmpty || !account.incomingTransfers.isEmpty
            if !inUse {
                context.delete(account)
                report.accountsRemoved += 1
            }
        }

        // The register: every entry goes (kept records are now normal records).
        for record in records { context.delete(record) }
        try? context.save()
        return report
    }
}
