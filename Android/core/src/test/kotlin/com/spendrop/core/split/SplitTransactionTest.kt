package com.spendrop.core.split

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.ledger.SettlementService
import com.spendrop.core.ledger.TestStore
import com.spendrop.core.model.Expense
import com.spendrop.core.model.SplitMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS SplitTransactionTests ("Split transaction", `--run-split-transaction-tests`), minus the OCR/screen parts. */
class SplitTransactionTest {
    private val store = TestStore()
    private val bijoy = store.person("Bijoy")
    private val riyad = store.person("Riyad")

    /** What Add Expense does on Save: the expense is created only when the split is valid, then the split is applied. */
    private fun save(minor: Long, title: String, draft: SplitDraft?): Expense? {
        if (draft != null && !draft.isValid(minor)) return null
        val e = store.expense(minor, title)
        if (draft != null) assertTrue(store.apply(draft, e))
        return store.expense(e.id)
    }

    private fun custom(draft: SplitDraft, amounts: List<String>, total: Long): SplitDraft {
        var d = draft.useCustomAmounts(total).copy(autoCalculate = false)
        amounts.forEachIndexed { i, text -> d = d.setAmountText(text, d.participants[i].id, total) }
        return d
    }

    private fun shares(e: Expense?): Map<String, Long> =
        store.shares(e!!).groupBy { if (it.isMe) "Me" else it.nameSnapshot }.mapValues { (_, v) -> v.sumOf { it.amountMinor } }

    @Test fun endToEnd() {
        // 1. Normal transaction
        val normal = save(4500, "Groceries", null)!!
        assertFalse(ExpenseMath.isShared(store.shares(normal)))
        assertEquals(4500L, ExpenseMath.myShareMinor(normal, store.shares(normal)))
        assertEquals(0L, store.net(bijoy)); assertEquals(0L, store.net(riyad))

        // 2. Two-person equal split
        val dinnerEqual = save(10000, "Dinner equal", SplitDraft().add(bijoy))!!
        assertEquals(mapOf("Me" to 5000L, "Bijoy" to 5000L), shares(dinnerEqual))
        assertEquals(5000L, store.net(bijoy))

        // 3/9. Custom 70/30 and 40/60
        val d7030 = save(10000, "Dinner 70/30", custom(SplitDraft().add(bijoy), listOf("70", "30"), 10000))
        val after7030 = store.net(bijoy)
        val d4060 = save(10000, "Dinner 40/60", custom(SplitDraft().add(bijoy), listOf("40", "60"), 10000))!!
        assertEquals(mapOf("Me" to 7000L, "Bijoy" to 3000L), shares(d7030))
        assertEquals(8000L, after7030)
        assertEquals(mapOf("Me" to 4000L, "Bijoy" to 6000L), shares(d4060))
        assertEquals(14000L, store.net(bijoy))

        // 4. Several people
        val a = store.person("Person A"); val b = store.person("Person B"); val c = store.person("Person C")
        val big = save(30000, "Trip", custom(SplitDraft().add(a).add(b).add(c), listOf("100", "80", "70", "50"), 30000))
        assertNotNull(big)
        assertEquals(listOf(8000L, 7000L, 5000L), listOf(store.net(a), store.net(b), store.net(c)))
        assertEquals(10000L, ExpenseMath.myShareMinor(big!!, store.shares(big)))

        // 5–7. Allocation must equal the total exactly
        val exact = custom(SplitDraft().add(bijoy).add(riyad), listOf("60", "30", "10"), 10000)
        val short = custom(SplitDraft().add(bijoy), listOf("60", "20"), 10000)
        val over = custom(SplitDraft().add(bijoy), listOf("80", "40"), 10000)
        assertEquals(0L, exact.remainingMinor(10000)); assertTrue(exact.isValid(10000))
        val countBefore = store.s.expenses.size
        assertNull(save(10000, "Short", short)); assertNull(save(10000, "Over", over))
        assertEquals(2000L, short.remainingMinor(10000))
        assertEquals("RM 20.00 remains unassigned.", short.problem(10000))
        assertEquals(-2000L, over.remainingMinor(10000))
        assertTrue(over.problem(10000)!!.contains("exceed"))
        assertEquals(countBefore, store.s.expenses.size)

        // 8. Rounding; switching to Custom Amount starts from the exact shares
        val thirds = SplitDraft().add(bijoy).add(riyad)
        val thirdShares = thirds.shares(10000)!!
        val prefilled = thirds.useCustomAmounts(10000)
        assertEquals(10000L, thirdShares.sum())
        assertEquals(setOf(3333L, 3334L), thirdShares.toSet())
        assertEquals(listOf(5000L, 5000L, 5000L), SplitDraft().add(bijoy).add(riyad).shares(15000))
        assertEquals(SplitMethod.AMOUNTS, prefilled.method)
        assertEquals(10000L, prefilled.assignedTypedMinor())
        assertTrue(prefilled.isValid(10000))

        // 11. Editing: new total, new shares
        var edit = SplitDraft.fromExpense(store.expense(dinnerEqual.id), store.shares(dinnerEqual), store.s.people)!!
        val bijoyBeforeEdit = store.net(bijoy)
        store.setAmount(dinnerEqual, 12000)
        edit = edit.useCustomAmounts(12000)
        edit = edit.setAmountText("90", edit.participants[0].id).setAmountText("30", edit.participants[1].id)
        assertTrue(edit.isValid(12000))
        store.apply(edit, dinnerEqual)
        assertEquals(mapOf("Me" to 9000L, "Bijoy" to 3000L), shares(dinnerEqual))
        assertEquals(bijoyBeforeEdit - 2000, store.net(bijoy))
        assertEquals(2, store.shares(dinnerEqual).size)

        // 12. Removing a participant
        val cinema = save(9000, "Cinema", SplitDraft().add(bijoy).add(riyad))!!
        val riyadWith = store.net(riyad); val bijoyWith = store.net(bijoy)
        var removing = SplitDraft.fromExpense(store.expense(cinema.id), store.shares(cinema), store.s.people)!!
        removing = removing.remove(removing.participants.first { it.person?.id == riyad.id }.id).useEqualSplit()
        store.apply(removing, cinema)
        assertEquals(3000L, riyadWith - store.net(riyad))
        assertEquals(1500L, store.net(bijoy) - bijoyWith)
        assertEquals(2, store.shares(cinema).size)
        assertFalse(store.shares(cinema).any { it.personId == riyad.id })
        assertTrue(store.s.people.any { it.id == riyad.id })

        // 13. Deleting a split
        val bijoyBeforeDelete = store.net(bijoy)
        val expensesBefore = store.s.expenses.size
        store.deleteExpense(d4060)
        assertEquals(6000L, bijoyBeforeDelete - store.net(bijoy))
        assertEquals(expensesBefore - 1, store.s.expenses.size)

        // 15. The normal transaction is unchanged
        assertEquals(normal, store.expense(normal.id))
        assertFalse(ExpenseMath.isShared(store.shares(normal)))
    }

