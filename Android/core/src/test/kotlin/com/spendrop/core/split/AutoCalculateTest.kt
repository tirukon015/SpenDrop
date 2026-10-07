package com.spendrop.core.split

import com.spendrop.core.Money
import com.spendrop.core.ledger.TestStore
import com.spendrop.core.model.SplitMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS AutoCalculateTests ("Auto Calculate & fixed", `--run-auto-calculate-tests`) + the Auto Calculate cases of DebtSettlementTests. */
class AutoCalculateTest {
    private val store = TestStore()
    private val vijay = store.person("Vijay")
    private val riyadh = store.person("Riyadh")

    private fun threeWay(total: Long) = SplitDraft().add(vijay).add(riyadh).useCustomAmounts(total)
    private fun id(d: SplitDraft, name: String) = d.participants.first { if (it.isMe) name == "Me" else it.name == name }.id

    @Test fun t24_typingOnePersonNeverMakesMeZero() {
        var reg = SplitDraft(method = SplitMethod.AMOUNTS).add(vijay).add(riyadh)
        reg = reg.setAmountText("50", id(reg, "Vijay"), 20000)
        var pre = threeWay(20000)
        pre = pre.setAmountText("50", id(pre, "Vijay"), 20000)
        assertEquals(listOf(7500L, 5000L, 7500L), reg.shares(20000))
        assertEquals(listOf(7500L, 5000L, 7500L), pre.shares(20000))
        assertEquals("75.00", reg.displayAmountText(id(reg, "Me"), 20000))
    }

    @Test fun t22_fixedAmountBasePlusEqualPart() {
        val fixed = threeWay(20000).let { it.setFixed(5000, id(it, "Vijay"), 20000) }
        assertNotNull(fixed)
        assertEquals(listOf(5000L, 10000L, 5000L), fixed!!.shares(20000))
        assertEquals(5000L, fixed.fixedTotalMinor)
        assertEquals(0L, fixed.remainingMinor(20000))
        assertTrue(fixed.isValid(20000))
    }

    @Test fun t25_severalFixedAmounts() {
        var m = threeWay(30000)
        m = m.setFixed(6000, id(m, "Vijay"), 30000)!!.setFixed(4000, id(m, "Riyadh"), 30000)!!
        assertEquals(listOf(6667L, 12667L, 10666L), m.shares(30000))
    }

    @Test fun t9_fixedAmountForMe() {
        val m = threeWay(20000).let { it.setFixed(6000, id(it, "Me"), 20000)!! }
        assertEquals(listOf(10667L, 4667L, 4666L), m.shares(20000))
    }

    @Test fun t26_senAreKept() {
        val cents = threeWay(15050).let { it.setFixed(5050, id(it, "Vijay"), 15050)!! }
        var typed = threeWay(10000)
        typed = typed.setAmountText("33.33", id(typed, "Vijay"), 10000).setAmountText("66.67", id(typed, "Riyadh"), 10000)
        assertEquals(listOf(3334L, 8383L, 3333L), cents.shares(15050))
        assertEquals(listOf(0L, 3333L, 6667L), typed.shares(10000))
        assertEquals(5050L, Money.parseMinor("50.50"))
    }

    @Test fun t27_roundingDeterministic() {
        val a = threeWay(10000).shares(10000)!!; val b = threeWay(10000).shares(10000)!!
        assertEquals(listOf(3334L, 3333L, 3333L), a)
        assertEquals(a, b)
        assertEquals(10000L, a.sum())
    }

    @Test fun t18_fixedValidation() {
        var tooMuch = threeWay(10000)
        tooMuch = tooMuch.setFixed(8000, id(tooMuch, "Vijay"), 10000)!!.setFixed(3000, id(tooMuch, "Riyadh"), 10000)!!
        val negative = threeWay(10000)
        val refused = negative.setFixed(-1000, id(negative, "Vijay"), 10000)
        var exact = threeWay(10000)
        exact = exact.setFixed(6000, id(exact, "Vijay"), 10000)!!.setFixed(4000, id(exact, "Riyadh"), 10000)!!
        assertEquals("Fixed amounts exceed the expense total by RM 10.00.", tooMuch.problem(10000))
        assertFalse(tooMuch.isValid(10000))
        assertNull(refused)
        assertTrue(negative.participants.all { it.fixedMinor == null })
        assertEquals(listOf(0L, 6000L, 4000L), exact.shares(10000))
    }

