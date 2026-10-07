package com.spendrop.core.insights

import com.spendrop.core.duplicates.DuplicateDetector
import com.spendrop.core.duplicates.MovementDuplicateDetector
import com.spendrop.core.duplicates.ReconcileCandidate
import com.spendrop.core.duplicates.TransactionReconciliationEngine
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ports of iOS duplicate checks: SplitFeatureTests "Duplicate detection", Phase7Tests "Movement duplicates",
 * TransactionParserTests duplicate / reconciliation scenarios.
 */
class DuplicateDetectionTest {
    private val engine = TransactionReconciliationEngine
    private val base = 1_790_000_000_000L

    @Test fun amountAloneNeverCounts_splitFeature() {
        val existing = TK.expense(100.0, "Bijoy", base, reference = "TNG-123456")
        val list = listOf(existing)
        fun find(amount: Long, merchant: String, date: Long, ref: String?) = engine.findMatch(amount, merchant, date, ref, list, now = base)
        val labib = find(10000, "Labib", base + 60_000, null)
        val nextDay = find(10000, "Bijoy", base + 86_400_000, null)
        val evening = find(10000, "Bijoy", base + 8 * 3_600_000, null)
        val sameMinute = find(10000, "bijoy ", base + 120_000, null)
        val sameRef = find(10000, "Other", base + 3_600_000, "tng-123456")
        val otherAmount = find(9900, "Bijoy", base, null)
        assertFalse(labib.isMatch); assertFalse(nextDay.isMatch); assertFalse(evening.isMatch)
        assertTrue(sameMinute.isMatch); assertFalse(sameMinute.isStrong); assertEquals(0.6, sameMinute.confidence, 0.0)
        assertTrue(sameRef.isMatch); assertTrue(sameRef.isStrong); assertSame(existing, sameRef.matchedExpense)
        assertFalse(otherAmount.isMatch)
        assertTrue(sameRef.reason!!.startsWith("A payment with the same reference (tng-123456) is already recorded: Bijoy, RM 100.00, "))
        assertTrue(sameMinute.reason!!.startsWith("Possible duplicate: RM 100.00 at Bijoy on "))
        assertTrue(sameMinute.reason!!.endsWith(" is already recorded. If this is a separate payment, add it anyway."))
    }

    @Test fun strongWindowAndReferenceRules() {
        val existing = TK.expense(50.0, "Shop", base, reference = "ABCD")
        val list = listOf(existing)
        assertTrue(engine.findMatch(5000, "X", base + 48 * 3_600_000, " abcd ", list).isStrong)
        assertFalse(engine.findMatch(5000, "X", base + 48 * 3_600_000 + 1, "ABCD", list).isMatch)
        // Reference must be >= 4 chars; a different amount never matches even with the same reference
        assertFalse(engine.findMatch(5000, "X", base, "ABC", listOf(existing.copy(transactionReference = "ABC"))).isMatch)
        assertFalse(engine.findMatch(5001, "Shop", base, "ABCD", list).isMatch)
        // No / zero amount never matches; Unknown merchant never weak-matches
        assertFalse(engine.findMatch(null, "Shop", base, "ABCD", list).isMatch)
        assertFalse(engine.findMatch(0, "Shop", base, "ABCD", list).isMatch)
        assertFalse(engine.findMatch(5000, "Unknown", base, null, listOf(existing.copy(merchant = "Unknown"))).isMatch)
        // Deleted records are ignored
        assertFalse(engine.findMatch(5000, "Shop", base, "ABCD", listOf(existing.copy(deletedAt = base))).isMatch)
        // Date nil = now
        assertTrue(engine.findMatch(5000, "shop", null, null, list, now = base + 15 * 60_000).isMatch)
        assertFalse(engine.findMatch(5000, "shop", null, null, list, now = base + 15 * 60_000 + 1).isMatch)
    }

    @Test fun weakMatchNeedsCompatibleChannelAndFunding() {
        val existing = TK.expense(20.0, "Kedai", base, fundingAccount = "Maybank", channel = PaymentChannel.APPLE_PAY)
        val list = listOf(existing)
        fun m(ch: PaymentChannel?, f: String?) = engine.findMatch(2000, "KEDAI", base + 60_000, null, list, ch, f).isMatch
        assertTrue(m(null, null))
        assertTrue(m(PaymentChannel.UNKNOWN, "unknown"))
        assertTrue(m(PaymentChannel.APPLE_PAY, " maybank "))
        assertFalse("Apple Pay vs QR is a different payment", m(PaymentChannel.QR_PAYMENT, null))
        assertFalse("Maybank vs CIMB is a different payment", m(null, "CIMB"))
        assertTrue(m(null, "Other"))
        assertTrue(engine.compatibleFunding("x", "Unknown"))
    }

