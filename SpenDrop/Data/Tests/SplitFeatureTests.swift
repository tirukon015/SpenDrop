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
                    exact == [2000, 3000, 5000] && problem == "RM 10.00 left to assign." && !applied && expense.shares.isEmpty,
                    expected: "[2000,3000,5000]; 'RM 10.00 left to assign.'; not applied",
                    actual: "exact=\(exact ?? []) problem=\(problem ?? "nil") applied=\(applied) shares=\(expense.shares.count)")
            draft.setAmountText("60", for: ids[2])
            t.check("Exact amounts over the total are reported", draft.problem(totalMinor: 10000) == "Amounts are RM 10.00 more than the total.",
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