    @Test fun t19_everyoneTypedRemainderNeverGivenAway() {
        var d = SplitDraft(method = SplitMethod.AMOUNTS).add(vijay).add(riyadh)
        for ((name, text) in listOf("Me" to "70", "Vijay" to "50", "Riyadh" to "50")) d = d.setAmountText(text, id(d, name))
        assertTrue(d.problem(20000)!!.startsWith("RM 30.00 remains unassigned. Select at least one participant"))
        assertFalse(d.isValid(20000))
    }

    @Test fun t23_t15_autoCalculatePerSplitOffChangesNothingByItself() {
        val firstNew = SplitDraft()
        var off = threeWay(20000).setAutoCalculate(false, 20000)
        val frozen = off.participants.map { it.amountText }
        off = off.setAmountText("70", id(off, "Me"), 20000).setAmountText("50", id(off, "Vijay"), 20000).setAmountText("50", id(off, "Riyadh"), 20000)
        val short = off.problem(20000); val remaining = off.remainingMinor(20000)
        val afterTyping = off.participants.map { it.amountText }
        off = off.setAmountText("80", id(off, "Riyadh"), 20000)
        val saved = store.expense(20000, "Dinner")
        val savedOK = store.apply(off, saved)
        val secondNew = SplitDraft()
        val fromLastTime = SplitDraft.lastTimeSuggestion("Dinner", store.s)
        assertTrue(firstNew.autoCalculate)
        assertEquals(listOf("66.67", "66.67", "66.66"), frozen)
        assertEquals(listOf("70", "50", "50"), afterTyping)
        assertEquals(3000L, remaining)
        assertEquals("RM 30.00 remains unassigned.", short)
        assertTrue(savedOK)
        assertEquals(listOf(7000L, 5000L, 8000L), store.shares(saved).sortedBy { it.sortIndex }.map { it.amountMinor })
        assertTrue(secondNew.autoCalculate)
        assertTrue(fromLastTime?.autoCalculate ?: true)
        assertFalse(off.autoCalculate)
    }

    @Test fun onFollowsTotalAndFixedChanges() {
        var live = threeWay(20000)
        live = live.setFixed(5000, id(live, "Vijay"), 20000)!!
        val at200 = live.shares(20000); val at230 = live.shares(23000)
        live = live.setFixed(null, id(live, "Vijay"), 23000)!!
        assertEquals(listOf(5000L, 10000L, 5000L), at200)
        assertEquals(listOf(6000L, 11000L, 6000L), at230)
        assertEquals(listOf(7667L, 7667L, 7666L), live.shares(23000))
    }

    @Test fun t20_savedSharesReopenWithAutoCalculateOnUnchanged() {
        val fixed = threeWay(20000).let { it.setFixed(5000, id(it, "Vijay"), 20000)!! }
        val dinner = store.expense(20000, "Fixed dinner")
        store.apply(fixed, dinner)
        val stored = store.shares(dinner).sortedBy { it.sortIndex }.map { it.amountMinor }
        val reopened = SplitDraft.fromExpense(store.expense(dinner.id), store.shares(dinner), store.s.people)
        assertEquals(listOf(5000L, 10000L, 5000L), stored)
        assertEquals(20000L, stored.sum())
        // Auto Calculate is on by default even when reopening; the saved amounts don't move.
        assertEquals(true, reopened?.autoCalculate)
        assertEquals(listOf(5000L, 10000L, 5000L), reopened?.shares(20000))
        assertTrue(reopened!!.isCalculated(reopened.participants[0].id)) // Me = total − the others
        assertFalse(reopened.isCalculated(reopened.participants[1].id))
        assertTrue(store.net(vijay) >= 10000)
    }

