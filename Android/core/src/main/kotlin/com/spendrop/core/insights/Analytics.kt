package com.spendrop.core.insights

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Expense
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement

/*
 * The math behind iOS AnalyticsView ("Breakdown") and DashboardView ("Home"), pulled out of the SwiftUI views.
 * Every label is the text iOS shows. Amount labels use MoneyText ("RM 1,234.50").
 */

/** A titled metric tile (iOS metricCard). */
data class MetricCard(val title: String, val value: String, val subtitle: String)

/** A "title ...... value" row. */
data class InsightRow(val title: String, val value: String, val bold: Boolean = false)

data class ComparisonCard(
    /** "LAST 7 DAYS COMPARISON" */
    val header: String,
    val comparison: PeriodComparison,
    /** Current period total, e.g. "RM 120.00". */
    val currentValue: String,
    /** "Last 7 Days" */
    val periodName: String,
)

data class DailySpendingCard(
    val title: String,
    /** "1 Oct — 7 Oct • Avg RM 12.00/day" */
    val subtitle: String,
    val range: DailySpendingRange,
    val points: List<DailySpendingPoint>,
    /** Only for 30 days: "Showing all 30 days (scroll to explore) • Zero-spending days included". */
    val footnote: String?,
)

data class TrendCard(
    /** "Spending Trend" / "Cash Flow Trend" */
    val title: String,
    val granularity: PeriodGrouping.Granularity,
    val buckets: List<PeriodGrouping.Bucket>,
    /** "All records · weekly totals" (+ " · own transfers excluded" for cash flow) */
    val footnote: String,
)

enum class BreakdownMode(val displayName: String) { SPENDING("Spending"), CASH_FLOW("Cash Flow") }

/** Breakdown, Spending mode. [isEmpty] = iOS shows the empty state ([EMPTY_TITLE] / [EMPTY_MESSAGE]). */
data class SpendingBreakdown(
    val isEmpty: Boolean,
    val totalSpent: MetricCard,
    val averagePerDay: MetricCard,
    val averagePerTransactionMinor: Double,
    val comparison: ComparisonCard,
    val daily: DailySpendingCard,
    val categories: List<CategoryBreakdownItem>,
    val channels: List<ChannelBreakdownItem>,
    val fundingAccounts: List<FundingBreakdownItem>,
    /** "Shared & Refunds" rows; null when there is nothing shared and no refund (section hidden). */
    val sharedAndRefunds: List<InsightRow>?,
    /** "Top Merchants" (max 8): "Dinner · 2" → "RM 42.00". */
    val topMerchants: List<InsightRow>,
    val trend: TrendCard,
) {
    companion object {
        const val EMPTY_TITLE = "No transactions match current filters"
        const val EMPTY_MESSAGE = "Try choosing another date filter or resetting your account/category filters."
    }
}

/** Breakdown, Cash Flow mode. */
data class CashFlowBreakdown(
    val summary: FinancialCalculator.Summary,
    val moneyIn: MetricCard,
    val moneyOut: MetricCard,
    val netCashFlow: MetricCard,
    val isNetPositive: Boolean,
    /** "By Type" rows, e.g. "Income · 1" → "+RM 3,000.00"; empty = section hidden. */
    val byType: List<InsightRow>,
    val trend: TrendCard,
)

object BreakdownAnalytics {
    private fun plural(n: Int, word: String) = "$n $word${if (n == 1) "" else "s"}"

    /**
     * Trend over ALL records (not the filters), like iOS: the view passes every expense and movement.
     */
    fun trend(
        engine: TransactionFilterEngine,
        granularity: PeriodGrouping.Granularity,
        showsCashFlow: Boolean,
    ): TrendCard {
        val buckets = PeriodGrouping.buckets(engine.expenses, engine.movements, granularity, now = engine.now,
            calendar = engine.calendar, sharesOf = engine.sharesOf)
        return TrendCard(
            title = if (showsCashFlow) "Cash Flow Trend" else "Spending Trend",
            granularity = granularity,
            buckets = buckets,
            footnote = "All records · ${granularity.displayName.lowercase()} totals" + if (showsCashFlow) " · own transfers excluded" else "",
        )
    }

