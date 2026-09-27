import Foundation
import SwiftData

public struct ReconcileCandidate {
    public let amount: Double
    public let merchant: String
    public let date: Date
    public let category: ExpenseCategory
    public let fundingAccount: String
    public let paymentChannel: PaymentChannel
    public let reference: String?
    public let notes: String?
    public let imageRelativePath: String?
    public let rawOCRText: String?

    public init(
        amount: Double,
        merchant: String,
        date: Date,
        category: ExpenseCategory = .other,
        fundingAccount: String = "Unknown",
        paymentChannel: PaymentChannel = .unknown,
        reference: String? = nil,
        notes: String? = nil,
        imageRelativePath: String? = nil,
        rawOCRText: String? = nil
    ) {
        self.amount = amount
        self.merchant = merchant
        self.date = date
        self.category = category
        self.fundingAccount = fundingAccount
        self.paymentChannel = paymentChannel
        self.reference = reference
        self.notes = notes
        self.imageRelativePath = imageRelativePath
        self.rawOCRText = rawOCRText
    }
}

public struct MatchResult {
    public let isMatch: Bool
    public let matchedExpense: Expense?
    public let confidence: Double
    public let reason: String?

    public static let none = MatchResult(isMatch: false, matchedExpense: nil, confidence: 0.0, reason: nil)
}

public struct TransactionReconciliationEngine {
    public static let shared = TransactionReconciliationEngine()

    public init() {}

    /// Finds a potential matching existing expense that represents the same real-world payment
    public func findMatch(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        in context: ModelContext
    ) -> MatchResult {
        guard let amount = amount, amount > 0 else {
            return .none
        }

        let calendar = Calendar.current
        let targetDate = date ?? Date()

        // 48-hour window to catch settlement delay between Apple Pay authorization and bank debit posting
        let startWindow = calendar.date(byAdding: .hour, value: -48, to: targetDate) ?? targetDate
        let endWindow = calendar.date(byAdding: .hour, value: 48, to: targetDate) ?? targetDate

        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { expense in
                expense.amount == amount && expense.date >= startWindow && expense.date <= endWindow
            }
        )
        descriptor.fetchLimit = 20

        do {
            let candidates = try context.fetch(descriptor)

            for candidate in candidates {
                // Rule 1: Exact reference match
                if let ref = reference, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let candRef = candidate.transactionReference, !candRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   ref.caseInsensitiveCompare(candRef) == .orderedSame {
                    return MatchResult(
                        isMatch: true,
                        matchedExpense: candidate,
                        confidence: 1.0,
                        reason: "Identical transaction reference (\(ref)) already recorded."
                    )
                }

                // Rule 2: Same merchant & same day
                let candMerchant = candidate.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let targetM = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let sameMerchant = !targetM.isEmpty && targetM != "unknown" &&
                    (candMerchant == targetM || candMerchant.contains(targetM) || targetM.contains(candMerchant))

                let sameDay = calendar.isDate(candidate.date, inSameDayAs: targetDate)

                if sameMerchant && sameDay {
                    return MatchResult(
                        isMatch: true,
                        matchedExpense: candidate,
                        confidence: 0.95,
                        reason: "Matching payment of \(candidate.formattedAmount) for \(candidate.merchant) recorded on \(candidate.date.formatted(date: .abbreviated, time: .shortened))."
                    )
                }

                // Rule 3: Apple Pay card authorization & Bank Debit reconciliation
                // One record has Apple Pay, the other has bank (e.g. Maybank), same amount within 24 hours
                let isApplePayPair = (candidate.paymentChannel == .applePay || candidate.paymentSourceRaw == "Apple Pay")
                let hasBankInfo = candidate.effectiveFundingAccount != "Unknown"
                if (isApplePayPair || hasBankInfo) && sameDay {
                    return MatchResult(
                        isMatch: true,
                        matchedExpense: candidate,
                        confidence: 0.90,
                        reason: "Corresponds to existing \(candidate.displayFundingAndChannel) transaction of \(candidate.formattedAmount) on \(candidate.date.formatted(date: .abbreviated, time: .shortened))."
                    )
                }

                // Rule 4: Same amount within 2 hours
                if abs(candidate.date.timeIntervalSince(targetDate)) < 7200 {
                    return MatchResult(
                        isMatch: true,
                        matchedExpense: candidate,
                        confidence: 0.85,
                        reason: "Matching expense of \(candidate.formattedAmount) recorded close to this time (\(candidate.date.formatted(date: .omitted, time: .shortened)))."
                    )
                }
            }
        } catch {
            print("[SpenDrop][Reconcile] Match query failed: \(error)")
        }

