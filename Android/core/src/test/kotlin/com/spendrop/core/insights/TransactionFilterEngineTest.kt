package com.spendrop.core.insights

import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek

/** iOS TransactionFilterEngine semantics (QuickDateFilter boundaries, dimension filters, search, KPIs, labels). */
class TransactionFilterEngineTest {
    private fun engine(expenses: List<Expense> = emptyList(), filters: TransactionFilters = TransactionFilters(), now: Long = TK.NOW,
                       cal: CalendarContext = TK.cal) = TransactionFilterEngine(expenses, emptyList(), filters, now, cal)

    private fun interval(f: QuickDateFilter, now: Long = TK.NOW, cal: CalendarContext = TK.cal, filters: TransactionFilters = TransactionFilters()) =
        engine(filters = filters, now = now, cal = cal).dateInterval(f)

    private fun di(s: Long, e: Long) = DateInterval(s, e)

    @Test fun quickDateBoundaries() {
        // Now: Wednesday 7 Oct 2026 12:00 (Kuala Lumpur). Ends are 23:59:59.
        assertEquals(di(TK.at(2026, 10, 7, 0), TK.at(2026, 10, 7, 23, 59, 59)), interval(QuickDateFilter.TODAY))
        assertEquals(di(TK.at(2026, 10, 6, 0), TK.at(2026, 10, 6, 23, 59, 59)), interval(QuickDateFilter.YESTERDAY))
        assertEquals(di(TK.at(2026, 10, 5, 0), TK.at(2026, 10, 7, 23, 59, 59)), interval(QuickDateFilter.LAST_3_DAYS))
        assertEquals(di(TK.at(2026, 10, 1, 0), TK.at(2026, 10, 7, 23, 59, 59)), interval(QuickDateFilter.LAST_7_DAYS))
        assertEquals(di(TK.at(2026, 9, 8, 0), TK.at(2026, 10, 7, 23, 59, 59)), interval(QuickDateFilter.LAST_30_DAYS))
        assertEquals(di(TK.at(2026, 10, 5, 0), TK.at(2026, 10, 11, 23, 59, 59)), interval(QuickDateFilter.THIS_WEEK))
        assertEquals(di(TK.at(2026, 9, 28, 0), TK.at(2026, 10, 4, 23, 59, 59)), interval(QuickDateFilter.LAST_WEEK))
        assertEquals(di(TK.at(2026, 10, 1, 0), TK.at(2026, 10, 31, 23, 59, 59)), interval(QuickDateFilter.THIS_MONTH))
        assertEquals(di(TK.at(2026, 9, 1, 0), TK.at(2026, 9, 30, 23, 59, 59)), interval(QuickDateFilter.LAST_MONTH))
        // Year boundaries
        assertEquals(di(TK.at(2026, 12, 1, 0), TK.at(2026, 12, 31, 23, 59, 59)), interval(QuickDateFilter.LAST_MONTH, TK.at(2027, 1, 15)))
        assertEquals(di(TK.at(2026, 12, 28, 0), TK.at(2027, 1, 3, 23, 59, 59)), interval(QuickDateFilter.THIS_WEEK, TK.at(2027, 1, 1)))
        assertEquals(di(TK.at(2026, 12, 21, 0), TK.at(2026, 12, 27, 23, 59, 59)), interval(QuickDateFilter.LAST_WEEK, TK.at(2027, 1, 1)))
        // Leap February
        assertEquals(di(TK.at(2028, 2, 1, 0), TK.at(2028, 2, 29, 23, 59, 59)), interval(QuickDateFilter.THIS_MONTH, TK.at(2028, 2, 10)))
    }

    @Test fun weekOnSundayAndSundayFirstCalendar() {
        val sunday = TK.at(2026, 10, 11, 20)
        // Monday-first (default): Sunday belongs to the week that started on Monday 5 Oct.
        assertEquals(di(TK.at(2026, 10, 5, 0), TK.at(2026, 10, 11, 23, 59, 59)), interval(QuickDateFilter.THIS_WEEK, sunday))
        // Sunday-first device calendar: iOS picks weekday 2 (Monday) of the week starting that Sunday -> 12..18 Oct.
        val sundayFirst = TK.cal.copy(firstDayOfWeek = DayOfWeek.SUNDAY)
        assertEquals(di(TK.at(2026, 10, 12, 0), TK.at(2026, 10, 18, 23, 59, 59)), interval(QuickDateFilter.THIS_WEEK, sunday, sundayFirst))
        assertEquals(di(TK.at(2026, 10, 5, 0), TK.at(2026, 10, 11, 23, 59, 59)), interval(QuickDateFilter.LAST_WEEK, sunday, sundayFirst))
        // Any other day is unaffected
        assertEquals(interval(QuickDateFilter.THIS_WEEK), interval(QuickDateFilter.THIS_WEEK, cal = sundayFirst))
    }

