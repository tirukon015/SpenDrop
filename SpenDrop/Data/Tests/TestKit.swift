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

