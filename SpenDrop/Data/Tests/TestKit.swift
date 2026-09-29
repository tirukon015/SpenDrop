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
