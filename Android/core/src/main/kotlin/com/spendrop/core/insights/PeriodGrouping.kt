package com.spendrop.core.insights

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import java.time.LocalDate

/** Groups spending and cash flow into consecutive days / weeks / months for trend charts. Pure; sen. */
object PeriodGrouping {
    enum class Granularity(val displayName: String, val defaultCount: Int) {
        DAILY("Daily", 7), WEEKLY("Weekly", 8), MONTHLY("Monthly", 6);

        internal val labelPattern: String
            get() = when (this) { DAILY -> "EEE d"; WEEKLY -> "d MMM"; MONTHLY -> "MMM" }

        internal fun periodStart(day: LocalDate, cal: CalendarContext): LocalDate = when (this) {
            DAILY -> day
            WEEKLY -> cal.weekStart(day)
            MONTHLY -> day.withDayOfMonth(1)
        }

        internal fun add(day: LocalDate, n: Long): LocalDate = when (this) {
            DAILY -> day.plusDays(n)
            WEEKLY -> day.plusWeeks(n)
            MONTHLY -> day.plusMonths(n)
        }
    }

    data class Bucket(
        /** Start of the period (local midnight). Also the id. */
        val start: Long,
        val label: String,
        val spendingMinor: Long = 0,
        val inMinor: Long = 0,
        val outMinor: Long = 0,
    ) {
        val netMinor: Long get() = inMinor - outMinor
    }

    /**
     * The last [count] periods ending with the one containing [now], oldest first. Only [currency] records count.
     * Spending adds my spending; out adds cash paid for expenses and Money Out; in adds Money In. Own transfers are
     * excluded. Weeks start on [CalendarContext.firstDayOfWeek] (iOS `dateInterval(of: .weekOfYear)`).
     */
    fun buckets(
        expenses: List<Expense>,
        movements: List<MoneyMovement>,
        granularity: Granularity,
        count: Int? = null,
        now: Long,
        currency: String = "RM",
        calendar: CalendarContext = CalendarContext(),
        sharesOf: (String) -> List<ExpenseShare> = { emptyList() },
    ): List<Bucket> {
        val n = maxOf(1, count ?: granularity.defaultCount)
        val current = granularity.periodStart(calendar.date(now), calendar)
        val starts = (n - 1 downTo 0).map { granularity.add(current, -it.toLong()) }
        val startMillis = starts.map { calendar.startOfDay(it) }
        val spending = LongArray(n); val inM = LongArray(n); val outM = LongArray(n)
        val first = startMillis.first()
        val end = calendar.startOfDay(granularity.add(current, 1))

        fun index(t: Long): Int? {
            if (t < first || t >= end) return null
            return startMillis.indexOfLast { it <= t }.takeIf { it >= 0 }
        }

        for (e in expenses) if (e.currency == currency) {
            val i = index(e.date) ?: continue
            spending[i] += ExpenseMath.spendingMinor(e, sharesOf(e.id))
            outM[i] += ExpenseMath.cashOutMinor(e)
        }
        for (m in movements) if (m.currency == currency) {
            val i = index(m.date) ?: continue
            when (m.kind.direction) {
                MoneyDirection.IN -> inM[i] += m.amountMinor
                MoneyDirection.OUT -> outM[i] += m.amountMinor
                MoneyDirection.INTERNAL -> Unit
            }
        }
        return starts.indices.map { i ->
            Bucket(startMillis[i], calendar.format(starts[i], granularity.labelPattern), spending[i], inM[i], outM[i])
        }
    }
}
