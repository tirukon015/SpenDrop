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
    public let fundingInstrument: String?

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
        rawOCRText: String? = nil,
        fundingInstrument: String? = nil
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
        self.fundingInstrument = fundingInstrument
    }
}

public struct MatchResult {
    public let isMatch: Bool
    public let matchedExpense: Expense?
    public let confidence: Double
    public let reason: String?
    /// True only for a match on the payment's own reference: then it is almost certainly the same payment and
    /// merging can be offered. Everything else is only a "possible duplicate" warning.
    public var isStrong: Bool = false

    public static let none = MatchResult(isMatch: false, matchedExpense: nil, confidence: 0.0, reason: nil)
}

public struct TransactionReconciliationEngine {
    public static let shared = TransactionReconciliationEngine()

    public init() {}

    /// Window in which two imports with the same amount and merchant are reported as a possible duplicate.
    public static let weakMatchWindow: TimeInterval = 15 * 60

    /// Finds an existing expense that may be the same real-world payment as an imported one.
    /// - Strong: same payment reference (and amount) within 48 hours — e.g. the same receipt shared twice.
    /// - Weak (warning only): same amount AND same merchant within 15 minutes, AND no conflicting payment channel or
    ///   funding account (Apple Pay vs QR Payment, or Maybank vs CIMB, are different payments; Unknown matches anything).
    /// Amount alone, amount + day, or amount + person never count: two RM100 payments are both kept.
    /// Only used for imports (screenshots, Share Extension); manually entered transactions are never checked.
    public func findMatch(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        paymentChannel: PaymentChannel? = nil,
        fundingAccount: String? = nil,
        in context: ModelContext
    ) -> MatchResult {
        guard let amount = amount, amount > 0 else {
            return .none
        }
        let amountMinor = Money.minorUnits(from: amount)
        let targetDate = date ?? Date()
        let startWindow = targetDate.addingTimeInterval(-48 * 3600)
        let endWindow = targetDate.addingTimeInterval(48 * 3600)
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { expense in
                expense.date >= startWindow && expense.date <= endWindow
            }
        )
        let fetched = (try? context.fetch(descriptor)) ?? []
        return findMatch(amount: amount, merchant: merchant, date: date, reference: reference,
                         paymentChannel: paymentChannel, fundingAccount: fundingAccount, among: fetched)
    }

    /// The same rules as `findMatch(…in:)`, applied to a given list of expenses instead of the store — Bulk Import
    /// uses it to compare a draft with the drafts before it in the same batch (not saved yet).
    public func findMatch(
        amount: Double?,
        merchant: String?,
        date: Date?,
        reference: String?,
        paymentChannel: PaymentChannel? = nil,
        fundingAccount: String? = nil,
        among records: [Expense]
    ) -> MatchResult {
        guard let amount = amount, amount > 0 else {
            return .none
        }
        let amountMinor = Money.minorUnits(from: amount)
        let targetDate = date ?? Date()
        let candidates = records.filter {
            abs($0.date.timeIntervalSince(targetDate)) <= 48 * 3600 && Money.minorUnits(from: $0.amount) == amountMinor
        }

        if let ref = Self.normalizedReference(reference),
           let candidate = candidates.first(where: { Self.normalizedReference($0.transactionReference) == ref }) {
            var result = MatchResult(isMatch: true, matchedExpense: candidate, confidence: 1.0,
                                     reason: "A payment with the same reference (\(reference ?? ref)) is already recorded: \(candidate.merchant), \(candidate.formattedAmount), \(candidate.date.formatted(date: .abbreviated, time: .shortened)).")
            result.isStrong = true
            return result
        }

        let merchantKey = Self.normalizedMerchant(merchant)
        if let merchantKey,
           let candidate = candidates.first(where: {
               Self.normalizedMerchant($0.merchant) == merchantKey && abs($0.date.timeIntervalSince(targetDate)) <= Self.weakMatchWindow &&
               Self.compatible(channel: paymentChannel, $0.paymentChannel) &&
               Self.compatible(funding: fundingAccount, $0.effectiveFundingAccount)
           }) {
            return MatchResult(isMatch: true, matchedExpense: candidate, confidence: 0.6,
                               reason: "Possible duplicate: \(candidate.formattedAmount) at \(candidate.merchant) on \(candidate.date.formatted(date: .abbreviated, time: .shortened)) is already recorded. If this is a separate payment, add it anyway.")
        }
        return .none
    }

    static func compatible(channel new: PaymentChannel?, _ old: PaymentChannel) -> Bool {
        guard let new, new != .unknown, old != .unknown else { return true }
        return new == old
    }

    static func compatible(funding new: String?, _ old: String) -> Bool {
        let a = new?.trimmingCharacters(in: .whitespaces).lowercased() ?? "", b = old.trimmingCharacters(in: .whitespaces).lowercased()
        let unknown: Set<String> = ["", "unknown", "other"]
        guard !unknown.contains(a), !unknown.contains(b) else { return true }
        return a == b
    }

    /// References shorter than 4 characters are too weak to identify a payment.
    static func normalizedReference(_ reference: String?) -> String? {
        guard let value = reference?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), value.count >= 4 else { return nil }
        return value
    }

    static func normalizedMerchant(_ merchant: String?) -> String? {
        guard let value = merchant?.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " "),
              !value.isEmpty, value != "unknown" else { return nil }
        return value
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

        // 2b. Reconcile Funding Instrument: if existing is empty, upgrade to candidate's instrument
        if (existing.fundingInstrument == nil || existing.fundingInstrument?.isEmpty == true),
           let inst = candidate.fundingInstrument, !inst.isEmpty {
            existing.fundingInstrument = inst
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

        #if DEBUG
        print("[SpenDrop][Reconcile] Reconciled expense ID \(existing.id) -> \(existing.displayFundingAndChannel) (\(existing.formattedAmount))")
        #endif
        return existing
    }

    /// Scans the entire database and consolidates any existing duplicate records into single reconciled transactions
    /// DATA SAFETY: this deletes records without asking the user. It is intentionally not called anywhere.
    @available(*, deprecated, message: "Deletes expenses without user confirmation. Do not call; duplicates must be confirmed by the user.")
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

                // Never merge records that carry financial relationships (splits, payer, refunds):
                // deleting one would silently destroy them.
                let hasRelationships = !itemA.shares.isEmpty || !itemB.shares.isEmpty ||
                                       !itemA.linkedMovements.isEmpty || !itemB.linkedMovements.isEmpty ||
                                       !itemA.paidByMe || !itemB.paidByMe
                let isDuplicate = !hasRelationships && sameAmount && within48Hours && (sameRef || sameMerchant || timeDiff < 3600)

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
