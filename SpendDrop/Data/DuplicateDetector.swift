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

    /// Checks if a parsed transaction likely duplicates an existing expense in SwiftData
    public func checkDuplicate(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        in context: ModelContext
    ) -> DuplicateCheckResult {
        guard let amount = amount, amount > 0 else {
            return .none
        }

        let calendar = Calendar.current
        let targetDate = date ?? Date()

        // Fetch recent expenses within a 48-hour window
        let startWindow = calendar.date(byAdding: .hour, value: -48, to: targetDate) ?? targetDate
        let endWindow = calendar.date(byAdding: .hour, value: 48, to: targetDate) ?? targetDate

        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { expense in
                expense.amount == amount && expense.date >= startWindow && expense.date <= endWindow
            }
        )
        descriptor.fetchLimit = 10

        do {
            let candidates = try context.fetch(descriptor)

            for candidate in candidates {
                // Exact reference match is an absolute duplicate
                if let ref = reference, !ref.isEmpty,
                   let candRef = candidate.transactionReference, !candRef.isEmpty,
                   ref.caseInsensitiveCompare(candRef) == .orderedSame {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchedExpense: candidate,
                        reason: "Identical transaction reference (\(ref)) already recorded."
                    )
                }

                // Matching merchant and same amount on the same day
                let candidateMerchant = candidate.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let targetMerchant = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                let sameMerchant = !targetMerchant.isEmpty &&
                                   targetMerchant != "unknown" &&
                                   (candidateMerchant == targetMerchant || candidateMerchant.contains(targetMerchant) || targetMerchant.contains(candidateMerchant))

                let sameDay = calendar.isDate(candidate.date, inSameDayAs: targetDate)

                if sameMerchant && sameDay {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchedExpense: candidate,
                        reason: "Matching expense of \(candidate.formattedAmount) for \(candidate.merchant) recorded on \(candidate.date.formatted(date: .abbreviated, time: .shortened))."
                    )
                }

                // If merchant is Unknown or generic, but same amount within 1 hour
                if abs(candidate.date.timeIntervalSince(targetDate)) < 3600 {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchedExpense: candidate,
                        reason: "Matching expense of \(candidate.formattedAmount) recorded recently at \(candidate.date.formatted(date: .omitted, time: .shortened))."
                    )
                }
            }
        } catch {
            print("Duplicate detection query failed: \(error)")
        }

        return .none
    }
}
