package com.spendrop.core.insights

import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.ZoneOffset

/** Port of iOS Phase7Tests "Trends and breakdowns" + the Breakdown / Home view math. */
class AnalyticsTest {
    @Test fun trendBuckets_phase7() {
        // iOS: Gregorian, UTC, firstWeekday = 2, now = 2026-09-29 12:00
        val cal = CalendarContext(ZoneOffset.UTC, DayOfWeek.MONDAY)
        val now = TK.at(2026, 9, 29, 12, zone = ZoneOffset.UTC)
        val e1 = TK.expense(10.0, "A", now)
        val e2 = TK.expense(20.0, "B", TK.at(2026, 8, 29, 12, zone = ZoneOffset.UTC))
        val old = TK.expense(99.0, "Old", TK.at(2024, 9, 29, 12, zone = ZoneOffset.UTC))
        val income = TK.movement(MoneyMovementKind.INCOME, 50000, now)
        val transfer = TK.movement(MoneyMovementKind.OWN_TRANSFER, 20000, now)
        val monthly = PeriodGrouping.buckets(listOf(e1, e2, old), listOf(income, transfer), PeriodGrouping.Granularity.MONTHLY, 3, now, calendar = cal)
        val weekly = PeriodGrouping.buckets(listOf(e1), emptyList(), PeriodGrouping.Granularity.WEEKLY, 4, now, calendar = cal)
        assertEquals(3, monthly.size)
        assertEquals(listOf(0L, 2000L, 1000L), monthly.map { it.spendingMinor })
        assertEquals(50000L, monthly.last().inMinor)
        assertEquals(1000L, monthly.last().outMinor)
        assertEquals(49000L, monthly.last().netMinor)
        assertEquals(listOf("Jul", "Aug", "Sep"), monthly.map { it.label })
        assertEquals(4, weekly.size)
        assertEquals(1000L, weekly.last().spendingMinor)
        assertEquals(listOf("7 Sep", "14 Sep", "21 Sep", "28 Sep"), weekly.map { it.label })
        assertEquals(TK.at(2026, 9, 28, 0, zone = ZoneOffset.UTC), weekly.last().start)
    }

    @Test fun trendBucketsDailyDefaultsAndCurrency() {
        val now = TK.NOW
        val usd = TK.expense(9.0, "Abroad", now, currency = "USD")
        val (shared, shares) = TK.equalSplit(TK.expense(30.0, "Dinner", now - TK.DAY), listOf(TK.person("Bijoy")), payer = TK.person("Bijoy"))
        val daily = PeriodGrouping.buckets(listOf(usd, shared), emptyList(), PeriodGrouping.Granularity.DAILY, now = now, calendar = TK.cal,
            sharesOf = TK.sharesFn(shares))
        assertEquals(7, daily.size)
        assertEquals(listOf("Thu 1", "Fri 2", "Sat 3", "Sun 4", "Mon 5", "Tue 6", "Wed 7"), daily.map { it.label })
        // Someone else paid: spending is my share, cash out 0; USD never mixed into RM
        assertEquals(listOf(0L, 0L, 0L, 0L, 0L, 1500L, 0L), daily.map { it.spendingMinor })
        assertEquals(0L, daily.sumOf { it.outMinor })
        assertEquals(8, PeriodGrouping.buckets(emptyList(), emptyList(), PeriodGrouping.Granularity.WEEKLY, now = now, calendar = TK.cal).size)
        assertEquals(6, PeriodGrouping.buckets(emptyList(), emptyList(), PeriodGrouping.Granularity.MONTHLY, now = now, calendar = TK.cal).size)
        assertEquals(1, PeriodGrouping.buckets(emptyList(), emptyList(), PeriodGrouping.Granularity.MONTHLY, count = 0, now = now, calendar = TK.cal).size)
    }

