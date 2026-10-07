package com.spendrop.core.split

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.ledger.TestStore
import com.spendrop.core.model.Expense
import com.spendrop.core.model.SplitMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS SplitFeatureTests ("Phase 4", `--run-split-tests`). */
class SplitFeatureTest {
    private val store = TestStore()
    private fun people(vararg names: String) = names.map { store.person(it) }
    private fun SplitDraft.addAll(ps: List<com.spendrop.core.model.Person>) = ps.fold(this) { d, p -> d.add(p) }

    @Test fun equalSplitRm100By4() {
        val d = SplitDraft().addAll(people("A", "B", "C"))
        assertEquals(listOf(2500L, 2500L, 2500L, 2500L), d.shares(10000))
    }

    @Test fun partsMe2A1B1() {
        var d = SplitDraft(method = SplitMethod.PARTS).addAll(people("A", "B"))
        d = d.setParts(2, d.participants[0].id)
        assertEquals(listOf(5000L, 2500L, 2500L), d.shares(10000))
    }

    @Test fun exactAmountsValidMismatchShownAndNeverSaved() {
        var d = SplitDraft(method = SplitMethod.AMOUNTS).addAll(people("A", "B"))
        val ids = d.participants.map { it.id }
        d = d.setAmountText("20", ids[0]).setAmountText("30", ids[1]).setAmountText("50", ids[2])
        val exact = d.shares(10000)
        d = d.setAmountText("40", ids[2])
        val problem = d.problem(10000)
        val expense = store.expense(10000, "Shop")
        val applied = store.apply(d, expense)
        assertEquals(listOf(2000L, 3000L, 5000L), exact)
        assertEquals("RM 10.00 remains unassigned. Select at least one participant for the remaining amount (clear someone's amount).", problem)
        assertFalse(applied)
        assertTrue(store.shares(expense).isEmpty())
        d = d.setAmountText("60", ids[2])
        assertEquals("Shares exceed the total by RM 10.00.", d.problem(10000))
    }

    @Test fun rm10By3LeftoverSenToMe() {
        val shares = SplitDraft().addAll(people("A", "B")).shares(1000)!!
        assertEquals(listOf(334L, 333L, 333L), shares)
        assertEquals(1000L, shares.sum())
    }

    @Test fun minimumTwoParticipantsExactlyOneMeNoDuplicatePerson() {
        var d = SplitDraft()
        val tooFew = d.problem(3000)
        d = d.remove(d.participants[0].id) // Me cannot be removed
        val a = people("A")[0]
        val first = d.add(a)
        val second = first.add(a)
        assertEquals("Add at least one other person.", tooFew)
        assertEquals(1, second.participants.count { it.isMe })
        assertTrue(first !== d)
        assertSame(first, second) // second add refused
        assertEquals(2, second.participants.size)
    }

    @Test fun payerMe() {
        val ppl = people("Bijoy", "Riyad", "Labib")
        val e0 = store.expense(3000, "Dinner")
        assertTrue(store.apply(SplitDraft().addAll(ppl), e0))
        val e = store.expense(e0.id)
        val shares = store.shares(e)
        val balances = FinancialCalculator.personBalances(listOf(e), store.s::sharesOf, emptyList())
        assertTrue(e.paidByMe)
        assertEquals(SplitMethod.EQUAL, e.splitMethod)
        assertEquals(3000L, ExpenseMath.spendingMinor(e, shares))
        assertEquals(3000L, ExpenseMath.cashOutMinor(e))
        assertEquals(750L, ExpenseMath.myShareMinor(e, shares))
        assertTrue(ppl.all { balances[it.id] == 750L })
    }

    @Test fun payerAli() {
        val ppl = people("Ali", "Bob", "Sara")
        val e0 = store.expense(4000, "Lunch")
        store.apply(SplitDraft().addAll(ppl).setPayer(ppl[0]), e0)
        val e = store.expense(e0.id)
        val shares = store.shares(e)
        val balances = FinancialCalculator.personBalances(listOf(e), store.s::sharesOf, emptyList())
        assertFalse(e.paidByMe)
        assertEquals(ppl[0].id, e.payerId)
        assertEquals("Ali", e.payerNameSnapshot)
        assertEquals(1000L, ExpenseMath.spendingMinor(e, shares))
        assertEquals(0L, ExpenseMath.cashOutMinor(e))
        assertEquals(-1000L, balances[ppl[0].id])
        assertNull(balances[ppl[1].id]); assertNull(balances[ppl[2].id])
        val summary = FinancialCalculator.summary(listOf(e), store.s::sharesOf, emptyList())
        assertEquals(1000L, summary.spendingMinor)
        assertEquals(0L, summary.moneyOutMinor)
    }