        return .none
    }

    /// Reconciles an existing expense with new incoming data, avoiding double-counting and merging metadata
    @discardableResult
    public func reconcile(
        existing: Expense,
        with candidate: ReconcileCandidate,
        in context: ModelContext
    ) -> Expense {
        // 1. Reconcile Payment Channel: if existing is unknown, upgrade to candidate's channel
        if existing.paymentChannel == .unknown && candidate.paymentChannel != .unknown {
            existing.paymentChannel = candidate.paymentChannel
        }

        // 2. Reconcile Funding Account: if existing is unknown, upgrade to candidate's funding account
        if existing.fundingAccount == "Unknown" && candidate.fundingAccount != "Unknown" && !candidate.fundingAccount.isEmpty {
            existing.fundingAccount = candidate.fundingAccount
        }

        // 3. Reconcile Merchant: if existing is "Unknown" or generic, use candidate's merchant
        if (existing.merchant == "Unknown" || existing.merchant.isEmpty) && !candidate.merchant.isEmpty && candidate.merchant != "Unknown" {
            existing.merchant = candidate.merchant
        }

        // 4. Reconcile Reference
        if (existing.transactionReference == nil || existing.transactionReference?.isEmpty == true),
           let ref = candidate.reference, !ref.isEmpty {
            existing.transactionReference = ref
        }

        // 5. Reconcile Image
        if (existing.imageRelativePath == nil || existing.imageRelativePath?.isEmpty == true),
           let imgPath = candidate.imageRelativePath, !imgPath.isEmpty {
            existing.imageRelativePath = imgPath
        }

        // 6. Merge Notes
        if let newNotes = candidate.notes, !newNotes.isEmpty {
            if let existingNotes = existing.notes, !existingNotes.isEmpty {
                if !existingNotes.contains(newNotes) {
                    existing.notes = "\(existingNotes) • \(newNotes)"
                }
            } else {
                existing.notes = newNotes
            }
        }

        // 7. Update status & confidence
        existing.matchingStatusRaw = "RECONCILED"
        existing.matchingConfidence = 1.0
        existing.updatedAt = Date()

        try? context.save()
        context.processPendingChanges()

        print("[SpenDrop][Reconcile] Reconciled expense ID \(existing.id) -> \(existing.displayFundingAndChannel) (\(existing.formattedAmount))")
        return existing
    }

    /// Scans the entire database and consolidates any existing duplicate records into single reconciled transactions
    public func consolidateExistingDuplicates(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allExpenses = try? context.fetch(descriptor) else { return 0 }

        var reconciledCount = 0
        var visitedIds = Set<UUID>()

        for i in 0..<allExpenses.count {
            let itemA = allExpenses[i]
            if visitedIds.contains(itemA.id) { continue }

            for j in (i + 1)..<allExpenses.count {
                let itemB = allExpenses[j]
                if visitedIds.contains(itemB.id) { continue }

                // Check if itemA and itemB represent the same transaction
                let sameAmount = abs(itemA.amount - itemB.amount) < 0.001
                let timeDiff = abs(itemA.date.timeIntervalSince(itemB.date))
                let within48Hours = timeDiff < (48 * 3600)

                let sameRef = itemA.transactionReference != nil &&
                              itemA.transactionReference == itemB.transactionReference &&
                              !(itemA.transactionReference?.isEmpty ?? true)

                let candM1 = itemA.merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let candM2 = itemB.merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let sameMerchant = !candM1.isEmpty && candM1 != "unknown" &&
                                   (candM1 == candM2 || candM1.contains(candM2) || candM2.contains(candM1))

                let isDuplicate = sameAmount && within48Hours && (sameRef || sameMerchant || timeDiff < 3600)

                if isDuplicate {
                    // Merge itemB into itemA
                    let candidate = ReconcileCandidate(
                        amount: itemB.amount,
                        merchant: itemB.merchant,
                        date: itemB.date,
                        category: itemB.category,
                        fundingAccount: itemB.effectiveFundingAccount,
                        paymentChannel: itemB.paymentChannel,
                        reference: itemB.transactionReference,
                        notes: itemB.notes,
                        imageRelativePath: itemB.imageRelativePath,
                        rawOCRText: itemB.ocrText
                    )
                    reconcile(existing: itemA, with: candidate, in: context)

                    // Remove itemB duplicate
                    context.delete(itemB)
                    visitedIds.insert(itemB.id)
                    reconciledCount += 1
                }
            }
            visitedIds.insert(itemA.id)
        }

        if reconciledCount > 0 {
            try? context.save()
            context.processPendingChanges()
        }

        print("[SpenDrop][Reconcile] Database consolidation complete: \(reconciledCount) duplicate(s) merged into single records.")
        return reconciledCount
    }
}
