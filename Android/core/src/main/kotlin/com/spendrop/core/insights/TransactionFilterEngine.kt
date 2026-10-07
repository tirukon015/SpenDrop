package com.spendrop.core.insights

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** iOS QuickDateFilter. [displayName] is the label iOS shows. */
enum class QuickDateFilter(val displayName: String) {
    TODAY("Today"), YESTERDAY("Yesterday"), LAST_3_DAYS("Last 3 Days"), LAST_7_DAYS("Last 7 Days"),
    LAST_30_DAYS("Last 30 Days"), THIS_WEEK("This Week"), LAST_WEEK("Last Week"), THIS_MONTH("This Month"),
    LAST_MONTH("Last Month"), CUSTOM("Custom Range");

    val raw: String get() = displayName
}

enum class DailySpendingRange(val displayName: String) { LAST_7_DAYS("Last 7 Days"), LAST_30_DAYS("Last 30 Days") }

/** Inclusive [start, end] in epoch millis. */
data class DateInterval(val start: Long, val end: Long) {
    operator fun contains(t: Long): Boolean = t in start..end
}

/**
 * The filter selection (iOS TransactionFilterEngine's mutable state, immutable here: every change returns a copy).
 * [customStart] / [customEnd] null = iOS defaults (now − 7 days / now).
 */
data class TransactionFilters(
    val dateFilter: QuickDateFilter = QuickDateFilter.LAST_7_DAYS,
    val customStart: Long? = null,
    val customEnd: Long? = null,
    val categories: Set<ExpenseCategory> = emptySet(),
    val paymentChannels: Set<PaymentChannel> = emptySet(),
    val fundingAccounts: Set<String> = emptySet(),
    val searchText: String = "",
    val dailySpendingRange: DailySpendingRange = DailySpendingRange.LAST_7_DAYS,
) {
    /** Single-select compatibility accessors (iOS selectedCategory etc.). */
    val selectedCategory: ExpenseCategory? get() = categories.singleOrNull()
    val selectedPaymentChannel: PaymentChannel? get() = paymentChannels.singleOrNull()
    val selectedFundingAccount: String? get() = fundingAccounts.singleOrNull()

    val searchTerm: String get() = searchText.trim().lowercase()

    val hasActiveDimensionFilters: Boolean
        get() = categories.isNotEmpty() || paymentChannels.isNotEmpty() || fundingAccounts.isNotEmpty() || searchText.trim().isNotEmpty()

    val hasActiveFilters: Boolean get() = hasActiveDimensionFilters || dateFilter != QuickDateFilter.LAST_7_DAYS

    fun clearDimensionFilters(): TransactionFilters =
        copy(categories = emptySet(), paymentChannels = emptySet(), fundingAccounts = emptySet(), searchText = "")

    fun clearAllFilters(keepDateFilter: Boolean = true): TransactionFilters =
        clearDimensionFilters().let { if (keepDateFilter) it else it.copy(dateFilter = QuickDateFilter.LAST_7_DAYS) }

    fun toggleCategory(category: ExpenseCategory): TransactionFilters =
        copy(categories = if (category in categories) categories - category else categories + category)

    fun toggleChannel(channel: PaymentChannel): TransactionFilters =
        copy(paymentChannels = if (channel in paymentChannels) paymentChannels - channel else paymentChannels + channel)

    /** Case-insensitive: removes the existing spelling if present. */
    fun toggleFundingAccount(account: String): TransactionFilters {
        val existing = fundingAccounts.firstOrNull { it.equals(account, ignoreCase = true) }
        return copy(fundingAccounts = if (existing != null) fundingAccounts - existing else fundingAccounts + account)
    }

    val accountsSummaryLabel: String
        get() = when (fundingAccounts.size) {
            0 -> "Accounts"
            1 -> fundingAccounts.first()
            2 -> fundingAccounts.sorted().let { "${it[0]} + ${it[1]}" }
            else -> "Accounts (${fundingAccounts.size})"
        }

    val categoriesSummaryLabel: String
        get() = when (categories.size) {
            0 -> "Categories"
            1 -> categories.first().raw
            2 -> categories.map { it.raw }.sorted().let { "${it[0]} + ${it[1]}" }
            else -> "Categories (${categories.size})"
        }

    val paymentChannelsSummaryLabel: String
        get() = when (paymentChannels.size) {
            0 -> "Payment"
            1 -> paymentChannels.first().displayName
            2 -> paymentChannels.map { it.displayName }.sorted().let { "${it[0]} + ${it[1]}" }
            else -> "Payment (${paymentChannels.size})"
        }

    /** Transactions screen badge: "Maybank • Food + Groceries • Card", null when no dimension is selected. */
    val activeDimensionSummary: String?
        get() {
            val parts = mutableListOf<String>()
            if (fundingAccounts.isNotEmpty()) parts += accountsSummaryLabel
            if (categories.isNotEmpty()) parts += categoriesSummaryLabel
            if (paymentChannels.isNotEmpty()) parts += paymentChannelsSummaryLabel
            return if (parts.isEmpty()) null else parts.joinToString(" • ")
        }
}