    @Test fun amountChangeEqualAndPartsRecalculateExactLeftAndFlagged() {
        val ppl = people("A", "B")
        val equal = store.expense(3000, "Equal"); val parts = store.expense(3000, "Parts"); val exact = store.expense(3000, "Exact")
        store.apply(SplitDraft().addAll(ppl), equal)
        var d2 = SplitDraft(method = SplitMethod.PARTS).addAll(ppl); d2 = d2.setParts(4, d2.participants[0].id)
        store.apply(d2, parts)
        var d3 = SplitDraft(method = SplitMethod.AMOUNTS).addAll(ppl)
        d3.participants.map { it.id }.forEach { d3 = d3.setAmountText("10", it) }
        assertTrue(store.apply(d3, exact))

        fun recalc(e: Expense): Boolean {
            val changed = store.setAmount(e, 4000)
            val r = SplitDraft.recalculateAfterAmountChange(changed, store.shares(changed), store.s.people, store.now())
            r.save?.let(store::save)
            return r.sharesMatch
        }
        val r1 = recalc(equal); val r2 = recalc(parts); val r3 = recalc(exact)
        fun sorted(e: Expense) = store.shares(e).sortedWith(compareBy({ if (it.isMe) 0 else 1 }, { it.sortIndex })).map { it.amountMinor }
        assertTrue(r1); assertEquals(listOf(1334L, 1333L, 1333L), sorted(equal))
        assertTrue(r2); assertEquals(listOf(2667L, 667L, 666L), sorted(parts))
        assertFalse(r3); assertEquals(listOf(1000L, 1000L, 1000L), sorted(exact))
        assertFalse(ExpenseMath.sharesMatchAmount(store.expense(exact.id), store.shares(exact)))
    }

    @Test fun participantRemovedSharesRecalculatedOldRowsDeleted() {
        val ppl = people("A", "B", "C")
        val e = store.expense(6000, "Trip")
        store.apply(SplitDraft().addAll(ppl), e)
        var reloaded = SplitDraft.fromExpense(store.expense(e.id), store.shares(e), store.s.people)!!
        assertEquals(4, reloaded.participants.size)
        assertTrue(reloaded.participants.first().isMe)
        assertEquals(SplitMethod.EQUAL, reloaded.method)
        reloaded = reloaded.remove(reloaded.participants.first { it.person?.id == ppl[2].id }.id)
        store.apply(reloaded, e)
        assertEquals(3, store.shares(e).size)
        assertTrue(store.shares(e).all { it.amountMinor == 2000L })
        assertEquals(3, store.s.shares.size)
    }

    @Test fun snapshotsSurviveRenameAndDeleteRemovingSplitMakesNormalExpense() {
        val bijoy = people("Bijoy")[0]
        val e = store.expense(2000, "Kopi")
        store.apply(SplitDraft().add(bijoy).setPayer(bijoy), e)
        store.updatePerson(bijoy.copy(name = "Bijoy Das")) // later rename does not rewrite history
        assertEquals("Bijoy", store.shares(e).first { !it.isMe }.nameSnapshot)
        assertEquals("Bijoy", store.expense(e.id).payerNameSnapshot)
        store.deletePerson(bijoy.id)
        assertEquals(2, store.shares(e).size)
        // the payer no longer resolves; reopening the split treats it as "I paid" (iOS: expense.payer == nil)
        assertNull(SplitDraft.fromExpense(store.expense(e.id), store.shares(e), store.s.people)!!.payer)
        store.save(SplitDraft.removeSplit(store.expense(e.id), store.shares(e), store.now()))
        val after = store.expense(e.id)
        assertTrue(store.shares(after).isEmpty())
        assertTrue(after.paidByMe)
        assertNull(after.splitMethod)
        assertNull(after.payerId)
        assertEquals(0, store.s.shares.size)
    }

    @Test fun sameAsLastTimeSuggestsPreviousPeopleArchivedExcluded() {
        val bijoy = store.person("Bijoy"); val riyad = store.person("Riyad"); val old = store.person("Old", archived = true)
        val first = store.expense(3000, "Nasi Kandar", date = TestStore.BASE - TestStore.DAY)
        store.apply(SplitDraft().add(bijoy).add(riyad).add(old), first)
        val suggestion = SplitDraft.lastTimeSuggestion("nasi kandar", store.s)
        val none = SplitDraft.lastTimeSuggestion("anything", TestStore().s)
        assertEquals(listOf("Bijoy", "Riyad"), suggestion?.others?.map { it.name })
        assertNull(none)
    }

    @Test fun sameAsLastTimePrefersSameMerchantAndKeepsParts() {
        val a = store.person("A"); val b = store.person("B")
        var parts = SplitDraft(method = SplitMethod.PARTS).add(a)
        parts = parts.setParts(3, parts.participants[0].id).setParts(2, parts.participants[1].id)
        store.apply(parts, store.expense(5000, "Cafe", date = TestStore.BASE - 2 * TestStore.DAY))
        store.apply(SplitDraft().add(b), store.expense(5000, "Other", date = TestStore.BASE))
        val atCafe = SplitDraft.lastTimeSuggestion(" Cafe ", store.s)!!
        assertEquals(SplitMethod.PARTS, atCafe.method)
        assertEquals(listOf(3, 2), atCafe.participants.map { it.parts })
        assertTrue(atCafe.autoCalculate)
        val latest = SplitDraft.lastTimeSuggestion(null, store.s)!!
        assertEquals(listOf("B"), latest.others.map { it.name })
        val excluded = SplitDraft.lastTimeSuggestion(null, store.s, excludingExpenseId = store.s.expenses.first { it.merchant == "Other" }.id)!!
        assertEquals(listOf("A"), excluded.others.map { it.name })
    }
}
