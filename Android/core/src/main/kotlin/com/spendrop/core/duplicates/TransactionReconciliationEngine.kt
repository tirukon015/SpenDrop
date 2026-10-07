package com.spendrop.core.duplicates

import com.spendrop.core.Money
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.insights.collapseWhitespace
import com.spendrop.core.insights.iosPaymentChannel
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import kotlin.math.abs

/** Incoming import data that may be merged into an existing expense. */
data class ReconcileCandidate(
    val amountMinor: Long,
    val merchant: String,
    val date: Long,
    val category: ExpenseCategory = ExpenseCategory.OTHER,
    val fundingAccount: String = "Unknown",
    val paymentChannel: PaymentChannel = PaymentChannel.UNKNOWN,
    val reference: String? = null,
    val notes: String? = null,
    val imageRelativePath: String? = null,
    val rawOCRText: String? = null,
    val fundingInstrument: String? = null,
)

data class MatchResult(
    val isMatch: Boolean,
    val matchedExpense: Expense?,
    val confidence: Double,
    val reason: String?,
    /** True only for a match on the payment's own reference: merging can be offered. Otherwise only a warning. */
    val isStrong: Boolean = false,
) {
    companion object { val NONE = MatchResult(false, null, 0.0, null) }
}

/**
 * Finds an existing expense that may be the same real-world payment as an imported one, and merges import data into it
 * (iOS TransactionReconciliationEngine). Only used for imports; manually entered transactions are never checked.
 */
object TransactionReconciliationEngine {
    /** Window in which two imports with the same amount and merchant are reported as a possible duplicate. */
    const val WEAK_MATCH_WINDOW_MS: Long = 15 * 60 * 1000L
    const val STRONG_MATCH_WINDOW_MS: Long = 48 * 3600 * 1000L

    /**
     * - Strong: same payment reference (≥ 4 chars, case-insensitive) and same amount within ±48 hours.
     * - Weak (warning only): same amount AND same merchant within 15 minutes, with no conflicting payment channel or
     *   funding account (Unknown/Other matches anything).
     * Amount alone, amount + day, or amount + person never count. Candidates are checked in [expenses] order.
     * [date] null = [now]. Deleted (tombstoned) expenses are ignored.
     */
    fun findMatch(
        amountMinor: Long?,
        merchant: String?,
        date: Long?,
        reference: String?,
        expenses: List<Expense>,
        paymentChannel: PaymentChannel? = null,
        fundingAccount: String? = null,
        now: Long = System.currentTimeMillis(),
        calendar: CalendarContext = CalendarContext(),
    ): MatchResult {
        if (amountMinor == null || amountMinor <= 0) return MatchResult.NONE
        val target = date ?: now
        val candidates = expenses.filter {
            it.deletedAt == null && it.date >= target - STRONG_MATCH_WINDOW_MS && it.date <= target + STRONG_MATCH_WINDOW_MS &&
                it.amountMinor == amountMinor
        }
        val ref = normalizedReference(reference)
        if (ref != null) {
            candidates.firstOrNull { normalizedReference(it.transactionReference) == ref }?.let { c ->
                return MatchResult(true, c, 1.0,
                    "A payment with the same reference (${reference ?: ref}) is already recorded: ${c.merchant}, ${Money.format(c.amountMinor, c.currency)}, ${describe(c.date, calendar)}.",
                    isStrong = true)
            }
        }
        val merchantKey = normalizedMerchant(merchant) ?: return MatchResult.NONE
        val c = candidates.firstOrNull {
            normalizedMerchant(it.merchant) == merchantKey && abs(it.date - target) <= WEAK_MATCH_WINDOW_MS &&
                compatibleChannel(paymentChannel, it.iosPaymentChannel) && compatibleFunding(fundingAccount, it.effectiveFundingAccount)
        } ?: return MatchResult.NONE
        return MatchResult(true, c, 0.6,
            "Possible duplicate: ${Money.format(c.amountMinor, c.currency)} at ${c.merchant} on ${describe(c.date, calendar)} is already recorded. If this is a separate payment, add it anyway.")
    }

    /** iOS `date.formatted(date: .abbreviated, time: .shortened)` in en: "Sep 29, 2026 at 12:00 PM". */
    private fun describe(millis: Long, calendar: CalendarContext) = calendar.format(millis, "MMM d, yyyy 'at' h:mm a")

    fun compatibleChannel(new: PaymentChannel?, old: PaymentChannel): Boolean {
        if (new == null || new == PaymentChannel.UNKNOWN || old == PaymentChannel.UNKNOWN) return true
        return new == old
    }

    fun compatibleFunding(new: String?, old: String): Boolean {
        val a = new?.trim(' ', '\t')?.lowercase() ?: ""
        val b = old.trim(' ', '\t').lowercase()
        val unknown = setOf("", "unknown", "other")
        if (a in unknown || b in unknown) return true
        return a == b
    }

