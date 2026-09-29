import Foundation
import SwiftData

/// Phase 8: cross-cutting edge cases, the full V1 → V3 migration chain and a full local backup round trip.
/// `--run-hardening-tests`
@MainActor
public struct HardeningTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 8") { results.append($0) }

        // MARK: Migration chain V1 → V2 → V3 on disk
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropChain-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("default.store")
            var ids: [UUID] = []
            do {
                let v1 = Schema(versionedSchema: SpenDropSchemaV1.self)
                if let c = try? ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: storeURL)]) {
                    let ctx = ModelContext(c)
                    for (i, funding) in ["Maybank", "Touch 'n Go", "Unknown"].enumerated() {
                        let e = SpenDropSchemaV1.Expense(amount: Double(i + 1) * 12.5, merchant: "M\(i)", fundingAccount: funding)
                        ctx.insert(e); ids.append(e.id)
                    }
                    let p = SpenDropSchemaV1.PayBookProfile(name: "Rahim"); ctx.insert(p)
                    try? ctx.save()
                }
            }
            var actual = "open failed"
            var passed = false
            if let c = try? ExpenseDataContainer.openPersistentContainer(configuration: ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)) {
                let ctx = ModelContext(c)
                let expenses = TestKit.fetch(Expense.self, in: ctx)
                let byID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
                ctx.insert(ClassificationRule(merchantKey: "m0", categoryRaw: "Food"))
                passed = Set(expenses.map(\.id)) == Set(ids) && byID[ids[0]]?.account?.name == "Maybank" &&
                    byID[ids[1]]?.account?.type == .eWallet && byID[ids[2]]?.account == nil && byID[ids[1]]?.amount == 25 &&
                    TestKit.count(PayBookProfile.self, in: ctx) == 1 && (try? ctx.save()) != nil && TestKit.count(ClassificationRule.self, in: ctx) == 1
                actual = "expenses=\(expenses.count) accounts=\(TestKit.fetch(Account.self, in: ctx).map(\.name).sorted()) rules=\(TestKit.count(ClassificationRule.self, in: ctx))"
            }
            t.check("Migration chain V1 → V2 → V3: ids/amounts kept, accounts linked, Unknown unlinked, rules table ready",
                    passed, expected: "all kept", actual: actual)
        }

