import Foundation
import SwiftData

/// Test-only model used to create a store that SpenDrop's schema cannot open (simulates a failed migration).
/// It is not part of the app schema.
@Model
final class DataSafetyProbeRecord {
    var label: String
    init(label: String) { self.label = label }
}

/// Test-only model whose `Expense.amount` type cannot be migrated to SpenDrop's `Expense` (simulates a failed migration).
enum IncompatibleProbe {
    @Model
    final class Expense {
        var amount: String
        init(amount: String) { self.amount = amount }
    }
}

/// Phase 0 data-safety checks. Every test runs in its own temporary directory or in-memory store and never
/// touches the user's database or backup files. Run with the `--run-data-safety-tests` launch argument.
@MainActor
public struct DataSafetyTests {
