package com.spendrop.core.ledger

import com.spendrop.core.split.SplitDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/** iOS PayBookFilterTests ("PayBook filter", `--run-paybook-filter-tests`). One store, steps in order. */
class PayBookFilterTest {
    private val store = TestStore()
    private fun names(f: PayBookBalanceFilter) = PersonLedger.outstanding(store.s, store.s.people, f).map { it.person.name }
    private fun amounts(f: PayBookBalanceFilter) = PersonLedger.outstanding(store.s, store.s.people, f).map { it.amountMinor }

    @Test fun theyOweMeIOweThem() {
        val bijoy = store.person("Bijoy"); val kamal = store.person("Kamal"); val riyad = store.person("Riyad")
        val labib = store.person("Labib"); val karim = store.person("Karim"); val rahim = store.person("Rahim")
        val settled = store.person("Settled Sam")
        store.paidFor(bijoy, 10899, "Bijoy dinner", daysAgo = 5)
        val kamalExpense = store.paidFor(kamal, 9999, "Kamal ticket", daysAgo = 4)
        val riyadExpense = store.paidFor(riyad, 4370, "Riyad lunch", daysAgo = 3)
        store.paidForMe(labib, 8000, "Labib paid", daysAgo = 5)
        store.paidForMe(karim, 4500, "Karim paid", daysAgo = 4)
        store.paidForMe(rahim, 2000, "Rahim paid", daysAgo = 3)
        store.paidFor(settled, 1000, "Sam coffee")
        store.apply(SettlementService.markPaid(store.debts(settled)[0], settled, store.now()))

        assertEquals(listOf("Bijoy", "Kamal", "Riyad"), names(PayBookBalanceFilter.THEY_OWE_ME))
        assertEquals(listOf(10899L, 9999L, 4370L), amounts(PayBookBalanceFilter.THEY_OWE_ME))
        assertEquals(listOf("Labib", "Karim", "Rahim"), names(PayBookBalanceFilter.I_OWE_THEM))
        assertEquals(listOf(8000L, 4500L, 2000L), amounts(PayBookBalanceFilter.I_OWE_THEM))
        assertFalse("Settled Sam" in names(PayBookBalanceFilter.THEY_OWE_ME))
        assertFalse("Settled Sam" in names(PayBookBalanceFilter.I_OWE_THEM))
        assertTrue(names(PayBookBalanceFilter.ALL).isEmpty())
        assertTrue(PersonLedger.hasHistory(store.s, settled))
        assertTrue(store.s.people.all { p ->
            val row = PersonLedger.outstanding(store.s, listOf(p), PayBookBalanceFilter.THEY_OWE_ME).firstOrNull()
                ?: PersonLedger.outstanding(store.s, listOf(p), PayBookBalanceFilter.I_OWE_THEM).firstOrNull()
            (row?.amountMinor ?: 0) == abs(store.net(p))
        })

        // Ties: same amount → most recent activity first
        val older = store.person("Older"); val newer = store.person("Newer")
        store.paidFor(older, 5000, "Old", daysAgo = 20)
        store.paidFor(newer, 5000, "New", daysAgo = 1)
        assertEquals(listOf("Newer", "Older"), names(PayBookBalanceFilter.THEY_OWE_ME).filter { it in listOf("Older", "Newer") })

        // Crossing zero
        store.apply(SettlementService.settleAll(store.s, bijoy, "RM", store.now()))
        val afterPayment = "Bijoy" in names(PayBookBalanceFilter.THEY_OWE_ME) || "Bijoy" in names(PayBookBalanceFilter.I_OWE_THEM)
        store.paidForMe(bijoy, 2000, "Bijoy paid for me")
        assertFalse(afterPayment)
        assertTrue("Bijoy" in names(PayBookBalanceFilter.I_OWE_THEM))
        assertFalse("Bijoy" in names(PayBookBalanceFilter.THEY_OWE_ME))
        assertEquals(2000L, PersonLedger.outstanding(store.s, listOf(bijoy), PayBookBalanceFilter.I_OWE_THEM).first().amountMinor)
        store.paidFor(labib, 10000, "I paid for Labib")
        assertTrue("Labib" in names(PayBookBalanceFilter.THEY_OWE_ME))
        assertFalse("Labib" in names(PayBookBalanceFilter.I_OWE_THEM))
        assertEquals(2000L, PersonLedger.outstanding(store.s, listOf(labib), PayBookBalanceFilter.THEY_OWE_ME).first().amountMinor)

        // Editing and deleting transactions
        val changed = store.setAmount(kamalExpense, 12000)
        SplitDraft.recalculateAfterAmountChange(changed, store.shares(changed), store.s.people, store.now()).save?.let(store::save)
        store.deleteExpense(riyadExpense)
        assertEquals("Kamal", names(PayBookBalanceFilter.THEY_OWE_ME).first())
        assertEquals(12000L, amounts(PayBookBalanceFilter.THEY_OWE_ME).first())
        assertFalse("Riyad" in names(PayBookBalanceFilter.THEY_OWE_ME))
    }

    @Test fun sameAmountAndActivityTieBreaksByNameCaseInsensitive() {
        val b = store.person("bob"); val a = store.person("Alice")
        store.paidFor(b, 1000, "x"); store.paidFor(a, 1000, "y")
        assertEquals(listOf("Alice", "bob"), names(PayBookBalanceFilter.THEY_OWE_ME))
    }
}
