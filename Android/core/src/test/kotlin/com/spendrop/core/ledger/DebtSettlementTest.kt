package com.spendrop.core.ledger

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.model.SettlementKind
import com.spendrop.core.model.SplitMethod
import com.spendrop.core.split.SplitDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** iOS DebtSettlementTests ("Debts & settlements", `--run-debt-tests`), minus duplicate detection / migration / backup. */
class DebtSettlementTest {
    private val store = TestStore()

    private inline fun <reified E : SettlementError> refused(block: () -> Unit): E {
        try { block() } catch (e: SettlementError) { return e as? E ?: throw AssertionError("wrong error $e") }
        fail("expected ${E::class.simpleName}"); throw IllegalStateException()
    }

    @Test fun paidForSomeoneAndRealLifeSplits() {
        val bijoy = store.person("Bijoy"); val labib = store.person("Labib")
        val forBijoy = store.paidFor(bijoy, 10000, "Dinner for Bijoy")
        val myShare = store.shares(forBijoy).first { it.isMe }
        assertEquals(0L, myShare.amountMinor)
        assertEquals(null, myShare.enteredMinor)
        assertEquals(10000L, store.shares(forBijoy).first { !it.isMe }.amountMinor)
        assertEquals(10000L, store.net(bijoy))
        assertEquals(SplitDraft.Purpose.PAID_FOR, SplitDraft.fromExpense(forBijoy, store.shares(forBijoy), store.s.people)?.purpose)

        val forMe = store.paidForMe(labib, 10000, "Bijoy paid for me")
        assertEquals(1, store.shares(forMe).size)
        assertEquals(10000L, ExpenseMath.myShareMinor(forMe, store.shares(forMe)))
        assertFalse(forMe.paidByMe)
        assertEquals(-10000L, store.net(labib))
        assertEquals(true, SplitDraft.fromExpense(forMe, store.shares(forMe), store.s.people)?.paidForMe)

        val two = store.expense(10000, "Groceries for two")
        store.apply(SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR).add(bijoy).add(labib), two)
        assertEquals(0L, store.shares(two).first { it.isMe }.amountMinor)
        assertEquals(listOf(5000L, 5000L), store.shares(two).filter { !it.isMe }.map { it.amountMinor })

