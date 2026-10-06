import Foundation
import SwiftData

/// Phase 5: PayBook people, calculated balances, history, record payment, archive/delete safety. `--run-people-tests`
@MainActor
public struct PeopleBalanceTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 5") { results.append($0) }

        func person(_ ctx: ModelContext, _ name: String) -> PayBookProfile {
            let p = PayBookProfile(name: name); ctx.insert(p); return p
        }
        func movement(_ ctx: ModelContext, _ kind: MoneyMovementKind, _ minor: Int, _ p: PayBookProfile, currency: String = "RM") -> MoneyMovement {
            let m = MoneyMovement(kind: kind, amountMinor: minor, currency: currency, person: p); ctx.insert(m); return m
        }
        func shared(_ ctx: ModelContext, _ amount: Double, payer: PayBookProfile?, with others: [PayBookProfile], currency: String = "RM") -> Expense {
            let e = Expense(amount: amount, currency: currency, merchant: "Dinner"); ctx.insert(e)
            var d = SplitDraft(); others.forEach { d.add($0) }; d.payer = payer; d.apply(to: e, in: ctx)
            return e
        }

        // Loan, repayment received, direction flip
        do {
            let ctx = TestKit.context()
            let shadin = person(ctx, "Shadin")
            _ = movement(ctx, .loanGiven, 15000, shadin)
            _ = movement(ctx, .loanGiven, 5000, shadin)
            try? ctx.save()
            let afterLoans = PersonLedger.balances(for: shadin)["RM"]
            _ = movement(ctx, .repaymentReceived, 10000, shadin)
            try? ctx.save()
            let afterRepay = PersonLedger.balances(for: shadin)["RM"]
            _ = movement(ctx, .repaymentReceived, 12000, shadin)
            try? ctx.save()
            let flipped = PersonLedger.balances(for: shadin)["RM"]
            t.check("Loan 150+50, repaid 100 -> owes 100; overpays 120 -> I owe 20 (direction flips)",
                    afterLoans == 20000 && afterRepay == 10000 && flipped == -2000 &&
                    PersonLedger.directionText(name: "Shadin", balanceMinor: flipped ?? 0, currency: "RM") == "You owe Shadin RM 20.00",
                    expected: "20000, 10000, -2000 ('You owe Shadin RM 20.00')",
                    actual: "\(afterLoans ?? 0), \(afterRepay ?? 0), \(flipped ?? 0)")
        }
        // Loans are not spending
        do {
            let ctx = TestKit.context()
            let shadin = person(ctx, "Shadin")
            let loan = movement(ctx, .loanGiven, 15000, shadin)
            let s = FinancialCalculator.summary(expenses: [], movements: [loan])
            t.check("Loan RM150: Money Out 150, spending 0", s.moneyOutMinor == 15000 && s.spendingMinor == 0,
                    expected: "out 15000, spending 0", actual: "out \(s.moneyOutMinor), spending \(s.spendingMinor)")
        }
        // Shared expense both ways + repayment made -> zero
        do {
            let ctx = TestKit.context()
            let bijoy = person(ctx, "Bijoy"), riyad = person(ctx, "Riyad")
            _ = shared(ctx, 30, payer: nil, with: [bijoy, riyad])             // each owes me 10
            _ = shared(ctx, 60, payer: bijoy, with: [bijoy, riyad])           // I owe Bijoy 20
            try? ctx.save()
            let bijoyBefore = PersonLedger.balances(for: bijoy)["RM"]
            let riyadBalance = PersonLedger.balances(for: riyad)["RM"]
            _ = movement(ctx, .repaymentMade, 1000, bijoy)
            try? ctx.save()
            let bijoyAfter = PersonLedger.balances(for: bijoy)
            t.check("Shared: Bijoy +10 -20 = I owe 10; repayment made 10 -> settled; Riyad owes 10",
                    bijoyBefore == -1000 && bijoyAfter.isEmpty && riyadBalance == 1000,
                    expected: "Bijoy -1000 then settled; Riyad 1000",
                    actual: "bijoy \(bijoyBefore ?? 0) -> \(bijoyAfter), riyad \(riyadBalance ?? 0)")
        }
        // Multiple currencies stay separate
        do {
            let ctx = TestKit.context()
            let ali = person(ctx, "Ali")
            _ = shared(ctx, 20, payer: nil, with: [ali])                      // RM 10 owed
            _ = shared(ctx, 40, payer: nil, with: [ali], currency: "USD")     // USD 20 owed
            _ = movement(ctx, .loanReceived, 500, ali, currency: "SGD")       // I owe SGD 5
            try? ctx.save()
            let b = PersonLedger.balances(for: ali)
            t.check("Balances are per currency (never mixed)", b == ["RM": 1000, "USD": 2000, "SGD": -500],
                    expected: "RM 1000, USD 2000, SGD -500", actual: "\(b)")
        }
        // Summary, history and snapshots
        do {
            let ctx = TestKit.context()
            let a = person(ctx, "A"), b = person(ctx, "B"), c = person(ctx, "C"), d = person(ctx, "D")
            _ = movement(ctx, .loanGiven, 1000, a)
            _ = movement(ctx, .loanReceived, 400, b)
            _ = movement(ctx, .loanGiven, 300, c); _ = movement(ctx, .repaymentReceived, 300, c)
            _ = d
            try? ctx.save()
            let s = PersonLedger.summary(of: [a, b, c, d])
            t.check("PayBook summary: owed to me / I owe / settled (people without history ignored)",
                    s.owedToMe == ["RM": 1000] && s.iOwe == ["RM": 400] && s.settledCount == 1 && s.owingMeCount == 1 && s.iOweCount == 1,
                    expected: "owed 1000, owe 400, 1 settled", actual: "\(s)")

            let loan = a.movements.first!
            a.name = "A renamed"
            let entries = PersonLedger.entries(for: a)
            t.check("History lists the loan with its effect; snapshot keeps the old name",
                    entries.count == 1 && entries[0].effectMinor == 1000 && loan.personNameSnapshot == "A",
                    expected: "1 entry +1000, snapshot 'A'", actual: "entries=\(entries.map(\.effectMinor)) snapshot=\(loan.personNameSnapshot ?? "nil")")
        }
        do {
            let ctx = TestKit.context()
            let bijoy = person(ctx, "Bijoy"), riyad = person(ctx, "Riyad")
            _ = shared(ctx, 30, payer: bijoy, with: [bijoy, riyad])
            try? ctx.save()
            let riyadEntries = PersonLedger.entries(for: riyad)
            let bijoyEntries = PersonLedger.entries(for: bijoy)
            t.check("History: expense paid by someone else shows for both, affects only the payer",
                    riyadEntries.count == 1 && riyadEntries[0].effectMinor == 0 && bijoyEntries.first?.effectMinor == -1000,
                    expected: "Riyad entry 0; Bijoy entry -1000", actual: "\(riyadEntries.map(\.effectMinor)) / \(bijoyEntries.map(\.effectMinor))")
        }
        // Record payment prefill
        do {
            let ctx = TestKit.context()
            let owesMe = person(ctx, "Owes"), iOwe = person(ctx, "Owed")
            _ = movement(ctx, .loanGiven, 7550, owesMe)
            _ = movement(ctx, .loanReceived, 2000, iOwe)
            try? ctx.save()
            let received = PersonLedger.repaymentDraft(for: owesMe, currency: "RM")
            let made = PersonLedger.repaymentDraft(for: iOwe, currency: "RM")
            let none = PersonLedger.repaymentDraft(for: owesMe, currency: "USD")
            var savedOK = false
            if let received {
                let saved = received.insertMovement(into: ctx)
                try? ctx.save()
                savedOK = saved != nil && PersonLedger.balances(for: owesMe).isEmpty
            }
            t.check("Record payment: they owe me -> Repayment Received 75.50; I owe -> Repayment Made 20.00; saving settles",
                    received?.kind == .repaymentReceived && received?.amountText == "75.50" && received?.person === owesMe &&
                    made?.kind == .repaymentMade && made?.amountText == "20.00" && none == nil && savedOK,
                    expected: "received 75.50, made 20.00, settles", actual: "\(received?.kind.rawValue ?? "nil") \(received?.amountText ?? "") / \(made?.kind.rawValue ?? "nil") \(made?.amountText ?? "") settled=\(savedOK)")
        }
        // Archive and delete safety
        do {
            let ctx = TestKit.context()
            let frequent = person(ctx, "F"), other = person(ctx, "O"), archived = person(ctx, "Z")
            frequent.isFrequent = true
            archived.isArchived = true
            _ = movement(ctx, .loanGiven, 500, archived)
            try? ctx.save()
            let g = PayBookGrouping.groups([frequent, other, archived])
            t.check("Grouping: Frequent / Other / Archived; archived person keeps their balance",
                    g.frequent.map(\.name) == ["F"] && g.other.map(\.name) == ["O"] && g.archived.map(\.name) == ["Z"] &&
                    PersonLedger.balances(for: archived)["RM"] == 500,
                    expected: "[F] [O] [Z], Z owes 500", actual: "\(g.frequent.map(\.name)) \(g.other.map(\.name)) \(g.archived.map(\.name))")
            t.check("Delete blocked while a balance exists; allowed when zero",
                    !PersonLedger.canDelete(archived) && PersonLedger.canDelete(other),
                    expected: "Z blocked, O allowed", actual: "Z=\(PersonLedger.canDelete(archived)) O=\(PersonLedger.canDelete(other))")
        }
        do {
            let ctx = TestKit.context()
            let p = person(ctx, "Temp")
            let e = shared(ctx, 20, payer: nil, with: [p])
            _ = movement(ctx, .repaymentReceived, 1000, p)
            try? ctx.save()
            let allowed = PersonLedger.canDelete(p)
            ctx.delete(p)
            try? ctx.save()
            t.check("Deleting a settled person keeps expenses, shares and money records (with snapshots)",
                    allowed && TestKit.count(Expense.self, in: ctx) == 1 && e.shares.count == 2 &&
                    e.shares.first { !$0.isMe }?.nameSnapshot == "Temp" && TestKit.count(MoneyMovement.self, in: ctx) == 1,
                    expected: "allowed; 1 expense, 2 shares, 1 movement kept", actual: "allowed=\(allowed) shares=\(e.shares.count) movements=\(TestKit.count(MoneyMovement.self, in: ctx))")
        }

        return results
    }
}
