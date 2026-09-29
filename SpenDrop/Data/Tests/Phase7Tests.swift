import Foundation
import SwiftData

/// Phase 7: payment channels, ClassificationRule, direction detection, scan→movement, Apple Pay automation,
/// trend/breakdown calculations, backup V3 and the V2 → V3 migration. `--run-phase7-tests`
@MainActor
public struct Phase7Tests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 7") { results.append($0) }

