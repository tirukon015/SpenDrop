package com.spendrop.core.insights

import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.SettlementAllocation
import com.spendrop.core.sample.SampleData
import com.spendrop.core.sample.SampleEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS SampleDataTests (Data/Tests/SplitFeatureTests.swift). Balances come from the core person ledger. */
class SampleDataTest {
    private val now = TK.NOW

    private fun net(name: String, s: FinanceSnapshot): Long {
        val p = s.people.firstOrNull { it.name == name } ?: return 0
        return FinancialCalculator.personBalances(s.expenses, s::sharesOf, s.movements)[p.id] ?: 0
    }

    /** iOS DebtSettlementTests.paidFor: I paid [minor] entirely for [person]. */
    private fun paidFor(s: FinanceSnapshot, person: com.spendrop.core.model.Person, minor: Long, merchant: String, accountId: String? = null): Pair<FinanceSnapshot, String> {
        val e = TK.expense(minor / 100.0, merchant, now - TK.DAY, accountId = accountId).copy(splitMethodRaw = "equal")
        val shares = listOf(
            ExpenseShare(TK.id(), e.id, null, true, "Me", 0, sortIndex = 0),
            ExpenseShare(TK.id(), e.id, person.id, false, person.name, minor, sortIndex = 1),
        )
        return s.copy(expenses = s.expenses + e, shares = s.shares + shares) to e.id
    }

    @Test fun sampleDataLifecycle() {
        var s = FinanceSnapshot()
        assertFalse("A fresh store has no sample data", SampleData.isLoaded(s))

        // Real data first
        val bijoy = TK.person("Bijoy")
        val maybank = TK.account("Maybank", AccountType.BANK)
        s = s.copy(people = listOf(bijoy), accounts = listOf(maybank))
        val (withReal, realId) = paidFor(s, bijoy, 10000, "Real dinner", maybank.id)
        val repayment = TK.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 3000, now, person = bijoy, accountId = maybank.id)
        val realAlloc = SettlementAllocation(TK.id(), TK.id(), paymentId = repayment.id, expenseId = realId, personId = bijoy.id, direction = 1,
            amountMinor = 3000, date = now, createdAt = now)
        s = withReal.copy(movements = listOf(repayment), allocations = listOf(realAlloc))
        val realNet = net("Bijoy", s)
        assertEquals(7000L, realNet)

        val set = SampleData.load(s, now, TK.cal)
        assertNotNull(set)
        s = set!!.addTo(s)
        assertEquals(listOf(9, 4, 5, 4, 21), listOf(s.expenses.size, s.people.size, s.movements.size, s.allocations.size, s.sampleRecords.size))
        assertEquals(14, set.shares.size)
        assertEquals(12000L, net("Aiman (Sample)", s))
        assertEquals(25000L, net("Ravi (Sample)", s))
        assertEquals(-3500L, net("Mei Ling (Sample)", s))
        // Mei Ling's RM50 payment: RM40 allocated to the dinner, RM10 stays as credit
        val mei = s.people.first { it.name == "Mei Ling (Sample)" }
        val meiPayment = s.movements.first { it.personId == mei.id && it.kind == MoneyMovementKind.REPAYMENT_RECEIVED }
        assertEquals(1000L, meiPayment.amountMinor - s.allocations.filter { it.paymentId == meiPayment.id }.sumOf { it.amountMinor })
        assertEquals(realNet, net("Bijoy", s))
        assertTrue(SampleData.isLoaded(s))
        assertEquals(8, SampleData.count(s))

        assertNull("Loading again adds nothing", SampleData.load(s, now, TK.cal))

        // A real record that uses a sample person: that person must survive removal.
        val aiman = s.people.first { it.name == "Aiman (Sample)" }
        val (withAiman, _) = paidFor(s, aiman, 1500, "Real lunch with Aiman")
        s = withAiman

        val plan = SampleData.removalPlan(s, now)
        s = plan.applyTo(s)
        val names = s.expenses.map { it.merchant }.toSet()
        assertEquals(setOf("Real dinner", "Real lunch with Aiman"), names)
        assertTrue(s.people.any { it.id == bijoy.id })
        assertEquals(realNet, net("Bijoy", s))
        assertEquals(listOf(realAlloc), s.allocations)
        assertEquals(listOf("Maybank"), s.accounts.map { it.name })
        assertEquals(0, s.sampleRecords.size)
        assertEquals(1, plan.report.peopleKept)
        assertEquals(2, plan.report.peopleRemoved)
        assertTrue(s.people.any { it.id == aiman.id })
        assertTrue(s.shares.any { it.personId == aiman.id })
        assertEquals(1500L, net("Aiman (Sample)", s))
        assertEquals(1, s.movements.size)
        assertEquals(8, plan.report.expensesRemoved)
        assertEquals(4, plan.report.movementsRemoved)
        assertEquals(3, plan.report.settlementsRemoved)
        assertEquals(2, plan.report.accountsRemoved)
        assertEquals(1, plan.report.paymentMethodsRemoved)
        assertEquals(8 + 2 + 4 + 3 + 2 + 1, plan.report.total)
        assertEquals(14, plan.shareIds.size)
        assertTrue(s.shares.none { it.expenseId in plan.expenseIds })

