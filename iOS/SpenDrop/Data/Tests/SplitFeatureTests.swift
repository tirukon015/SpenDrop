import Foundation
import SwiftData

/// Phase 4: shared expenses (SplitDraft on top of SplitCalculator + ExpenseShare). `--run-split-tests`
@MainActor
public struct SplitFeatureTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 4") { results.append($0) }

        func people(_ ctx: ModelContext, _ names: String...) -> [PayBookProfile] {
            names.map { name in
                let p = PayBookProfile(name: name)
                ctx.insert(p)
                return p
            }
        }

        // Equal: RM100 / 4
        do {
            let ctx = TestKit.context()
            var draft = SplitDraft()
            people(ctx, "A", "B", "C").forEach { draft.add($0) }
            t.check("Equal split RM100 / 4", draft.shares(totalMinor: 10000) == [2500, 2500, 2500, 2500],
                    expected: "2500 x4", actual: "\(draft.shares(totalMinor: 10000) ?? [])")
        }
        // Parts: Me 2, A 1, B 1 of RM100
        do {
            let ctx = TestKit.context()
            var draft = SplitDraft()
            draft.method = .parts
            people(ctx, "A", "B").forEach { draft.add($0) }
            draft.setParts(2, for: draft.participants[0].id)
            t.check("Parts split Me 2 / A 1 / B 1", draft.shares(totalMinor: 10000) == [5000, 2500, 2500],
                    expected: "[5000, 2500, 2500]", actual: "\(draft.shares(totalMinor: 10000) ?? [])")
        }
        // Exact amounts and mismatch
        do {
            let ctx = TestKit.context()
            var draft = SplitDraft()
            draft.method = .amounts
            people(ctx, "A", "B").forEach { draft.add($0) }
            let ids = draft.participants.map(\.id)
            draft.setAmountText("20", for: ids[0]); draft.setAmountText("30", for: ids[1]); draft.setAmountText("50", for: ids[2])
            let exact = draft.shares(totalMinor: 10000)
            draft.setAmountText("40", for: ids[2])
            let problem = draft.problem(totalMinor: 10000)
            let expense = Expense(amount: 100, merchant: "Shop")
            ctx.insert(expense)
            let applied = draft.apply(to: expense, in: ctx)
            t.check("Exact amounts: valid total; mismatch shown and never saved",
                    exact == [2000, 3000, 5000] && problem == "RM 10.00 remains unassigned. Select at least one participant for the remaining amount (clear someone's amount)." && !applied && expense.shares.isEmpty,
                    expected: "[2000,3000,5000]; 'RM 10.00 remains unassigned…'; not applied",
                    actual: "exact=\(exact ?? []) problem=\(problem ?? "nil") applied=\(applied) shares=\(expense.shares.count)")
            draft.setAmountText("60", for: ids[2])
            t.check("Exact amounts over the total are reported", draft.problem(totalMinor: 10000) == "Shares exceed the total by RM 10.00.",
                    expected: "over by RM 10.00", actual: draft.problem(totalMinor: 10000) ?? "nil")
        }
        // Largest remainder / leftover sen
        do {
            let ctx = TestKit.context()
            var draft = SplitDraft()
            people(ctx, "A", "B").forEach { draft.add($0) }
            let shares = draft.shares(totalMinor: 1000) ?? []
            t.check("RM10 / 3: leftover sen goes to Me, total exact", shares == [334, 333, 333] && shares.reduce(0, +) == 1000,
                    expected: "[334, 333, 333]", actual: "\(shares)")
        }
        // Minimum participants / exactly one Me / duplicate people
        do {
            let ctx = TestKit.context()
            var draft = SplitDraft()
            let tooFew = draft.problem(totalMinor: 3000)
            draft.remove(id: draft.participants[0].id)                 // Me cannot be removed
            let a = people(ctx, "A")[0]
            let firstAdd = draft.add(a)
            let secondAdd = draft.add(a)
            t.check("Minimum 2 participants, exactly one Me, no duplicate person",
                    tooFew == "Add at least one other person." && draft.participants.filter(\.isMe).count == 1 &&
                    firstAdd && !secondAdd && draft.participants.count == 2,
                    expected: "too few reported; Me kept; A added once",
                    actual: "tooFew=\(tooFew ?? "nil") me=\(draft.participants.filter(\.isMe).count) adds=\(firstAdd)/\(secondAdd) count=\(draft.participants.count)")
        }
        // Payer = Me
        do {
            let ctx = TestKit.context()
            let expense = Expense(amount: 30, merchant: "Dinner")
            ctx.insert(expense)
            var draft = SplitDraft()
            let ppl = people(ctx, "Bijoy", "Riyad", "Labib")
            ppl.forEach { draft.add($0) }
            let applied = draft.apply(to: expense, in: ctx)
            try? ctx.save()
            let balances = FinancialCalculator.personBalances(expenses: [expense], movements: [])
            t.check("Payer = Me: spending RM30, cash out RM30, my share RM7.50, each owes RM7.50",
                    applied && expense.paidByMe && expense.splitMethod == .equal && expense.spendingMinor == 3000 &&
                    expense.cashOutMinor == 3000 && expense.myShareMinor == 750 && ppl.allSatisfy { balances[$0.id] == 750 },
                    expected: "3000/3000/750, +750 each",
                    actual: "spending=\(expense.spendingMinor) cashOut=\(expense.cashOutMinor) mine=\(expense.myShareMinor) balances=\(ppl.map { balances[$0.id] ?? 0 })")
        }
        // Payer != Me (Ali paid RM40)
        do {
            let ctx = TestKit.context()
            let expense = Expense(amount: 40, merchant: "Lunch")
            ctx.insert(expense)
            let ppl = people(ctx, "Ali", "Bob", "Sara")
            var draft = SplitDraft()
            ppl.forEach { draft.add($0) }
            draft.payer = ppl[0]
            draft.apply(to: expense, in: ctx)
            try? ctx.save()
            let balances = FinancialCalculator.personBalances(expenses: [expense], movements: [])
            t.check("Payer = Ali: my spending RM10, cash out RM0, I owe Ali RM10; Bob/Sara not involved with me",
                    !expense.paidByMe && expense.payer === ppl[0] && expense.payerNameSnapshot == "Ali" &&
                    expense.spendingMinor == 1000 && expense.cashOutMinor == 0 &&
                    balances[ppl[0].id] == -1000 && balances[ppl[1].id] == nil && balances[ppl[2].id] == nil,
                    expected: "1000 / 0 / Ali -1000",
                    actual: "spending=\(expense.spendingMinor) cashOut=\(expense.cashOutMinor) balances=\(balances.values.sorted())")
            let summary = FinancialCalculator.summary(expenses: [expense], movements: [])
            t.check("Shared spending/cash-out totals use my share when someone else paid",
                    summary.spendingMinor == 1000 && summary.moneyOutMinor == 0,
                    expected: "spending 1000, out 0", actual: "\(summary.spendingMinor)/\(summary.moneyOutMinor)")
        }
        // Editing the amount
        do {
            let ctx = TestKit.context()
            let ppl = people(ctx, "A", "B")
            let equal = Expense(amount: 30, merchant: "Equal")
            let parts = Expense(amount: 30, merchant: "Parts")
            let exact = Expense(amount: 30, merchant: "Exact")
            [equal, parts, exact].forEach { ctx.insert($0) }
            var d1 = SplitDraft(); ppl.forEach { d1.add($0) }; d1.apply(to: equal, in: ctx)
            var d2 = SplitDraft(); d2.method = .parts; ppl.forEach { d2.add($0) }; d2.setParts(4, for: d2.participants[0].id); d2.apply(to: parts, in: ctx)
            var d3 = SplitDraft(); d3.method = .amounts; ppl.forEach { d3.add($0) }
            zip(d3.participants.map(\.id), ["10", "10", "10"]).forEach { d3.setAmountText($1, for: $0) }
            d3.apply(to: exact, in: ctx)
            try? ctx.save()

            [equal, parts, exact].forEach { $0.amount = 40 }
            let r1 = SplitDraft.recalculateAfterAmountChange(equal, in: ctx)
            let r2 = SplitDraft.recalculateAfterAmountChange(parts, in: ctx)
            let r3 = SplitDraft.recalculateAfterAmountChange(exact, in: ctx)
            try? ctx.save()
            func sorted(_ e: Expense) -> [Int] { e.shares.sorted { ($0.isMe ? 0 : 1, $0.sortIndex) < ($1.isMe ? 0 : 1, $1.sortIndex) }.map(\.amountMinor) }
            t.check("Amount change: Equal and Parts recalculate; exact amounts are left and flagged",
                    r1 && sorted(equal) == [1334, 1333, 1333] && r2 && sorted(parts) == [2667, 667, 666] &&
                    !r3 && sorted(exact) == [1000, 1000, 1000] && !exact.sharesMatchAmount,
                    expected: "equal [1334,1333,1333], parts [2667,667,666], exact unchanged + flagged",
                    actual: "equal=\(sorted(equal)) parts=\(sorted(parts)) exact=\(sorted(exact)) exactOK=\(exact.sharesMatchAmount)")
        }
        // Participant changes and reload
        do {
            let ctx = TestKit.context()
            let ppl = people(ctx, "A", "B", "C")
            let expense = Expense(amount: 60, merchant: "Trip")
            ctx.insert(expense)
            var draft = SplitDraft(); ppl.forEach { draft.add($0) }
            draft.apply(to: expense, in: ctx)
            try? ctx.save()
            var reloaded = SplitDraft(expense: expense)
            let reloadOK = reloaded?.participants.count == 4 && reloaded?.participants.first?.isMe == true && reloaded?.method == .equal
            if let removeID = reloaded?.participants.first(where: { $0.person === ppl[2] })?.id {
                reloaded?.remove(id: removeID)
            }
            reloaded?.apply(to: expense, in: ctx)
            try? ctx.save()
            t.check("Participant removed: shares recalculated, old share rows deleted",
                    reloadOK && expense.shares.count == 3 && expense.shares.allSatisfy { $0.amountMinor == 2000 } &&
                    TestKit.count(ExpenseShare.self, in: ctx) == 3,
                    expected: "3 shares of 2000, 3 rows in store", actual: "shares=\(expense.shares.map(\.amountMinor)) rows=\(TestKit.count(ExpenseShare.self, in: ctx))")
        }
        // Person snapshot, deletion behaviour, removing a split
        do {
            let ctx = TestKit.context()
            let bijoy = people(ctx, "Bijoy")[0]
            let expense = Expense(amount: 20, merchant: "Kopi")
            ctx.insert(expense)
            var draft = SplitDraft(); draft.add(bijoy); draft.payer = bijoy
            draft.apply(to: expense, in: ctx)
            try? ctx.save()
            bijoy.name = "Bijoy Das"                                   // later rename does not rewrite history
            let snapshotKept = expense.shares.first { !$0.isMe }?.nameSnapshot == "Bijoy" && expense.payerNameSnapshot == "Bijoy"
            ctx.delete(bijoy)
            try? ctx.save()
            let afterPersonDelete = expense.shares.count == 2 && expense.payer == nil && expense.payerNameSnapshot == "Bijoy"
            SplitDraft.removeSplit(from: expense, in: ctx)
            try? ctx.save()
            let removed = !expense.isShared && expense.paidByMe && expense.splitMethod == nil && TestKit.count(ExpenseShare.self, in: ctx) == 0
            t.check("Snapshots survive rename/delete; removing a split makes it a normal expense again",
                    snapshotKept && afterPersonDelete && removed,
                    expected: "snapshot 'Bijoy' kept; shares kept after person delete; split removable",
                    actual: "snapshot=\(snapshotKept) afterDelete=\(afterPersonDelete) removed=\(removed)")
        }
        do {
            let ctx = TestKit.context()
            let a = people(ctx, "A")[0]
            let expense = Expense(amount: 10, merchant: "X")
            ctx.insert(expense)
            var draft = SplitDraft(); draft.add(a); draft.apply(to: expense, in: ctx)
            try? ctx.save()
            ctx.delete(expense)
            try? ctx.save()
            t.check("Deleting a shared expense deletes its shares (person kept)",
                    TestKit.count(ExpenseShare.self, in: ctx) == 0 && TestKit.count(PayBookProfile.self, in: ctx) == 1,
                    expected: "0 shares, 1 person", actual: "shares=\(TestKit.count(ExpenseShare.self, in: ctx)) people=\(TestKit.count(PayBookProfile.self, in: ctx))")
        }
        // Duplicate safety for shared expenses
        do {
            let ctx = TestKit.context()
            let a = people(ctx, "A")[0]
            let shared = Expense(amount: 30, merchant: "Nasi")
            let plain = Expense(amount: 30, merchant: "Nasi", date: shared.date)
            ctx.insert(shared); ctx.insert(plain)
            var draft = SplitDraft(); draft.add(a); draft.apply(to: shared, in: ctx)
            try? ctx.save()
            let merged = TransactionReconciliationEngine.shared.consolidateExistingDuplicates(in: ctx)
            t.check("Duplicate cleanup never merges a shared expense", merged == 0 && TestKit.count(Expense.self, in: ctx) == 2,
                    expected: "0 merged", actual: "merged=\(merged)")
        }
        // Same as last time
        do {
            let ctx = TestKit.context()
            let ppl = people(ctx, "Bijoy", "Riyad", "Old")
            ppl[2].isArchived = true
            let first = Expense(amount: 30, merchant: "Nasi Kandar", date: Date().addingTimeInterval(-86_400))
            ctx.insert(first)
            var d = SplitDraft(); ppl.forEach { d.add($0) }; d.apply(to: first, in: ctx)
            try? ctx.save()
            let suggestion = SplitDraft.lastTimeSuggestion(merchant: "nasi kandar", in: ctx)
            let emptyCtx = TestKit.context()
            let none = SplitDraft.lastTimeSuggestion(merchant: "anything", in: emptyCtx)
            t.check("Same as last time: suggests previous people (archived excluded); nothing without history",
                    suggestion?.others.map(\.name) == ["Bijoy", "Riyad"] && none == nil,
                    expected: "[Bijoy, Riyad]; nil", actual: "\(suggestion?.others.map(\.name) ?? []) / \(none == nil ? "nil" : "value")")
        }

        return results
    }
}