    @Test fun sharedAndRefundsBreakdown_phase7() {
        val bijoy = TK.person("Bijoy")
        val (dinner, shares) = TK.equalSplit(TK.expense(30.0, "Dinner", TK.NOW), listOf(bijoy))
        val lunch = TK.expense(12.0, "Dinner", TK.NOW)
        val refund = TK.movement(MoneyMovementKind.REFUND, 500, TK.NOW, linkedExpense = lunch)
        val engine = TransactionFilterEngine.of(FinanceSnapshot(expenses = listOf(dinner, lunch), shares = shares, people = listOf(bijoy),
            movements = listOf(refund)), TransactionFilters(dateFilter = QuickDateFilter.TODAY), TK.NOW, TK.cal)
        val s = engine.sharedSpendingSummary
        assertEquals(SharedSpendingSummary(1, 3000, 1500, 500, 4200 - 500), s)
        assertEquals("Dinner", engine.merchantBreakdown.first().name)
        assertEquals(2, engine.merchantBreakdown.first().count)
        assertEquals(MoneyMovementKind.REFUND, engine.movementKindBreakdown.first().kind)

        val view = BreakdownAnalytics.spending(engine)
        assertEquals(
            listOf(
                InsightRow("Shared expenses", "1 · bills RM 30.00"), InsightRow("My share", "RM 15.00"),
                InsightRow("Gross spending", "RM 42.00"), InsightRow("Refunds", "−RM 5.00"), InsightRow("Net spending", "RM 37.00", bold = true),
            ),
            view.sharedAndRefunds,
        )
        assertEquals(listOf(InsightRow("Dinner · 2", "RM 42.00")), view.topMerchants)
    }

    @Test fun spendingModeCards() {
        val e1 = TK.expense(30.0, "Kopi", TK.NOW, category = ExpenseCategory.FOOD)
        val e2 = TK.expense(12.5, "Bus", TK.NOW - 3 * TK.DAY, category = ExpenseCategory.TRANSPORT)
        val engine = TransactionFilterEngine(listOf(e1, e2), emptyList(), TransactionFilters(), TK.NOW, TK.cal)
        val v = BreakdownAnalytics.spending(engine)
        assertEquals(false, v.isEmpty)
        assertEquals(MetricCard("TOTAL SPENT", "RM 42.50", "2 transactions"), v.totalSpent)
        assertEquals(MetricCard("AVERAGE / DAY", "RM 6.07", "over 7 days"), v.averagePerDay)
        assertEquals(2125.0, v.averagePerTransactionMinor, 0.0)
        assertEquals("LAST 7 DAYS COMPARISON", v.comparison.header)
        assertEquals("RM 42.50", v.comparison.currentValue)
        assertEquals("Last 7 Days", v.comparison.periodName)
        assertEquals("+100.0% vs Previous 7 Days", v.comparison.comparison.percentageLabel)
        assertEquals("Daily Spending", v.daily.title)
        assertEquals("1 Oct — 7 Oct • Avg RM 6.07/day", v.daily.subtitle)
        assertNull(v.daily.footnote)
        assertNull(v.sharedAndRefunds)
        assertEquals("Spending Trend", v.trend.title)
        assertEquals("All records · weekly totals", v.trend.footnote)
        assertEquals(8, v.trend.buckets.size)

        val today = BreakdownAnalytics.spending(engine.withFilters(TransactionFilters(dateFilter = QuickDateFilter.TODAY,
            dailySpendingRange = DailySpendingRange.LAST_30_DAYS)), PeriodGrouping.Granularity.MONTHLY)
        assertEquals(MetricCard("TOTAL SPENT", "RM 30.00", "1 transaction"), today.totalSpent)
        assertEquals("over 1 day", today.averagePerDay.subtitle)
        assertEquals("Showing all 30 days (scroll to explore) • Zero-spending days included", today.daily.footnote)
        assertEquals("All records · monthly totals", today.trend.footnote)
        assertTrue(BreakdownAnalytics.spending(engine.withFilters(TransactionFilters(dateFilter = QuickDateFilter.LAST_MONTH))).isEmpty)
    }

    @Test fun cashFlowMode() {
        val maybank = TK.account("Maybank")
        val salary = TK.movement(MoneyMovementKind.INCOME, 300000, TK.NOW, accountId = maybank.id)
        val loan = TK.movement(MoneyMovementKind.LOAN_GIVEN, 15000, TK.NOW)
        val loan2 = TK.movement(MoneyMovementKind.LOAN_GIVEN, 5000, TK.NOW)
        val transfer = TK.movement(MoneyMovementKind.OWN_TRANSFER, 99900, TK.NOW)
        val lunch = TK.expense(25.0, "Lunch", TK.NOW)
        val engine = TransactionFilterEngine(listOf(lunch), listOf(salary, loan, loan2, transfer), TransactionFilters(dateFilter = QuickDateFilter.THIS_MONTH), TK.NOW, TK.cal)
        val v = BreakdownAnalytics.cashFlow(engine)
        assertEquals(MetricCard("MONEY IN", "RM 3,000.00", "This Month"), v.moneyIn)
        assertEquals(MetricCard("MONEY OUT", "RM 225.00", "expenses paid + other out"), v.moneyOut)
        assertEquals(MetricCard("NET CASH FLOW", "+RM 2,775.00", "Money In − Money Out · spending is shown separately (RM 25.00)"), v.netCashFlow)
        assertTrue(v.isNetPositive)
        assertEquals(listOf(InsightRow("Income · 1", "+RM 3,000.00"), InsightRow("Loan given · 2", "−RM 200.00")), v.byType)
        assertEquals("Cash Flow Trend", v.trend.title)
        assertEquals("All records · weekly totals · own transfers excluded", v.trend.footnote)

        val negative = BreakdownAnalytics.cashFlow(TransactionFilterEngine(listOf(lunch), emptyList(), TransactionFilters(), TK.NOW, TK.cal))
        assertEquals("-RM 25.00", negative.netCashFlow.value)
        assertEquals(false, negative.isNetPositive)
    }

