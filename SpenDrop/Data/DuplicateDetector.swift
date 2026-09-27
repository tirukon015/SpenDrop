import Foundation
import SwiftData

public struct DuplicateCheckResult {
    public let isDuplicate: Bool
    public let matchedExpense: Expense?
    public let reason: String?

    public static let none = DuplicateCheckResult(isDuplicate: false, matchedExpense: nil, reason: nil)
}

public struct DuplicateDetector {
    public static let shared = DuplicateDetector()

    private init() {}

    /// Checks if a transaction likely matches an existing expense in SwiftData
    public func checkDuplicate(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        in context: ModelContext
    ) -> DuplicateCheckResult {
        let match = TransactionReconciliationEngine.shared.findMatch(
            amount: amount,
            merchant: merchant,
            date: date,
            reference: reference,
            in: context
        )

        if match.isMatch {
            return DuplicateCheckResult(
                isDuplicate: true,
                matchedExpense: match.matchedExpense,
                reason: match.reason
            )
        }
        return .none
    }
}