        val s2 = TestStore()
        val p = s2.person("Bijoy")
        val lunch = s2.expense(5000, "Lunch")
        var s = SplitDraft(method = SplitMethod.AMOUNTS).add(p)
        s = s.setAmountText("30", s.participants[0].id, 5000)
        s2.apply(s, lunch)
        val netAfterMine = s2.net(p)
        val theirs = s2.expense(5000, "Bijoy's lunch")
        var t = SplitDraft(method = SplitMethod.AMOUNTS, autoCalculate = false).add(p).setPayer(p)
        t = t.setAmountText("20", t.participants[0].id).setAmountText("30", t.participants[1].id)
        s2.apply(t, theirs)
        assertEquals(2000L, netAfterMine)
        assertEquals(0L, s2.net(p))
        assertEquals(2, s2.debts(p).size)
    }

    private fun scenario(): Pair<Person, List<Debt>> {
        val bijoy = store.person("Bijoy")
        store.paidFor(bijoy, 5000, "A Dinner", daysAgo = 3)
        store.paidFor(bijoy, 3000, "B Grab", daysAgo = 2)
        store.paidFor(bijoy, 2000, "C Food", daysAgo = 1)
        return bijoy to store.debts(bijoy)
    }

    @Test fun paymentTowardsOneDebtOnly() {
        val (bijoy, debts) = scenario()
        val a = debts.first { it.title == "A Dinner" }
        store.apply(SettlementService.recordPayment(bijoy, 1, 2000, listOf(a to 2000L), "RM", store.now()))
        val o = store.outstanding(bijoy)
        assertEquals(mapOf("A Dinner" to 3000L, "B Grab" to 3000L, "C Food" to 2000L), o)
        assertEquals(8000L, store.net(bijoy))
        assertEquals(5000L, store.debt("A Dinner", bijoy).originalMinor)
        assertTrue(store.debt("A Dinner", bijoy).isPartiallyPaid)
    }

    @Test fun markPaidAndUndo() {
        val (bijoy, _) = scenario()
        val group = store.apply(SettlementService.markPaid(store.debt("A Dinner", bijoy), bijoy, store.now()))
        val payment = store.s.movements.single()
        assertEquals(mapOf("A Dinner" to 0L, "B Grab" to 3000L, "C Food" to 2000L), store.outstanding(bijoy))
        assertEquals(5000L, store.net(bijoy))
        assertEquals(5000L, payment.amountMinor)
        assertEquals(MoneyMovementKind.REPAYMENT_RECEIVED, payment.kind)
        assertEquals("Settled: A Dinner", payment.note)
        assertEquals(3, store.s.expenses.size)
        store.undo(group)
        assertEquals(5000L, store.outstanding(bijoy)["A Dinner"])
        assertEquals(0, store.movementCount())
        assertEquals(10000L, store.net(bijoy))
        assertEquals(5000L, store.debt("A Dinner", bijoy).originalMinor)
    }

    @Test fun selectAAndCSettle() {
        val (bijoy, debts) = scenario()
        val selected = debts.filter { it.title != "B Grab" }
        store.apply(SettlementService.recordPayment(bijoy, 1, 7000, selected.map { it to it.outstandingMinor }, "RM", store.now()))
        assertEquals(mapOf("A Dinner" to 0L, "B Grab" to 3000L, "C Food" to 0L), store.outstanding(bijoy))
        assertEquals(3000L, store.net(bijoy))
        assertEquals(1, store.movementCount())
        assertEquals(2, store.allocationCount())
    }

    @Test fun autoAllocateOldestFirst() {
        val (bijoy, debts) = scenario()
        val plan60 = SettlementService.autoAllocate(6000, debts)
        val plan20 = SettlementService.autoAllocate(2000, debts)
        store.apply(SettlementService.recordPayment(bijoy, 1, 6000, listOf(debts[0] to 5000L, debts[1] to 1000L), "RM", store.now()))
        assertEquals(listOf(5000L, 1000L), plan60.map { it.second })
        assertEquals(listOf("A Dinner", "B Grab"), plan60.map { it.first.title })
        assertEquals(listOf(2000L), plan20.map { it.second })
        assertEquals(mapOf("A Dinner" to 0L, "B Grab" to 2000L, "C Food" to 2000L), store.outstanding(bijoy))
        assertEquals(4000L, store.net(bijoy))
    }

    @Test fun severalPaymentsOnOneDebtHistoryKeepsAll() {
        val bijoy = store.person("Bijoy")
        store.paidFor(bijoy, 10000, "Big dinner")
        for (amount in listOf(2000L, 3000L, 5000L)) {
            store.apply(SettlementService.recordPayment(bijoy, 1, amount, listOf(store.debt("Big dinner", bijoy) to amount), "RM", store.now()))
        }
        val history = DebtLedger.settlementGroups(store.s, personId = bijoy.id)
        assertTrue(store.debt("Big dinner", bijoy).isSettled)
        assertEquals(3, history.size)
        assertEquals(listOf(2000L, 3000L, 5000L), history.map { it.totalMinor }.sorted())
        assertEquals(listOf(5000L, 3000L, 2000L), history.map { it.totalMinor }) // newest first
        assertTrue(history.all { it.payment != null && it.direction == 1 })
        assertEquals(0L, store.net(bijoy))
    }

    @Test fun onePaymentThreeAllocations() {
        val (bijoy, debts) = scenario()
        store.apply(SettlementService.recordPayment(bijoy, 1, 10000, debts.map { it to it.outstandingMinor }, "RM", store.now()))
        assertTrue(store.debts(bijoy).all { it.isSettled })
        assertEquals(1, store.movementCount())
        assertEquals(3, store.allocationCount())
    }

    @Test fun invalidPaymentsRefusedBeforeAnythingIsSaved() {
        val (bijoy, debts) = scenario()
        val a = debts[0]; val b = debts[1]
        val over = refused<SettlementError.ExceedsOutstanding> { SettlementService.recordPayment(bijoy, 1, 9000, listOf(a to 6000L), "RM", 0) }
        refused<SettlementError.AllocationExceedsPayment> { SettlementService.recordPayment(bijoy, 1, 1000, listOf(a to 2000L), "RM", 0) }
        refused<SettlementError.MixedPeopleOrDirections> { SettlementService.recordPayment(bijoy, -1, 1000, listOf(b to 1000L), "RM", 0) }
        refused<SettlementError.InvalidAmount> { SettlementService.recordPayment(bijoy, 1, 0, emptyList(), "RM", 0) }
        assertEquals(SettlementError.ExceedsOutstanding("A Dinner"), over)
        assertEquals("That's more than what's left on A Dinner.", over.message)
        assertEquals("The amounts applied are more than the payment.", SettlementError.AllocationExceedsPayment.message)
        assertEquals("These transactions can't be paid together.", SettlementError.MixedPeopleOrDirections.message)
        assertEquals("Enter an amount greater than zero.", SettlementError.InvalidAmount.message)
        assertEquals(0, store.movementCount())
    }

    @Test fun nettingSettleAllAndUndo() {
        val bijoy = store.person("Bijoy")
        store.paidFor(bijoy, 10000, "I paid")
        store.paidForMe(bijoy, 2000, "Bijoy paid")
        val netBefore = store.net(bijoy)
        store.apply(SettlementService.recordPayment(bijoy, 1, 2000, listOf(store.debt("I paid", bijoy) to 2000L), "RM", store.now()))
        val afterPayment = store.net(bijoy)
        val iOwe = store.debt("Bijoy paid", bijoy)
        assertEquals(8000L, netBefore)
        assertEquals("Bijoy owes you RM 80.00", PersonLedger.directionText("Bijoy", netBefore, "RM"))
        assertEquals(6000L, afterPayment)
        assertEquals(2000L, iOwe.outstandingMinor)
        assertEquals(-1, iOwe.direction)
        assertEquals(2, store.debts(bijoy).size)

        val change = SettlementService.settleAll(store.s, bijoy, "RM", store.now())
        val group = store.apply(change)
        val cash = store.s.movements.filter { it.note == "Settled all with Bijoy" }
        assertEquals(0L, store.net(bijoy))
        assertTrue(store.debts(bijoy).all { it.isSettled })
        assertEquals(listOf(6000L), cash.map { it.amountMinor })
        assertEquals(MoneyMovementKind.REPAYMENT_RECEIVED, cash.single().kind)
        assertEquals(2, store.s.expenses.size)
        // offsets of RM20 in both directions, then the payment
        assertEquals(listOf(SettlementKind.OFFSET to 2000L, SettlementKind.OFFSET to 2000L, SettlementKind.PAYMENT to 6000L),
            change.newAllocations.map { it.kind to it.amountMinor })
        val g = DebtLedger.settlementGroups(store.s, personId = bijoy.id).first { it.id == group }
        assertEquals(6000L, g.totalMinor); assertEquals(2000L, g.offsetMinor); assertEquals(1, g.direction)

        store.undo(group)
        assertEquals(6000L, store.net(bijoy))
        assertEquals(2000L, store.debt("Bijoy paid", bijoy).outstandingMinor)
        assertEquals(8000L, store.debt("I paid", bijoy).outstandingMinor)
    }

    @Test fun reverseNetting() {
        val bijoy = store.person("Bijoy")
        store.paidForMe(bijoy, 10000, "Bijoy paid big")
        store.paidFor(bijoy, 2000, "I paid small")
        assertEquals("You owe Bijoy RM 80.00", PersonLedger.directionText("Bijoy", store.net(bijoy), "RM"))
    }

    @Test fun twoIdenticalTransactionsSettlingOneLeavesOther() {
        val bijoy = store.person("Bijoy")
        val one = store.paidFor(bijoy, 10000, "Same"); val two = store.paidFor(bijoy, 10000, "Same")
        val debts = store.debts(bijoy)
        store.apply(SettlementService.markPaid(debts.first { it.expenseId == one.id }, bijoy, store.now()))
        val after = store.debts(bijoy)
        assertTrue(one.id != two.id)
        assertEquals(2, debts.size)
        assertEquals(10000L, store.net(bijoy))
        assertTrue(after.first { it.expenseId == one.id }.isSettled)
        assertEquals(10000L, after.first { it.expenseId == two.id }.outstandingMinor)
    }

    @Test fun directTransferIsADebtAndOldUnlinkedRepaymentUsedBySettleAll() {
        val bijoy = store.person("Bijoy")
        val transfer = store.movement(MoneyMovementKind.LOAN_GIVEN, 10000, bijoy)
        store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 3000, bijoy)
        val loan = store.debts(bijoy).first()
        val unassignedBefore = DebtLedger.unassignedMinor(store.s, bijoy, "RM")
        store.apply(SettlementService.settleAll(store.s, bijoy, "RM", store.now()))
        val newCash = store.s.movements.filter { it.note == "Settled all with Bijoy" }.map { it.amountMinor }
        assertEquals(1, loan.direction)
        assertEquals(10000L, loan.originalMinor)
        assertEquals(transfer.id, loan.loanId)
        assertEquals("Money you gave", loan.title)
        assertEquals(-3000L, unassignedBefore)
        assertEquals(0L, store.net(bijoy))
        assertEquals(listOf(7000L), newCash)
    }

    @Test fun creditUnallocatedPaymentsAndIntegrity() {
        val bijoy = store.person("Bijoy")
        store.paidFor(bijoy, 1000, "A", daysAgo = 9); store.paidFor(bijoy, 500, "B", daysAgo = 8)
        store.paidFor(bijoy, 300, "C", daysAgo = 7); store.paidFor(bijoy, 1000, "D", daysAgo = 6)
        val abc = store.debts(bijoy).filter { it.title in listOf("A", "B", "C") }
        store.apply(SettlementService.recordPayment(bijoy, 1, 2000, abc.map { it to it.outstandingMinor }, "RM", store.now()))
        val uses = DebtLedger.paymentUses(store.s, bijoy)
        val credit = DebtLedger.creditMinor(store.s, bijoy, "RM", 1)
        assertEquals(1, uses.size)
        assertEquals(1800L, uses[0].allocatedMinor)
        assertEquals(200L, uses[0].unallocatedMinor)
        assertEquals(200L, credit)
        assertEquals(mapOf("A" to 0L, "B" to 0L, "C" to 0L, "D" to 1000L), store.outstanding(bijoy))
        assertEquals(800L, store.net(bijoy))
        assertEquals(1, store.movementCount())

        store.paidFor(bijoy, 1000, "E", daysAgo = 1)
        val e = store.debt("E", bijoy)
        val tooMuch = refused<SettlementError.NotEnoughCredit> { SettlementService.applyCredit(store.s, bijoy, 1, listOf(e to 500L), "RM", store.now()) }
        val group = store.apply(SettlementService.applyCredit(store.s, bijoy, 1, listOf(e to 200L), "RM", store.now()))
        assertEquals(SettlementError.NotEnoughCredit(200, "RM"), tooMuch)
        assertEquals("Only RM 2.00 of credit is available. Apply less, or record a new payment.", tooMuch.message)
        assertEquals(800L, store.debt("E", bijoy).outstandingMinor)
        assertEquals(0L, DebtLedger.creditMinor(store.s, bijoy, "RM", 1))
        store.undo(group)
        assertEquals(1000L, store.debt("E", bijoy).outstandingMinor)
        assertEquals(200L, DebtLedger.creditMinor(store.s, bijoy, "RM", 1))
        assertEquals(1, store.movementCount())

        // Integrity: original = settled + outstanding; payment = applied + credit; net = outstanding + unassigned
        val debts = store.debts(bijoy)
        assertTrue(DebtLedger.paymentUses(store.s, bijoy).all { it.allocatedMinor + it.unallocatedMinor == it.payment.amountMinor })
        assertTrue(debts.all { it.settledMinor + it.outstandingMinor == it.originalMinor })
        val unassigned = DebtLedger.unassignedMinor(store.s, bijoy, "RM")
        assertEquals(store.net(bijoy), debts.sumOf { it.signedOutstandingMinor } + unassigned)
        assertEquals(-DebtLedger.creditMinor(store.s, bijoy, "RM", 1), unassigned)
    }

    @Test fun paymentLargerThanDebtLeavesCreditIndependentRepaymentSurvivesUndo() {
        val bijoy = store.person("Bijoy")
        store.paidFor(bijoy, 1000, "Small debt")
        val plan = SettlementService.autoAllocate(2000, store.debts(bijoy))
        store.apply(SettlementService.recordPayment(bijoy, 1, 2000, plan, "RM", store.now()))
        assertTrue(store.debt("Small debt", bijoy).isSettled)
        assertEquals(1000L, DebtLedger.creditMinor(store.s, bijoy, "RM", 1))
        assertEquals(-1000L, store.net(bijoy))

        val legacy = store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 500, bijoy)
        store.paidFor(bijoy, 800, "Later")
        val change = SettlementService.applyCredit(store.s, bijoy, 1, listOf(store.debt("Later", bijoy) to 800L), "RM", store.now())
        // oldest credit first: RM10 left of the first payment would cover it entirely
        assertEquals(1, change.newAllocations.size)
        val group = store.apply(change)
        store.undo(group)
        assertNotNull(store.s.movements.firstOrNull { it.id == legacy.id })
        assertEquals(800L, store.debt("Later", bijoy).outstandingMinor)
    }

    @Test fun applyCreditSpansSeveralPaymentsOldestFirst() {
        val bijoy = store.person("Bijoy")
        val p1 = store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 300, bijoy)
        val p2 = store.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 500, bijoy)
        store.paidFor(bijoy, 1000, "Debt")
        val change = SettlementService.applyCredit(store.s, bijoy, 1, listOf(store.debt("Debt", bijoy) to 700L), "RM", store.now())
        assertEquals(listOf(p1.id to 300L, p2.id to 400L), change.newAllocations.map { it.paymentId to it.amountMinor })
        assertTrue(change.newAllocations.all { it.kind == SettlementKind.ASSIGN })
        assertTrue(change.newMovements.isEmpty())
        refused<SettlementError.InvalidAmount> { SettlementService.applyCredit(store.s, bijoy, 1, emptyList(), "RM", 0) }
        refused<SettlementError.NothingToSettle> { SettlementService.settleAll(store.s, store.person("Nobody"), "RM", 0) }
    }

    @Test fun scenarioA_autoCalculatedShareThenPartialPayment() {
        val bijoy = store.person("Bijoy")
        val e = store.expense(700, "BIJOYSHARIARALAMIN")
        var s = SplitDraft(method = SplitMethod.AMOUNTS).add(bijoy)
        s = s.setAmountText("0.01", s.participants[0].id, 700)
        store.apply(s, e)
        assertEquals(699L, store.net(bijoy))
        assertEquals(SplitDraft.Purpose.SHARED, SplitDraft.fromExpense(store.expense(e.id), store.shares(e), store.s.people)?.purpose)
        store.apply(SettlementService.recordPayment(bijoy, 1, 300, listOf(store.debt("BIJOYSHARIARALAMIN", bijoy) to 300L), "RM", store.now()))
        assertEquals(300L, store.debt("BIJOYSHARIARALAMIN", bijoy).settledMinor)
        assertEquals(399L, store.debt("BIJOYSHARIARALAMIN", bijoy).outstandingMinor)
        assertEquals("Bijoy owes you RM 3.99", store.debt("BIJOYSHARIARALAMIN", bijoy).statusText)
    }

    @Test fun debtsForExpenseAndLoanReceived() {
        val a = store.person("A"); val b = store.person("B")
        val e = store.expense(3000, "Dinner")
        store.apply(SplitDraft().add(a).add(b), e)
        assertEquals(listOf(1000L, 1000L), DebtLedger.debts(store.s, store.expense(e.id)).map { it.originalMinor })
        val loan = store.movement(MoneyMovementKind.LOAN_RECEIVED, 2500, b, note = "Rent")
        val d = store.debts(b).first { it.loanId == loan.id }
        assertEquals(-1, d.direction)
        assertEquals("Rent", d.title)
        assertEquals("B gave you money", d.detail)
        assertEquals("You owe B RM 25.00", d.statusText)
    }
}
