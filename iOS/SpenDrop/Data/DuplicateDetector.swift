import Foundation
import SwiftData

public struct DuplicateCheckResult {
    public let isDuplicate: Bool
    public let matchedExpense: Expense?
    public let reason: String?
    /// Same payment reference: merging may be offered. Otherwise only "Add Anyway / Cancel".
    public var isStrong: Bool = false

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
        paymentChannel: PaymentChannel? = nil,
        fundingAccount: String? = nil,
        in context: ModelContext
    ) -> DuplicateCheckResult {
        let match = TransactionReconciliationEngine.shared.findMatch(
            amount: amount,
            merchant: merchant,
            date: date,
            reference: reference,
            paymentChannel: paymentChannel,
            fundingAccount: fundingAccount,
            in: context
        )

        return Self.result(match)
    }

    /// The same check against a given list of (possibly unsaved) expenses, e.g. earlier drafts of a Bulk Import.
    public func checkDuplicate(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        paymentChannel: PaymentChannel? = nil,
        fundingAccount: String? = nil,
        among records: [Expense]
    ) -> DuplicateCheckResult {
        Self.result(TransactionReconciliationEngine.shared.findMatch(
            amount: amount, merchant: merchant, date: date, reference: reference,
            paymentChannel: paymentChannel, fundingAccount: fundingAccount, among: records))
    }

    private static func result(_ match: MatchResult) -> DuplicateCheckResult {
        if match.isMatch {
            return DuplicateCheckResult(
                isDuplicate: true,
                matchedExpense: match.matchedExpense,
                reason: match.reason,
                isStrong: match.isStrong
            )
        }
        return .none
    }
}