/// Splits (incl. paid for someone and Auto Calculate), per-transaction debts, settlements, netting and duplicate
/// rules. In-memory stores and fixed amounts only. `--run-debt-tests`
@MainActor
public struct DebtSettlementTests {
    static func person(_ name: String, in ctx: ModelContext) -> PayBookProfile {
        let p = PayBookProfile(name: name); ctx.insert(p); return p
    }

    /// An expense I paid entirely for `person` (their share = amount).
    @discardableResult
    static func paidFor(_ person: PayBookProfile, _ minor: Int, _ title: String, daysAgo: Int = 0, in ctx: ModelContext) -> Expense {
        let e = Expense(amount: Money.majorAmount(fromMinor: minor), merchant: title, date: Date(timeIntervalSince1970: 1_790_000_000 - Double(daysAgo) * 86_400))
        ctx.insert(e)
        var d = SplitDraft(); d.purpose = .paidFor; d.add(person); d.apply(to: e, in: ctx)
        try? ctx.save()
        return e
    }

    static func outstanding(_ person: PayBookProfile) -> [String: Int] {
        Dictionary(DebtLedger.debts(for: person).map { ($0.title, $0.outstandingMinor) }, uniquingKeysWith: { a, b in a + b })
    }
    static func net(_ person: PayBookProfile) -> Int { PersonLedger.balances(for: person)["RM"] ?? 0 }

    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Debts & settlements") { results.append($0) }

        // MARK: Split methods and rounding (integer sen; always adds up exactly)
        do {
            func split(_ total: Int, _ method: SplitMethod, _ count: Int, parts: [Int]? = nil) -> [Int]? {
                let ps = (0..<count).map { SplitCalculator.Participant(isMe: $0 == 0, parts: parts?[$0]) }
                return try? SplitCalculator.calculate(totalMinor: total, method: method, participants: ps).get()
            }
            let two = split(10000, .equal, 2), three = split(1000, .equal, 3), five = split(10003, .equal, 5)
            let parts = split(10000, .parts, 2, parts: [1, 2])
            t.check("Equal (2, 3, 5 people) and parts (1:2) always add up exactly; leftover sen are deterministic",
                    two == [5000, 5000] && three == [334, 333, 333] && five?.reduce(0, +) == 10003 && five == [2001, 2001, 2001, 2000, 2000] &&
                    parts == [3333, 6667],
                    expected: "[5000,5000] [334,333,333] Σ10003 [3333,6667]", actual: "\(String(describing: two)) \(String(describing: three)) \(String(describing: five)) \(String(describing: parts))")
        }

        // MARK: Amounts: Auto Calculate ON / OFF and validation
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            var auto = SplitDraft(); auto.method = .amounts; auto.add(bijoy)
            let me = auto.participants[0].id, b = auto.participants[1].id
            auto.setAmountText("0.01", for: me, totalMinor: 700)
            let first = auto.participants[1].amountText
            auto.setAmountText("2", for: me, totalMinor: 700)
            let second = auto.participants[1].amountText
            t.check("Auto Calculate ON: RM7.00, Me 0.01 → Bijoy 6.99; Me 2.00 → Bijoy 5.00; valid with nothing left",
                    first == "6.99" && second == "5.00" && auto.isValid(totalMinor: 700) && auto.remainingMinor(totalMinor: 700) == 0,
                    expected: "6.99, 5.00, valid", actual: "\(first), \(second), \(String(describing: auto.problem(totalMinor: 700)))")

            let labib = person("Labib", in: ctx)
            var three = SplitDraft(); three.method = .amounts; three.add(bijoy); three.add(labib)
            three.setAmountText("30", for: three.participants[0].id, totalMinor: 10000)
            three.setAmountText("20", for: three.participants[1].id, totalMinor: 10000)
            t.check("Auto Calculate with 3 people: the person not typed for gets the rest (Labib 50.00)",
                    three.participants[2].amountText == "50.00" && three.isValid(totalMinor: 10000),
                    expected: "50.00", actual: three.participants[2].amountText)