    @Test fun home() {
        val bijoy = TK.person("Bijoy"); val riyad = TK.person("Riyad"); val settled = TK.person("Settled")
        val today1 = TK.expense(10.0, "Kopi", TK.NOW - TK.HOUR)
        val (sharedPaidByBijoy, s1) = TK.equalSplit(TK.expense(30.0, "Dinner", TK.at(2026, 10, 5, 20)), listOf(bijoy), payer = bijoy)
        val (sharedMine, s2) = TK.equalSplit(TK.expense(100.0, "Villa", TK.at(2026, 10, 2, 9)), listOf(riyad))
        val lastWeek = TK.expense(7.0, "Old week", TK.at(2026, 10, 4, 23, 59, 59))
        val monthEdge = TK.expense(1.0, "Month start", TK.at(2026, 10, 1, 0))
        val lastMonth = TK.expense(50.0, "September", TK.at(2026, 9, 30, 23))
        val nextMonthMidnight = TK.expense(2.0, "Nov 1 00:00", TK.at(2026, 11, 1, 0))
        val pay = TK.movement(MoneyMovementKind.REPAYMENT_RECEIVED, 1000, TK.at(2026, 10, 3), person = settled)
        val lend = TK.movement(MoneyMovementKind.LOAN_GIVEN, 1000, TK.at(2026, 9, 3), person = settled)
        val snap = FinanceSnapshot(
            expenses = listOf(lastMonth, today1, sharedPaidByBijoy, sharedMine, lastWeek, monthEdge, nextMonthMidnight),
            shares = s1 + s2, people = listOf(bijoy, riyad, settled), movements = listOf(pay, lend),
        )
        val h = HomeAnalytics.home(snap, TK.NOW, TK.cal)
        assertEquals("RM 10.00", h.today.value)
        assertEquals(1000L, h.today.amountMinor)
        // Week Mon 5 Oct .. Mon 12 Oct 00:00 (inclusive end, iOS DateInterval.contains): Kopi 10 + my share 15
        assertEquals(2500L, h.thisWeek.amountMinor)
        // Month 1 Oct .. 1 Nov 00:00 inclusive: 10 + 15 + 100 + 7 + 1 + 2
        assertEquals(13500L, h.thisMonth.amountMinor)
        assertEquals(listOf("Kopi"), h.todayExpenses.map { it.merchant })
        assertEquals("1 transactions", h.todayCountLabel)
        assertEquals(2, h.sharedThisMonthCount)
        assertEquals(1500L + 5000L, h.sharedThisMonthMyShareMinor)
        assertEquals("My share of 2 shared expenses this month", h.sharedThisMonthLabel)
        assertEquals(1000L, h.cashFlowThisMonth!!.moneyInMinor)
        assertEquals(listOf("Money In", "Money Out", "Net"), h.cashFlowRows.map { it.title })
        assertEquals("-RM 110.00", h.cashFlowRows[2].value)
        assertEquals(5000L, h.owedToMeMinor)
        assertEquals(1500L, h.iOweMinor)
        assertEquals(BalancesSummary(mapOf("RM" to 5000L), mapOf("RM" to 1500L), settledCount = 1, owingMeCount = 1, iOweCount = 1), h.balances)
        assertEquals("October 2026", h.monthYear)
        assertEquals(listOf("Nov 1 00:00", "Dinner", "Old week", "Villa", "Month start"), h.recentNonToday.map { it.merchant })

        val quiet = HomeAnalytics.home(FinanceSnapshot(expenses = listOf(today1)), TK.NOW, TK.cal)
        assertNull(quiet.cashFlowThisMonth)
        assertNull(quiet.sharedThisMonthLabel)
        assertTrue(quiet.balances.isEmpty)
    }
}