    @Test fun duplicateDetector_parserSuite() {
        val existing = TK.expense(18.50, "McDonald's", base, category = ExpenseCategory.FOOD, paymentSource = PaymentSource.TOUCH_N_GO, reference = "TNG12345")
        assertEquals("Touch 'n Go", existing.fundingAccount)
        val dup = DuplicateDetector.checkDuplicate(1850, "McDonald's", base, "TNG12345", listOf(existing))
        assertTrue("Duplicate Detection (Identical Transaction)", dup.isDuplicate)
        assertTrue(dup.isStrong)
        val unique = DuplicateDetector.checkDuplicate(9900, "Uniqlo", base, "UNIQLO999", listOf(existing))
        assertFalse("Unique Transaction (Non-Duplicate)", unique.isDuplicate)
        assertNull(unique.matchedExpense)
        val saved = TK.expense(22.0, "Test Merchant", base, reference = "REF-TEST-2200")
        assertTrue("Persistence Lifecycle & Duplicate Verification",
            DuplicateDetector.checkDuplicate(2200, "Test Merchant", base, "REF-TEST-2200", listOf(saved)).isDuplicate)
    }

    @Test fun reconciliationIntoOneExpense_scenario13() {
        val exp1 = TK.expense(50.0, "Starbucks", base, category = ExpenseCategory.FOOD, channel = PaymentChannel.APPLE_PAY, fundingAccount = "Unknown")
        val match = engine.findMatch(5000, "Starbucks", base, "MBB12345", listOf(exp1))
        val candidate = ReconcileCandidate(5000, "Starbucks Mid Valley", base, ExpenseCategory.FOOD, "Maybank", PaymentChannel.UNKNOWN,
            "MBB12345", "Bank debit statement")
        val reconciled = engine.reconcile(exp1, candidate, now = base + 1)
        assertTrue(match.isMatch); assertFalse(match.isStrong)
        assertEquals("Maybank", reconciled.effectiveFundingAccount)
        assertEquals(PaymentChannel.APPLE_PAY, reconciled.paymentChannel)
        assertTrue(reconciled.isReconciled)
        assertEquals("MBB12345", reconciled.transactionReference)
        assertEquals(5000L, reconciled.amountMinor)
        assertEquals("Starbucks", reconciled.merchant)
        assertEquals("Bank debit statement", reconciled.notes)
        assertEquals(1.0, reconciled.matchingConfidence!!, 0.0)
        assertEquals(base + 1, reconciled.updatedAt)
        assertEquals(exp1.id, reconciled.id)
    }

    @Test fun reconcileMergeRules() {
        val unknown = TK.expense(9.0, "Unknown", base, notes = "first").copy(fundingInstrument = "", imageRelativePath = null)
        val c = ReconcileCandidate(900, "Cafe", base, paymentChannel = PaymentChannel.CARD, fundingAccount = "CIMB", reference = "R-1",
            notes = "second", imageRelativePath = "img.jpg", fundingInstrument = "Visa 1234")
        val r = engine.reconcile(unknown, c, base)
        assertEquals(PaymentChannel.CARD, r.paymentChannel)
        assertEquals("CIMB", r.fundingAccount)
        assertEquals("Visa 1234", r.fundingInstrument)
        assertEquals("Cafe", r.merchant)
        assertEquals("R-1", r.transactionReference)
        assertEquals("img.jpg", r.imageRelativePath)
        assertEquals("first • second", r.notes)
        // Notes already contained are not repeated; existing values are never overwritten
        val again = engine.reconcile(r, c.copy(notes = "second", merchant = "Other", fundingAccount = "Maybank", paymentChannel = PaymentChannel.CASH), base)
        assertEquals("first • second", again.notes)
        assertEquals("Cafe", again.merchant); assertEquals("CIMB", again.fundingAccount); assertEquals(PaymentChannel.CARD, again.paymentChannel)
        assertEquals("RECONCILED", again.matchingStatusRaw)
    }

    @Test fun movementDuplicates_phase7() {
        val date = base
        val existing = TK.movement(MoneyMovementKind.OTHER_IN, 5000, date, reference = "REF-9")
        val list = listOf(existing)
        val byRef = MovementDuplicateDetector.findMatch(1, date + 9_999_999_000, "REF-9", MoneyMovementKind.INCOME, list)
        val byAmount = MovementDuplicateDetector.findMatch(5000, date + 300_000, null, MoneyMovementKind.INCOME, list)
        val hourLater = MovementDuplicateDetector.findMatch(5000, date + 3_600_000, null, MoneyMovementKind.INCOME, list)
        val otherDirection = MovementDuplicateDetector.findMatch(5000, date, null, MoneyMovementKind.OTHER_OUT, list)
        val later = MovementDuplicateDetector.findMatch(5000, date + 2 * 86_400_000, null, MoneyMovementKind.OTHER_IN, list)
        assertSame(existing, byRef); assertSame(existing, byAmount)
        assertNull(hourLater); assertNull(otherDirection); assertNull(later)
        assertNull("the record being edited is excluded", MovementDuplicateDetector.findMatch(5000, date, "REF-9", MoneyMovementKind.OTHER_IN, list, excludingId = existing.id))
    }
}
