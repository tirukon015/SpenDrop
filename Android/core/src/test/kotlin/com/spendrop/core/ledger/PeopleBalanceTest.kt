package com.spendrop.core.ledger

import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Expense
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.split.SplitDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS PeopleBalanceTests ("Phase 5", `--run-people-tests`). */
class PeopleBalanceTest {
    private val store = TestStore()

    private fun shared(minor: Long, payer: Person?, with: List<Person>, currency: String = "RM"): Expense {
        val e = store.expense(minor, "Dinner", currency = currency)
        store.apply(with.fold(SplitDraft()) { d, p -> d.add(p) }.setPayer(payer), e)
        return store.expense(e.id)
    }

    private fun balances(p: Person) = PersonLedger.balances(store.s, p)

    @Test fun loanRepaymentDirectionFlip() {
        val shadin = store.person("Shadin")
        store.movement(MoneyMovementKind.LOAN_GIVEN, 15000, shadin)
        store.movement(MoneyMovementKind.LOAN_GIVEN, 5000, shadin)
        val afterLoans = balances(shadin)["RM"]
        store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 10000, shadin)
        val afterRepay = balances(shadin)["RM"]
        store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 12000, shadin)
        val flipped = balances(shadin)["RM"]!!
        assertEquals(20000L, afterLoans); assertEquals(10000L, afterRepay); assertEquals(-2000L, flipped)
        assertEquals("You owe Shadin RM 20.00", PersonLedger.directionText("Shadin", flipped, "RM"))
        assertEquals("Settled with Shadin", PersonLedger.directionText("Shadin", 0, "RM"))
    }

    @Test fun loansAreNotSpending() {
        val shadin = store.person("Shadin")
        val loan = store.movement(MoneyMovementKind.LOAN_GIVEN, 15000, shadin)
        val s = FinancialCalculator.summary(emptyList(), { emptyList() }, listOf(loan))
        assertEquals(15000L, s.moneyOutMinor); assertEquals(0L, s.spendingMinor)
    }

    @Test fun sharedBothWaysPlusRepaymentMadeSettles() {
        val bijoy = store.person("Bijoy"); val riyad = store.person("Riyad")
        shared(3000, null, listOf(bijoy, riyad))   // each owes me 10
        shared(6000, bijoy, listOf(bijoy, riyad))  // I owe Bijoy 20
        val bijoyBefore = balances(bijoy)["RM"]
        val riyadBalance = balances(riyad)["RM"]
        store.movement(MoneyMovementKind.REPAYMENT_MADE, 1000, bijoy)
        assertEquals(-1000L, bijoyBefore)
        assertTrue(balances(bijoy).isEmpty())
        assertEquals(1000L, riyadBalance)
    }

    @Test fun balancesArePerCurrency() {
        val ali = store.person("Ali")
        shared(2000, null, listOf(ali))
        shared(4000, null, listOf(ali), currency = "USD")
        store.movement(MoneyMovementKind.LOAN_RECEIVED, 500, ali, currency = "SGD")
        assertEquals(mapOf("RM" to 1000L, "USD" to 2000L, "SGD" to -500L), balances(ali))
    }

    @Test fun summaryHistoryAndSnapshots() {
        val a = store.person("A"); val b = store.person("B"); val c = store.person("C"); val d = store.person("D")
        val loan = store.movement(MoneyMovementKind.LOAN_GIVEN, 1000, a)
        store.movement(MoneyMovementKind.LOAN_RECEIVED, 400, b)
        store.movement(MoneyMovementKind.LOAN_GIVEN, 300, c); store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 300, c)
        val s = PersonLedger.summary(store.s, listOf(a, b, c, d))
        assertEquals(PersonLedger.Summary(mapOf("RM" to 1000L), mapOf("RM" to 400L), settledCount = 1, owingMeCount = 1, iOweCount = 1), s)
        assertFalse(s.isEmpty)

        store.updatePerson(a.copy(name = "A renamed"))
        val renamed = store.s.people.first { it.id == a.id }
        val entries = PersonLedger.entries(store.s, renamed)
        assertEquals(listOf(1000L), entries.map { it.effectMinor })
        assertEquals("A", loan.personNameSnapshot)
        assertEquals("Loan given", entries[0].title)
    }

    @Test fun historyExpensePaidBySomeoneElseShowsForBothAffectsOnlyPayer() {
        val bijoy = store.person("Bijoy"); val riyad = store.person("Riyad")
        shared(3000, bijoy, listOf(bijoy, riyad))
        val riyadEntries = PersonLedger.entries(store.s, riyad)
        val bijoyEntries = PersonLedger.entries(store.s, bijoy)
        assertEquals(listOf(0L), riyadEntries.map { it.effectMinor })
        assertEquals("Paid by Bijoy · not between you", riyadEntries[0].detail)
        assertEquals(-1000L, bijoyEntries.first().effectMinor)
        assertEquals("Bijoy paid · your share RM 10.00", bijoyEntries.first().detail)
    }

    @Test fun recordPaymentPrefill() {
        val owesMe = store.person("Owes"); val iOwe = store.person("Owed")
        store.movement(MoneyMovementKind.LOAN_GIVEN, 7550, owesMe)
        store.movement(MoneyMovementKind.LOAN_RECEIVED, 2000, iOwe)
        val received = PersonLedger.repaymentDraft(store.s, owesMe, "RM", store.now())!!
        val made = PersonLedger.repaymentDraft(store.s, iOwe, "RM", store.now())!!
        val none = PersonLedger.repaymentDraft(store.s, owesMe, "USD", store.now())
        val saved = received.newMovement(store.now())!!
        store.insert(saved)
        assertEquals(MoneyMovementKind.REPAYMENT_RECEIVED, received.kind)
        assertEquals("75.50", received.amountText)
        assertEquals(owesMe, received.person)
        assertEquals(TransactionEntryType.MONEY_IN, received.entryType)
        assertEquals(MoneyMovementKind.REPAYMENT_MADE, made.kind)
        assertEquals("20.00", made.amountText)
        assertNull(none)
        assertTrue(balances(owesMe).isEmpty())
    }

    @Test fun groupingAndDeleteSafety() {
        val frequent = store.person("F", frequent = true); val other = store.person("O"); val archived = store.person("Z", archived = true)
        store.movement(MoneyMovementKind.LOAN_GIVEN, 500, archived)
        val g = PayBookGrouping.groups(listOf(frequent, other, archived))
        assertEquals(listOf("F"), g.frequent.map { it.name })
        assertEquals(listOf("O"), g.other.map { it.name })
        assertEquals(listOf("Z"), g.archived.map { it.name })
        assertEquals(500L, balances(archived)["RM"])
        assertFalse(PersonLedger.canDelete(store.s, archived))
        assertTrue(PersonLedger.canDelete(store.s, other))
    }

    @Test fun deletingSettledPersonKeepsSnapshots() {
        val p = store.person("Temp")
        val e = shared(2000, null, listOf(p))
        store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 1000, p)
        assertTrue(PersonLedger.canDelete(store.s, p))
        assertTrue(PersonLedger.hasHistory(store.s, p))
        store.deletePerson(p.id)
        assertEquals(2, store.shares(e).size)
        assertEquals("Temp", store.shares(e).first { !it.isMe }.nameSnapshot)
        assertEquals(1, store.movementCount())
    }
}