            var manual = SplitDraft(); manual.method = .amounts; manual.autoCalculate = false; manual.add(bijoy)
            manual.setAmountText("30", for: manual.participants[0].id, totalMinor: 10000)
            let untouched = manual.participants[1].amountText
            manual.setAmountText("60", for: manual.participants[1].id, totalMinor: 10000)
            let short = manual.problem(totalMinor: 10000)
            manual.setAmountText("75", for: manual.participants[1].id, totalMinor: 10000)
            let over = manual.problem(totalMinor: 10000)
            manual.setAmountText("70", for: manual.participants[1].id, totalMinor: 10000)
            t.check("Auto Calculate OFF: nothing changes by itself; 'RM 10.00 remains unassigned.' / 'exceed the total by RM 5.00'; exact match valid",
                    untouched == "" && short == "RM 10.00 remains unassigned." && over == "Shares exceed the total by RM 5.00." &&
                    manual.isValid(totalMinor: 10000) && manual.remainingMinor(totalMinor: 10000) == 0,
                    expected: "untouched, short, over, valid", actual: "'\(untouched)' \(String(describing: short)) \(String(describing: over))")
        }

        // MARK: Paid for someone / someone paid for me / real-life splits
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx), labib = person("Labib", in: ctx)
            let forBijoy = paidFor(bijoy, 10000, "Dinner for Bijoy", in: ctx)
            let myShare = forBijoy.shares.first(where: \.isMe)
            t.check("I paid RM100 for Bijoy: my share is an automatic 0 (nothing typed), Bijoy owes me RM100; recognised again when edited",
                    myShare?.amountMinor == 0 && myShare?.enteredMinor == nil && forBijoy.shares.first { !$0.isMe }?.amountMinor == 10000 &&
                    net(bijoy) == 10000 && SplitDraft(expense: forBijoy)?.purpose == .paidFor,
                    expected: "0 / 10000, +10000, paidFor", actual: "net=\(net(bijoy)) purpose=\(String(describing: SplitDraft(expense: forBijoy)?.purpose))")

            let forMe = Expense(amount: 100, merchant: "Bijoy paid for me"); ctx.insert(forMe)
            var d = SplitDraft(); d.purpose = .paidFor; d.payer = labib; d.apply(to: forMe, in: ctx); try? ctx.save()
            t.check("Labib paid RM100 for me: only my share (RM100) is stored, payer Labib; I owe Labib RM100",
                    forMe.shares.count == 1 && forMe.myShareMinor == 10000 && !forMe.paidByMe && net(labib) == -10000 &&
                    SplitDraft(expense: forMe)?.paidForMe == true,
                    expected: "-10000", actual: "\(net(labib))")

            let two = Expense(amount: 100, merchant: "Groceries for two"); ctx.insert(two)
            var d2 = SplitDraft(); d2.purpose = .paidFor; d2.add(bijoy); d2.add(labib); d2.apply(to: two, in: ctx)
            t.check("Paid for two people equally: RM50 each, my share 0",
                    two.shares.first(where: \.isMe)?.amountMinor == 0 && two.shares.filter { !$0.isMe }.map(\.amountMinor) == [5000, 5000],
                    expected: "0, 5000, 5000", actual: "\(two.shares.map(\.amountMinor))")

            let ctx2 = TestKit.context()
            let p = person("Bijoy", in: ctx2)
            let lunch = Expense(amount: 50, merchant: "Lunch"); ctx2.insert(lunch)
            var s = SplitDraft(); s.method = .amounts; s.add(p)
            s.setAmountText("30", for: s.participants[0].id, totalMinor: 5000); s.apply(to: lunch, in: ctx2)
            let netAfterMine = net(p)
            let theirs = Expense(amount: 50, merchant: "Bijoy's lunch"); ctx2.insert(theirs)
            var s2 = SplitDraft(); s2.method = .amounts; s2.autoCalculate = false; s2.add(p); s2.payer = p
            s2.setAmountText("20", for: s2.participants[0].id); s2.setAmountText("30", for: s2.participants[1].id); s2.apply(to: theirs, in: ctx2)
            try? ctx2.save()
            t.check("Real life: I paid RM50, my share RM30 → Bijoy owes RM20; Bijoy paid RM50, my share RM20 → net 0 (both kept)",
                    netAfterMine == 2000 && net(p) == 0 && DebtLedger.debts(for: p).count == 2,
                    expected: "+2000, then 0 with 2 debts", actual: "\(netAfterMine) \(net(p)) \(DebtLedger.debts(for: p).count)")
        }

        // MARK: Settlements on individual transactions
        func scenario() -> (ModelContext, PayBookProfile, [Debt]) {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            paidFor(bijoy, 5000, "A Dinner", daysAgo: 3, in: ctx)
            paidFor(bijoy, 3000, "B Grab", daysAgo: 2, in: ctx)
            paidFor(bijoy, 2000, "C Food", daysAgo: 1, in: ctx)
            return (ctx, bijoy, DebtLedger.debts(for: bijoy))
        }
        func debt(_ title: String, _ person: PayBookProfile) -> Debt { DebtLedger.debts(for: person).first { $0.title == title }! }
        do {
            let (ctx, bijoy, debts) = scenario()
            let a = debts.first { $0.title == "A Dinner" }!
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 2000, allocations: [(a, 2000)], currency: "RM", in: ctx)
            let o = outstanding(bijoy)
            t.check("RM20 paid towards A only: A 30, B 30, C 20 → RM80 left (not 0); A's original share still RM50",
                    o["A Dinner"] == 3000 && o["B Grab"] == 3000 && o["C Food"] == 2000 && net(bijoy) == 8000 &&
                    debt("A Dinner", bijoy).originalMinor == 5000 && debt("A Dinner", bijoy).isPartiallyPaid,
                    expected: "30/30/20, net 80", actual: "\(o) net=\(net(bijoy))")
        }
        do {
            let (ctx, bijoy, _) = scenario()
            let group = try? SettlementService.markPaid(debt("A Dinner", bijoy), person: bijoy, in: ctx)
            let o = outstanding(bijoy)
            let payment = (try? ctx.fetch(FetchDescriptor<MoneyMovement>()))?.first
            t.check("Mark as Paid on A uses its RM50 automatically; only A is settled (B 30 + C 20 left); expense kept",
                    group != nil && o["A Dinner"] == 0 && o["B Grab"] == 3000 && o["C Food"] == 2000 && net(bijoy) == 5000 &&
                    payment?.amountMinor == 5000 && payment?.kind == .repaymentReceived && TestKit.count(Expense.self, in: ctx) == 3,
                    expected: "0/30/20, one RM50 repayment", actual: "\(o)")
            if let group { try? SettlementService.undo(groupID: group, in: ctx) }
            t.check("Undo: A is outstanding again (RM50), the repayment is removed, the expense and its share are unchanged",
                    outstanding(bijoy)["A Dinner"] == 5000 && TestKit.count(MoneyMovement.self, in: ctx) == 0 && net(bijoy) == 10000 &&
                    debt("A Dinner", bijoy).originalMinor == 5000,
                    expected: "50 again", actual: "\(outstanding(bijoy))")
        }
        do {
            let (ctx, bijoy, debts) = scenario()
            let selected = debts.filter { $0.title != "B Grab" }
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 7000,
                                                     allocations: selected.map { ($0, $0.outstandingMinor) }, currency: "RM", in: ctx)
            t.check("Select A + C (RM70) and settle: one payment; A and C settled, B RM30 left",
                    outstanding(bijoy) == ["A Dinner": 0, "B Grab": 3000, "C Food": 0] && net(bijoy) == 3000 &&
                    TestKit.count(MoneyMovement.self, in: ctx) == 1 && TestKit.count(SettlementAllocation.self, in: ctx) == 2,
                    expected: "0/30/0", actual: "\(outstanding(bijoy))")
        }
        do {
            let (ctx, bijoy, debts) = scenario()
            let plan60 = SettlementService.autoAllocate(amountMinor: 6000, to: debts)
            let plan20 = SettlementService.autoAllocate(amountMinor: 2000, to: debts)
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 6000,
                                                     allocations: [(debts[0], 5000), (debts[1], 1000)], currency: "RM", in: ctx)
            t.check("Auto Apply previews oldest first (RM60 → A 50 + B 10; RM20 → A 20); manual RM60 as A 50 + B 10 leaves B 20, C 20",
                    plan60.map(\.1) == [5000, 1000] && plan60.map(\.0.title) == ["A Dinner", "B Grab"] && plan20.map(\.1) == [2000] &&
                    outstanding(bijoy) == ["A Dinner": 0, "B Grab": 2000, "C Food": 2000] && net(bijoy) == 4000,
                    expected: "plan [50,10] [20]; 0/20/20", actual: "\(plan60.map(\.1)) \(plan20.map(\.1)) \(outstanding(bijoy))")
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            paidFor(bijoy, 10000, "Big dinner", in: ctx)
            for amount in [2000, 3000, 5000] {
                _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: amount,
                                                         allocations: [(debt("Big dinner", bijoy), amount)], currency: "RM", in: ctx)
            }
            let history = DebtLedger.settlementGroups(personID: bijoy.id, in: ctx)
            t.check("Several payments on one debt (20 + 30 + 50): settled; history keeps all three",
                    debt("Big dinner", bijoy).isSettled && history.count == 3 && history.map(\.totalMinor).sorted() == [2000, 3000, 5000] && net(bijoy) == 0,
                    expected: "settled, 3 entries", actual: "\(history.map(\.totalMinor))")
        }
        do {
            let (ctx, bijoy, debts) = scenario()
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 10000,
                                                     allocations: debts.map { ($0, $0.outstandingMinor) }, currency: "RM", in: ctx)
            t.check("One RM100 payment allocated to A, B and C: one payment, three allocations, all settled",
                    DebtLedger.debts(for: bijoy).allSatisfy(\.isSettled) && TestKit.count(MoneyMovement.self, in: ctx) == 1 &&
                    TestKit.count(SettlementAllocation.self, in: ctx) == 3,
                    expected: "all settled", actual: "\(outstanding(bijoy))")
        }
        do {
            let (ctx, bijoy, debts) = scenario()
            let a = debts[0], b = debts[1]
            let over = Result { try SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 9000, allocations: [(a, 6000)], currency: "RM", in: ctx) }
            let tooMuch = Result { try SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 1000, allocations: [(a, 2000)], currency: "RM", in: ctx) }
            let wrongWay = Result { try SettlementService.recordPayment(person: bijoy, direction: -1, amountMinor: 1000, allocations: [(b, 1000)], currency: "RM", in: ctx) }
            func err(_ r: Result<UUID, Error>) -> SettlementService.SettlementError? { if case .failure(let e) = r { return e as? SettlementService.SettlementError }; return nil }
            t.check("Invalid payments are refused before anything is saved (more than outstanding, more than paid, wrong direction)",
                    err(over) == .exceedsOutstanding(debtTitle: "A Dinner") && err(tooMuch) == .allocationExceedsPayment &&
                    err(wrongWay) == .mixedPeopleOrDirections && TestKit.count(MoneyMovement.self, in: ctx) == 0,
                    expected: "3 refusals, nothing saved", actual: "\(String(describing: err(over))) \(String(describing: err(tooMuch))) \(String(describing: err(wrongWay)))")
        }

        // MARK: Netting, settle all, identical transactions, transfers, legacy payments
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            paidFor(bijoy, 10000, "I paid", in: ctx)
            let theirs = Expense(amount: 20, merchant: "Bijoy paid"); ctx.insert(theirs)
            var d = SplitDraft(); d.purpose = .paidFor; d.payer = bijoy; d.apply(to: theirs, in: ctx); try? ctx.save()
            let netBefore = net(bijoy)
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 2000,
                                                     allocations: [(debt("I paid", bijoy), 2000)], currency: "RM", in: ctx)
            let afterPayment = net(bijoy)
            let iOwe = debt("Bijoy paid", bijoy)
            t.check("Netting: Bijoy owes 100, I owe 20 → 'Bijoy owes you RM 80.00', both kept; Bijoy pays 20 on his debt → net 60, my RM20 untouched",
                    netBefore == 8000 && PersonLedger.directionText(name: "Bijoy", balanceMinor: netBefore, currency: "RM") == "Bijoy owes you RM 80.00" &&
                    afterPayment == 6000 && iOwe.outstandingMinor == 2000 && iOwe.direction == -1 && DebtLedger.debts(for: bijoy).count == 2,
                    expected: "80 → 60; I still owe 20", actual: "\(netBefore) \(afterPayment) \(iOwe.outstandingMinor)")

            let group = try? SettlementService.settleAll(person: bijoy, currency: "RM", in: ctx)
            let cash = (try? ctx.fetch(FetchDescriptor<MoneyMovement>()))?.filter { $0.note == "Settled all with Bijoy" } ?? []
            t.check("Settle All: debts in both directions cancel (RM20), one RM60 payment for the rest; net 0; every transaction kept",
                    group != nil && net(bijoy) == 0 && DebtLedger.debts(for: bijoy).allSatisfy(\.isSettled) &&
                    cash.count == 1 && cash.first?.amountMinor == 6000 && cash.first?.kind == .repaymentReceived && TestKit.count(Expense.self, in: ctx) == 2,
                    expected: "net 0, one 60 payment", actual: "net=\(net(bijoy)) cash=\(cash.map(\.amountMinor))")
            if let group { try? SettlementService.undo(groupID: group, in: ctx) }
            t.check("Undo Settle All restores the previous state exactly (net 60, I owe 20)",
                    net(bijoy) == 6000 && debt("Bijoy paid", bijoy).outstandingMinor == 2000 && debt("I paid", bijoy).outstandingMinor == 8000,
                    expected: "60, 20, 80", actual: "\(net(bijoy))")
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            let theirs = Expense(amount: 100, merchant: "Bijoy paid big"); ctx.insert(theirs)
            var d = SplitDraft(); d.purpose = .paidFor; d.payer = bijoy; d.apply(to: theirs, in: ctx)
            paidFor(bijoy, 2000, "I paid small", in: ctx)
            t.check("Reverse netting: I owe 100, Bijoy owes 20 → 'You owe Bijoy RM 80.00'",
                    PersonLedger.directionText(name: "Bijoy", balanceMinor: net(bijoy), currency: "RM") == "You owe Bijoy RM 80.00",
                    expected: "You owe Bijoy RM 80.00", actual: PersonLedger.directionText(name: "Bijoy", balanceMinor: net(bijoy), currency: "RM"))
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            let one = paidFor(bijoy, 10000, "Same", in: ctx), two = paidFor(bijoy, 10000, "Same", in: ctx)
            let debts = DebtLedger.debts(for: bijoy)
            _ = try? SettlementService.markPaid(debts.first { $0.expenseID == one.id }!, person: bijoy, in: ctx)
            let after = DebtLedger.debts(for: bijoy)
            t.check("Two identical RM100 transactions both exist; settling one leaves the other RM100",
                    one.id != two.id && debts.count == 2 && net(bijoy) == 10000 &&
                    after.first { $0.expenseID == one.id }?.isSettled == true && after.first { $0.expenseID == two.id }?.outstandingMinor == 10000,
                    expected: "200 → 100", actual: "net=\(net(bijoy))")
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            let transfer = MoneyMovement(kind: .loanGiven, amountMinor: 10000, person: bijoy); ctx.insert(transfer)
            let legacy = MoneyMovement(kind: .repaymentReceived, amountMinor: 3000, person: bijoy); ctx.insert(legacy)
            try? ctx.save()
            let loan = DebtLedger.debts(for: bijoy).first
            let unassignedBefore = DebtLedger.unassignedMinor(for: bijoy, currency: "RM")
            _ = try? SettlementService.settleAll(person: bijoy, currency: "RM", in: ctx)
            let newCash = (try? ctx.fetch(FetchDescriptor<MoneyMovement>()))?.filter { $0.note == "Settled all with Bijoy" }.map(\.amountMinor)
            t.check("Direct transfer (gave Bijoy RM100) is a debt with no shares; an older unlinked RM30 repayment is used by Settle All (only RM70 new)",
                    loan?.direction == 1 && loan?.originalMinor == 10000 && loan?.loanID == transfer.id && unassignedBefore == -3000 &&
                    net(bijoy) == 0 && newCash == [7000],
                    expected: "loan 100; unassigned -30; new 70", actual: "\(String(describing: loan?.originalMinor)) \(unassignedBefore) \(String(describing: newCash))")
        }

        // MARK: Duplicate detection (imports only; amount alone never counts)
        do {
            let ctx = TestKit.context()
            let base = Date(timeIntervalSince1970: 1_790_000_000)
            let existing = Expense(amount: 100, merchant: "Bijoy", date: base, transactionReference: "TNG-123456"); ctx.insert(existing)
            try? ctx.save()
            let engine = TransactionReconciliationEngine.shared
            let labib = engine.findMatch(amount: 100, merchant: "Labib", date: base.addingTimeInterval(60), reference: nil, in: ctx)
            let nextDay = engine.findMatch(amount: 100, merchant: "Bijoy", date: base.addingTimeInterval(86_400), reference: nil, in: ctx)
            let evening = engine.findMatch(amount: 100, merchant: "Bijoy", date: base.addingTimeInterval(8 * 3600), reference: nil, in: ctx)
            let sameMinute = engine.findMatch(amount: 100, merchant: "bijoy ", date: base.addingTimeInterval(120), reference: nil, in: ctx)
            let sameRef = engine.findMatch(amount: 100, merchant: "Other", date: base.addingTimeInterval(3600), reference: "tng-123456", in: ctx)
            let otherAmount = engine.findMatch(amount: 99, merchant: "Bijoy", date: base, reference: nil, in: ctx)
            t.check("Duplicates: same amount for another person, next day, or 8 hours later are NOT duplicates; same merchant within minutes = warning; same reference = strong",
                    !labib.isMatch && !nextDay.isMatch && !evening.isMatch && sameMinute.isMatch && !sameMinute.isStrong &&
                    sameRef.isMatch && sameRef.isStrong && !otherAmount.isMatch,
                    expected: "no, no, no, weak, strong, no",
                    actual: "\(labib.isMatch) \(nextDay.isMatch) \(evening.isMatch) \(sameMinute.isMatch)/\(sameMinute.isStrong) \(sameRef.isStrong) \(otherAmount.isMatch)")
            for _ in 0..<3 { ctx.insert(Expense(amount: 100, merchant: "Bijoy", date: base)) }
            try? ctx.save()
            t.check("Manual entries are never blocked: three identical RM100 'Bijoy' expenses all exist with their own ids",
                    TestKit.count(Expense.self, in: ctx) == 4 && Set(TestKit.fetch(Expense.self, in: ctx).map(\.id)).count == 4,
                    expected: "4 distinct", actual: "\(TestKit.count(Expense.self, in: ctx))")
        }

        // MARK: Credit (unallocated payments) and integrity
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            paidFor(bijoy, 1000, "A", daysAgo: 9, in: ctx); paidFor(bijoy, 500, "B", daysAgo: 8, in: ctx)
            paidFor(bijoy, 300, "C", daysAgo: 7, in: ctx); paidFor(bijoy, 1000, "D", daysAgo: 6, in: ctx)
            let abc = DebtLedger.debts(for: bijoy).filter { ["A", "B", "C"].contains($0.title) }
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 2000,
                                                     allocations: abc.map { ($0, $0.outstandingMinor) }, currency: "RM", in: ctx)
            let uses = DebtLedger.paymentUses(for: bijoy)
            let credit = DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1)
            t.check("ONE RM20 payment for A 10 + B 5 + C 3: applied RM18, RM2 credit visible; D untouched; one repayment, not three",
                    uses.count == 1 && uses[0].allocatedMinor == 1800 && uses[0].unallocatedMinor == 200 && credit == 200 &&
                    outstanding(bijoy) == ["A": 0, "B": 0, "C": 0, "D": 1000] && net(bijoy) == 800 &&
                    TestKit.count(MoneyMovement.self, in: ctx) == 1,
                    expected: "18 applied, 2 credit, D 10", actual: "applied=\(uses.first?.allocatedMinor ?? -1) credit=\(credit) \(outstanding(bijoy))")

            paidFor(bijoy, 1000, "E", daysAgo: 1, in: ctx)
            let e = debt("E", bijoy)
            let tooMuch = Result { try SettlementService.applyCredit(person: bijoy, direction: 1, allocations: [(e, 500)], currency: "RM", in: ctx) }
            let group = try? SettlementService.applyCredit(person: bijoy, direction: 1, allocations: [(e, 200)], currency: "RM", in: ctx)
            t.check("Credit reused later: RM2 applied to a new RM10 debt → RM8 left, credit 0; asking for more than the credit is refused",
                    debt("E", bijoy).outstandingMinor == 800 && DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1) == 0 &&
                    { if case .failure(let err) = tooMuch { return (err as? SettlementService.SettlementError) == .notEnoughCredit(availableMinor: 200, currency: "RM") }; return false }(),
                    expected: "E 8, credit 0", actual: "E=\(debt("E", bijoy).outstandingMinor)")
            if let group { try? SettlementService.undo(groupID: group, in: ctx) }
            t.check("Undo the credit application: E back to RM10, credit back to RM2, and the real RM20 repayment is NOT deleted",
                    debt("E", bijoy).outstandingMinor == 1000 && DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1) == 200 &&
                    TestKit.count(MoneyMovement.self, in: ctx) == 1,
                    expected: "10, 2, repayment kept", actual: "E=\(debt("E", bijoy).outstandingMinor) movements=\(TestKit.count(MoneyMovement.self, in: ctx))")

            // Integrity: original = settled + outstanding; payment = applied + credit; net = outstanding + credit (signed)
            let debts = DebtLedger.debts(for: bijoy)
            let paymentsOK = DebtLedger.paymentUses(for: bijoy).allSatisfy { $0.allocatedMinor + $0.unallocatedMinor == $0.payment.amountMinor }
            let debtsOK = debts.allSatisfy { $0.settledMinor + $0.outstandingMinor == $0.originalMinor }
            let netOK = net(bijoy) == debts.reduce(0) { $0 + $1.signedOutstandingMinor } + DebtLedger.unassignedMinor(for: bijoy, currency: "RM") &&
                        DebtLedger.unassignedMinor(for: bijoy, currency: "RM") == -DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1)
            t.check("No money disappears or is duplicated: every debt = settled + outstanding, every payment = applied + credit, net = outstanding − credit",
                    paymentsOK && debtsOK && netOK, expected: "all hold", actual: "\(paymentsOK) \(debtsOK) \(netOK)")
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            paidFor(bijoy, 1000, "Small debt", in: ctx)
            let plan = SettlementService.autoAllocate(amountMinor: 2000, to: DebtLedger.debts(for: bijoy))
            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 2000, allocations: plan, currency: "RM", in: ctx)
            t.check("Payment larger than the debt (RM20 for RM10): the debt is settled and RM10 stays as visible credit",
                    debt("Small debt", bijoy).isSettled && DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1) == 1000 && net(bijoy) == -1000,
                    expected: "settled, credit 10", actual: "credit=\(DebtLedger.creditMinor(for: bijoy, currency: "RM", direction: 1))")

            let legacy = MoneyMovement(kind: .repaymentReceived, amountMinor: 500, person: bijoy); ctx.insert(legacy)
            paidFor(bijoy, 800, "Later", in: ctx)
            try? ctx.save()
            let group = try? SettlementService.applyCredit(person: bijoy, direction: 1, allocations: [(debt("Later", bijoy), 800)], currency: "RM", in: ctx)
            if let group { try? SettlementService.undo(groupID: group, in: ctx) }
            t.check("An independent repayment (recorded on its own) survives undoing the allocation that used it",
                    group != nil && ((try? ctx.fetch(FetchDescriptor<MoneyMovement>())) ?? []).contains { $0.id == legacy.id } &&
                    debt("Later", bijoy).outstandingMinor == 800,
                    expected: "repayment kept", actual: "\(group != nil)")
        }
        do {
            let tiny = [1, 2, 3].flatMap { total in [2, 3].map { count -> Bool in
                let ps = (0..<count).map { SplitCalculator.Participant(isMe: $0 == 0) }
                guard let r = try? SplitCalculator.calculate(totalMinor: total, method: .equal, participants: ps).get() else { return false }
                return r.reduce(0, +) == total && r.allSatisfy { $0 >= 0 }
            } }
            t.check("Tiny amounts (RM0.01–RM0.03 split between 2 and 3 people) still add up exactly, never negative", tiny.allSatisfy { $0 },
                    expected: "all exact", actual: "\(tiny)")
        }
        do {
            let ctx = TestKit.context()
            let base = Date(timeIntervalSince1970: 1_790_000_000)
            ctx.insert(Expense(amount: 100, merchant: "Bijoy", date: base, paymentChannel: .applePay, fundingAccount: "Maybank"))
            try? ctx.save()
            let engine = TransactionReconciliationEngine.shared
            let qr = engine.findMatch(amount: 100, merchant: "Bijoy", date: base.addingTimeInterval(60), reference: nil, paymentChannel: .qrPayment, fundingAccount: "Maybank", in: ctx)
            let cimb = engine.findMatch(amount: 100, merchant: "Bijoy", date: base.addingTimeInterval(60), reference: nil, paymentChannel: .applePay, fundingAccount: "CIMB", in: ctx)
            let unknown = engine.findMatch(amount: 100, merchant: "Bijoy", date: base.addingTimeInterval(60), reference: nil, paymentChannel: .unknown, fundingAccount: "Unknown", in: ctx)
            t.check("Different payment channel (Apple Pay vs QR) or funding account (Maybank vs CIMB) is not a duplicate; Unknown details only warn",
                    !qr.isMatch && !cimb.isMatch && unknown.isMatch && !unknown.isStrong,
                    expected: "no, no, weak", actual: "\(qr.isMatch) \(cimb.isMatch) \(unknown.isMatch)")
        }

        // MARK: Migration V3 → V4 on an on-disk store (existing data kept, balances unchanged)
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropV4Migration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("default.store")
            var before: [String: Int] = [:]
            var expenseIDs = Set<UUID>()
            // The V3 store is written with the frozen V2 model types (the shapes V3 shipped with); the expected
            // balances come from the same records built with the live types in memory.
            do {
                let ctx = TestKit.context()
                let account = Account(name: "Maybank", type: .bank); ctx.insert(account)
                let bijoy = PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
                let labib = PayBookProfile(name: "Labib"); ctx.insert(labib)
                let dinner = Expense(amount: 100, merchant: "Dinner", category: .food, paymentChannel: .qrPayment, fundingAccount: "Maybank"); ctx.insert(dinner)
                dinner.account = account
                var d = SplitDraft(); d.add(bijoy); d.apply(to: dinner, in: ctx)
                let taxi = Expense(amount: 20, merchant: "Taxi", category: .transport, paymentChannel: .unknown); ctx.insert(taxi)
                var t2 = SplitDraft(); t2.add(labib); t2.payer = labib; t2.apply(to: taxi, in: ctx)
                ctx.insert(MoneyMovement(kind: .loanGiven, amountMinor: 5000, person: bijoy, account: account))
                ctx.insert(MoneyMovement(kind: .repaymentReceived, amountMinor: 2000, person: bijoy, account: account))
                try? ctx.save()
                before = ["Bijoy": PersonLedger.balances(for: bijoy)["RM"] ?? 0, "Labib": PersonLedger.balances(for: labib)["RM"] ?? 0]
            }
            do {
                typealias V2 = SpenDropSchemaV2
                let v3 = Schema(versionedSchema: SpenDropSchemaV3.self)
                if let container = try? ModelContainer(for: v3, configurations: [ModelConfiguration(schema: v3, url: storeURL)]) {
                    let ctx = ModelContext(container)
                    let account = V2.Account(name: "Maybank", typeRaw: AccountType.bank.rawValue, currency: "RM", sortIndex: 0); ctx.insert(account)
                    let bijoy = V2.PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
                    let labib = V2.PayBookProfile(name: "Labib"); ctx.insert(labib)
                    func expense(_ merchant: String, _ amount: Double, _ category: ExpenseCategory, _ channel: PaymentChannel, payer: V2.PayBookProfile?,
                                 shares: [(V2.PayBookProfile?, Int)]) -> V2.Expense {
                        let e = V2.Expense(amount: amount, merchant: merchant); ctx.insert(e)
                        e.categoryRaw = category.rawValue
                        e.paymentChannelRaw = channel.rawValue
                        e.splitMethodRaw = SplitMethod.equal.rawValue
                        e.payer = payer; e.paidByMe = payer == nil; e.payerNameSnapshot = payer?.name
                        for (index, (person, minor)) in shares.enumerated() {
                            let share = V2.ExpenseShare(isMe: person == nil, nameSnapshot: person?.name ?? "Me", amountMinor: minor, sortIndex: index)
                            ctx.insert(share); share.expense = e; share.person = person
                        }
                        return e
                    }
                    let dinner = expense("Dinner", 100, .food, .qrPayment, payer: nil, shares: [(nil, 5000), (bijoy, 5000)])
                    dinner.fundingAccount = "Maybank"; dinner.account = account
                    _ = expense("Taxi", 20, .transport, .unknown, payer: labib, shares: [(nil, 1000), (labib, 1000)])
                    for (kind, minor) in [(MoneyMovementKind.loanGiven, 5000), (.repaymentReceived, 2000)] {
                        let m = V2.MoneyMovement(directionRaw: kind.direction.rawValue, kindRaw: kind.rawValue, amountMinor: minor); ctx.insert(m)
                        m.person = bijoy; m.personNameSnapshot = bijoy.name; m.account = account
                    }
                    try? ctx.save()
                    expenseIDs = Set(((try? ctx.fetch(FetchDescriptor<V2.Expense>())) ?? []).map(\.id))
                }
            }
            var actual = "open failed"
            var passed = false
            if let container = try? ExpenseDataContainer.openPersistentContainer(configuration: ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)) {
                let ctx = ModelContext(container)
                let people = Dictionary(TestKit.fetch(PayBookProfile.self, in: ctx).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                let after = people.mapValues { PersonLedger.balances(for: $0)["RM"] ?? 0 }
                let bijoy = people["Bijoy"]
                let taxi = TestKit.fetch(Expense.self, in: ctx).first { $0.merchant == "Taxi" }
                let debts = bijoy.map { DebtLedger.debts(for: $0) } ?? []
                let credit = bijoy.map { DebtLedger.creditMinor(for: $0, currency: "RM", direction: 1) } ?? -1
                if let bijoy, let first = debts.first(where: { $0.title == "Dinner" }) {
                    _ = try? SettlementService.markPaid(first, person: bijoy, in: ctx)
                }
                passed = after == before && Set(TestKit.fetch(Expense.self, in: ctx).map(\.id)) == expenseIDs &&
                    TestKit.count(MoneyMovement.self, in: ctx) >= 2 && debts.count == 2 && credit == 2000 &&
                    taxi?.paymentChannel == .unknown && taxi?.shares.count == 2 && !TestKit.fetch(Expense.self, in: ctx).contains(where: \.isSampleData) &&
                    TestKit.count(SampleDataRecord.self, in: ctx) == 0 && TestKit.count(SettlementAllocation.self, in: ctx) == 1
                actual = "before=\(before) after=\(after) debts=\(debts.count) credit=\(credit) allocations=\(TestKit.count(SettlementAllocation.self, in: ctx))"
            }
            t.check("Migration V3 → V4 on disk: every expense, share, person, loan and repayment kept; balances identical; old repayment shows as credit; nothing marked sample; settlements work",
                    passed, expected: "identical balances, 2 debts, credit 20, new tables usable", actual: actual)
        }

        // MARK: Funding account / payment channel / compatibility / backup
        do {
            let ctx = TestKit.context()
            let bijoy = person("Bijoy", in: ctx)
            let e = Expense(amount: 7, merchant: "BIJOYSHARIARALAMIN", paymentSource: .maybank, paymentChannel: .unknown, fundingAccount: "Maybank")
            ctx.insert(e)
            var s = SplitDraft(); s.method = .amounts; s.add(bijoy)
            s.setAmountText("0.01", for: s.participants[0].id, totalMinor: 700); s.apply(to: e, in: ctx)
            let qr = Expense(amount: 7, merchant: "QR", paymentChannel: .qrPayment, fundingAccount: "Maybank"); ctx.insert(qr)
            try? ctx.save()
            t.check("Scenario A (RM7, Me 0.01 → Bijoy 6.99 automatically): Bijoy owes me RM6.99; funding Maybank and channel Unknown kept and shown",
                    net(bijoy) == 699 && e.effectiveFundingAccount == "Maybank" && e.paymentChannel == .unknown && e.paymentChannel.displayName == "Unknown" &&
                    qr.paymentChannel == .qrPayment && qr.effectiveFundingAccount == "Maybank" && SplitDraft(expense: e)?.purpose == .shared,
                    expected: "+699; Maybank/Unknown; Maybank/QR", actual: "net=\(net(bijoy)) \(e.effectiveFundingAccount)/\(e.paymentChannel.displayName)")

            // An older shared expense where Me typed 0 stays a normal shared split (not reinterpreted).
            let old = Expense(amount: 10, merchant: "Old split"); ctx.insert(old)
            ctx.insert(ExpenseShare(expense: old, isMe: true, nameSnapshot: "Me", amountMinor: 0, enteredMinor: 0, sortIndex: 0))
            ctx.insert(ExpenseShare(expense: old, person: bijoy, nameSnapshot: "Bijoy", amountMinor: 1000, enteredMinor: 1000, sortIndex: 1))
            old.splitMethod = .amounts
            try? ctx.save()
            t.check("Existing expenses keep working: an old split with Me typed as 0 stays 'shared' and still counts (Bijoy +RM10)",
                    SplitDraft(expense: old)?.purpose == .shared && net(bijoy) == 1699,
                    expected: "shared, 1699", actual: "\(String(describing: SplitDraft(expense: old)?.purpose)) \(net(bijoy))")

            _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 300, allocations: [(debt("BIJOYSHARIARALAMIN", bijoy), 300)],
                                                     currency: "RM", in: ctx)
            let payload = UserDataBackupService.makePayload(from: ctx)
            let data = try? UserDataBackupService.makeEncoder().encode(payload)
            let decoded = data.flatMap { try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
            let target = TestKit.context()
            if let decoded { UserDataBackupService.applyBackupPayload(decoded, into: target); try? target.save() }
            let restoredPerson = TestKit.fetch(PayBookProfile.self, in: target).first
            let restoredDebt = restoredPerson.flatMap { DebtLedger.debts(for: $0).first { $0.title == "BIJOYSHARIARALAMIN" } }
            t.check("Backup format 4 keeps settlements: after restore the RM6.99 debt shows RM3.00 paid, RM3.99 left",
                    decoded?.version == 4 && decoded?.settlementAllocations?.count == 1 && restoredDebt?.settledMinor == 300 &&
                    restoredDebt?.outstandingMinor == 399,
                    expected: "v4, 300 paid, 399 left", actual: "\(String(describing: decoded?.version)) \(String(describing: restoredDebt?.outstandingMinor))")
        }
        return results
    }
}