    @Test fun customRange() {
        val f = TransactionFilters(customStart = TK.at(2026, 9, 3, 15), customEnd = TK.at(2026, 9, 10, 8))
        assertEquals(di(TK.at(2026, 9, 3, 0), TK.at(2026, 9, 10, 23, 59, 59)), interval(QuickDateFilter.CUSTOM, filters = f))
        // Defaults: 7 days ago .. today
        assertEquals(di(TK.at(2026, 9, 30, 0), TK.at(2026, 10, 7, 23, 59, 59)), interval(QuickDateFilter.CUSTOM))
        // Reversed input: iOS returns (min, max) of startOfDay(start) and endOfDay(end)
        val rev = TransactionFilters(customStart = TK.at(2026, 9, 10, 8), customEnd = TK.at(2026, 9, 3, 15))
        assertEquals(di(TK.at(2026, 9, 3, 23, 59, 59), TK.at(2026, 9, 10, 0)), interval(QuickDateFilter.CUSTOM, filters = rev))
    }

    @Test fun boundariesAreInclusiveToTheSecond() {
        val inEnd = TK.expense(1.0, "A", TK.at(2026, 10, 7, 23, 59, 59))
        val afterEnd = TK.expense(2.0, "B", TK.at(2026, 10, 7, 23, 59, 59) + 500)
        val atStart = TK.expense(3.0, "C", TK.at(2026, 10, 7, 0))
        val before = TK.expense(4.0, "D", TK.at(2026, 10, 7, 0) - 1)
        val e = engine(listOf(inEnd, afterEnd, atStart, before), TransactionFilters(dateFilter = QuickDateFilter.TODAY))
        assertEquals(listOf("A", "C"), e.filteredExpenses.map { it.merchant })
    }

    @Test fun subtitles() {
        assertEquals("7 Oct 2026", engine().dateSubtitle(QuickDateFilter.TODAY))
        assertEquals("6 Oct 2026", engine().dateSubtitle(QuickDateFilter.YESTERDAY))
        assertEquals("1 Oct — 7 Oct", engine().dateSubtitle(QuickDateFilter.LAST_7_DAYS))
        assertEquals("5 Oct — 11 Oct", engine().dateSubtitle(QuickDateFilter.THIS_WEEK))
        assertEquals("7 Dec 2026 — 5 Jan 2027", engine(now = TK.at(2027, 1, 5)).dateSubtitle(QuickDateFilter.LAST_30_DAYS))
        assertEquals("1 Oct — 7 Oct", engine().currentSubtitle)
    }

    private val food = TK.expense(10.0, "Nasi Lemak", TK.NOW, category = ExpenseCategory.FOOD, fundingAccount = "Maybank", channel = PaymentChannel.CARD)
    private val grocery = TK.expense(55.5, "Lotus's", TK.NOW - TK.HOUR, category = ExpenseCategory.GROCERIES, fundingAccount = "Touch 'n Go",
        channel = PaymentChannel.DUITNOW_QR, notes = "weekly shop")
    private val grab = TK.expense(12.3, "Grab", TK.NOW - 2 * TK.DAY, category = ExpenseCategory.TRANSPORT, fundingAccount = "maybank",
        channel = PaymentChannel.CARD)
    private val all = listOf(food, grocery, grab)

    private fun merchants(f: TransactionFilters) = engine(all, f).filteredExpenses.map { it.merchant }

    @Test fun multiSelectOrWithinAndAcross() {
        assertEquals(listOf("Nasi Lemak", "Lotus's"), merchants(TransactionFilters(categories = setOf(ExpenseCategory.FOOD, ExpenseCategory.GROCERIES))))
        assertEquals(listOf("Nasi Lemak", "Grab"), merchants(TransactionFilters(paymentChannels = setOf(PaymentChannel.CARD))))
        // Funding accounts match case-insensitively
        assertEquals(listOf("Nasi Lemak", "Grab"), merchants(TransactionFilters(fundingAccounts = setOf("MAYBANK"))))
        // AND across dimensions
        assertEquals(listOf("Grab"), merchants(TransactionFilters(categories = setOf(ExpenseCategory.TRANSPORT, ExpenseCategory.GROCERIES),
            paymentChannels = setOf(PaymentChannel.CARD))))
        assertEquals(emptyList<String>(), merchants(TransactionFilters(categories = setOf(ExpenseCategory.FOOD), fundingAccounts = setOf("Touch 'n Go"))))
    }

