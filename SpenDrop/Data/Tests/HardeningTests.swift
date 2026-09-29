import Foundation
import SwiftData

/// Phase 8: cross-cutting edge cases, the full V1 → V3 migration chain and a full local backup round trip.
/// `--run-hardening-tests`
@MainActor
public struct HardeningTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 8") { results.append($0) }

