import Foundation
import SwiftData

/// Small shared helpers for the in-app test suites (in-memory stores only; never the user's data).
@MainActor
public struct TestKit {
    let suite: String
    let sink: (TestCaseResult) -> Void

    public init(suite: String, sink: @escaping (TestCaseResult) -> Void) {
        self.suite = suite
        self.sink = sink
    }

    public func check(_ name: String, _ passed: Bool, expected: String, actual: String) {
        sink(TestCaseResult(testName: name, passed: passed, expected: expected, actual: actual, details: suite))
    }

    public static func context() -> ModelContext {
        let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config])
        return ModelContext(container)
    }

    public static func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    public static func fetch<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> [T] {
        (try? ctx.fetch(FetchDescriptor<T>())) ?? []
    }
}

/// Runs every in-app suite and reports per-suite totals. `--run-all-tests`
@MainActor
public enum AllTestSuites {
    public struct SuiteResult {
        public let name: String
        public let results: [TestCaseResult]
        public var passed: Int { results.filter(\.passed).count }
    }

    public static let suites: [(name: String, flag: String, run: () -> [TestCaseResult])] = [
        ("Existing", "--run-tests", { TransactionParserTests.runAllTests() }),
        ("Data safety", "--run-data-safety-tests", { DataSafetyTests.runAllTests() }),
        ("Phase 2", "--run-financial-tests", { FinancialModelTests.runAllTests() }),
        ("Phase 3", "--run-account-tests", { AccountFeatureTests.runAllTests() }),
        ("Phase 4", "--run-split-tests", { SplitFeatureTests.runAllTests() }),
        ("Phase 5", "--run-people-tests", { PeopleBalanceTests.runAllTests() }),
        ("Phase 6", "--run-timeline-tests", { ActivityFeedTests.runAllTests() }),
        ("Phase 7", "--run-phase7-tests", { Phase7Tests.runAllTests() }),
        ("Phase 8", "--run-hardening-tests", { HardeningTests.runAllTests() }),
        ("Authentication", "--run-auth-tests", { blocking { await AuthTests.runAllTests() } }),
        ("Cloud Backup", "--run-cloud-tests", { blocking { await CloudBackupTests.runAllTests() } }),
        // Must stay last: proves none of the suites above touched the user's real database.
        ("Test isolation", "--run-all-tests", { isolationCheck() })
    ]

    /// Test runs happen before the app opens its database. If any suite had opened the real store,
    /// `storeStatus` would no longer be the initial "not opened yet" state.
    static func isolationCheck() -> [TestCaseResult] {
        var untouched = false
        if case .safeMode(_, let url) = ExpenseDataContainer.storeStatus, url == nil { untouched = true }
        return [TestCaseResult(testName: "Test suites never open the real database", passed: untouched,
                               expected: "store never opened", actual: untouched ? "never opened" : "OPENED: \(ExpenseDataContainer.storeStatus)",
                               details: "Isolation")]
    }

    /// Runs an async suite to completion from the synchronous launch path by driving the main run loop
    /// (test runs exit before any UI or the real database is created).
    static func blocking(_ work: @escaping @MainActor () async -> [TestCaseResult]) -> [TestCaseResult] {
        var output: [TestCaseResult]?
        Task { @MainActor in output = await work() }
        while output == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return output ?? []
    }