    @Test fun searchFields() {
        fun s(t: String) = merchants(TransactionFilters(searchText = t))
        assertEquals("merchant", listOf("Lotus's"), s("  LOTUS "))
        assertEquals("category", listOf("Grab"), s("transport"))
        assertEquals("funding", listOf("Lotus's"), s("touch"))
        assertEquals("channel display name", listOf("Lotus's"), s("duitnow"))
        assertEquals("notes", listOf("Lotus's"), s("weekly"))
        assertEquals("amount %.2f", listOf("Lotus's"), s("55.50"))
        assertEquals("amount %.2f", listOf("Nasi Lemak"), s("10.00"))
        assertEquals(listOf("Nasi Lemak", "Lotus's", "Grab"), s("   "))
    }

    @Test fun kpisAndComparison() {
        val now = TK.NOW
        val current = listOf(TK.expense(60.0, "A", now), TK.expense(40.0, "B", TK.at(2026, 10, 1, 0)))
        val previous = listOf(TK.expense(80.0, "P", TK.at(2026, 9, 30, 23, 59, 59)), TK.expense(5.0, "Older", TK.at(2026, 9, 24, 0) - 1000),
            TK.expense(0.5, "Edge", TK.at(2026, 9, 24, 0)))
        val e = engine(current + previous)
        assertEquals(10000L, e.totalSpendingMinor)
        assertEquals(2, e.transactionCount)
        assertEquals(7, e.numberOfCalendarDays)
        assertEquals(10000.0 / 7, e.averagePerDayMinor, 1e-9)
        assertEquals(5000.0, e.averagePerTransactionMinor, 1e-9)
        val c = e.previousPeriodComparison
        assertEquals(di(TK.at(2026, 9, 24, 0), TK.at(2026, 9, 30, 23, 59, 59)), c.previousInterval)
        assertEquals(8050L, c.previousTotalMinor)
        assertEquals(1950L, c.differenceMinor)
        assertTrue(c.isIncreased)
        assertEquals("vs Previous 7 Days", c.previousPeriodSubtitle)
        assertEquals("+RM 19.50", c.differenceLabel)
        assertEquals("+24.2% vs Previous 7 Days", c.percentageLabel)

        val onlyCurrent = engine(current, TransactionFilters(dateFilter = QuickDateFilter.TODAY)).previousPeriodComparison
        assertEquals(100.0, onlyCurrent.percentageChange!!, 0.0)
        assertEquals("vs Yesterday", onlyCurrent.previousPeriodSubtitle)
        val nothing = engine(emptyList(), TransactionFilters(dateFilter = QuickDateFilter.THIS_MONTH)).previousPeriodComparison
        assertEquals(0.0, nothing.percentageChange!!, 0.0)
        assertFalse(nothing.isIncreased)
        assertEquals("-RM 0.00", nothing.differenceLabel)
        assertEquals("vs Previous Month", nothing.previousPeriodSubtitle)
        assertEquals(31, engine(filters = TransactionFilters(dateFilter = QuickDateFilter.THIS_MONTH)).numberOfCalendarDays)

        val custom = engine(filters = TransactionFilters(dateFilter = QuickDateFilter.CUSTOM, customStart = TK.at(2026, 9, 10), customEnd = TK.at(2026, 9, 12)))
        assertEquals("vs 7 Sep — 9 Sep", custom.previousPeriodComparison.previousPeriodSubtitle)
        assertEquals(3, custom.numberOfCalendarDays)
    }

    @Test fun dailySpending() {
        val e = engine(all, TransactionFilters(dateFilter = QuickDateFilter.TODAY, categories = setOf(ExpenseCategory.FOOD, ExpenseCategory.TRANSPORT)))
        val pts = e.dailySpending
        assertEquals(listOf("Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"), pts.map { it.dayLabel })
        assertEquals("2026-10-01", pts.first().fullDateString)
        assertEquals(TK.at(2026, 10, 1, 0), pts.first().date)
        // Own range (not the Today filter), dimension filters apply: Grab (5 Oct) + Nasi Lemak (7 Oct); groceries excluded.
        assertEquals(listOf(0L, 0L, 0L, 0L, 1230L, 0L, 1000L), pts.map { it.amountMinor })
        assertEquals(listOf(0, 0, 0, 0, 1, 0, 1), pts.map { it.count })
        assertEquals(2230.0 / 7, e.dailySpendingAverageMinor, 1e-9)
        assertEquals("1 Oct — 7 Oct", e.dailySpendingSubtitle)
        val month = engine(all, TransactionFilters(dailySpendingRange = DailySpendingRange.LAST_30_DAYS))
        assertEquals(30, month.dailySpending.size)
        assertEquals("8", month.dailySpending.first().dayLabel)
        assertEquals("7", month.dailySpending.last().dayLabel)
        assertEquals("8 Sep — 7 Oct", month.dailySpendingSubtitle)
    }