    @Test fun t10_paidForSomeoneUnchanged() {
        val d = SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR, method = SplitMethod.AMOUNTS).add(vijay)
        assertEquals(listOf(0L, 10000L), d.shares(10000))
    }

    @Test fun t21_existingAmountsExpenseLoadsExactly() {
        val old = store.expense(9000, "Old amounts")
        var d = SplitDraft(method = SplitMethod.AMOUNTS, autoCalculate = false).add(vijay)
        d = d.setAmountText("60", d.participants[0].id).setAmountText("30", d.participants[1].id)
        store.apply(d, old)
        val before = store.shares(old).map { it.amountMinor }.sorted()
        val loaded = SplitDraft.fromExpense(store.expense(old.id), store.shares(old), store.s.people)!!
        assertEquals(listOf(6000L, 3000L), loaded.shares(9000))
        assertTrue(loaded.autoCalculate)
        // Editing someone else's amount now recalculates Me automatically
        assertEquals(listOf(5000L, 4000L), loaded.setAmountText("40", loaded.participants[1].id, 9000).shares(9000))
        assertTrue(loaded.participants.all { it.fixedMinor == null })
        assertEquals(before, store.shares(old).map { it.amountMinor }.sorted())
    }

    // DebtSettlementTests: "Amounts: Auto Calculate ON / OFF and validation"
    @Test fun autoOnMeTypedBijoyFollows() {
        val bijoy = store.person("Bijoy")
        var auto = SplitDraft(method = SplitMethod.AMOUNTS).add(bijoy)
        val me = auto.participants[0].id
        auto = auto.setAmountText("0.01", me, 700)
        val first = auto.participants[1].amountText
        auto = auto.setAmountText("2", me, 700)
        assertEquals("6.99", first)
        assertEquals("5.00", auto.participants[1].amountText)
        assertTrue(auto.isValid(700))
        assertEquals(0L, auto.remainingMinor(700))

        val labib = store.person("Labib")
        var three = SplitDraft(method = SplitMethod.AMOUNTS).add(bijoy).add(labib)
        three = three.setAmountText("30", three.participants[0].id, 10000).setAmountText("20", three.participants[1].id, 10000)
        assertEquals("50.00", three.participants[2].amountText)
        assertTrue(three.isValid(10000))

        var manual = SplitDraft(method = SplitMethod.AMOUNTS, autoCalculate = false).add(bijoy)
        manual = manual.setAmountText("30", manual.participants[0].id, 10000)
        val untouched = manual.participants[1].amountText
        manual = manual.setAmountText("60", manual.participants[1].id, 10000)
        val short = manual.problem(10000)
        manual = manual.setAmountText("75", manual.participants[1].id, 10000)
        val over = manual.problem(10000)
        manual = manual.setAmountText("70", manual.participants[1].id, 10000)
        assertEquals("", untouched)
        assertEquals("RM 10.00 remains unassigned.", short)
        assertEquals("Shares exceed the total by RM 5.00.", over)
        assertTrue(manual.isValid(10000))
        assertEquals(0L, manual.remainingMinor(10000))
    }

    @Test fun allTypedWithTotalHandsOldestBackToAutoCalculate() {
        var d = SplitDraft(method = SplitMethod.AMOUNTS).add(vijay)
        d = d.setAmountText("30", d.participants[0].id, 10000)
        d = d.setAmountText("40", d.participants[1].id, 10000) // Me (typed first) is handed back: 60
        assertEquals(listOf(d.participants[1].id), d.typedOrder)
        assertTrue(d.isCalculated(d.participants[0].id))
        assertEquals("60.00", d.participants[0].amountText)
        assertEquals(listOf(6000L, 4000L), d.shares(10000))
        // Clearing the box hands the person back to Auto Calculate.
        d = d.setAmountText("", d.participants[1].id, 10000)
        assertEquals(listOf(5000L, 5000L), d.shares(10000))
    }

    @Test fun problemMessagesForEveryCalculatorError() {
        assertEquals("Enter the expense amount first.", SplitDraft().add(vijay).problem(0))
        assertEquals("Choose who you paid for.", SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR).problem(100))
        assertEquals("Parts must be whole numbers from 1 to 99.",
            SplitDraft(method = SplitMethod.PARTS, participants = listOf(SplitDraft.Participant.me().copy(parts = 0), SplitDraft.Participant(name = "X"))).problem(100))
        var off = SplitDraft(method = SplitMethod.AMOUNTS, autoCalculate = false).add(vijay)
        off = off.setAmountText("1", off.participants[0].id)
        // iOS 2026-10-07: Vijay's empty box is RM 0.00, so RM 1.00 of RM 1.00 is complete; non-numbers are reported.
        assertEquals(null, off.problem(100))
        off = off.setAmountText("x", off.participants[1].id)
        assertEquals("Enter a valid amount for Vijay.", off.problem(100))
        off = off.setAmountText("-1", off.participants[1].id)
        assertEquals("Vijay's amount can't be negative.", off.problem(100))
    }
}