    fun spending(
        engine: TransactionFilterEngine,
        trendGranularity: PeriodGrouping.Granularity = PeriodGrouping.Granularity.WEEKLY,
    ): SpendingBreakdown {
        val filter = engine.filters.dateFilter
        val days = engine.numberOfCalendarDays
        val shared = engine.sharedSpendingSummary
        val sharedRows = if (shared.sharedCount > 0 || shared.refundsMinor > 0) buildList<InsightRow> {
            if (shared.sharedCount > 0) {
                add(InsightRow("Shared expenses", "${shared.sharedCount} · bills ${MoneyText.format(shared.sharedTotalMinor)}"))
                add(InsightRow("My share", MoneyText.format(shared.myShareMinor)))
            }
            if (shared.refundsMinor > 0) {
                add(InsightRow("Gross spending", MoneyText.format(engine.cashFlowSummary.spendingMinor)))
                add(InsightRow("Refunds", "−" + MoneyText.format(shared.refundsMinor)))
                add(InsightRow("Net spending", MoneyText.format(shared.netSpendingMinor), bold = true))
            }
        } else null
        val range = engine.filters.dailySpendingRange
        return SpendingBreakdown(
            isEmpty = engine.filteredExpenses.isEmpty(),
            totalSpent = MetricCard("TOTAL SPENT", MoneyText.format(engine.totalSpendingMinor), plural(engine.transactionCount, "transaction")),
            averagePerDay = MetricCard("AVERAGE / DAY", MoneyText.format(engine.averagePerDayMinor), "over ${plural(days, "day")}"),
            averagePerTransactionMinor = engine.averagePerTransactionMinor,
            comparison = ComparisonCard(
                header = "${filter.displayName.uppercase()} COMPARISON",
                comparison = engine.previousPeriodComparison,
                currentValue = MoneyText.format(engine.totalSpendingMinor),
                periodName = filter.displayName,
            ),
            daily = DailySpendingCard(
                title = "Daily Spending",
                subtitle = "${engine.dailySpendingSubtitle} • Avg ${MoneyText.format(engine.dailySpendingAverageMinor)}/day",
                range = range,
                points = engine.dailySpending,
                footnote = if (range == DailySpendingRange.LAST_30_DAYS) "Showing all 30 days (scroll to explore) • Zero-spending days included" else null,
            ),
            categories = engine.categoryBreakdown,
            channels = engine.paymentChannelBreakdown,
            fundingAccounts = engine.fundingAccountBreakdown,
            sharedAndRefunds = sharedRows,
            topMerchants = engine.merchantBreakdown.take(8).map { InsightRow("${it.name} · ${it.count}", MoneyText.format(it.totalMinor)) },
            trend = trend(engine, trendGranularity, showsCashFlow = false),
        )
    }

    fun cashFlow(
        engine: TransactionFilterEngine,
        trendGranularity: PeriodGrouping.Granularity = PeriodGrouping.Granularity.WEEKLY,
    ): CashFlowBreakdown {
        val flow = engine.cashFlowSummary
        val net = flow.netCashFlowMinor
        return CashFlowBreakdown(
            summary = flow,
            moneyIn = MetricCard("MONEY IN", MoneyText.format(flow.moneyInMinor), engine.filters.dateFilter.displayName),
            moneyOut = MetricCard("MONEY OUT", MoneyText.format(flow.moneyOutMinor), "expenses paid + other out"),
            netCashFlow = MetricCard(
                "NET CASH FLOW",
                (if (net >= 0) "+" else "") + MoneyText.format(net),
                "Money In − Money Out · spending is shown separately (${MoneyText.format(flow.spendingMinor)})",
            ),
            isNetPositive = net >= 0,
            byType = engine.movementKindBreakdown.map {
                InsightRow("${it.kind.displayName} · ${it.count}", (if (it.kind.direction == MoneyDirection.IN) "+" else "−") + MoneyText.format(it.totalMinor))
            },
            trend = trend(engine, trendGranularity, showsCashFlow = true),
        )
    }
}

// MARK: - Home (Dashboard)

/** "Owed to you" / "You owe" (iOS PersonLedger.Summary). Per currency, positive values. */
data class BalancesSummary(
    val owedToMe: Map<String, Long> = emptyMap(),
    val iOwe: Map<String, Long> = emptyMap(),
    /** People with history whose balances are all zero. */
    val settledCount: Int = 0,
    val owingMeCount: Int = 0,
    val iOweCount: Int = 0,
) {
    val isEmpty: Boolean get() = owedToMe.isEmpty() && iOwe.isEmpty() && settledCount == 0
}

data class SpendingSummaryCard(val title: String, val amountMinor: Long, val currency: String = "RM") {
    val value: String get() = MoneyText.format(amountMinor, currency)
}

data class HomeSummary(
    val today: SpendingSummaryCard,
    val thisWeek: SpendingSummaryCard,
    val thisMonth: SpendingSummaryCard,
    /** Today's expenses, newest first. */
    val todayExpenses: List<Expense>,
    /** "3 transactions" (iOS always says "transactions"). */
    val todayCountLabel: String,
    val sharedThisMonthCount: Int,
    val sharedThisMonthMyShareMinor: Long,
    /** "My share of 2 shared expenses this month" — null when nothing shared this month (row hidden). */
    val sharedThisMonthLabel: String?,
    /** "CASH FLOW · THIS MONTH" card; null when there is no movement this month (card hidden). */
    val cashFlowThisMonth: FinancialCalculator.Summary?,
    /** Rows of the cash-flow card: Money In / Money Out / Net. */
    val cashFlowRows: List<InsightRow>,
    /** RM balances for the "BALANCES" card (hidden when both are 0). */
    val owedToMeMinor: Long,
    val iOweMinor: Long,
    val balances: BalancesSummary,
    /** "October 2026" */
    val monthYear: String,
    /** "Recent Activity": up to 5 expenses not from today, newest first. */
    val recentNonToday: List<Expense>,
)