    @Test fun t10_someoneElsePaidIOweThem() {
        var theyPaid = SplitDraft().add(bijoy).setPayer(bijoy).useCustomAmounts(10000).copy(autoCalculate = false)
        theyPaid = theyPaid.setAmountText("70", theyPaid.participants[0].id).setAmountText("30", theyPaid.participants[1].id)
        val lunch = store.expense(10000, "Lunch"); store.apply(theyPaid, lunch)
        val taxi = store.expense(2000, "Taxi")
        store.apply(SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR).setPayer(bijoy), taxi)
        val l = store.expense(lunch.id)
        assertEquals(-9000L, store.net(bijoy))
        assertFalse(l.paidByMe)
        assertEquals(7000L, ExpenseMath.myShareMinor(l, store.shares(l)))
    }

    @Test fun t14_settlingTheSplit() {
        var s3 = SplitDraft().add(bijoy).useCustomAmounts(10000).copy(autoCalculate = false)
        s3 = s3.setAmountText("70", s3.participants[0].id).setAmountText("30", s3.participants[1].id)
        val meal = store.expense(10000, "Dinner"); store.apply(s3, meal)
        val owedBefore = store.net(bijoy)
        store.apply(SettlementService.markPaid(store.debts(bijoy).first(), bijoy, store.now()))
        assertEquals(3000L, owedBefore)
        assertEquals(0L, store.net(bijoy))
        assertTrue(store.debts(bijoy).all { it.outstandingMinor == 0L })
        assertEquals(1, store.s.expenses.size)
        assertEquals(2, store.shares(meal).size)
    }

    @Test fun t16_t17_savingAgainNeverDuplicates() {
        val again = SplitDraft().add(bijoy)
        val pizza = store.expense(6000, "Pizza")
        store.apply(again, pizza)
        var reopened = SplitDraft.fromExpense(store.expense(pizza.id), store.shares(pizza), store.s.people)!!
        store.apply(reopened, pizza); store.apply(again, pizza)
        assertEquals(3000L, store.net(bijoy))
        assertEquals(1, store.debts(bijoy).size)
        reopened = SplitDraft.fromExpense(store.expense(pizza.id), store.shares(pizza), store.s.people)!!
        val added = reopened.add(bijoy)
        assertEquals(2, store.shares(pizza).size)
        assertEquals(2, store.s.shares.size)
        assertSame(reopened, added)
        assertEquals(2, added.participants.size)
    }

    @Test fun t19_mismatchedSplitNeverSaved() {
        var split = SplitDraft().add(bijoy).add(riyad).useCustomAmounts(10000).copy(autoCalculate = false)
        split = split.setAmountText("40", split.participants[0].id).setAmountText("30", split.participants[1].id).setAmountText("30", split.participants[2].id)
        val wrong = split.setAmountText("50", split.participants[0].id)
        val mismatch = store.expense(10000, "X")
        assertFalse(wrong.isValid(10000))
        assertFalse(store.apply(wrong, mismatch))
        assertTrue(store.shares(mismatch).isEmpty())
        assertEquals(10000L, store.expense(mismatch.id).amountMinor)
        // the valid 40/30/30 split saves with 3 shares
        assertTrue(store.apply(split, mismatch))
        assertEquals(3, store.shares(mismatch).size)
        assertEquals(3000L, store.net(bijoy)); assertEquals(3000L, store.net(riyad))
    }
}