/// Optional demo data: empty by default, loads once, removes only registered sample records.
/// `--run-sample-data-tests`
@MainActor
public struct SampleDataTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Sample data") { results.append($0) }
        func net(_ name: String, _ ctx: ModelContext) -> Int {
            TestKit.fetch(PayBookProfile.self, in: ctx).first { $0.name == name }.map { PersonLedger.balances(for: $0)["RM"] ?? 0 } ?? 0
        }

        let ctx = TestKit.context()
        t.check("A fresh store has no sample data, no transactions and no people (nothing is inserted automatically)",
                !SampleData.isLoaded(in: ctx) && TestKit.count(Expense.self, in: ctx) == 0 && TestKit.count(PayBookProfile.self, in: ctx) == 0 &&
                TestKit.count(SampleDataRecord.self, in: ctx) == 0,
                expected: "empty", actual: "\(TestKit.count(Expense.self, in: ctx)) expenses")

        // Real data first
        let bijoy = PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
        let maybank = Account(name: "Maybank", type: .bank); ctx.insert(maybank)
        let real = DebtSettlementTests.paidFor(bijoy, 10000, "Real dinner", in: ctx)
        real.account = maybank
        _ = try? SettlementService.recordPayment(person: bijoy, direction: 1, amountMinor: 3000,
                                                 allocations: [(DebtLedger.debts(for: bijoy)[0], 3000)], currency: "RM", in: ctx)
        let realNet = PersonLedger.balances(for: bijoy)["RM"] ?? 0

        let loaded = SampleData.load(into: ctx)
        let counts = [TestKit.count(Expense.self, in: ctx), TestKit.count(PayBookProfile.self, in: ctx), TestKit.count(MoneyMovement.self, in: ctx),
                      TestKit.count(SettlementAllocation.self, in: ctx), TestKit.count(SampleDataRecord.self, in: ctx)]
        let mei = TestKit.fetch(PayBookProfile.self, in: ctx).first { $0.name == "Mei Ling (Sample)" }
        t.check("Load Sample Data adds the demo set (8 expenses, 3 people, loan, 3 payments, 21 registered records) with correct balances and credit",
                loaded && counts == [9, 4, 5, 4, 21] && net("Aiman (Sample)", ctx) == 12000 && net("Ravi (Sample)", ctx) == 25000 &&
                net("Mei Ling (Sample)", ctx) == -3500 && mei.map { DebtLedger.creditMinor(for: $0, currency: "RM", direction: 1) } == 1000 &&
                PersonLedger.balances(for: bijoy)["RM"] == realNet,
                expected: "[9,4,5,4,21], 120/250/−35, credit 10", actual: "\(counts) \(net("Aiman (Sample)", ctx)) \(net("Ravi (Sample)", ctx)) \(net("Mei Ling (Sample)", ctx))")

        let again = SampleData.load(into: ctx)
        t.check("Loading again adds nothing (no second copy)", !again && TestKit.count(Expense.self, in: ctx) == 9 && TestKit.count(SampleDataRecord.self, in: ctx) == 21,
                expected: "false, unchanged", actual: "\(again) \(TestKit.count(Expense.self, in: ctx))")

        // A real record that uses a sample person: that person must survive removal.
        let aiman = TestKit.fetch(PayBookProfile.self, in: ctx).first { $0.name == "Aiman (Sample)" }!
        let realWithAiman = DebtSettlementTests.paidFor(aiman, 1500, "Real lunch with Aiman", in: ctx)

        let report = SampleData.remove(from: ctx)
        let names = Set(TestKit.fetch(Expense.self, in: ctx).map(\.merchant))
        t.check("Remove Sample Data removes only sample records: real expenses, Bijoy, his repayment and settlement, and Maybank remain; Bijoy's balance unchanged",
                names == ["Real dinner", "Real lunch with Aiman"] && TestKit.fetch(PayBookProfile.self, in: ctx).contains { $0.id == bijoy.id } &&
                PersonLedger.balances(for: bijoy)["RM"] == realNet && DebtLedger.debts(for: bijoy).first?.settledMinor == 3000 &&
                TestKit.fetch(Account.self, in: ctx).map(\.name) == ["Maybank"] && TestKit.count(SampleDataRecord.self, in: ctx) == 0,
                expected: "2 real expenses, Bijoy intact", actual: "\(names.sorted()) accounts=\(TestKit.fetch(Account.self, in: ctx).map(\.name))")
        t.check("A sample person used by a real expense is kept (with that expense); unused sample people and all sample money records go",
                report.peopleKept == 1 && report.peopleRemoved == 2 && TestKit.fetch(PayBookProfile.self, in: ctx).contains { $0.id == aiman.id } &&
                realWithAiman.shares.contains { $0.person?.id == aiman.id } && net("Aiman (Sample)", ctx) == 1500 &&
                TestKit.count(MoneyMovement.self, in: ctx) == 1,
                expected: "Aiman kept with RM15; only Bijoy's repayment left", actual: "\(report)")

        let reloaded = SampleData.load(into: ctx)
        let secondRemove = SampleData.remove(from: ctx)
        t.check("Load → Remove → Load works; removing again leaves the real data exactly as it was",
                reloaded && secondRemove.expensesRemoved == 8 && Set(TestKit.fetch(Expense.self, in: ctx).map(\.merchant)) == names &&
                PersonLedger.balances(for: bijoy)["RM"] == realNet && !SampleData.isLoaded(in: ctx),
                expected: "reload ok, real intact", actual: "\(reloaded) \(secondRemove.expensesRemoved)")
        return results
    }
}

