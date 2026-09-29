import Foundation
import SwiftData

/// Phase 6: unified Transactions timeline (calculated feed of Expense + MoneyMovement). `--run-timeline-tests`
@MainActor
public struct ActivityFeedTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 6") { results.append($0) }

        let ctx = TestKit.context()
        let now = Date()
        let maybank = Account(name: "Maybank", type: .bank), tng = Account(name: "Touch 'n Go", type: .eWallet)
        let bijoy = PayBookProfile(name: "Bijoy")
        ctx.insert(maybank); ctx.insert(tng); ctx.insert(bijoy)

        let lunch = Expense(amount: 25, merchant: "McDonald's", date: now.addingTimeInterval(-3600))
        let dinner = Expense(amount: 30, merchant: "Dinner", date: now.addingTimeInterval(-7200))
        ctx.insert(lunch); ctx.insert(dinner)
        lunch.account = maybank
        var split = SplitDraft(); split.add(bijoy); split.payer = bijoy; split.apply(to: dinner, in: ctx)

        let salary = MoneyMovement(kind: .income, amountMinor: 300000, date: now.addingTimeInterval(-60), account: maybank, note: "Salary")
        let loan = MoneyMovement(kind: .loanGiven, amountMinor: 15000, date: now.addingTimeInterval(-120), person: bijoy, account: maybank)
        let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, date: now.addingTimeInterval(-180), account: maybank, counterAccount: tng)
        let refund = MoneyMovement(kind: .refund, amountMinor: 500, date: now.addingTimeInterval(-240), linkedExpense: lunch)
        [salary, loan, transfer, refund].forEach { ctx.insert($0) }
        try? ctx.save()

        let expenses = [lunch, dinner]
        var movements = [salary, loan, transfer, refund]
        func ids(_ f: ActivityFilter, newestFirst: Bool = true) -> [UUID] {
            ActivityFeed.items(expenses: expenses, movements: movements, filter: f, newestFirst: newestFirst).map(\.id)
        }

        t.check("All: every expense and movement once, newest first",
                ids(.all) == [salary.id, loan.id, transfer.id, refund.id, lunch.id, dinner.id],
                expected: "salary, loan, transfer, refund, lunch, dinner", actual: "\(ids(.all).count) items")
        t.check("Sorting oldest first reverses the order", ids(.all, newestFirst: false) == ids(.all).reversed(),
                expected: "reversed", actual: "\(ids(.all, newestFirst: false) == ids(.all).reversed())")
        t.check("Expenses filter", ids(.expenses) == [lunch.id, dinner.id], expected: "lunch, dinner", actual: "\(ids(.expenses).count)")
        t.check("Money In filter (income + refund)", ids(.moneyIn) == [salary.id, refund.id], expected: "salary, refund", actual: "\(ids(.moneyIn).count)")
        t.check("Money Out filter (loan; transfers excluded)", ids(.moneyOut) == [loan.id], expected: "loan", actual: "\(ids(.moneyOut).count)")
        t.check("Shared filter", ids(.shared) == [dinner.id], expected: "dinner", actual: "\(ids(.shared).count)")
        t.check("Transfers filter", ids(.transfers) == [transfer.id], expected: "transfer", actual: "\(ids(.transfers).count)")

        let duplicated = ActivityFeed.items(expenses: expenses + expenses, movements: movements + movements, filter: .all)
        t.check("No duplicate timeline entries (refund linked to lunch appears once, lunch once)",
                duplicated.count == 6 && Set(duplicated.map(\.id)).count == 6,
                expected: "6 unique", actual: "\(duplicated.count)")

        // Editing moves a record between filters; deleting removes it
        loan.kind = .repaymentReceived
        let afterEdit = (ids(.moneyIn).contains(loan.id), ids(.moneyOut).contains(loan.id))
        loan.kind = .loanGiven
        ctx.delete(refund)
        try? ctx.save()
        movements.removeAll { $0.id == refund.id }
        t.check("Editing a record moves it between filters; deleting removes it",
                afterEdit == (true, false) && !ids(.all).contains(refund.id) && TestKit.count(MoneyMovement.self, in: ctx) == 3,
                expected: "moved to Money In; refund gone", actual: "edit=\(afterEdit) remaining=\(TestKit.count(MoneyMovement.self, in: ctx))")

        // Engine: spending unchanged by movements; own transfer excluded; category filter hides movements
        let engine = TransactionFilterEngine()
        engine.selectedDateFilter = .today
        engine.update(expenses: expenses)
        engine.update(movements: movements)
        let summary = engine.cashFlowSummary
        t.check("Spent = 25 (lunch) + 15 (my share of dinner Bijoy paid); movements don't change spending",
                engine.totalSpending == 40 && summary.spendingMinor == 4000,
                expected: "40.00", actual: "\(engine.totalSpending)")
        t.check("Header In/Out: salary in; lunch + loan out; own transfer and Bijoy's payment excluded",
                summary.moneyInMinor == 300000 && summary.moneyOutMinor == 2500 + 15000,
                expected: "in 300000, out 17500", actual: "in \(summary.moneyInMinor), out \(summary.moneyOutMinor)")
        engine.searchText = "salary"
        let searched = engine.filteredMovements.map(\.id)
        engine.searchText = ""
        engine.selectedFundingAccounts = ["Touch 'n Go"]
        let byAccount = engine.filteredMovements.map(\.id)
        engine.selectedFundingAccounts = []
        engine.selectedCategories = [.food]
        let withCategory = engine.filteredMovements.count
        t.check("Engine filters movements by search and account (transfer matches its destination); category hides them",
                searched == [salary.id] && byAccount == [transfer.id] && withCategory == 0,
                expected: "[salary], [transfer], 0", actual: "search=\(searched.count) account=\(byAccount.count) category=\(withCategory)")

        return results
    }
}