object HomeAnalytics {
    /** iOS PersonLedger.summary(of: people), from the core per-person balances. */
    fun balancesSummary(snapshot: FinanceSnapshot): BalancesSummary {
        val currencies = (snapshot.expenses.map { it.currency } + snapshot.movements.map { it.currency }).toSet()
        val byCurrency = currencies.associateWith {
            FinancialCalculator.personBalances(snapshot.expenses, snapshot::sharesOf, snapshot.movements, it)
        }
        val owed = HashMap<String, Long>(); val owe = HashMap<String, Long>()
        var settled = 0; var owingMe = 0; var iOweCount = 0
        for (person in snapshot.people) {
            val balances = byCurrency.mapNotNull { (cur, map) -> map[person.id]?.takeIf { it != 0L }?.let { cur to it } }.toMap()
            if (balances.isEmpty()) {
                val hasHistory = snapshot.shares.any { it.personId == person.id } ||
                    snapshot.expenses.any { it.payerId == person.id } || snapshot.movements.any { it.personId == person.id }
                if (hasHistory) settled++
                continue
            }
            if (balances.values.any { it > 0 }) owingMe++
            if (balances.values.any { it < 0 }) iOweCount++
            for ((cur, v) in balances) {
                if (v > 0) owed[cur] = (owed[cur] ?: 0) + v
                if (v < 0) owe[cur] = (owe[cur] ?: 0) - v
            }
        }
        return BalancesSummary(owed, owe, settled, owingMe, iOweCount)
    }

    fun home(snapshot: FinanceSnapshot, now: Long, calendar: CalendarContext = CalendarContext()): HomeSummary {
        val all = snapshot.expenses.sortedByDescending { it.date }
        val today = calendar.date(now)
        // DateInterval.contains is inclusive of its end (iOS).
        val weekStart = calendar.weekStart(today)
        val week = DateInterval(calendar.startOfDay(weekStart), calendar.startOfDay(weekStart.plusWeeks(1)))
        val monthStart = today.withDayOfMonth(1)
        val month = DateInterval(calendar.startOfDay(monthStart), calendar.startOfDay(monthStart.plusMonths(1)))

        fun spend(list: List<Expense>) = list.sumOf { ExpenseMath.spendingMinor(it, snapshot.sharesOf(it.id)) }
        val todayExpenses = all.filter { calendar.date(it.date) == today }
        val weekExpenses = all.filter { it.date in week }
        val monthExpenses = all.filter { it.date in month }
        val monthMovements: List<MoneyMovement> = snapshot.movements.sortedByDescending { it.date }.filter { it.date in month }
        val shared = monthExpenses.filter { snapshot.sharesOf(it.id).isNotEmpty() }
        val sharedMine = shared.sumOf { ExpenseMath.myShareMinor(it, snapshot.sharesOf(it.id)) }
        val flow = if (monthMovements.isEmpty()) null else FinancialCalculator.summary(monthExpenses, snapshot::sharesOf, monthMovements)
        val balances = balancesSummary(snapshot)
        return HomeSummary(
            today = SpendingSummaryCard("Today", spend(todayExpenses)),
            thisWeek = SpendingSummaryCard("This Week", spend(weekExpenses)),
            thisMonth = SpendingSummaryCard("This Month", spend(monthExpenses)),
            todayExpenses = todayExpenses,
            todayCountLabel = "${todayExpenses.size} transactions",
            sharedThisMonthCount = shared.size,
            sharedThisMonthMyShareMinor = sharedMine,
            sharedThisMonthLabel = if (shared.isEmpty()) null
            else "My share of ${shared.size} shared expense${if (shared.size == 1) "" else "s"} this month",
            cashFlowThisMonth = flow,
            cashFlowRows = flow?.let {
                listOf(
                    InsightRow("Money In", MoneyText.format(it.moneyInMinor)),
                    InsightRow("Money Out", MoneyText.format(it.moneyOutMinor)),
                    InsightRow("Net", (if (it.netCashFlowMinor >= 0) "+" else "") + MoneyText.format(it.netCashFlowMinor)),
                )
            }.orEmpty(),
            owedToMeMinor = balances.owedToMe["RM"] ?: 0,
            iOweMinor = balances.iOwe["RM"] ?: 0,
            balances = balances,
            monthYear = calendar.format(now, "MMMM yyyy"),
            recentNonToday = all.filter { calendar.date(it.date) != today }.take(5),
        )
    }
}