data class DailySpendingPoint(
    /** Start of the local day. */
    val date: Long,
    val dayLabel: String,
    /** "yyyy-MM-dd"; also the id. */
    val fullDateString: String,
    val amountMinor: Long,
    val count: Int,
)

data class CategoryBreakdownItem(val category: ExpenseCategory, val totalMinor: Long, val count: Int, val percentage: Double) {
    val id: String get() = category.raw
    /** "42.0% (3 txns)" */
    val detailLabel: String get() = percentLabel(percentage, count)
}

data class ChannelBreakdownItem(val channel: PaymentChannel, val totalMinor: Long, val count: Int, val percentage: Double) {
    val id: String get() = channel.raw
    val detailLabel: String get() = percentLabel(percentage, count)
}

data class FundingBreakdownItem(
    val name: String, val totalMinor: Long, val count: Int, val percentage: Double, val paymentSource: PaymentSource?,
) {
    val id: String get() = name
    val detailLabel: String get() = percentLabel(percentage, count)
}

data class MerchantBreakdownItem(val name: String, val totalMinor: Long, val count: Int)

data class MovementKindBreakdownItem(val kind: MoneyMovementKind, val totalMinor: Long, val count: Int)

data class SharedSpendingSummary(
    val sharedCount: Int = 0,
    /** Full bills of shared expenses. */
    val sharedTotalMinor: Long = 0,
    /** My share of those bills. */
    val myShareMinor: Long = 0,
    val refundsMinor: Long = 0,
    val netSpendingMinor: Long = 0,
)

data class PeriodComparison(
    val currentTotalMinor: Long,
    val previousTotalMinor: Long,
    val differenceMinor: Long,
    val percentageChange: Double?,
    val isIncreased: Boolean,
    val previousPeriodSubtitle: String,
    /** The preceding interval that was compared against. */
    val previousInterval: DateInterval,
) {
    /** "+RM 5.00" / "-RM 5.00" (iOS uses "-" whenever not increased, including no change). */
    val differenceLabel: String get() = (if (isIncreased) "+" else "-") + MoneyText.format(kotlin.math.abs(differenceMinor))
    /** "+12.5% vs Previous 7 Days" */
    val percentageLabel: String?
        get() = percentageChange?.let {
            (if (isIncreased) "+" else "-") + String.format(java.util.Locale.ROOT, "%.1f%%", kotlin.math.abs(it)) + " " + previousPeriodSubtitle
        }
}

internal fun percentLabel(percentage: Double, count: Int): String =
    String.format(java.util.Locale.ROOT, "%.1f%% (%d txns)", percentage, count)

/**
 * Port of iOS TransactionFilterEngine: the single source of truth for the Transactions and Breakdown screens.
 * Pure: give it the records, the filter selection, "now" and the calendar; every value is computed on demand.
 *
 * Money is sen. Spending = full amount when I paid, my share when someone else paid ([ExpenseMath.spendingMinor]).
 */
