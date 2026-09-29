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