/// PayBook "They Owe Me / I Owe Them": grouping and order come only from the canonical net balance.
/// `--run-paybook-filter-tests`
@MainActor
public struct PayBookFilterTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "PayBook filter") { results.append($0) }
        let ctx = TestKit.context()
        func person(_ name: String) -> PayBookProfile { DebtSettlementTests.person(name, in: ctx) }
        /// `payer` paid `minor` entirely for me.
        @discardableResult
        func paidForMe(_ payer: PayBookProfile, _ minor: Int, _ title: String, daysAgo: Int = 0) -> Expense {
            let e = Expense(amount: Money.majorAmount(fromMinor: minor), merchant: title, date: Date(timeIntervalSince1970: 1_790_000_000 - Double(daysAgo) * 86_400))
            ctx.insert(e)
            var d = SplitDraft(); d.purpose = .paidFor; d.payer = payer; d.apply(to: e, in: ctx)
            try? ctx.save()
            return e
        }
        func names(_ filter: PayBookBalanceFilter) -> [String] { PersonLedger.outstanding(TestKit.fetch(PayBookProfile.self, in: ctx), filter: filter).map(\.person.name) }
        func amounts(_ filter: PayBookBalanceFilter) -> [Int] { PersonLedger.outstanding(TestKit.fetch(PayBookProfile.self, in: ctx), filter: filter).map(\.amountMinor) }

        let bijoy = person("Bijoy"), kamal = person("Kamal"), riyad = person("Riyad")
        let labib = person("Labib"), karim = person("Karim"), rahim = person("Rahim"), settled = person("Settled Sam")
        DebtSettlementTests.paidFor(bijoy, 10899, "Bijoy dinner", daysAgo: 5, in: ctx)
        let kamalExpense = DebtSettlementTests.paidFor(kamal, 9999, "Kamal ticket", daysAgo: 4, in: ctx)
        let riyadExpense = DebtSettlementTests.paidFor(riyad, 4370, "Riyad lunch", daysAgo: 3, in: ctx)
        paidForMe(labib, 8000, "Labib paid", daysAgo: 5)
        paidForMe(karim, 4500, "Karim paid", daysAgo: 4)
        paidForMe(rahim, 2000, "Rahim paid", daysAgo: 3)
        DebtSettlementTests.paidFor(settled, 1000, "Sam coffee", in: ctx)
        _ = try? SettlementService.markPaid(DebtLedger.debts(for: settled)[0], person: settled, in: ctx)

        t.check("They Owe Me: only people with a positive balance, highest first (Bijoy 108.99, Kamal 99.99, Riyad 43.70)",
                names(.theyOweMe) == ["Bijoy", "Kamal", "Riyad"] && amounts(.theyOweMe) == [10899, 9999, 4370],
                expected: "Bijoy, Kamal, Riyad", actual: "\(names(.theyOweMe)) \(amounts(.theyOweMe))")
        t.check("I Owe Them: only people I owe, highest first (Labib 80, Karim 45, Rahim 20)",
                names(.iOweThem) == ["Labib", "Karim", "Rahim"] && amounts(.iOweThem) == [8000, 4500, 2000],
                expected: "Labib, Karim, Rahim", actual: "\(names(.iOweThem)) \(amounts(.iOweThem))")
        t.check("A settled person (RM 0) is in neither list; All shows nothing here (it keeps the existing grouped list)",
                !names(.theyOweMe).contains("Settled Sam") && !names(.iOweThem).contains("Settled Sam") && names(.all).isEmpty &&
                PersonLedger.hasHistory(settled),
                expected: "not listed, history kept", actual: "\(names(.theyOweMe)) \(names(.iOweThem))")
        let canonical = TestKit.fetch(PayBookProfile.self, in: ctx).allSatisfy { p in
            let row = PersonLedger.outstanding([p], filter: .theyOweMe).first ?? PersonLedger.outstanding([p], filter: .iOweThem).first
            return (row.map { $0.amountMinor } ?? 0) == abs(PersonLedger.balances(for: p)["RM"] ?? 0)
        }
        t.check("Amounts are exactly the canonical net balances (FinancialCalculator), no second calculation", canonical,
                expected: "equal", actual: "\(canonical)")

        // Ties: same amount → most recent activity first
        let older = person("Older"), newer = person("Newer")
        DebtSettlementTests.paidFor(older, 5000, "Old", daysAgo: 20, in: ctx)
        DebtSettlementTests.paidFor(newer, 5000, "New", daysAgo: 1, in: ctx)
        t.check("Same amount: the person with the most recent activity comes first",
                names(.theyOweMe).filter { ["Older", "Newer"].contains($0) } == ["Newer", "Older"],
                expected: "Newer, Older", actual: "\(names(.theyOweMe))")

        // Crossing zero
        _ = try? SettlementService.settleAll(person: bijoy, currency: "RM", in: ctx)
        let afterPayment = names(.theyOweMe).contains("Bijoy") || names(.iOweThem).contains("Bijoy")
        paidForMe(bijoy, 2000, "Bijoy paid for me")
        t.check("Bijoy pays in full → leaves They Owe Me (settled); a new expense he paid for me → appears under I Owe Them with RM 20",
                !afterPayment && names(.iOweThem).contains("Bijoy") && !names(.theyOweMe).contains("Bijoy") &&
                PersonLedger.outstanding([bijoy], filter: .iOweThem).first?.amountMinor == 2000,
                expected: "settled, then I owe 20", actual: "\(names(.iOweThem))")
        DebtSettlementTests.paidFor(labib, 10000, "I paid for Labib", in: ctx)
        t.check("Labib: I owed 80, then I paid 100 for him → he moves to They Owe Me with RM 20",
                names(.theyOweMe).contains("Labib") && !names(.iOweThem).contains("Labib") &&
                PersonLedger.outstanding([labib], filter: .theyOweMe).first?.amountMinor == 2000,
                expected: "They Owe Me 20", actual: "\(names(.theyOweMe))")

        // Editing and deleting transactions
        kamalExpense.amount = 120
        SplitDraft.recalculateAfterAmountChange(kamalExpense, in: ctx)
        ctx.delete(riyadExpense)
        try? ctx.save()
        t.check("Editing Kamal's expense to RM 120 moves him to the top; deleting Riyad's only expense removes him",
                names(.theyOweMe).first == "Kamal" && amounts(.theyOweMe).first == 12000 && !names(.theyOweMe).contains("Riyad"),
                expected: "Kamal first (120), no Riyad", actual: "\(names(.theyOweMe)) \(amounts(.theyOweMe))")
        return results
    }
}

