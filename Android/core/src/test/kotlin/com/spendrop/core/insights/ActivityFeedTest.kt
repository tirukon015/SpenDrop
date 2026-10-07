package com.spendrop.core.insights

import com.spendrop.core.model.AccountType
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS Data/Tests/ActivityFeedTests.swift (Phase 6) + the Transactions screen day grouping. */
class ActivityFeedTest {
    // Midday today, so every fixture (now minus up to 2 hours) is "Today".
    private val now = TK.NOW
    private val maybank = TK.account("Maybank", AccountType.BANK)
    private val tng = TK.account("Touch 'n Go", AccountType.E_WALLET)
    private val bijoy = TK.person("Bijoy")
    private val lunch = TK.expense(25.0, "McDonald's", now - 3_600_000).copy(accountId = maybank.id)
    private val dinnerSplit = TK.equalSplit(TK.expense(30.0, "Dinner", now - 7_200_000), listOf(bijoy), payer = bijoy)
    private val dinner = dinnerSplit.first
    private val shares = dinnerSplit.second
    private val salary = TK.movement(MoneyMovementKind.INCOME, 300000, now - 60_000, accountId = maybank.id, note = "Salary")
    private val loan = TK.movement(MoneyMovementKind.LOAN_GIVEN, 15000, now - 120_000, person = bijoy, accountId = maybank.id)
    private val transfer = TK.movement(MoneyMovementKind.OWN_TRANSFER, 20000, now - 180_000, accountId = maybank.id, counterAccountId = tng.id)
    private val refund = TK.movement(MoneyMovementKind.REFUND, 500, now - 240_000, linkedExpense = lunch)
    private val expenses = listOf(lunch, dinner)
    private val sharesOf = TK.sharesFn(shares)

    private fun ids(f: ActivityFilter, newestFirst: Boolean = true, movements: List<com.spendrop.core.model.MoneyMovement> = listOf(salary, loan, transfer, refund)) =
        ActivityFeed.items(expenses, movements, f, newestFirst, sharesOf).map { it.id }

    @Test fun allNewestFirst() =
        assertEquals(listOf(salary.id, loan.id, transfer.id, refund.id, lunch.id, dinner.id), ids(ActivityFilter.ALL))

    @Test fun oldestFirstReverses() = assertEquals(ids(ActivityFilter.ALL).reversed(), ids(ActivityFilter.ALL, newestFirst = false))

    @Test fun typeFilters() {
        assertEquals(listOf(lunch.id, dinner.id), ids(ActivityFilter.EXPENSES))
        assertEquals("Money In filter (income + refund)", listOf(salary.id, refund.id), ids(ActivityFilter.MONEY_IN))
        assertEquals("Money Out filter (loan; transfers excluded)", listOf(loan.id), ids(ActivityFilter.MONEY_OUT))
        assertEquals(listOf(dinner.id), ids(ActivityFilter.SHARED))
        assertEquals(listOf(transfer.id), ids(ActivityFilter.TRANSFERS))
    }

    @Test fun noDuplicateEntries() {
        val all = listOf(salary, loan, transfer, refund)
        val dup = ActivityFeed.items(expenses + expenses, all + all, ActivityFilter.ALL, sharesOf = sharesOf)
        assertEquals(6, dup.size)
        assertEquals(6, dup.map { it.id }.toSet().size)
    }

    @Test fun editingMovesBetweenFiltersDeletingRemoves() {
        val edited = loan.copy(kindRaw = MoneyMovementKind.REPAYMENT_RECEIVED.raw, directionRaw = "in")
        val withEdit = listOf(salary, edited, transfer, refund)
        assertTrue(ids(ActivityFilter.MONEY_IN, movements = withEdit).contains(loan.id))
        assertFalse(ids(ActivityFilter.MONEY_OUT, movements = withEdit).contains(loan.id))
        assertFalse(ids(ActivityFilter.ALL, movements = listOf(salary, loan, transfer)).contains(refund.id))
    }

    private fun engine(filters: TransactionFilters) = TransactionFilterEngine.of(
        FinanceSnapshot(expenses = expenses, shares = shares, accounts = listOf(maybank, tng), people = listOf(bijoy),
            movements = listOf(salary, loan, transfer)),
        filters, now, TK.cal,
    )

    @Test fun engineSpendingAndHeader() {
        val e = engine(TransactionFilters(dateFilter = QuickDateFilter.TODAY))
        val summary = e.cashFlowSummary
        // Spent = 25 (lunch) + 15 (my share of dinner Bijoy paid); movements don't change spending
        assertEquals(4000L, e.totalSpendingMinor)
        assertEquals(4000L, summary.spendingMinor)
        // Header In/Out: salary in; lunch + loan out; own transfer and Bijoy's payment excluded
        assertEquals(300000L, summary.moneyInMinor)
        assertEquals(2500L + 15000L, summary.moneyOutMinor)
    }

    @Test fun engineFiltersMovementsBySearchAccountAndCategory() {
        val base = TransactionFilters(dateFilter = QuickDateFilter.TODAY)
        assertEquals(listOf(salary.id), engine(base.copy(searchText = "salary")).filteredMovements.map { it.id })
        // transfer matches its destination account
        assertEquals(listOf(transfer.id), engine(base.copy(fundingAccounts = setOf("Touch 'n Go"))).filteredMovements.map { it.id })
        assertEquals(0, engine(base.copy(categories = setOf(ExpenseCategory.FOOD))).filteredMovements.size)
        // person name search and amount search on movements
        assertEquals(listOf(loan.id), engine(base.copy(searchText = "bijoy")).filteredMovements.map { it.id })
        assertEquals(listOf(transfer.id), engine(base.copy(searchText = "200.00")).filteredMovements.map { it.id })
    }

    @Test fun groupByDayTodayYesterdayAndDates() {
        val y = TK.expense(5.0, "Y", now - TK.DAY)
        val old = TK.expense(6.0, "Old", TK.at(2026, 9, 1, 9))
        val items = ActivityFeed.items(listOf(lunch, y, old), listOf(salary), ActivityFilter.ALL)
        val groups = ActivityFeed.groupByDay(items, now, true, TK.cal)
        assertEquals(listOf("Today", "Yesterday", "1 Sep 2026"), groups.map { it.dateHeader })
        assertEquals(listOf("7 Oct 2026", "6 Oct 2026", null), groups.map { it.dateSubtitle })
        assertEquals(listOf(salary.id, lunch.id), groups[0].items.map { it.id })
        val asc = ActivityFeed.groupByDay(ActivityFeed.items(listOf(lunch, y, old), listOf(salary), ActivityFilter.ALL, newestFirst = false), now, false, TK.cal)
        assertEquals(listOf("1 Sep 2026", "Yesterday", "Today"), asc.map { it.dateHeader })
        assertEquals(listOf(lunch.id, salary.id), asc[2].items.map { it.id })
    }
}