    /** References shorter than 4 characters are too weak to identify a payment. */
    fun normalizedReference(reference: String?): String? {
        val value = reference?.trim()?.lowercase() ?: return null
        return if (value.codePointCount(0, value.length) >= 4) value else null
    }

    fun normalizedMerchant(merchant: String?): String? {
        val value = merchant?.lowercase()?.collapseWhitespace() ?: return null
        return if (value.isEmpty() || value == "unknown") null else value
    }

    /**
     * Merges import data into an existing expense (never double-counts): fills unknown channel / funding account /
     * instrument / merchant / reference / image, appends new notes, marks it RECONCILED. Returns the updated expense.
     */
    fun reconcile(existing: Expense, candidate: ReconcileCandidate, now: Long): Expense {
        var e = existing
        if (e.iosPaymentChannel == PaymentChannel.UNKNOWN && candidate.paymentChannel != PaymentChannel.UNKNOWN) {
            e = e.copy(paymentChannelRaw = candidate.paymentChannel.raw)
        }
        if (e.fundingAccount == "Unknown" && candidate.fundingAccount != "Unknown" && candidate.fundingAccount.isNotEmpty()) {
            e = e.copy(fundingAccount = candidate.fundingAccount)
        }
        if (e.fundingInstrument.isNullOrEmpty() && !candidate.fundingInstrument.isNullOrEmpty()) {
            e = e.copy(fundingInstrument = candidate.fundingInstrument)
        }
        if ((e.merchant == "Unknown" || e.merchant.isEmpty()) && candidate.merchant.isNotEmpty() && candidate.merchant != "Unknown") {
            e = e.copy(merchant = candidate.merchant)
        }
        if (e.transactionReference.isNullOrEmpty() && !candidate.reference.isNullOrEmpty()) {
            e = e.copy(transactionReference = candidate.reference)
        }
        if (e.imageRelativePath.isNullOrEmpty() && !candidate.imageRelativePath.isNullOrEmpty()) {
            e = e.copy(imageRelativePath = candidate.imageRelativePath)
        }
        val newNotes = candidate.notes
        if (!newNotes.isNullOrEmpty()) {
            val old = e.notes
            e = if (!old.isNullOrEmpty()) {
                if (!old.contains(newNotes)) e.copy(notes = "$old • $newNotes") else e
            } else e.copy(notes = newNotes)
        }
        return e.copy(matchingStatusRaw = "RECONCILED", matchingConfidence = 1.0, updatedAt = now)
    }
}

data class DuplicateCheckResult(
    val isDuplicate: Boolean,
    val matchedExpense: Expense?,
    val reason: String?,
    /** Same payment reference: merging may be offered. Otherwise only "Add Anyway / Cancel". */
    val isStrong: Boolean = false,
) {
    companion object { val NONE = DuplicateCheckResult(false, null, null) }
}

/** iOS DuplicateDetector: a thin wrapper over [TransactionReconciliationEngine.findMatch]. */
object DuplicateDetector {
    fun checkDuplicate(
        amountMinor: Long?,
        merchant: String?,
        date: Long?,
        reference: String?,
        expenses: List<Expense>,
        paymentChannel: PaymentChannel? = null,
        fundingAccount: String? = null,
        now: Long = System.currentTimeMillis(),
        calendar: CalendarContext = CalendarContext(),
    ): DuplicateCheckResult {
        val m = TransactionReconciliationEngine.findMatch(amountMinor, merchant, date, reference, expenses, paymentChannel, fundingAccount, now, calendar)
        return if (m.isMatch) DuplicateCheckResult(true, m.matchedExpense, m.reason, m.isStrong) else DuplicateCheckResult.NONE
    }
}

/**
 * Finds an existing Money In / Money Out / Transfer that looks like the same real-world transaction (iOS
 * MovementDuplicateDetector). Only used to WARN for imports; manually entered records are never checked.
 */
object MovementDuplicateDetector {
    fun findMatch(
        amountMinor: Long,
        date: Long,
        reference: String?,
        kind: MoneyMovementKind,
        movements: List<MoneyMovement>,
        excludingId: String? = null,
    ): MoneyMovement? {
        val list = movements.filter { it.deletedAt == null && (excludingId == null || !it.id.equals(excludingId, ignoreCase = true)) }
        TransactionReconciliationEngine.normalizedReference(reference)?.let { ref ->
            list.firstOrNull { TransactionReconciliationEngine.normalizedReference(it.transactionReference) == ref }?.let { return it }
        }
        // Same amount alone is never enough: only the same direction within a few minutes is worth a warning.
        return list.firstOrNull {
            it.amountMinor == amountMinor && it.kind.direction == kind.direction &&
                abs(it.date - date) <= TransactionReconciliationEngine.WEAK_MATCH_WINDOW_MS
        }
    }
}