/// "Split Transaction" inside Add Expense, end to end: the draft the inline section edits, the save gate
/// (only a split that adds up exactly can be saved), PayBook balances through the one canonical calculation,
/// editing, removing people, deleting, and settling. In-memory stores only. `--run-split-transaction-tests`
@MainActor
public enum SplitTransactionTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Split transaction") { results.append($0) }
        let ctx = TestKit.context()
        func person(_ name: String) -> PayBookProfile { DebtSettlementTests.person(name, in: ctx) }
        func net(_ p: PayBookProfile) -> Int { DebtSettlementTests.net(p) }
        /// What Add Expense does on Save: the expense is created only when the split is valid, then the split is applied.
        func save(_ minor: Int, _ title: String, _ draft: SplitDraft?) -> Expense? {
            if let draft, !draft.isValid(totalMinor: minor) { return nil }
            let e = Expense(amount: Money.majorAmount(fromMinor: minor), merchant: title, category: .food, paymentChannel: .duitNowQR, fundingAccount: "Maybank")
            ctx.insert(e)
            draft?.apply(to: e, in: ctx)
            try? ctx.save()
            return e
        }
        func custom(_ draft: inout SplitDraft, _ amounts: [String], total: Int) {
            draft.useCustomAmounts(totalMinor: total)
            draft.autoCalculate = false
            for (index, text) in amounts.enumerated() { draft.setAmountText(text, for: draft.participants[index].id, totalMinor: total) }
        }
        func shares(_ e: Expense?) -> [String: Int] {
            Dictionary((e?.shares ?? []).map { ($0.isMe ? "Me" : $0.nameSnapshot, $0.amountMinor) }, uniquingKeysWith: { a, b in a + b })
        }

        let bijoy = person("Bijoy"), riyad = person("Riyad")
        try? ctx.save()

        // 1 + 15. Normal transaction, no split
        let normal = save(4500, "Groceries", nil)
        t.check("1. Normal transaction without a split: saved as before, no shares, my share is the whole amount, nobody's PayBook balance changes",
                normal?.isShared == false && normal?.myShareMinor == 4500 && net(bijoy) == 0 && net(riyad) == 0,
                expected: "not shared, 45.00 mine, balances 0", actual: "\(String(describing: normal?.isShared)) \(String(describing: normal?.myShareMinor)) \(net(bijoy))")

        // 2. Two-person equal split
        var equal = SplitDraft(); equal.add(bijoy)
        let dinnerEqual = save(10000, "Dinner equal", equal)
        t.check("2. Two-person equal split: RM100 → You RM50, Bijoy RM50; Bijoy owes me RM50",
                shares(dinnerEqual) == ["Me": 5000, "Bijoy": 5000] && net(bijoy) == 5000,
                expected: "50/50, +50", actual: "\(shares(dinnerEqual)) \(net(bijoy))")

        // 3 + 9. Two-person custom splits (70/30 and 40/60)
        var c1 = SplitDraft(); c1.add(bijoy); custom(&c1, ["70", "30"], total: 10000)
        let dinner7030 = save(10000, "Dinner 70/30", c1)
        let after7030 = net(bijoy)
        var c2 = SplitDraft(); c2.add(bijoy); custom(&c2, ["40", "60"], total: 10000)
        let dinner4060 = save(10000, "Dinner 40/60", c2)
        t.check("3/9. Custom split: I paid RM100, my share RM70 → Bijoy owes me RM30 more; my share RM40 → Bijoy owes me RM60 more",
                shares(dinner7030) == ["Me": 7000, "Bijoy": 3000] && dinner7030?.myShareMinor == 7000 && after7030 == 8000 &&
                shares(dinner4060) == ["Me": 4000, "Bijoy": 6000] && net(bijoy) == 14000,
                expected: "+30 (total 80), +60 (total 140)", actual: "\(after7030) \(net(bijoy))")

        // 4. Several people
        let ctxPeople = (a: person("Person A"), b: person("Person B"), c: person("Person C"))
        var many = SplitDraft(); many.add(ctxPeople.a); many.add(ctxPeople.b); many.add(ctxPeople.c)
        custom(&many, ["100", "80", "70", "50"], total: 30000)
        let big = save(30000, "Trip", many)
        t.check("4. Multi-person split: RM300 → You 100, A 80, B 70, C 50; each person's PayBook balance is their own share",
                big != nil && net(ctxPeople.a) == 8000 && net(ctxPeople.b) == 7000 && net(ctxPeople.c) == 5000 && big?.myShareMinor == 10000,
                expected: "80, 70, 50", actual: "\(net(ctxPeople.a)) \(net(ctxPeople.b)) \(net(ctxPeople.c))")

        // 5–7. Allocation must equal the total exactly
        var exact = SplitDraft(); exact.add(bijoy); exact.add(riyad); custom(&exact, ["60", "30", "10"], total: 10000)
        var short = SplitDraft(); short.add(bijoy); custom(&short, ["60", "20"], total: 10000)
        var over = SplitDraft(); over.add(bijoy); custom(&over, ["80", "40"], total: 10000)
        t.check("5. Allocated RM100 of RM100 (60 + 30 + 10): remaining 0, valid",
                exact.remainingMinor(totalMinor: 10000) == 0 && exact.isValid(totalMinor: 10000),
                expected: "0, valid", actual: "\(exact.remainingMinor(totalMinor: 10000))")
        let countBefore = TestKit.count(Expense.self, in: ctx)
        let blockedShort = save(10000, "Short", short), blockedOver = save(10000, "Over", over)
        t.check("6. Allocated RM80 of RM100: remaining RM20, can't be saved, says it's short; the total stays RM100",
                short.remainingMinor(totalMinor: 10000) == 2000 && !short.isValid(totalMinor: 10000) && blockedShort == nil &&
                (short.problem(totalMinor: 10000) ?? "") == "RM 20.00 remains unassigned.",
                expected: "20 left, blocked", actual: "\(short.remainingMinor(totalMinor: 10000)) \(short.problem(totalMinor: 10000) ?? "nil")")
        t.check("7. Allocated RM120 of RM100: clear error ('exceed'), can't be saved, nothing written",
                over.remainingMinor(totalMinor: 10000) == -2000 && blockedOver == nil && (over.problem(totalMinor: 10000) ?? "").contains("exceed") &&
                TestKit.count(Expense.self, in: ctx) == countBefore,
                expected: "−20, blocked", actual: "\(over.problem(totalMinor: 10000) ?? "nil") \(TestKit.count(Expense.self, in: ctx) - countBefore) written")

        // 8. Rounding: integer cents, the sum is always the total
        var thirds = SplitDraft(); thirds.add(bijoy); thirds.add(riyad)
        let thirdShares = thirds.shares(totalMinor: 10000) ?? []
        var fifty = SplitDraft(); fifty.add(bijoy); fifty.add(riyad)
        var prefilled = thirds; prefilled.useCustomAmounts(totalMinor: 10000)
        t.check("8. RM100 ÷ 3 → 33.34 + 33.33 + 33.33 = 100.00 (never 99.99); RM150 ÷ 3 = 50 each; switching to Custom Amount starts from those exact shares",
                thirdShares.reduce(0, +) == 10000 && Set(thirdShares) == [3333, 3334] && fifty.shares(totalMinor: 15000) == [5000, 5000, 5000] &&
                prefilled.method == .amounts && prefilled.assignedMinor() == 10000 && prefilled.isValid(totalMinor: 10000),
                expected: "sum 10000; 5000×3; prefilled valid", actual: "\(thirdShares) \(String(describing: fifty.shares(totalMinor: 15000))) \(prefilled.assignedMinor())")

        // 10. Someone else paid: I owe them
        let ctx2 = TestKit.context()
        let bijoy2 = DebtSettlementTests.person("Bijoy", in: ctx2)
        var theyPaid = SplitDraft(); theyPaid.add(bijoy2); theyPaid.payer = bijoy2
        theyPaid.useCustomAmounts(totalMinor: 10000); theyPaid.autoCalculate = false
        theyPaid.setAmountText("70", for: theyPaid.participants[0].id); theyPaid.setAmountText("30", for: theyPaid.participants[1].id)
        let lunch = Expense(amount: 100, merchant: "Lunch"); ctx2.insert(lunch); theyPaid.apply(to: lunch, in: ctx2)
        var paidForMe = SplitDraft(); paidForMe.purpose = .paidFor; paidForMe.payer = bijoy2
        let taxi = Expense(amount: 20, merchant: "Taxi"); ctx2.insert(taxi); paidForMe.apply(to: taxi, in: ctx2)
        try? ctx2.save()
        t.check("10. Bijoy paid RM100, my share RM70 → I owe Bijoy RM70; he also paid a RM20 taxi for me → I owe RM90 (negative balance = I owe)",
                DebtSettlementTests.net(bijoy2) == -9000 && !lunch.paidByMe && lunch.myShareMinor == 7000,
                expected: "−9000", actual: "\(DebtSettlementTests.net(bijoy2))")

        // 11. Editing: new total, new shares
        var edit = SplitDraft(expense: dinnerEqual!)!
        let bijoyBeforeEdit = net(bijoy)
        dinnerEqual!.amount = 120
        edit.useCustomAmounts(totalMinor: 12000)
        edit.setAmountText("90", for: edit.participants[0].id); edit.setAmountText("30", for: edit.participants[1].id)
        let editValid = edit.isValid(totalMinor: 12000)
        edit.apply(to: dinnerEqual!, in: ctx); try? ctx.save()
        t.check("11. Editing a split: total RM100 → RM120, shares 90/30 → Bijoy's balance goes from +50 to +30 for this dinner; still two shares",
                editValid && shares(dinnerEqual) == ["Me": 9000, "Bijoy": 3000] && net(bijoy) == bijoyBeforeEdit - 2000 && dinnerEqual!.shares.count == 2,
                expected: "90/30, −20 for Bijoy", actual: "\(shares(dinnerEqual)) \(bijoyBeforeEdit) → \(net(bijoy))")

        // 12. Removing a participant
        var three = SplitDraft(); three.add(bijoy); three.add(riyad)
        let cinema = save(9000, "Cinema", three)!
        let riyadWith = net(riyad), bijoyWith = net(bijoy)
        var removing = SplitDraft(expense: cinema)!
        removing.remove(id: removing.participants.first { $0.person?.id == riyad.id }!.id)
        removing.useEqualSplit(); removing.apply(to: cinema, in: ctx); try? ctx.save()
        t.check("12. Removing Riyad from a RM90 three-way split: his RM30 share is gone, Bijoy's share becomes RM45; Riyad's profile is kept",
                riyadWith - net(riyad) == 3000 && net(bijoy) - bijoyWith == 1500 && cinema.shares.count == 2 &&
                !cinema.shares.contains { $0.person?.id == riyad.id } && TestKit.fetch(PayBookProfile.self, in: ctx).contains { $0.id == riyad.id },
                expected: "Riyad −30, Bijoy +15", actual: "\(riyadWith) → \(net(riyad)), \(bijoyWith) → \(net(bijoy))")

        // 13. Deleting a split transaction
        let bijoyBeforeDelete = net(bijoy)
        let expensesBefore = TestKit.count(Expense.self, in: ctx)
        ctx.delete(dinner4060!); try? ctx.save()
        t.check("13. Deleting a split: its RM60 is removed from Bijoy's balance and its shares are removed; Bijoy and every other transaction stay",
                bijoyBeforeDelete - net(bijoy) == 6000 && TestKit.count(Expense.self, in: ctx) == expensesBefore - 1 &&
                normal?.modelContext != nil && TestKit.fetch(PayBookProfile.self, in: ctx).contains { $0.id == bijoy.id } &&
                !TestKit.fetch(ExpenseShare.self, in: ctx).contains { $0.expense == nil },
                expected: "−60, one expense fewer, no orphan shares", actual: "\(bijoyBeforeDelete) → \(net(bijoy))")

        // 14. Settling
        let ctx3 = TestKit.context()
        let bijoy3 = DebtSettlementTests.person("Bijoy", in: ctx3)
        var s3 = SplitDraft(); s3.add(bijoy3)
        s3.useCustomAmounts(totalMinor: 10000); s3.autoCalculate = false
        s3.setAmountText("70", for: s3.participants[0].id); s3.setAmountText("30", for: s3.participants[1].id)
        let meal = Expense(amount: 100, merchant: "Dinner"); ctx3.insert(meal); s3.apply(to: meal, in: ctx3); try? ctx3.save()
        let owedBefore = DebtSettlementTests.net(bijoy3)
        if let debt = DebtLedger.debts(for: bijoy3).first { _ = try? SettlementService.markPaid(debt, person: bijoy3, in: ctx3) }
        try? ctx3.save()
        t.check("14. Bijoy owes RM30 from the split; recording that he paid RM30 → balance RM0, debt settled, the dinner is kept",
                owedBefore == 3000 && DebtSettlementTests.net(bijoy3) == 0 && DebtLedger.debts(for: bijoy3).allSatisfy { $0.outstandingMinor == 0 } &&
                TestKit.count(Expense.self, in: ctx3) == 1 && meal.shares.count == 2,
                expected: "30 → 0, dinner kept", actual: "\(owedBefore) → \(DebtSettlementTests.net(bijoy3))")

        // 15. Non-split transactions untouched by all of the above
        t.check("15. The normal transaction is unchanged after all split saves, edits and deletes",
                normal?.amount == 45 && normal?.isShared == false && normal?.myShareMinor == 4500,
                expected: "45.00, not shared", actual: "\(String(describing: normal?.amount)) \(String(describing: normal?.isShared))")

        // 16–17. Saving the same split again never duplicates anything
        let ctx4 = TestKit.context()
        let bijoy4 = DebtSettlementTests.person("Bijoy", in: ctx4)
        var again = SplitDraft(); again.add(bijoy4)
        let pizza = Expense(amount: 60, merchant: "Pizza"); ctx4.insert(pizza)
        again.apply(to: pizza, in: ctx4); try? ctx4.save()
        var reopened = SplitDraft(expense: pizza)!
        reopened.apply(to: pizza, in: ctx4); again.apply(to: pizza, in: ctx4); try? ctx4.save()
        t.check("16. Saving a split three times: Bijoy is owed RM30 once (one debt, one balance), not three times",
                DebtSettlementTests.net(bijoy4) == 3000 && DebtLedger.debts(for: bijoy4).count == 1,
                expected: "3000, 1 debt", actual: "\(DebtSettlementTests.net(bijoy4)) \(DebtLedger.debts(for: bijoy4).count)")
        reopened = SplitDraft(expense: pizza)!
        let addedTwice = reopened.add(bijoy4)
        t.check("17. No duplicate split rows: still exactly 2 shares on the expense and in the store; adding Bijoy again is refused",
                pizza.shares.count == 2 && TestKit.count(ExpenseShare.self, in: ctx4) == 2 && !addedTwice && reopened.participants.count == 2,
                expected: "2, 2, refused", actual: "\(pizza.shares.count) \(TestKit.count(ExpenseShare.self, in: ctx4)) \(addedTwice)")

        // 18. Screenshot import: OCR amount → split on the review screen → one save
        let ctx5 = TestKit.context()
        let bijoy5 = DebtSettlementTests.person("Bijoy", in: ctx5), riyad5 = DebtSettlementTests.person("Riyad", in: ctx5)
        let parsed = TransactionParser.shared.parse(ocrResult: PDFReceiptImporter.ocrResult(from: ClassifierEvaluation.tng("DuitNow QR", "RESTORAN SELERA KAMPUNG", "100.00")))
        let review = ShareExtensionViewModel()
        review.splitDraft = SplitDraft()
        review.applyParsedTransaction(parsed)
        let resetOnNewScreenshot = review.splitDraft == nil
        var split = SplitDraft(); split.add(bijoy5); split.add(riyad5)
        let ocrMinor = Money.minorUnits(from: parsed.amount ?? 0)
        split.useCustomAmounts(totalMinor: ocrMinor); split.autoCalculate = false
        split.setAmountText("40", for: split.participants[0].id); split.setAmountText("30", for: split.participants[1].id)
        split.setAmountText("30", for: split.participants[2].id)
        review.splitDraft = split
        let imported = Expense(amount: parsed.amount ?? 0, merchant: parsed.merchant ?? "", category: review.selectedCategory,
                               paymentChannel: review.selectedPaymentChannel, fundingAccount: review.fundingAccount)
        ctx5.insert(imported)
        let attached = review.splitDraft?.apply(to: imported, in: ctx5) ?? false
        try? ctx5.save()
        t.check("18. Screenshot import: OCR reads RM100 (DuitNow QR, Touch 'n Go); split 40/30/30 before saving → one expense of RM100 with 3 shares; Bijoy and Riyad each owe RM30; a new screenshot starts unsplit",
                resetOnNewScreenshot && ocrMinor == 10000 && attached && imported.amount == 100 && imported.myShareMinor == 4000 &&
                imported.paymentChannel == .duitNowQR && imported.fundingAccount == "Touch 'n Go" && imported.shares.count == 3 &&
                DebtSettlementTests.net(bijoy5) == 3000 && DebtSettlementTests.net(riyad5) == 3000 && TestKit.count(Expense.self, in: ctx5) == 1,
                expected: "RM100, mine 40, 30 + 30", actual: "\(ocrMinor) \(imported.myShareMinor) \(DebtSettlementTests.net(bijoy5)) \(DebtSettlementTests.net(riyad5)) \(imported.paymentChannel) \(imported.fundingAccount)")
        var wrong = split; wrong.setAmountText("50", for: wrong.participants[0].id)
        let mismatch = Expense(amount: 100, merchant: "X"); ctx5.insert(mismatch)
        let wrongApplied = wrong.apply(to: mismatch, in: ctx5)
        t.check("19. A split that doesn't match the OCR amount (RM110 of RM100) is never saved and never changes the amount",
                !wrong.isValid(totalMinor: 10000) && !wrongApplied && mismatch.shares.isEmpty && mismatch.amount == 100,
                expected: "blocked, RM100 kept", actual: "\(wrongApplied) \(mismatch.amount)")
        return results
    }
}