class TransactionFilterEngine(
    val expenses: List<Expense>,
    val movements: List<MoneyMovement> = emptyList(),
    val filters: TransactionFilters = TransactionFilters(),
    val now: Long,
    val calendar: CalendarContext = CalendarContext(),
    /** Live shares of an expense (for spending / my share / shared). */
    val sharesOf: (String) -> List<ExpenseShare> = { emptyList() },
    /** Account id -> name (archived included), for movement filters and search. */
    private val accountName: (String) -> String? = { null },
    /** Person id -> current name (falls back to the movement's snapshot). */
    private val personName: (String) -> String? = { null },
) {
    companion object {
        fun of(
            snapshot: FinanceSnapshot,
            filters: TransactionFilters,
            now: Long,
            calendar: CalendarContext = CalendarContext(),
            expenses: List<Expense> = snapshot.expenses,
            movements: List<MoneyMovement> = snapshot.movements,
        ): TransactionFilterEngine {
            val accounts = snapshot.accounts.associate { it.id to it.name }
            val people = snapshot.people.associate { it.id to it.name }
            return TransactionFilterEngine(expenses, movements, filters, now, calendar, snapshot::sharesOf, { accounts[it] }, { people[it] })
        }
    }

    fun withFilters(newFilters: TransactionFilters) =
        TransactionFilterEngine(expenses, movements, newFilters, now, calendar, sharesOf, accountName, personName)

    fun spendingMinor(e: Expense): Long = ExpenseMath.spendingMinor(e, sharesOf(e.id))
    fun isShared(e: Expense): Boolean = sharesOf(e.id).isNotEmpty()
    fun myShareMinor(e: Expense): Long = ExpenseMath.myShareMinor(e, sharesOf(e.id))

    // MARK: Date intervals

    /** iOS dateInterval(for:now:). Ends are 23:59:59 local time. */
    fun dateInterval(filter: QuickDateFilter = filters.dateFilter): DateInterval {
        val cal = calendar
        val today = cal.date(now)
        val startOfToday = cal.startOfDay(today)
        val endOfToday = cal.endOfDay(today)
        return when (filter) {
            QuickDateFilter.TODAY -> DateInterval(startOfToday, endOfToday)
            QuickDateFilter.YESTERDAY -> today.minusDays(1).let { DateInterval(cal.startOfDay(it), cal.endOfDay(it)) }
            QuickDateFilter.LAST_3_DAYS -> DateInterval(cal.startOfDay(today.minusDays(2)), endOfToday)
            QuickDateFilter.LAST_7_DAYS -> DateInterval(cal.startOfDay(today.minusDays(6)), endOfToday)
            QuickDateFilter.LAST_30_DAYS -> DateInterval(cal.startOfDay(today.minusDays(29)), endOfToday)
            QuickDateFilter.THIS_WEEK -> mondayOfCurrentWeek().let { DateInterval(cal.startOfDay(it), cal.endOfDay(it.plusDays(6))) }
            QuickDateFilter.LAST_WEEK -> mondayOfCurrentWeek().minusWeeks(1).let { DateInterval(cal.startOfDay(it), cal.endOfDay(it.plusDays(6))) }
            QuickDateFilter.THIS_MONTH -> today.withDayOfMonth(1).let { DateInterval(cal.startOfDay(it), cal.endOfDay(it.plusDays(it.lengthOfMonth() - 1L))) }
            QuickDateFilter.LAST_MONTH -> today.withDayOfMonth(1).minusMonths(1).let {
                DateInterval(cal.startOfDay(it), cal.endOfDay(it.plusDays(it.lengthOfMonth() - 1L)))
            }
            QuickDateFilter.CUSTOM -> {
                val s = cal.startOfDay(customStart)
                val e = cal.endOfDay(customEnd)
                DateInterval(minOf(s, e), maxOf(s, e))
            }
        }
    }

    private val customStart: Long get() = filters.customStart ?: calendar.zoned(now).minusDays(7).toInstant().toEpochMilli()
    private val customEnd: Long get() = filters.customEnd ?: now

    /** iOS: the Monday (weekday 2) of the week — per the calendar's first weekday — that contains now. */
    private fun mondayOfCurrentWeek(): LocalDate {
        val start = calendar.weekStart(calendar.date(now))
        return start.plusDays(((DayOfWeek.MONDAY.value - calendar.firstDayOfWeek.value + 7) % 7).toLong())
    }

    /** "22 Sep — 28 Sep"; "7 Oct 2026" for Today / Yesterday; years shown when the range crosses a year. */
    fun dateSubtitle(filter: QuickDateFilter = filters.dateFilter): String {
        val (start, end) = dateInterval(filter)
        return when (filter) {
            QuickDateFilter.TODAY, QuickDateFilter.YESTERDAY -> calendar.format(start, "d MMM yyyy")
            else -> {
                val pattern = if (calendar.date(start).year == calendar.date(end).year) "d MMM" else "d MMM yyyy"
                "${calendar.format(start, pattern)} — ${calendar.format(end, pattern)}"
            }
        }
    }

    val currentSubtitle: String get() = dateSubtitle(filters.dateFilter)

    // MARK: Filtering

    private fun matchesDimensions(e: Expense, interval: DateInterval): Boolean {
        if (e.date !in interval) return false
        if (filters.categories.isNotEmpty() && e.category !in filters.categories) return false
        if (filters.paymentChannels.isNotEmpty() && e.iosPaymentChannel !in filters.paymentChannels) return false
        if (filters.fundingAccounts.isNotEmpty()) {
            val funding = e.effectiveFundingAccount
            if (filters.fundingAccounts.none { it.equals(funding, ignoreCase = true) }) return false
        }
        val term = filters.searchTerm
        if (term.isNotEmpty() && !expenseMatchesSearch(e, term)) return false
        return true
    }

    /** Search over merchant, category, funding account, channel, notes and amount ("%.2f" of the full amount). */
    fun expenseMatchesSearch(e: Expense, term: String): Boolean =
        e.merchant.lowercase().contains(term) ||
            e.category.raw.lowercase().contains(term) ||
            e.effectiveFundingAccount.lowercase().contains(term) ||
            e.iosPaymentChannel.displayName.lowercase().contains(term) ||
            (e.notes?.lowercase()?.contains(term) ?: false) ||
            MoneyText.plain(e.amountMinor).contains(term)

    /** Search over kind, note, person (current name, else snapshot), both accounts and amount. */
    fun movementMatchesSearch(m: MoneyMovement, term: String): Boolean {
        val fields = listOf(
            m.kind.displayName, m.note ?: "", m.personId?.let(personName) ?: m.personNameSnapshot ?: "",
            m.accountId?.let(accountName) ?: "", m.counterAccountId?.let(accountName) ?: "",
            MoneyText.plain(m.amountMinor),
        )
        return fields.any { it.lowercase().contains(term) }
    }

    val filteredExpenses: List<Expense> by lazy {
        val interval = dateInterval(filters.dateFilter)
        expenses.filter { matchesDimensions(it, interval) }
    }

    /**
     * Money In / Money Out / Transfers in the selected range. They have no category, so an active category filter
     * hides them. The account filter matches the movement's account or the transfer destination.
     */
    val filteredMovements: List<MoneyMovement> by lazy {
        if (filters.categories.isNotEmpty()) return@lazy emptyList()
        val interval = dateInterval(filters.dateFilter)
        val term = filters.searchTerm
        movements.filter { m ->
            if (m.date !in interval) return@filter false
            if (filters.paymentChannels.isNotEmpty() && m.paymentChannel !in filters.paymentChannels) return@filter false
            if (filters.fundingAccounts.isNotEmpty()) {
                val names = listOfNotNull(m.accountId?.let(accountName), m.counterAccountId?.let(accountName))
                val match = names.any { name -> filters.fundingAccounts.any { it.equals(name, ignoreCase = true) } }
                if (!match) return@filter false
            }
            if (term.isNotEmpty() && !movementMatchesSearch(m, term)) return@filter false
            true
        }
    }

    // MARK: KPIs

    /** Sum of spending over the filtered expenses (all currencies, like iOS). */
    val totalSpendingMinor: Long by lazy { filteredExpenses.sumOf { spendingMinor(it) } }
    val transactionCount: Int get() = filteredExpenses.size

    val numberOfCalendarDays: Int
        get() {
            val (s, e) = dateInterval(filters.dateFilter)
            val diff = ChronoUnit.DAYS.between(calendar.date(s), calendar.date(e)).toInt()
            return maxOf(1, diff + 1)
        }

    /** Sen (not rounded). */
    val averagePerDayMinor: Double get() = numberOfCalendarDays.let { if (it > 0) totalSpendingMinor.toDouble() / it else 0.0 }
    val averagePerTransactionMinor: Double get() = if (transactionCount > 0) totalSpendingMinor.toDouble() / transactionCount else 0.0

    /** Spending, Money In, Money Out and Net Cash Flow for the current filters (RM). */
    val cashFlowSummary: FinancialCalculator.Summary by lazy {
        FinancialCalculator.summary(filteredExpenses, sharesOf, filteredMovements)
    }

    val sharedSpendingSummary: SharedSpendingSummary
        get() {
            val shared = filteredExpenses.filter { isShared(it) }
            val summary = cashFlowSummary
            return SharedSpendingSummary(
                sharedCount = shared.size,
                sharedTotalMinor = shared.sumOf { it.amountMinor },
                myShareMinor = shared.sumOf { myShareMinor(it) },
                refundsMinor = summary.refundsMinor,
                netSpendingMinor = summary.netSpendingMinor,
            )
        }

    /** Spending per merchant, largest first (ties by name). */
    val merchantBreakdown: List<MerchantBreakdownItem>
        get() = filteredExpenses.groupBy { it.merchant.trim() }
            .map { (name, items) -> MerchantBreakdownItem(name.ifEmpty { "Unknown" }, items.sumOf { spendingMinor(it) }, items.size) }
            .sortedWith(compareByDescending<MerchantBreakdownItem> { it.totalMinor }.thenBy { it.name })

    /** Movements by kind (own transfers excluded), largest first. */
    val movementKindBreakdown: List<MovementKindBreakdownItem>
        get() = filteredMovements.filter { it.kind != MoneyMovementKind.OWN_TRANSFER }.groupBy { it.kind }
            .map { (kind, items) -> MovementKindBreakdownItem(kind, items.sumOf { it.amountMinor }, items.size) }
            .sortedWith(compareByDescending<MovementKindBreakdownItem> { it.totalMinor }.thenBy { it.kind.ordinal })

    /** Funding-account choices for the filter: a fixed list, then names used by expenses (sorted, no case duplicates). */
    val availableFundingAccounts: List<String>
        get() {
            val accounts = mutableListOf("Maybank", "Wise", "CIMB", "RHB", "Touch 'n Go", "Cash")
            val existing = expenses.map { it.effectiveFundingAccount }.filter { it != "Unknown" && it.isNotEmpty() }.toSortedSet()
            for (acc in existing) if (accounts.none { it.equals(acc, ignoreCase = true) }) accounts += acc
            return accounts
        }

    // MARK: Daily spending (own 7 / 30 day range; dimension filters apply)

    private fun dailyInterval(): DateInterval {
        val today = calendar.date(now)
        val back = if (filters.dailySpendingRange == DailySpendingRange.LAST_7_DAYS) 6L else 29L
        return DateInterval(calendar.startOfDay(today.minusDays(back)), calendar.endOfDay(today))
    }

    /** "1 Oct — 7 Oct" (ends with today's date). */
    val dailySpendingSubtitle: String
        get() = "${calendar.format(dailyInterval().start, "d MMM")} — ${calendar.format(now, "d MMM")}"

    val dailySpending: List<DailySpendingPoint> by lazy {
        val interval = dailyInterval()
        val byDay = expenses.filter { matchesDimensions(it, interval) }.groupBy { calendar.date(it.date) }
        val points = mutableListOf<DailySpendingPoint>()
        var day = calendar.date(interval.start)
        val last = calendar.date(interval.end)
        val labelPattern = if (filters.dailySpendingRange == DailySpendingRange.LAST_7_DAYS) "EEE" else "d"
        while (!day.isAfter(last)) {
            val items = byDay[day].orEmpty()
            points += DailySpendingPoint(
                date = calendar.startOfDay(day),
                dayLabel = calendar.format(day, labelPattern),
                fullDateString = day.toString(),
                amountMinor = items.sumOf { spendingMinor(it) },
                count = items.size,
            )
            day = day.plusDays(1)
        }
        points
    }

    val dailySpendingAverageMinor: Double
        get() = if (dailySpending.isEmpty()) 0.0 else dailySpending.sumOf { it.amountMinor }.toDouble() / dailySpending.size

    // MARK: Breakdowns (% of total spending)

    private fun pct(sum: Long, total: Long) = if (total > 0) sum.toDouble() / total * 100.0 else 0.0

    val categoryBreakdown: List<CategoryBreakdownItem>
        get() {
            val total = totalSpendingMinor
            return filteredExpenses.groupBy { it.category }.map { (cat, items) ->
                val sum = items.sumOf { spendingMinor(it) }
                CategoryBreakdownItem(cat, sum, items.size, pct(sum, total))
            }.sortedWith(compareByDescending<CategoryBreakdownItem> { it.totalMinor }.thenBy { it.category.ordinal })
        }

    val paymentChannelBreakdown: List<ChannelBreakdownItem>
        get() {
            val total = totalSpendingMinor
            return filteredExpenses.groupBy { it.iosPaymentChannel }.map { (ch, items) ->
                val sum = items.sumOf { spendingMinor(it) }
                ChannelBreakdownItem(ch, sum, items.size, pct(sum, total))
            }.sortedWith(compareByDescending<ChannelBreakdownItem> { it.totalMinor }.thenBy { it.channel.ordinal })
        }

    val fundingAccountBreakdown: List<FundingBreakdownItem>
        get() {
            val total = totalSpendingMinor
            return filteredExpenses.groupBy { it.effectiveFundingAccount }.map { (account, items) ->
                val sum = items.sumOf { spendingMinor(it) }
                val ps = PaymentSource.entries.firstOrNull { it.raw.equals(account, ignoreCase = true) }
                FundingBreakdownItem(account, sum, items.size, pct(sum, total), ps)
            }.sortedWith(compareByDescending<FundingBreakdownItem> { it.totalMinor }.thenBy { it.name })
        }

    // MARK: Previous period comparison (same dimension filters, preceding interval of equal length)

    val previousPeriodComparison: PeriodComparison
        get() {
            val (start, end) = dateInterval(filters.dateFilter)
            val duration = maxOf(86_400_000L, end - start)
            val prevEnd = start - 1_000L
            val prevStart = prevEnd - duration
            val prevInterval = DateInterval(prevStart, prevEnd)
            val prevTotal = expenses.filter { matchesDimensions(it, prevInterval) }.sumOf { spendingMinor(it) }
            val current = totalSpendingMinor
            val diff = current - prevTotal
            val pctChange = when {
                prevTotal > 0 -> (current - prevTotal).toDouble() / prevTotal * 100.0
                current > 0 -> 100.0
                else -> 0.0
            }
            val sub = when (filters.dateFilter) {
                QuickDateFilter.TODAY -> "vs Yesterday"
                QuickDateFilter.YESTERDAY -> "vs Previous Day"
                QuickDateFilter.LAST_3_DAYS -> "vs Previous 3 Days"
                QuickDateFilter.LAST_7_DAYS -> "vs Previous 7 Days"
                QuickDateFilter.LAST_30_DAYS -> "vs Previous 30 Days"
                QuickDateFilter.THIS_WEEK -> "vs Previous Week"
                QuickDateFilter.LAST_WEEK -> "vs Prior Week"
                QuickDateFilter.THIS_MONTH -> "vs Previous Month"
                QuickDateFilter.LAST_MONTH -> "vs Prior Month"
                QuickDateFilter.CUSTOM -> "vs ${calendar.format(prevStart, "d MMM")} — ${calendar.format(prevEnd, "d MMM")}"
            }
            return PeriodComparison(current, prevTotal, diff, pctChange, diff > 0, sub, prevInterval)
        }
}
