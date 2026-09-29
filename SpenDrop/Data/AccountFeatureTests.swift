import Foundation
import SwiftData

/// Phase 3 checks: account activity, account resolving/relinking, funding options, Money In/Out/Transfer drafts
/// and account form validation. In-memory only. Launch argument: `--run-account-tests`.
@MainActor
public struct AccountFeatureTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        func check(_ name: String, _ passed: Bool, expected: String, actual: String) {
            results.append(TestCaseResult(testName: name, passed: passed, expected: expected, actual: actual, details: "Phase 3"))
        }
        func context() -> ModelContext {
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config])
            return ModelContext(container)
        }
        func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
            (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
        }

        // MARK: Recorded account activity
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank", type: .bank), tng = Account(name: "Touch 'n Go", type: .eWallet)
            let bijoy = PayBookProfile(name: "Bijoy")
            ctx.insert(maybank); ctx.insert(tng); ctx.insert(bijoy)

            let lunch = Expense(amount: 25, merchant: "McDonald's")
            let paidByOther = Expense(amount: 30, merchant: "Dinner")
            let foreign = Expense(amount: 10, currency: "USD", merchant: "Abroad")
            [lunch, paidByOther, foreign].forEach { ctx.insert($0); $0.account = maybank }
            paidByOther.setPayer(bijoy)

            let salary = MoneyMovement(kind: .income, amountMinor: 100000, account: maybank)
            let loan = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: bijoy, account: maybank)
            let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, account: maybank, counterAccount: tng)
            [salary, loan, transfer].forEach { ctx.insert($0) }
            try? ctx.save()

            let m = FinancialCalculator.accountActivity(for: maybank)
            let t = FinancialCalculator.accountActivity(for: tng)
            check("Account activity: Maybank in/out/net", m.inMinor == 100000 && m.outMinor == 37500 && m.netMinor == 62500,
                  expected: "in 100000, out 37500 (25 + 150 + 200), net 62500", actual: "in \(m.inMinor), out \(m.outMinor), net \(m.netMinor)")
            check("Account activity: transfer arrives in Touch 'n Go", t.inMinor == 20000 && t.outMinor == 0,
                  expected: "in 20000, out 0", actual: "in \(t.inMinor), out \(t.outMinor)")
        }