/// Amounts: Auto Calculate (per split, default ON) and Fixed Amounts (base + equal part of the remainder).
/// In-memory stores and fixed amounts only. `--run-auto-calculate-tests`
@MainActor
public enum AutoCalculateTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Auto Calculate & fixed") { results.append($0) }
        let ctx = TestKit.context()
        let vijay = DebtSettlementTests.person("Vijay", in: ctx), riyadh = DebtSettlementTests.person("Riyadh", in: ctx)
        func threeWay(total: Int) -> SplitDraft {
            var d = SplitDraft(); d.add(vijay); d.add(riyadh); d.useCustomAmounts(totalMinor: total); return d
        }
        func id(_ d: SplitDraft, _ name: String) -> UUID { d.participants.first { $0.isMe ? name == "Me" : $0.name == name }!.id }

        // 24. Regression: typing one person's amount never makes Me RM0
        var reg = SplitDraft(); reg.method = .amounts; reg.add(vijay); reg.add(riyadh)
        reg.setAmountText("50", for: id(reg, "Vijay"), totalMinor: 20000)
        let regShares = reg.shares(totalMinor: 20000) ?? []
        var regPrefilled = threeWay(total: 20000)
        regPrefilled.setAmountText("50", for: id(regPrefilled, "Vijay"), totalMinor: 20000)
        t.check("24. RM200 shared by Me, Vijay, Riyadh; Vijay typed RM50 → the rest (RM150) is shared by Me and Riyadh: 75 + 75. Me is never RM0",
                regShares == [7500, 5000, 7500] && regPrefilled.shares(totalMinor: 20000) == [7500, 5000, 7500] &&
                reg.displayAmountText(for: id(reg, "Me"), totalMinor: 20000) == "75.00",
                expected: "[7500, 5000, 7500]", actual: "\(regShares) \(String(describing: regPrefilled.shares(totalMinor: 20000)))")

        // 22. Fixed amount: base + equal part of the remainder, everyone still shares the remainder
        var fixed = threeWay(total: 20000)
        let fixedSaved = fixed.setFixed(5000, for: id(fixed, "Vijay"), totalMinor: 20000)
        t.check("22. RM200, Vijay fixed RM50 → fixed 50, shared 150 by all three → Me 50, Vijay 100, Riyadh 50 (total exactly RM200)",
                fixedSaved && fixed.shares(totalMinor: 20000) == [5000, 10000, 5000] && fixed.fixedTotalMinor == 5000 &&
                fixed.remainingMinor(totalMinor: 20000) == 0 && fixed.isValid(totalMinor: 20000),
                expected: "[5000, 10000, 5000]", actual: "\(String(describing: fixed.shares(totalMinor: 20000)))")

        // 25. Several fixed amounts
        var multi = threeWay(total: 30000)
        multi.setFixed(6000, for: id(multi, "Vijay"), totalMinor: 30000); multi.setFixed(4000, for: id(multi, "Riyadh"), totalMinor: 30000)
        let multiShares = multi.shares(totalMinor: 30000) ?? []
        t.check("25. RM300, Vijay fixed 60, Riyadh fixed 40 → RM200 shared by 3 (66.67 + 66.67 + 66.66, extra sen to Me) → Me 66.67, Vijay 126.67, Riyadh 106.66; sum exactly RM300",
                multiShares == [6667, 12667, 10666] && multiShares.reduce(0, +) == 30000,
                expected: "[6667, 12667, 10666]", actual: "\(multiShares)")

        // 9. Fixed amount for Me
        var mine = threeWay(total: 20000)
        mine.setFixed(6000, for: id(mine, "Me"), totalMinor: 20000)
        let mineShares = mine.shares(totalMinor: 20000) ?? []
        t.check("9. RM200, Me fixed RM60 → RM140 shared by 3 → Me 106.67, Vijay 46.67, Riyadh 46.66; sum exactly RM200",
                mineShares == [10667, 4667, 4666] && mineShares.reduce(0, +) == 20000,
                expected: "[10667, 4667, 4666]", actual: "\(mineShares)")

        // 26. Decimal amounts and fixed amounts with sen
        var cents = threeWay(total: 15050)
        cents.setFixed(5050, for: id(cents, "Vijay"), totalMinor: 15050)
        var typedCents = threeWay(total: 10000)
        typedCents.setAmountText("33.33", for: id(typedCents, "Vijay"), totalMinor: 10000)
        typedCents.setAmountText("66.67", for: id(typedCents, "Riyadh"), totalMinor: 10000)
        t.check("26. Sen are kept: RM150.50 with Vijay fixed RM50.50 → 33.34 + 83.83 + 33.33; typed 33.33 and 66.67 of RM100 → Me 0.00 calculated, exact",
                cents.shares(totalMinor: 15050) == [3334, 8383, 3333] && typedCents.shares(totalMinor: 10000) == [0, 3333, 6667] &&
                Money.minorUnits(parsing: "50.50") == 5050,
                expected: "[3334, 8383, 3333] / [0, 3333, 6667]", actual: "\(String(describing: cents.shares(totalMinor: 15050))) \(String(describing: typedCents.shares(totalMinor: 10000)))")

        // 27. Rounding is deterministic and exact
        let roundA = threeWay(total: 10000).shares(totalMinor: 10000) ?? [], roundB = threeWay(total: 10000).shares(totalMinor: 10000) ?? []
        t.check("27. RM100 among 3 → 33.34 / 33.33 / 33.33 (the extra sen always to Me, the payer), never 99.99 or 100.01",
                roundA == [3334, 3333, 3333] && roundA == roundB && roundA.reduce(0, +) == 10000,
                expected: "[3334, 3333, 3333]", actual: "\(roundA)")

        // 18. Fixed amount validation
        var tooMuch = threeWay(total: 10000)
        tooMuch.setFixed(8000, for: id(tooMuch, "Vijay"), totalMinor: 10000); tooMuch.setFixed(3000, for: id(tooMuch, "Riyadh"), totalMinor: 10000)
        var negative = threeWay(total: 10000)
        let negativeRefused = !negative.setFixed(-1000, for: id(negative, "Vijay"), totalMinor: 10000)
        var exactFixed = threeWay(total: 10000)
        exactFixed.setFixed(6000, for: id(exactFixed, "Vijay"), totalMinor: 10000); exactFixed.setFixed(4000, for: id(exactFixed, "Riyadh"), totalMinor: 10000)
        t.check("18. Fixed 80 + 30 of RM100 → 'Fixed amounts exceed the expense total by RM 10.00.' (not saved); a negative fixed amount is refused; fixed 60 + 40 = RM100 → valid, Me 0 calculated",
                tooMuch.problem(totalMinor: 10000) == "Fixed amounts exceed the expense total by RM 10.00." && !tooMuch.isValid(totalMinor: 10000) &&
                negativeRefused && negative.participants.allSatisfy { $0.fixedMinor == nil } &&
                exactFixed.shares(totalMinor: 10000) == [0, 6000, 4000],
                expected: "exceed message, refused, [0, 6000, 4000]", actual: "\(tooMuch.problem(totalMinor: 10000) ?? "nil") \(String(describing: exactFixed.shares(totalMinor: 10000)))")

        // 19. Money left with nobody to give it to
        var allTyped = SplitDraft(); allTyped.method = .amounts; allTyped.add(vijay); allTyped.add(riyadh)
        for (name, text) in [("Me", "70"), ("Vijay", "50"), ("Riyadh", "50")] { allTyped.setAmountText(text, for: id(allTyped, name)) }
        t.check("19. Everyone typed (70 + 50 + 50 of RM200): RM30 is never given away silently → asks for someone to take the remainder",
                (allTyped.problem(totalMinor: 20000) ?? "").hasPrefix("RM 30.00 remains unassigned. Select at least one participant") &&
                !allTyped.isValid(totalMinor: 20000),
                expected: "remains unassigned + select", actual: allTyped.problem(totalMinor: 20000) ?? "nil")

        // 23 + 2 + 15. Auto Calculate is per split: every new split starts ON; OFF changes nothing by itself
        let firstNew = SplitDraft()
        var off = threeWay(total: 20000)
        off.setAutoCalculate(false, totalMinor: 20000)
        let frozen = off.participants.map(\.amountText)
        off.setAmountText("70", for: id(off, "Me"), totalMinor: 20000)
        off.setAmountText("50", for: id(off, "Vijay"), totalMinor: 20000)
        off.setAmountText("50", for: id(off, "Riyadh"), totalMinor: 20000)
        let offShort = off.problem(totalMinor: 20000), offRemaining = off.remainingMinor(totalMinor: 20000)
        let afterTyping = off.participants.map(\.amountText)
        off.setAmountText("80", for: id(off, "Riyadh"), totalMinor: 20000)
        let saved = Expense(amount: 200, merchant: "Dinner"); ctx.insert(saved)
        let savedOK = off.apply(to: saved, in: ctx); try? ctx.save()
        let secondNew = SplitDraft(), fromLastTime = SplitDraft.lastTimeSuggestion(merchant: "Dinner", in: ctx)
        t.check("23. New split → Auto Calculate ON. Turned OFF: the shown amounts freeze (66.67/66.67/66.66); 70/50/50 stays 70/50/50 with 'RM 30.00 remains unassigned.'; 70/50/80 saves",
                firstNew.autoCalculate && frozen == ["66.67", "66.67", "66.66"] && afterTyping == ["70", "50", "50"] && offRemaining == 3000 &&
                offShort == "RM 30.00 remains unassigned." && savedOK && saved.shares.sorted { $0.sortIndex < $1.sortIndex }.map(\.amountMinor) == [7000, 5000, 8000],
                expected: "ON; frozen; untouched; RM30 unassigned; saved", actual: "\(firstNew.autoCalculate) \(frozen) \(afterTyping) \(offShort ?? "nil")")
        t.check("15. OFF applied to that split only: the next new split (and a 'same as last time' suggestion) starts with Auto Calculate ON; nothing is stored as a setting",
                secondNew.autoCalculate && (fromLastTime?.autoCalculate ?? true) && !off.autoCalculate,
                expected: "ON, ON", actual: "\(secondNew.autoCalculate) \(String(describing: fromLastTime?.autoCalculate))")

        // 3/14. ON recalculates when the total or a fixed amount changes
        var live = threeWay(total: 20000)
        live.setFixed(5000, for: id(live, "Vijay"), totalMinor: 20000)
        let at200 = live.shares(totalMinor: 20000) ?? [], at230 = live.shares(totalMinor: 23000) ?? []
        live.setFixed(nil, for: id(live, "Vijay"), totalMinor: 23000)
        let cleared = live.shares(totalMinor: 23000) ?? []
        t.check("ON follows changes: total RM200 → RM230 with Vijay fixed 50 → 60/110/60; removing the fixed amount → equal 76.67/76.67/76.66",
                at200 == [5000, 10000, 5000] && at230 == [6000, 11000, 6000] && cleared == [7667, 7667, 7666],
                expected: "recalculated", actual: "\(at230) \(cleared)")

        // 20. Saved shares are the final amounts
        let dinner = Expense(amount: 200, merchant: "Fixed dinner"); ctx.insert(dinner)
        fixed.apply(to: dinner, in: ctx); try? ctx.save()
        let stored = dinner.shares.sorted { $0.sortIndex < $1.sortIndex }.map(\.amountMinor)
        let reopened = SplitDraft(expense: dinner)
        t.check("20. Saved shares hold the final amounts (5000 / 10000 / 5000 = 20000); reopening shows them unchanged with Auto Calculate OFF (nothing recalculated)",
                stored == [5000, 10000, 5000] && stored.reduce(0, +) == dinner.amountMinor && reopened?.autoCalculate == false &&
                reopened?.shares(totalMinor: 20000) == [5000, 10000, 5000] && DebtSettlementTests.net(vijay) >= 10000,
                expected: "[5000, 10000, 5000]", actual: "\(stored) \(String(describing: reopened?.shares(totalMinor: 20000)))")

        // 10. Paid for someone keeps its own rule (my share 0) and has no fixed amounts
        var paidFor = SplitDraft(); paidFor.purpose = .paidFor; paidFor.method = .amounts; paidFor.add(vijay)
        let paidForShares = paidFor.shares(totalMinor: 10000)
        t.check("10. Paid for Someone is unchanged: I paid RM100 for Vijay → Me 0, Vijay 100",
                paidForShares == [0, 10000], expected: "[0, 10000]", actual: "\(String(describing: paidForShares))")

        // 21. Existing expenses load exactly as saved
        let old = Expense(amount: 90, merchant: "Old amounts"); ctx.insert(old)
        var oldDraft = SplitDraft(); oldDraft.method = .amounts; oldDraft.autoCalculate = false; oldDraft.add(vijay)
        oldDraft.setAmountText("60", for: oldDraft.participants[0].id); oldDraft.setAmountText("30", for: oldDraft.participants[1].id)
        oldDraft.apply(to: old, in: ctx); try? ctx.save()
        let before = old.shares.map(\.amountMinor).sorted()
        let loaded = SplitDraft(expense: old)!
        t.check("21. An existing Amounts expense opens with its exact shares, Auto Calculate OFF and no fixed amounts inferred",
                loaded.shares(totalMinor: 9000) == [6000, 3000] && !loaded.autoCalculate && loaded.participants.allSatisfy { $0.fixedMinor == nil } &&
                old.shares.map(\.amountMinor).sorted() == before,
                expected: "[6000, 3000], OFF", actual: "\(String(describing: loaded.shares(totalMinor: 9000)))")
        return results
    }
}

