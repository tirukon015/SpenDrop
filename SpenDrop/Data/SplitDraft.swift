import Foundation
import SwiftData

/// Editable state of an expense split (participants, method, payer). Pure logic on top of `SplitCalculator`;
/// the SwiftUI editor only binds to it. A split is stored as `ExpenseShare` rows on the one `Expense`.
public struct SplitDraft: Equatable {
