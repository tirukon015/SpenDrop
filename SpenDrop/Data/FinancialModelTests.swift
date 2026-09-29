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

