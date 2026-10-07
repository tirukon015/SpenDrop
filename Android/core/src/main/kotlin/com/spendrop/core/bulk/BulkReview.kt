package com.spendrop.core.bulk

import com.spendrop.core.duplicates.DuplicateCheckResult
import com.spendrop.core.duplicates.DuplicateDetector
import com.spendrop.core.model.Expense
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.parser.CategoryDetector
import com.spendrop.core.parser.ParsedTransaction
import com.spendrop.core.parser.ParsingConfidence
import java.time.ZoneId

/** Shared Bulk Import rules (Common/BusinessRules/bulk-import.md §2–3), independent of any UI. */
object BulkReview {
    enum class Status { READY, NEEDS_REVIEW, POSSIBLE_DUPLICATE }
    enum class DuplicateChoice { SKIP, ADD_ANYWAY, MERGE }

    /** What the review queue knows about one draft (built from the platform's normal editor state). */
    data class DraftFacts(
        val valid: Boolean,
        val merchantFound: Boolean,
        val confidence: ParsingConfidence,
        val failedOrBalanceOnly: Boolean,
        val duplicate: DuplicateCheckResult,
        val choice: DuplicateChoice?,
        val removed: Boolean = false,
    )

    fun status(f: DraftFacts): Status = when {
        f.duplicate.isDuplicate && (f.choice == null || f.choice == DuplicateChoice.SKIP) -> Status.POSSIBLE_DUPLICATE
        !f.valid || !f.merchantFound || f.confidence == ParsingConfidence.LOW || f.failedOrBalanceOnly -> Status.NEEDS_REVIEW
        else -> Status.READY
    }

    /** Saved only when kept, valid, and (if a possible duplicate) the user chose Add Anyway or Merge. */
    fun willSave(f: DraftFacts): Boolean =
        !f.removed && f.valid && (!f.duplicate.isDuplicate || f.choice == DuplicateChoice.ADD_ANYWAY || f.choice == DuplicateChoice.MERGE)

    /**
     * The existing duplicate detector, first against saved expenses, then against the drafts BEFORE this one in the
     * batch (the same payment screenshotted twice). [earlierDrafts] are the earlier drafts as unsaved Expense values.
     */
    fun duplicate(
        amountMinor: Long?, merchant: String?, date: Long?, reference: String?,
        saved: List<Expense>, earlierDrafts: List<Expense>,
        channel: com.spendrop.core.model.PaymentChannel? = null, funding: String? = null, now: Long = System.currentTimeMillis(),
    ): DuplicateCheckResult {
        val vsSaved = DuplicateDetector.checkDuplicate(amountMinor, merchant, date, reference, saved, channel, funding, now)
        if (vsSaved.isDuplicate) return vsSaved
        val vsBatch = DuplicateDetector.checkDuplicate(amountMinor, merchant, date, reference, earlierDrafts, channel, funding, now)
        // A match inside the batch can't be merged (nothing is saved yet): it is reported as a weak duplicate.
        return if (vsBatch.isDuplicate) vsBatch.copy(isStrong = false, reason = "Also in this import: ${vsBatch.matchedExpense?.merchant ?: "another screenshot"}. ${vsBatch.reason ?: ""}".trim()) else vsBatch
    }

    /** A list row (§1) as a normal parsed transaction for the existing editor. Nothing beyond the row is guessed. */
    fun rowToParsed(row: ScreenshotSplitter.Row, line: String, zone: ZoneId = ZoneId.systemDefault()): ParsedTransaction {
        val cat = CategoryDetector.suggest(row.merchant, line)
        return ParsedTransaction(
            amountMinor = row.amountMinor,
            merchant = row.merchant,
            date = row.date.atTime(row.time).atZone(zone).toInstant().toEpochMilli(),
            localDateTime = row.date.atTime(row.time),
            category = cat.category.takeIf { cat.confidence > 0 },
            categoryConfidence = cat.confidence,
            categoryReason = cat.reason,
            suggestedMovementKind = if (row.direction == "in") MoneyMovementKind.OTHER_IN else null,
            directionReason = if (row.direction == "in") "the history shows it as money in (+)" else null,
            confidence = ParsingConfidence.MEDIUM,
            rawOCRText = line,
            detectedLines = listOf(line),
            isCompletedTransaction = true,
        )
    }

}