        // Load → Remove → Load works; removing again leaves the real data exactly as it was
        val reloaded = SampleData.load(s, now, TK.cal)
        assertNotNull(reloaded)
        s = reloaded!!.addTo(s)
        val second = SampleData.removalPlan(s, now)
        s = second.applyTo(s)
        assertEquals(8, second.report.expensesRemoved)
        assertEquals(names, s.expenses.map { it.merchant }.toSet())
        assertEquals(realNet, net("Bijoy", s))
        assertFalse(SampleData.isLoaded(s))
    }

    @Test fun datasetShape() {
        val set = SampleData.build(now, TK.cal)
        assertTrue(set.people.all { it.name.endsWith("(Sample)") })
        assertTrue(set.accounts.all { it.name.endsWith("(Sample)") })
        assertTrue(set.expenses.all { it.merchant.endsWith("(Sample)") && it.isSampleData && it.notes!!.endsWith(" [Sample]") })
        assertTrue(set.people.first { it.name == "Aiman (Sample)" }.isFrequent)
        assertEquals(listOf(900, 901), set.accounts.map { it.sortIndex })
        val byEntity = set.sampleRecords.groupBy { it.entityRaw }.mapValues { it.value.size }
        assertEquals(mapOf("person" to 3, "paymentMethod" to 1, "account" to 2, "expense" to 8, "movement" to 4, "allocation" to 3), byEntity)
        assertEquals(SampleEntity.entries.map { it.raw }.toSet() - "rule", byEntity.keys)
        // Day offsets from the local start of today
        val start = TK.cal.startOfDay(now)
        val grocer = set.expenses.first { it.merchant == "Grocer (Sample)" }
        assertEquals(start - 24 * TK.HOUR + 18 * TK.HOUR, grocer.date)
        assertEquals(4590L, grocer.amountMinor)
        val taxi = set.expenses.first { it.merchant.startsWith("Taxi") }
        assertFalse(taxi.paidByMe)
        assertEquals("Mei Ling (Sample)", taxi.payerNameSnapshot)
        // Every split's shares add up to its amount
        for (e in set.expenses) {
            val sh = set.shares.filter { it.expenseId == e.id }
            assertTrue(e.merchant, sh.isEmpty() || sh.sumOf { it.amountMinor } == e.amountMinor)
            assertEquals(e.merchant, if (sh.isEmpty()) 0 else 1, sh.count { it.isMe })
        }
        val loan = set.movements.first { it.kind == MoneyMovementKind.LOAN_GIVEN }
        assertEquals("Lent for books (Sample)", loan.note)
        assertEquals(set.accounts.first { it.name == SampleData.BANK_NAME }.id, loan.accountId)
    }

    @Test fun olderFlaggedDataAndLinkedRefunds() {
        // Older demo data: flagged expenses without a register, on an account created with them; a real refund linked to one.
        val oldAccount = TK.account("Old Demo", createdAt = now)
        val realAccount = TK.account("Maybank", createdAt = now - 10 * TK.DAY)
        val flagged = TK.expense(5.0, "Old sample", accountId = oldAccount.id, createdAt = now, isSample = true)
        val flaggedOnReal = TK.expense(6.0, "Old sample 2", accountId = realAccount.id, createdAt = now, isSample = true)
        val real = TK.expense(7.0, "Real", accountId = realAccount.id)
        val refund = TK.movement(MoneyMovementKind.REFUND, 100, linkedExpense = flagged)
        val s = FinanceSnapshot(expenses = listOf(flagged, flaggedOnReal, real), accounts = listOf(oldAccount, realAccount), movements = listOf(refund))
        assertTrue(SampleData.isLoaded(s))
        val plan = SampleData.removalPlan(s, now + 5)
        assertEquals(setOf(flagged.id, flaggedOnReal.id), plan.expenseIds)
        assertEquals("only the account created with the samples and now unused", setOf(oldAccount.id), plan.accountIds)
        assertEquals(listOf(refund.copy(linkedExpenseId = null, updatedAt = now + 5)), plan.unlinkedMovements)
        val after = plan.applyTo(s)
        assertNull(after.movements.single().linkedExpenseId)
        assertEquals(listOf("Real"), after.expenses.map { it.merchant })
    }
}