/// One Split Money everywhere: the same SplitDraft rules for Add, Edit, scan review, Share Extension (screenshots and
/// PDFs) — payer independent of allocations, empty custom box = RM 0, floating amount reported, exact persistence
/// through a store re-open. `--run-split-everywhere-tests`
@MainActor
public enum SplitEverywhereTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Split everywhere") { results.append($0) }
        let ctx = TestKit.context()
        let riyad = DebtSettlementTests.person("Riyad", in: ctx), bijoy = DebtSettlementTests.person("Bijoy", in: ctx)
        try? ctx.save()
        func id(_ d: SplitDraft, _ name: String) -> UUID { d.participants.first { name == "Me" ? $0.isMe : $0.name == name }!.id }
        func custom(_ amounts: [(String, String)], payer: PayBookProfile? = nil, people: [PayBookProfile] = []) -> SplitDraft {
            var d = SplitDraft()
            for p in people.isEmpty ? [riyad] : people { d.add(p) }
            d.payer = payer
            d.useCustomAmounts(totalMinor: 10000)
            d.setAutoCalculate(false, totalMinor: 10000)
            for (who, text) in amounts { d.setAmountText(text, for: id(d, who), totalMinor: 10000) }
            return d
        }
        func save(_ d: SplitDraft?, title: String, in c: ModelContext) -> Expense {
            let e = Expense(amount: 100, merchant: title, category: .food, paymentChannel: .duitNowQR, fundingAccount: "Touch 'n Go")
            c.insert(e)
            d?.apply(to: e, in: c)
            try? c.save()
            return e
        }
        func shares(_ e: Expense) -> [String: Int] {
            Dictionary(e.shares.map { ($0.isMe ? "Me" : $0.nameSnapshot, $0.amountMinor) }, uniquingKeysWith: { a, b in a + b })
        }

        // 1. Split OFF, paid by Me
        let plain = save(nil, title: "Plain", in: ctx)
        t.check("1. RM100, split off, paid by Me → normal transaction (no shares, my spending RM100)",
                !plain.isShared && plain.paidByMe && plain.myShareMinor == 10000, expected: "normal", actual: "\(plain.shares.count) shares")

        // 2. Equal You + Riyad
        var equal = SplitDraft(); equal.add(riyad)
        t.check("2. Equal split You + Riyad → 50 / 50", equal.shares(totalMinor: 10000) == [5000, 5000],
                expected: "[5000, 5000]", actual: "\(String(describing: equal.shares(totalMinor: 10000)))")

        // 3. Custom 40/60
        let c4060 = custom([("Me", "40"), ("Riyad", "60")])
        t.check("3. Custom You 40 / Riyad 60 → remaining RM0, valid", c4060.remainingMinor(totalMinor: 10000) == 0 && c4060.isValid(totalMinor: 10000),
                expected: "0, valid", actual: "\(c4060.remainingMinor(totalMinor: 10000))")

        // 4. Paid by Riyad, You 0 (left empty), Riyad 100 — the screenshot case
        let screenshot = custom([("Me", ""), ("Riyad", "100")], payer: riyad)
        let screenshotMe = custom([("Me", ""), ("Riyad", "100")])
        t.check("4. Paid by Riyad (or Me), You left empty, Riyad RM100 → valid; no 'Enter an amount for Me'",
                screenshot.problem(totalMinor: 10000) == nil && screenshot.shares(totalMinor: 10000) == [0, 10000] &&
                screenshotMe.problem(totalMinor: 10000) == nil,
                expected: "valid", actual: "\(screenshot.problem(totalMinor: 10000) ?? "valid") / \(screenshotMe.problem(totalMinor: 10000) ?? "valid")")

        // 5. Paid by Riyad, You 40, Riyad 60
        let riyadPaid = custom([("Me", "40"), ("Riyad", "60")], payer: riyad)
        t.check("5. Paid by Riyad, You 40 / Riyad 60 → valid; I owe Riyad RM40", riyadPaid.isValid(totalMinor: 10000) && riyadPaid.myShareMinor(totalMinor: 10000) == 4000,
                expected: "valid, mine 4000", actual: "\(String(describing: riyadPaid.myShareMinor(totalMinor: 10000)))")

        // 6. Floating
        let floating = custom([("Me", "40"), ("Riyad", "50")])
        let floatingExpense = Expense(amount: 100, merchant: "Floating"); ctx.insert(floatingExpense)
        let floatingSaved = floating.apply(to: floatingExpense, in: ctx)
        t.check("6. You 40 / Riyad 50 of RM100 → RM10 remains unassigned; not saved, not given to anyone",
                floating.remainingMinor(totalMinor: 10000) == 1000 && floating.problem(totalMinor: 10000) == "RM 10.00 remains unassigned." &&
                !floatingSaved && floatingExpense.shares.isEmpty,
                expected: "RM10 unassigned, blocked", actual: "\(floating.problem(totalMinor: 10000) ?? "nil")")

        // 7 + 8. Share Extension (screenshots) and PDF use the same view model + SplitDraft + apply
        let shareVM = ShareExtensionViewModel()
        let screenshotParsed = TransactionParser.shared.parse(ocrResult: PDFReceiptImporter.ocrResult(from: ClassifierEvaluation.tng("DuitNow QR", "RESTORAN TEST", "100.00")))
        shareVM.applyParsedTransaction(screenshotParsed)
        shareVM.splitDraft = riyadPaid
        let pdfParsed = TransactionParser.shared.parse(ocrResult: PDFReceiptImporter.ocrResult(from: ["Maybank", "DuitNow QR", "Successful", "RM 100.00", "Recipient", "KEDAI PDF", "Reference ID", "QR12345678"]))
        let pdfVM = ShareExtensionViewModel()
        pdfVM.applyParsedTransaction(pdfParsed)
        pdfVM.splitDraft = screenshot
        t.check("7/8. Share Extension (screenshot) and PDF reviews hold a full SplitDraft (payer, custom amounts) before saving",
                shareVM.splitDraft?.payer?.id == riyad.id && shareVM.splitDraft?.isValid(totalMinor: Money.minorUnits(from: screenshotParsed.amount ?? 0)) == true &&
                pdfVM.splitDraft?.isValid(totalMinor: Money.minorUnits(from: pdfParsed.amount ?? 0)) == true,
                expected: "valid drafts", actual: "\(String(describing: screenshotParsed.amount)) \(String(describing: pdfParsed.amount))")

        // 9–11. Persist an imported expense, re-open the store, edit, change payer
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SplitEverywhere-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        let schema = ExpenseDataContainer.currentSchema
        var expenseID = UUID()
        do {
            let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            if let container {
                let c = ModelContext(container)
                let r = PayBookProfile(name: "Riyad"); c.insert(r)
                var d = SplitDraft(); d.add(r); d.payer = r
                d.useCustomAmounts(totalMinor: 10000); d.setAutoCalculate(false, totalMinor: 10000)
                d.setAmountText("40", for: d.participants[0].id, totalMinor: 10000); d.setAmountText("60", for: d.participants[1].id, totalMinor: 10000)
                let e = Expense(amount: 100, merchant: "Imported", sourceType: .shareExtension, paymentChannel: .duitNowQR, fundingAccount: "Touch 'n Go")
                c.insert(e); d.apply(to: e, in: c); try? c.save()
                expenseID = e.id
            }
        }
        var reopened = "open failed", restored = false, payerChanged = false, balanceAfter = 0
        if let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]) {
            let c = ModelContext(container)
            if let e = TestKit.fetch(Expense.self, in: c).first(where: { $0.id == expenseID }), let r = e.payer {
                let draft = SplitDraft(expense: e)
                reopened = "payer=\(r.name) paidByMe=\(e.paidByMe) shares=\(shares(e)) channel=\(e.paymentChannel.rawValue) funding=\(e.fundingAccount)"
                restored = !e.paidByMe && r.name == "Riyad" && shares(e) == ["Me": 4000, "Riyad": 6000] && e.paymentChannel == .duitNowQR &&
                    e.fundingAccount == "Touch 'n Go" && draft?.payer?.id == r.id && draft?.shares(totalMinor: 10000) == [4000, 6000] && draft?.method == .amounts
                // 11. Change payer Riyad → Me; allocations unchanged
                if var edit = draft {
                    edit.payer = nil
                    edit.apply(to: e, in: c); try? c.save()
                    payerChanged = e.paidByMe && e.payer == nil && shares(e) == ["Me": 4000, "Riyad": 6000]
                    balanceAfter = PersonLedger.balances(for: r)["RM"] ?? 0
                }
            }
        }
        t.check("9. Imported expense (paid by Riyad, You 40 / Riyad 60) is exactly the same after closing and re-opening the store",
                restored, expected: "Riyad, 4000/6000, DuitNow QR, Touch 'n Go", actual: reopened)
        t.check("10. Edit restores the same split: payer Riyad, Custom Amount, 40 / 60", restored, expected: "restored", actual: reopened)
        t.check("11. Changing the payer Riyad → You keeps the allocations; Riyad now owes me RM60",
                payerChanged && balanceAfter == 6000, expected: "40/60 kept, +6000", actual: "\(payerChanged) \(balanceAfter)")

        // 12. Remove a participant
        var three = SplitDraft(); three.add(riyad); three.add(bijoy)
        let before = three.shares(totalMinor: 10000)
        three.remove(id: id(three, "Bijoy"))
        t.check("12. Removing Bijoy from an equal split of 3 → the remaining two split it 50 / 50",
                before == [3334, 3333, 3333] && three.shares(totalMinor: 10000) == [5000, 5000],
                expected: "[5000, 5000]", actual: "\(String(describing: three.shares(totalMinor: 10000)))")

        // 13. Add a participant (Auto Calculate ON → the new person shares the rest)
        var adding = SplitDraft(); adding.add(riyad)
        adding.useCustomAmounts(totalMinor: 10000)
        adding.add(bijoy)
        t.check("13. Adding a person to a custom split with Auto Calculate ON → shared equally again (exact sen)",
                adding.shares(totalMinor: 10000) == [3334, 3333, 3333], expected: "[3334, 3333, 3333]",
                actual: "\(String(describing: adding.shares(totalMinor: 10000)))")

        // 14. Equal among 3 → exact sen
        var equal3 = SplitDraft(); equal3.add(riyad); equal3.add(bijoy)
        let e3 = equal3.shares(totalMinor: 10000) ?? []
        t.check("14. RM100 equally among You, Riyad, Bijoy → 33.34 / 33.33 / 33.33 = RM100.00 exactly",
                e3 == [3334, 3333, 3333] && e3.reduce(0, +) == 10000, expected: "[3334, 3333, 3333]", actual: "\(e3)")
        return results
    }
}
