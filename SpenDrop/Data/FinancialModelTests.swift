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

