package com.spendrop.core.insights

import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind

/** Type filter for the unified Transactions timeline (iOS ActivityFilter). */
enum class ActivityFilter(val raw: String, val title: String) {
    ALL("all", "All"), EXPENSES("expenses", "Expenses"), MONEY_IN("moneyIn", "Money In"),
    MONEY_OUT("moneyOut", "Money Out"), SHARED("shared", "Shared"), TRANSFERS("transfers", "Transfers"),
}

/** One timeline row, built on the fly from an Expense or a MoneyMovement; never stored. */
sealed interface ActivityItem {
    val id: String
    val date: Long

    data class ExpenseItem(val expense: Expense, val isShared: Boolean) : ActivityItem {
        override val id: String get() = expense.id
        override val date: Long get() = expense.date
    }

    data class MovementItem(val movement: MoneyMovement) : ActivityItem {
        override val id: String get() = movement.id
        override val date: Long get() = movement.date
    }
}

/** Expenses screen sort order (iOS ExpenseSortOrder). */
enum class ExpenseSortOrder(val displayName: String) { NEWEST_FIRST("Newest First"), OLDEST_FIRST("Oldest First") }

/** A day section of the timeline: "Today" / "Yesterday" (with the date as subtitle) or "7 Oct 2026". */
data class ActivityDayGroup(val dateHeader: String, val dateSubtitle: String?, val date: Long, val items: List<ActivityItem>)

object ActivityFeed {
    fun matches(item: ActivityItem, filter: ActivityFilter): Boolean = when (filter) {
        ActivityFilter.ALL -> true
        ActivityFilter.EXPENSES -> item is ActivityItem.ExpenseItem
        ActivityFilter.SHARED -> item is ActivityItem.ExpenseItem && item.isShared
        ActivityFilter.MONEY_IN -> item is ActivityItem.MovementItem && item.movement.kind.direction == MoneyDirection.IN
        ActivityFilter.MONEY_OUT -> item is ActivityItem.MovementItem && item.movement.kind.direction == MoneyDirection.OUT
        ActivityFilter.TRANSFERS -> item is ActivityItem.MovementItem && item.movement.kind == MoneyMovementKind.OWN_TRANSFER
    }

    /** Combined, de-duplicated (by id, among matching items), sorted timeline. Stable for equal dates. */
    fun items(
        expenses: List<Expense>,
        movements: List<MoneyMovement>,
        filter: ActivityFilter,
        newestFirst: Boolean = true,
        sharesOf: (String) -> List<ExpenseShare> = { emptyList() },
    ): List<ActivityItem> {
        val seen = HashSet<String>()
        val all = expenses.map { ActivityItem.ExpenseItem(it, sharesOf(it.id).isNotEmpty()) } + movements.map { ActivityItem.MovementItem(it) }
        val kept = all.filter { matches(it, filter) && seen.add(it.id) }
        return if (newestFirst) kept.sortedByDescending { it.date } else kept.sortedBy { it.date }
    }

    /** iOS ExpensesView.groupedItems: groups by local day (item order kept), groups sorted by day. */
    fun groupByDay(
        items: List<ActivityItem>,
        now: Long,
        newestFirst: Boolean = true,
        calendar: CalendarContext = CalendarContext(),
    ): List<ActivityDayGroup> {
        val today = calendar.date(now)
        val groups = LinkedHashMap<String, MutableList<ActivityItem>>()
        for (item in items) groups.getOrPut(calendar.format(item.date, "d MMM yyyy")) { mutableListOf() } += item
        val result = groups.map { (key, list) ->
            val day = calendar.date(list.first().date)
            val (header, subtitle) = when (day) {
                today -> "Today" to key
                today.minusDays(1) -> "Yesterday" to key
                else -> key to null
            }
            ActivityDayGroup(header, subtitle, calendar.startOfDay(day), list)
        }
        return if (newestFirst) result.sortedByDescending { it.date } else result.sortedBy { it.date }
    }
}