    @Test fun breakdowns() {
        val e = engine(all)
        val cats = e.categoryBreakdown
        assertEquals(listOf(ExpenseCategory.GROCERIES, ExpenseCategory.TRANSPORT, ExpenseCategory.FOOD), cats.map { it.category })
        assertEquals("71.3% (1 txns)", cats[0].detailLabel)
        assertEquals(100.0, cats.sumOf { it.percentage }, 1e-9)
        val ch = e.paymentChannelBreakdown
        assertEquals(listOf(PaymentChannel.DUITNOW_QR, PaymentChannel.CARD), ch.map { it.channel })
        assertEquals(2230L, ch[1].totalMinor)
        assertEquals(2, ch[1].count)
        // Funding grouped by the exact text (iOS groups "Maybank" and "maybank" separately), PaymentSource matched case-insensitively
        val f = e.fundingAccountBreakdown
        assertEquals(listOf("Touch 'n Go", "maybank", "Maybank"), f.map { it.name })
        assertEquals(listOf(PaymentSource.TOUCH_N_GO, PaymentSource.MAYBANK, PaymentSource.MAYBANK), f.map { it.paymentSource })
        assertEquals(listOf("Maybank", "Wise", "CIMB", "RHB", "Touch 'n Go", "Cash"), e.availableFundingAccounts)
        val extra = engine(all + TK.expense(1.0, "X", fundingAccount = "GXBank") + TK.expense(1.0, "Y", fundingAccount = "cimb"))
        assertEquals(listOf("Maybank", "Wise", "CIMB", "RHB", "Touch 'n Go", "Cash", "GXBank"), extra.availableFundingAccounts)
        // Empty totals give 0%
        assertTrue(engine(listOf(TK.expense(0.0, "Zero"))).categoryBreakdown.all { it.percentage == 0.0 })
    }

    @Test fun filterStateLabelsAndToggles() {
        var f = TransactionFilters()
        assertFalse(f.hasActiveFilters)
        assertEquals("Categories", f.categoriesSummaryLabel)
        f = f.toggleCategory(ExpenseCategory.GROCERIES).toggleCategory(ExpenseCategory.FOOD)
        assertEquals("Food + Groceries", f.categoriesSummaryLabel)
        assertNull(f.selectedCategory)
        f = f.toggleCategory(ExpenseCategory.BILLS)
        assertEquals("Categories (3)", f.categoriesSummaryLabel)
        f = f.toggleCategory(ExpenseCategory.BILLS).toggleCategory(ExpenseCategory.FOOD)
        assertEquals("Groceries", f.categoriesSummaryLabel)
        assertEquals(ExpenseCategory.GROCERIES, f.selectedCategory)
        f = f.toggleFundingAccount("Maybank").toggleFundingAccount("CIMB")
        assertEquals("CIMB + Maybank", f.accountsSummaryLabel)
        f = f.toggleFundingAccount("MAYBANK")
        assertEquals(setOf("CIMB"), f.fundingAccounts)
        f = f.toggleChannel(PaymentChannel.CARD).toggleChannel(PaymentChannel.APPLE_PAY)
        assertEquals("Apple Pay + Card", f.paymentChannelsSummaryLabel)
        assertEquals("CIMB • Groceries • Apple Pay + Card", f.activeDimensionSummary)
        assertTrue(f.hasActiveDimensionFilters)
        val cleared = f.copy(dateFilter = QuickDateFilter.TODAY, searchText = "x").clearAllFilters()
        assertEquals(QuickDateFilter.TODAY, cleared.dateFilter)
        assertTrue(cleared.hasActiveFilters)
        assertFalse(cleared.hasActiveDimensionFilters)
        assertNull(cleared.activeDimensionSummary)
        assertEquals(QuickDateFilter.LAST_7_DAYS, cleared.clearAllFilters(keepDateFilter = false).dateFilter)
        assertTrue(TransactionFilters(searchText = " a ").hasActiveDimensionFilters)
        assertFalse(TransactionFilters(searchText = "  ").hasActiveDimensionFilters)
    }

    @Test fun legacyChannelFallback() {
        val legacy = TK.expense(5.0, "Old").copy(paymentChannelRaw = "SOMETHING_NEW", paymentSourceRaw = "Apple Pay")
        assertEquals(PaymentChannel.APPLE_PAY, legacy.iosPaymentChannel)
        assertEquals(PaymentChannel.UNKNOWN, TK.expense(1.0).copy(paymentChannelRaw = "SOMETHING_NEW").iosPaymentChannel)
        assertEquals(listOf("Old"), engine(listOf(legacy), TransactionFilters(paymentChannels = setOf(PaymentChannel.APPLE_PAY))).filteredExpenses.map { it.merchant })
    }
}
