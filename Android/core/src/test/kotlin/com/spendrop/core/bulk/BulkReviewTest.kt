package com.spendrop.core.bulk

import com.spendrop.core.bulk.BulkReview.DraftFacts
import com.spendrop.core.bulk.BulkReview.DuplicateChoice
import com.spendrop.core.bulk.BulkReview.Status
import com.spendrop.core.duplicates.DuplicateCheckResult
import com.spendrop.core.model.Expense
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.parser.ParsingConfidence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset

class BulkReviewTest {
    private val dup = DuplicateCheckResult(true, null, "Same reference", isStrong = true)
    private fun facts(valid: Boolean = true, merchant: Boolean = true, conf: ParsingConfidence = ParsingConfidence.HIGH, d: DuplicateCheckResult = DuplicateCheckResult.NONE, choice: DuplicateChoice? = null, removed: Boolean = false) =
        DraftFacts(valid, merchant, conf, false, d, choice, removed)

    @Test fun statuses() {
        assertEquals(Status.READY, BulkReview.status(facts()))
        assertEquals(Status.NEEDS_REVIEW, BulkReview.status(facts(merchant = false)))
        assertEquals(Status.NEEDS_REVIEW, BulkReview.status(facts(valid = false)))
        assertEquals(Status.NEEDS_REVIEW, BulkReview.status(facts(conf = ParsingConfidence.LOW)))
        assertEquals(Status.POSSIBLE_DUPLICATE, BulkReview.status(facts(d = dup)))
        assertEquals(Status.POSSIBLE_DUPLICATE, BulkReview.status(facts(d = dup, choice = DuplicateChoice.SKIP)))
        assertEquals(Status.READY, BulkReview.status(facts(d = dup, choice = DuplicateChoice.ADD_ANYWAY)))
    }

    @Test fun addCountRules() {
        val drafts = listOf(facts(), facts(), facts(d = dup), facts(removed = true), facts(valid = false), facts(d = dup, choice = DuplicateChoice.MERGE))
        // duplicate defaults to skip, removed and invalid drafts are excluded
        assertEquals(3, drafts.count(BulkReview::willSave))
        assertTrue(BulkReview.willSave(facts(merchant = false))) // needs review but valid: still saved as entered
    }

    @Test fun sameScreenshotTwiceInOneBatchIsCaught_andCantBeMerged() {
        val t = 1_790_000_000_000L
        val first = Expense("d1", 1850, merchant = "McDonald's", transactionReference = "TNG992837194", date = t, createdAt = t, updatedAt = t)
        val r = BulkReview.duplicate(1850, "McDonald's", t, "TNG992837194", saved = emptyList(), earlierDrafts = listOf(first), now = t)
        assertTrue(r.isDuplicate); assertFalse(r.isStrong)
        assertTrue(r.reason!!.startsWith("Also in this import"))
        // different payments in one batch are not duplicates
        assertFalse(BulkReview.duplicate(1290, "Grab", t, null, emptyList(), listOf(first), now = t).isDuplicate)
        // a saved match stays strong (merge possible)
        assertTrue(BulkReview.duplicate(1850, "McDonald's", t, "TNG992837194", saved = listOf(first), earlierDrafts = emptyList(), now = t).isStrong)
    }

    @Test fun listRowsBecomeNormalParsedTransactionsWithTheirOwnDate() {
        val row = ScreenshotSplitter.Row("DUITNOW FROM ALI", 5000, "in", LocalDate.of(2026, 10, 6), LocalTime.of(14, 5))
        val p = BulkReview.rowToParsed(row, "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", ZoneOffset.UTC)
        assertEquals(5000L, p.amountMinor)
        assertEquals(LocalDate.of(2026, 10, 6).atTime(14, 5).toInstant(ZoneOffset.UTC).toEpochMilli(), p.date)
        assertEquals(MoneyMovementKind.OTHER_IN, p.suggestedMovementKind)
        assertEquals(null, p.fundingAccount) // nothing guessed
    }
}
