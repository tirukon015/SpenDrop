import Foundation
import SwiftData

/// Phase 2 checks for the financial models, calculations, backup V2 and the V1 -> V2 migration.
/// Runs only on in-memory stores and temporary folders. Launch argument: `--run-financial-tests`.
@MainActor
public struct FinancialModelTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        func check(_ name: String, _ passed: Bool, expected: String, actual: String) {
            results.append(TestCaseResult(testName: name, passed: passed, expected: expected, actual: actual, details: "Phase 2"))
        }
        func context() -> ModelContext {
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config])
            return ModelContext(container)
        }
        func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
            (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
        }
        func fetch<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> [T] {
            (try? ctx.fetch(FetchDescriptor<T>())) ?? []
        }

        /// Creates a shared expense with shares for Me + people, all inserted and linked.
        func sharedExpense(_ ctx: ModelContext, amount: Double, payer: PayBookProfile?, people: [PayBookProfile], merchant: String = "Dinner") -> Expense {
            let expense = Expense(amount: amount, merchant: merchant)
            ctx.insert(expense)
            expense.setPayer(payer)
            expense.splitMethod = .equal
            let participants = [SplitCalculator.Participant(isMe: true)] + people.map { _ in SplitCalculator.Participant() }
            let amounts = (try? SplitCalculator.calculate(totalMinor: expense.amountMinor, method: .equal, participants: participants,
                                                          iPaid: payer == nil).get()) ?? []
            for (index, amountMinor) in amounts.enumerated() {
                let person = index == 0 ? nil : people[index - 1]
                let share = ExpenseShare(person: person, isMe: index == 0, nameSnapshot: person?.name ?? "Me", amountMinor: amountMinor, sortIndex: index)
                ctx.insert(share)
                share.expense = expense
            }
            return expense
        }

        // MARK: Money conversion
        do {
            let cases: [(Double, Int)] = [(0, 0), (0.01, 1), (7.50, 750), (30, 3000), (100.99, 10099), (0.1 + 0.2, 30), (19.999, 2000), (42.90, 4290)]
            let actual = cases.map { Money.minorUnits(from: $0.0) }
            check("Money: Double -> sen", actual == cases.map(\.1),
                  expected: "\(cases.map(\.1))", actual: "\(actual)")
            let parsed = ["7.50", "RM 1,234.5", "0.01", "100.99", "abc", ""].map { Money.minorUnits(parsing: $0) }
            check("Money: text -> sen (exact decimal)", parsed == [750, 123450, 1, 10099, nil, nil],
                  expected: "[750, 123450, 1, 10099, nil, nil]", actual: "\(parsed)")
        }

        // MARK: Split calculator
        do {
            let me = SplitCalculator.Participant(isMe: true)
            let other = SplitCalculator.Participant()
            func split(_ total: Int, _ method: SplitMethod, _ ps: [SplitCalculator.Participant], iPaid: Bool = true) -> Result<[Int], SplitCalculator.SplitError> {
                SplitCalculator.calculate(totalMinor: total, method: method, participants: ps, iPaid: iPaid)
            }

            let equal = split(3000, .equal, [me, other, other, other])
            check("Split: equal RM30 / 4", equal == .success([750, 750, 750, 750]), expected: "750 x4", actual: "\(equal)")

            let odd = split(1000, .equal, [other, me, other])
            check("Split: odd sen goes to Me when I paid", odd == .success([333, 334, 333]), expected: "[333, 334, 333]", actual: "\(odd)")

            let oddOtherPaid = split(1000, .equal, [other, me, other], iPaid: false)
            check("Split: odd sen in list order when someone else paid", oddOtherPaid == .success([334, 333, 333]),
                  expected: "[334, 333, 333]", actual: "\(oddOtherPaid)")

            let sevenWay = split(10000, .equal, [me] + Array(repeating: other, count: 6))
            let sevenSum = (try? sevenWay.get())?.reduce(0, +)
            check("Split: 7-way RM100 totals exactly", sevenSum == 10000 && (try? sevenWay.get()) == [1429, 1429, 1429, 1429, 1428, 1428, 1428],
                  expected: "sum 10000, 4 leftover sen to Me then list order", actual: "\(sevenWay)")

            let parts = split(3000, .parts, [SplitCalculator.Participant(isMe: true, parts: 1), .init(parts: 1), .init(parts: 2), .init(parts: 1)])
            check("Split: parts 1/1/2/1", parts == .success([600, 600, 1200, 600]), expected: "[600, 600, 1200, 600]", actual: "\(parts)")

            let partsOdd = split(1000, .parts, [SplitCalculator.Participant(isMe: true, parts: 1), .init(parts: 2)])
            check("Split: parts with remainder", partsOdd == .success([333, 667]), expected: "[333, 667]", actual: "\(partsOdd)")

            let exact = split(3000, .amounts, [SplitCalculator.Participant(isMe: true, enteredMinor: 800), .init(enteredMinor: 700), .init(enteredMinor: 800), .init(enteredMinor: 700)])
            check("Split: exact amounts", exact == .success([800, 700, 800, 700]), expected: "[800, 700, 800, 700]", actual: "\(exact)")

            let mismatch = split(3000, .amounts, [SplitCalculator.Participant(isMe: true, enteredMinor: 800), .init(enteredMinor: 2199)])
            check("Split: total mismatch is an error (not adjusted)", mismatch == .failure(.amountsDoNotMatchTotal(differenceMinor: -1)),
                  expected: "difference -1", actual: "\(mismatch)")

            let zeroMe = split(3000, .amounts, [SplitCalculator.Participant(isMe: true, enteredMinor: 0), .init(enteredMinor: 3000)])
            check("Split: Me may have RM0", zeroMe == .success([0, 3000]), expected: "[0, 3000]", actual: "\(zeroMe)")

            let errors = [
                split(3000, .equal, [me]),
                split(3000, .equal, [other, other]),
                split(3000, .equal, [me, me]),
                split(0, .equal, [me, other]),
                split(3000, .parts, [SplitCalculator.Participant(isMe: true, parts: 0), .init(parts: 1)]),
                split(3000, .amounts, [SplitCalculator.Participant(isMe: true, enteredMinor: -1), .init(enteredMinor: 3001)])
            ]
            let expectedErrors: [Result<[Int], SplitCalculator.SplitError>] = [
                .failure(.tooFewParticipants), .failure(.missingMe), .failure(.moreThanOneMe),
                .failure(.nonPositiveTotal), .failure(.invalidParts(index: 0)), .failure(.negativeAmount(index: 0))
            ]
            check("Split: validation errors", errors == expectedErrors, expected: "\(expectedErrors)", actual: "\(errors)")
        }

        // MARK: Accounts and the linker
        do {
            let ctx = context()
            let a = Account(name: "Maybank", type: .bank)
            let b = Account(name: "Maybank", type: .bank)
            ctx.insert(a); ctx.insert(b)
            check("Account: each account has its own identity", a.id != b.id && a.nameKey == b.nameKey && a.nameKey == "maybank",
                  expected: "different ids, same name key", actual: "idsDiffer=\(a.id != b.id) key=\(a.nameKey ?? "nil")")
        }
        do {
            let ctx = context()
            let e1 = Expense(amount: 10, merchant: "A", fundingAccount: "Maybank")
            let e2 = Expense(amount: 20, merchant: "B", fundingAccount: " MAYBANK ")
            let e3 = Expense(amount: 30, merchant: "C", fundingAccount: "CIMB")
            let e4 = Expense(amount: 40, merchant: "D", fundingAccount: "Unknown")
            let e5 = Expense(amount: 50, merchant: "E", fundingAccount: "Other")
            let e6 = Expense(amount: 60, merchant: "F", fundingAccount: "Touch 'n Go")
            let e7 = Expense(amount: 70, merchant: "G", fundingAccount: "Cash")
            [e1, e2, e3, e4, e5, e6, e7].forEach { ctx.insert($0) }
            let first = AccountLinker.linkUnlinkedExpenses(in: ctx)
            try? ctx.save()
            let second = AccountLinker.linkUnlinkedExpenses(in: ctx)
            let accounts = fetch(Account.self, in: ctx)
            let names = accounts.sorted { $0.sortIndex < $1.sortIndex }.map(\.name)
            let passed = first.accountsCreated == 4 && first.expensesLinked == 5 && second.accountsCreated == 0 && second.expensesLinked == 0 &&
                e1.account === e2.account && e1.account?.name == "Maybank" && e3.account?.name == "CIMB" &&
                e4.account == nil && e5.account == nil &&
                e2.fundingAccount == " MAYBANK " && e4.fundingAccount == "Unknown"
            check("Account migration: one account per distinct value, unknowns unlinked, text preserved", passed,
                  expected: "4 accounts, 5 linked, rerun adds 0, Unknown/Other nil",
                  actual: "created=\(first.accountsCreated) linked=\(first.expensesLinked) rerun=\(second.accountsCreated)/\(second.expensesLinked) names=\(names) unknownLinked=\(e4.account != nil)")
            let types = [e1, e6, e7, e3].map { $0.account?.type }
            check("Account: type inferred (bank / e-wallet / cash)", types == [.bank, .eWallet, .cash, .bank],
                  expected: "[bank, eWallet, cash, bank]", actual: "\(types)")
            check("Account: inverse relationship lists expenses", e1.account?.expenses.count == 2,
                  expected: "Maybank has 2 expenses", actual: "\(e1.account?.expenses.count ?? -1)")
        }
        do {
            let ctx = context()
            let existing = Account(name: "Maybank", type: .bank)
            ctx.insert(existing)
            let manual = Expense(amount: 5, merchant: "Kept", fundingAccount: "CIMB")
            ctx.insert(manual)
            manual.account = existing
            AccountLinker.linkUnlinkedExpenses(in: ctx)
            check("Account linker never changes an existing link", manual.account === existing && count(Account.self, in: ctx) == 1,
                  expected: "link unchanged, no new account", actual: "account=\(manual.account?.name ?? "nil") accounts=\(count(Account.self, in: ctx))")
        }

        // MARK: Existing expenses keep working
        do {
            let ctx = context()
            let plain = Expense(amount: 25, merchant: "McDonald's", paymentSource: .maybank, fundingAccount: "Maybank")
            ctx.insert(plain)
            try? ctx.save()
            let passed = plain.paidByMe && plain.payer == nil && plain.splitMethod == nil && plain.shares.isEmpty &&
                plain.amountMinor == 2500 && plain.spendingMinor == 2500 && plain.cashOutMinor == 2500 && plain.myShareMinor == 2500 &&
                plain.fundingAccount == "Maybank" && plain.paymentSourceRaw == "Maybank"
            check("Expense: defaults keep a normal expense unchanged", passed,
                  expected: "paidByMe, no split, spending=cashOut=2500", actual: "spending=\(plain.spendingMinor) cashOut=\(plain.cashOutMinor) shared=\(plain.isShared)")
        }

        // MARK: Money movements
        do {
            let kinds = MoneyMovementKind.allCases.map { "\($0.rawValue)=\($0.direction.rawValue)" }
            let passed = MoneyMovementKind.income.direction == .moneyIn && MoneyMovementKind.refund.direction == .moneyIn &&
                MoneyMovementKind.loanGiven.direction == .moneyOut && MoneyMovementKind.repaymentMade.direction == .moneyOut &&
                MoneyMovementKind.ownTransfer.direction == .internal && MoneyMovementKind.allCases.count == 9
            check("MoneyMovement: kind -> direction", passed, expected: "in/out/internal as specified", actual: kinds.joined(separator: ","))
        }
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank", type: .bank)
            let tng = Account(name: "Touch 'n Go", type: .eWallet)
            let shadin = PayBookProfile(name: "Shadin")
            [maybank, tng].forEach { ctx.insert($0) }
            ctx.insert(shadin)
            let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, account: maybank, counterAccount: tng)
            let loan = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: shadin, account: maybank)
            let badTransfer = MoneyMovement(kind: .ownTransfer, amountMinor: 100, account: maybank, counterAccount: maybank)
            let noPerson = MoneyMovement(kind: .loanGiven, amountMinor: 100)
            let zero = MoneyMovement(kind: .income, amountMinor: 0)
            [transfer, loan, badTransfer, noPerson, zero].forEach { ctx.insert($0) }
            try? ctx.save()
            let relOK = transfer.account === maybank && transfer.counterAccount === tng && tng.incomingTransfers.contains { $0 === transfer } &&
                maybank.movements.contains { $0 === loan } && shadin.movements.contains { $0 === loan } && loan.personNameSnapshot == "Shadin"
            check("MoneyMovement: account, counter-account and person relationships", relOK,
                  expected: "links and inverses set, name snapshot", actual: "transferIn=\(tng.incomingTransfers.count) personMovements=\(shadin.movements.count) snapshot=\(loan.personNameSnapshot ?? "nil")")
            let issues = [transfer.validationIssues, loan.validationIssues, badTransfer.validationIssues, noPerson.validationIssues, zero.validationIssues]
            let expected: [[MoneyMovement.ValidationIssue]] = [[], [], [.sameTransferAccount], [.missingPerson], [.nonPositiveAmount]]
            check("MoneyMovement: validation", issues == expected, expected: "\(expected)", actual: "\(issues)")
        }

        // MARK: Financial calculations
        do {
            let ctx = context()
            let bijoy = PayBookProfile(name: "Bijoy"), riyad = PayBookProfile(name: "Riyad"), labib = PayBookProfile(name: "Labib")
            [bijoy, riyad, labib].forEach { ctx.insert($0) }

            let iPaid = sharedExpense(ctx, amount: 30, payer: nil, people: [bijoy, riyad, labib])
            let bijoyPaid = sharedExpense(ctx, amount: 30, payer: bijoy, people: [bijoy, riyad, labib])
            try? ctx.save()
            check("Shared expense I paid: spending 30, cash out 30, my share 7.50",
                  iPaid.spendingMinor == 3000 && iPaid.cashOutMinor == 3000 && iPaid.myShareMinor == 750 && iPaid.sharesMatchAmount,
                  expected: "3000/3000/750", actual: "\(iPaid.spendingMinor)/\(iPaid.cashOutMinor)/\(iPaid.myShareMinor)")
            check("Shared expense Bijoy paid: spending 7.50, cash out 0",
                  bijoyPaid.spendingMinor == 750 && bijoyPaid.cashOutMinor == 0 && bijoyPaid.payerNameSnapshot == "Bijoy" && !bijoyPaid.paidByMe,
                  expected: "750/0, payer snapshot Bijoy", actual: "\(bijoyPaid.spendingMinor)/\(bijoyPaid.cashOutMinor) \(bijoyPaid.payerNameSnapshot ?? "nil")")

            let ownWeek = Expense(amount: 400, merchant: "Week spending")
            ctx.insert(ownWeek)
            let received = MoneyMovement(kind: .repaymentReceived, amountMinor: 50000, person: bijoy)
            ctx.insert(received)
            let weekSummary = FinancialCalculator.summary(expenses: [ownWeek], movements: [received])
            check("Spend 400 + receive 500: spending 400, in 500, net +100",
                  weekSummary.spendingMinor == 40000 && weekSummary.moneyInMinor == 50000 && weekSummary.moneyOutMinor == 40000 && weekSummary.netCashFlowMinor == 10000,
                  expected: "40000/50000/40000/+10000",
                  actual: "\(weekSummary.spendingMinor)/\(weekSummary.moneyInMinor)/\(weekSummary.moneyOutMinor)/\(weekSummary.netCashFlowMinor)")

            let expenses450 = Expense(amount: 450, merchant: "Expenses")
            ctx.insert(expenses450)
            let loan = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: labib)
            let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000)
            let income = MoneyMovement(kind: .income, amountMinor: 100000)
            [loan, transfer, income].forEach { ctx.insert($0) }
            let s = FinancialCalculator.summary(expenses: [expenses450], movements: [loan, transfer, income])
            check("450 expenses + 150 loan (+ own transfer ignored): out 600, spending 450",
                  s.spendingMinor == 45000 && s.moneyOutMinor == 60000 && s.moneyInMinor == 100000 && s.netCashFlowMinor == 40000,
                  expected: "spending 45000, out 60000, in 100000, net +40000",
                  actual: "\(s.spendingMinor)/\(s.moneyOutMinor)/\(s.moneyInMinor)/\(s.netCashFlowMinor)")

            let ownOnly = FinancialCalculator.summary(expenses: [], movements: [transfer])
            check("Own transfer excluded from every total", ownOnly == FinancialCalculator.Summary(),
                  expected: "all zero", actual: "\(ownOnly)")

            let purchase = Expense(amount: 100, merchant: "Uniqlo")
            ctx.insert(purchase)
            let refund = MoneyMovement(kind: .refund, amountMinor: 3000, linkedExpense: purchase)
            ctx.insert(refund)
            try? ctx.save()
            let r = FinancialCalculator.summary(expenses: [purchase], movements: [refund])
            check("Refund: original expense unchanged, gross 100, refund 30, net 70, money in 30",
                  purchase.amount == 100 && r.spendingMinor == 10000 && r.refundsMinor == 3000 && r.netSpendingMinor == 7000 && r.moneyInMinor == 3000 &&
                  purchase.linkedMovements.contains { $0 === refund } && refund.linkedExpenseSnapshot?.hasPrefix("Uniqlo") == true,
                  expected: "10000/3000/7000, linked", actual: "\(r.spendingMinor)/\(r.refundsMinor)/\(r.netSpendingMinor) linked=\(purchase.linkedMovements.count)")

            let usd = Expense(amount: 10, currency: "USD", merchant: "Abroad")
            ctx.insert(usd)
            let rmOnly = FinancialCalculator.summary(expenses: [usd, purchase], movements: [])
            check("Currencies are never mixed", rmOnly.spendingMinor == 10000, expected: "RM total excludes USD", actual: "\(rmOnly.spendingMinor)")
        }

        // MARK: Person balances
        do {
            let ctx = context()
            let bijoy = PayBookProfile(name: "Bijoy"), riyad = PayBookProfile(name: "Riyad"), labib = PayBookProfile(name: "Labib"), shadin = PayBookProfile(name: "Shadin")
            [bijoy, riyad, labib, shadin].forEach { ctx.insert($0) }

            let lunchIPaid = sharedExpense(ctx, amount: 30, payer: nil, people: [bijoy, riyad, labib])
            var b = FinancialCalculator.personBalances(expenses: [lunchIPaid], movements: [])
            check("Balance: I paid RM30 split 4 -> each owes me 7.50",
                  b[bijoy.id] == 750 && b[riyad.id] == 750 && b[labib.id] == 750,
                  expected: "750 each", actual: "\(b[bijoy.id] ?? 0)/\(b[riyad.id] ?? 0)/\(b[labib.id] ?? 0)")

            let lunchBijoyPaid = sharedExpense(ctx, amount: 30, payer: bijoy, people: [bijoy, riyad, labib])
            b = FinancialCalculator.personBalances(expenses: [lunchBijoyPaid], movements: [])
            check("Balance: Bijoy paid -> I owe Bijoy 7.50; Riyad/Labib not involved with me",
                  b[bijoy.id] == -750 && b[riyad.id] == nil && b[labib.id] == nil,
                  expected: "Bijoy -750 only", actual: "\(b)")

            let given1 = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: shadin)
            let given2 = MoneyMovement(kind: .loanGiven, amountMinor: 5000, person: shadin)
            let back = MoneyMovement(kind: .repaymentReceived, amountMinor: 10000, person: shadin)
            [given1, given2, back].forEach { ctx.insert($0) }
            b = FinancialCalculator.personBalances(expenses: [], movements: [given1, given2])
            let afterLoans = b[shadin.id]
            b = FinancialCalculator.personBalances(expenses: [], movements: [given1, given2, back])
            check("Balance: Shadin loan 150 + 50, repays 100 -> owes 100",
                  afterLoans == 20000 && b[shadin.id] == 10000, expected: "20000 then 10000", actual: "\(afterLoans ?? 0) then \(b[shadin.id] ?? 0)")

            let borrowed = MoneyMovement(kind: .loanReceived, amountMinor: 2000, person: riyad)
            let repaid = MoneyMovement(kind: .repaymentMade, amountMinor: 2000, person: riyad)
            [borrowed, repaid].forEach { ctx.insert($0) }
            let owe = FinancialCalculator.personBalances(expenses: [], movements: [borrowed])[riyad.id]
            let settled = FinancialCalculator.personBalances(expenses: [], movements: [borrowed, repaid])[riyad.id]
            check("Balance: loan received -> I owe; repayment made -> settled", owe == -2000 && settled == 0,
                  expected: "-2000 then 0", actual: "\(owe ?? 0) then \(settled ?? 0)")

            let overpay = MoneyMovement(kind: .repaymentReceived, amountMinor: 1000, person: bijoy)
            ctx.insert(overpay)
            let mixed = FinancialCalculator.personBalances(expenses: [lunchIPaid, lunchBijoyPaid], movements: [overpay])
            check("Balance: mixed (Bijoy owes 7.50, I owe 7.50, he pays 10) -> I owe him 10",
                  mixed[bijoy.id] == -1000 && mixed[riyad.id] == 750, expected: "Bijoy -1000, Riyad 750", actual: "\(mixed[bijoy.id] ?? 0), \(mixed[riyad.id] ?? 0)")

            let refund = MoneyMovement(kind: .refund, amountMinor: 500, person: bijoy)
            let income = MoneyMovement(kind: .income, amountMinor: 500, person: bijoy)
            [refund, income].forEach { ctx.insert($0) }
            let noEffect = FinancialCalculator.personBalances(expenses: [], movements: [refund, income])
            check("Balance: refunds and income never change a person balance", noEffect.isEmpty, expected: "empty", actual: "\(noEffect)")
        }

        // MARK: Delete rules preserve history
        do {
            let ctx = context()
            let bijoy = PayBookProfile(name: "Bijoy")
            let maybank = Account(name: "Maybank", type: .bank)
            ctx.insert(bijoy); ctx.insert(maybank)
            let dinner = sharedExpense(ctx, amount: 30, payer: bijoy, people: [bijoy])
            dinner.account = maybank
            let purchase = Expense(amount: 100, merchant: "Shop")
            ctx.insert(purchase)
            let refund = MoneyMovement(kind: .refund, amountMinor: 3000, linkedExpense: purchase, account: maybank)
            let loan = MoneyMovement(kind: .loanGiven, amountMinor: 500, person: bijoy)
            ctx.insert(refund); ctx.insert(loan)
            try? ctx.save()

            let bijoyShare = dinner.shares.first { !$0.isMe }
            ctx.delete(bijoy)
            try? ctx.save()
            let personDeleteOK = dinner.payer == nil && dinner.payerNameSnapshot == "Bijoy" && bijoyShare?.person == nil &&
                bijoyShare?.nameSnapshot == "Bijoy" && loan.person == nil && loan.personNameSnapshot == "Bijoy" && count(ExpenseShare.self, in: ctx) == 2
            check("Deleting a person keeps shares/payer/movements with name snapshots", personDeleteOK,
                  expected: "links nil, snapshots 'Bijoy', shares kept",
                  actual: "payerSnapshot=\(dinner.payerNameSnapshot ?? "nil") shareSnapshot=\(bijoyShare?.nameSnapshot ?? "nil") shares=\(count(ExpenseShare.self, in: ctx))")

            ctx.delete(purchase)
            try? ctx.save()
            let expenseDeleteOK = count(MoneyMovement.self, in: ctx) == 2 && refund.linkedExpense == nil && refund.linkedExpenseSnapshot?.hasPrefix("Shop") == true
            check("Deleting an expense keeps its refund (with snapshot)", expenseDeleteOK,
                  expected: "refund kept, link nil, snapshot 'Shop…'", actual: "movements=\(count(MoneyMovement.self, in: ctx)) snapshot=\(refund.linkedExpenseSnapshot ?? "nil")")

            ctx.delete(dinner)
            try? ctx.save()
            check("Deleting a shared expense deletes its shares", count(ExpenseShare.self, in: ctx) == 0,
                  expected: "0 shares", actual: "\(count(ExpenseShare.self, in: ctx))")

            let other = Expense(amount: 8, merchant: "Kopi", fundingAccount: "Maybank")
            ctx.insert(other)
            other.account = maybank
            try? ctx.save()
            ctx.delete(maybank)
            try? ctx.save()
            check("Deleting an account keeps expenses, movements and the text", other.account == nil && other.fundingAccount == "Maybank" &&
                  count(Expense.self, in: ctx) == 1 && refund.account == nil && count(MoneyMovement.self, in: ctx) == 2,
                  expected: "expense + movements kept, text 'Maybank'", actual: "expenses=\(count(Expense.self, in: ctx)) text=\(other.fundingAccount)")
        }

        // MARK: Duplicate cleanup never merges records with financial relationships
        do {
            let ctx = context()
            let bijoy = PayBookProfile(name: "Bijoy")
            ctx.insert(bijoy)
            let a = sharedExpense(ctx, amount: 30, payer: nil, people: [bijoy], merchant: "Nasi Kandar")
            let b = Expense(amount: 30, merchant: "Nasi Kandar", date: a.date)
            ctx.insert(b)
            try? ctx.save()
            let merged = TransactionReconciliationEngine.shared.consolidateExistingDuplicates(in: ctx)
            check("Duplicate cleanup skips shared expenses", merged == 0 && count(Expense.self, in: ctx) == 2 && count(ExpenseShare.self, in: ctx) == 2,
                  expected: "0 merged, both kept", actual: "merged=\(merged) expenses=\(count(Expense.self, in: ctx))")
        }

