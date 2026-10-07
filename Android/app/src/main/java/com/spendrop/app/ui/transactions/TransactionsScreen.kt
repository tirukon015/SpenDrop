package com.spendrop.app.ui.transactions

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.ExpenseRow
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MovementRow
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.insights.ActivityFeed
import com.spendrop.core.insights.ActivityFilter
import com.spendrop.core.insights.ActivityItem
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.insights.ExpenseSortOrder
import com.spendrop.core.insights.TransactionFilterEngine
import com.spendrop.core.model.FinanceSnapshot
import kotlinx.coroutines.launch

class TransactionsNav(val add: () -> Unit, val openExpense: (String) -> Unit, val openMovement: (String) -> Unit)

/** Unified timeline of expenses and money movements (iOS ExpensesView), grouped by day. */
@Composable
fun TransactionsScreen(container: AppContainer, nav: TransactionsNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    val filters by container.filters.collectAsState()
    var activity by rememberSaveable { mutableStateOf(ActivityFilter.ALL) }
    var sort by rememberSaveable { mutableStateOf(ExpenseSortOrder.NEWEST_FIRST) }
    var showFilters by remember { mutableStateOf(false) }
    var sortMenu by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    SDScreen(title = "Transactions", snackbar = snackbar, actions = {
        Box {
            IconButton(onClick = { sortMenu = true }) { Icon(Icons.AutoMirrored.Filled.Sort, "Sort") }
            DropdownMenu(sortMenu, { sortMenu = false }) {
                ExpenseSortOrder.entries.forEach { o -> DropdownMenuItem({ Text((if (o == sort) "✓ " else "") + o.displayName) }, { sort = o; sortMenu = false }) }
            }
        }
        Box {
            IconButton(onClick = { showFilters = true }) { Icon(Icons.Filled.FilterList, "Filters") }
            if (filters.hasActiveDimensionFilters) Box(Modifier.padding(10.dp).size(8.dp).clip(CircleShape).background(SD.colors.blue).align(Alignment.TopEnd))
        }
        IconButton(onClick = nav.add) { Icon(Icons.Filled.Add, "Add") }
    }) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val now = System.currentTimeMillis()
        val cal = remember { CalendarContext.device() }
        val engine = remember(s, filters, now / 60_000) { TransactionFilterEngine.of(s, filters, now, cal) }
        val items = remember(engine, activity, sort) {
            ActivityFeed.items(engine.filteredExpenses, engine.filteredMovements, activity, sort == ExpenseSortOrder.NEWEST_FIRST, s::sharesOf)
        }
        val groups = remember(items) { ActivityFeed.groupByDay(items, now, sort == ExpenseSortOrder.NEWEST_FIRST, cal) }
        val summary = engine.cashFlowSummary
        val accountNames = s.accounts.associate { it.id to it.name }
        val peopleNames = s.people.associate { it.id to it.name }

        LazyColumn(contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            item {
                OutlinedTextField(filters.searchText, { t -> container.filters.value = filters.copy(searchText = t) },
                    placeholder = { Text("Search merchant, amount, category...") }, leadingIcon = { Icon(Icons.Filled.Search, null) }, singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), shape = RoundedCornerShape(Radius.field))
            }
            item {
                Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    AssistChip(onClick = { showFilters = true }, label = { Text(filters.dateFilter.displayName + " ▾") })
                    filters.activeDimensionSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.blue, modifier = Modifier.padding(start = 8.dp).weight(1f), maxLines = 1) }
                }
            }
            item {
                androidx.compose.foundation.lazy.LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(ActivityFilter.entries) { f -> FilterChip(activity == f, { activity = f }, { Text(f.title) }) }
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
                    Column(Modifier.weight(1f)) {
                        Text("SPENT", style = SD.sectionHeader, color = SD.colors.secondaryLabel)
                        Text(Fmt.money(summary.spendingMinor), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text("In ${Fmt.money(summary.moneyInMinor)}", color = SD.colors.green, style = MaterialTheme.typography.bodySmall)
                        Text("Out ${Fmt.money(summary.moneyOutMinor)}", color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            when {
                s.expenses.isEmpty() && s.movements.isEmpty() -> item {
                    EmptyState(Icons.Outlined.Inbox, "No expenses recorded", "Add your first cash expense or drop a transaction screenshot.", action = "Add Expense" to nav.add)
                }
                items.isEmpty() -> item {
                    EmptyState(Icons.Outlined.Inbox,
                        if (filters.searchTerm.isNotEmpty()) "No matching transactions" else if (activity == ActivityFilter.ALL) "Nothing recorded yet" else "No ${activity.title.lowercase()}",
                        "Transactions from ${filters.dateFilter.displayName} will appear here.",
                        action = if (filters.hasActiveFilters) "Reset Filters" to { container.filters.value = filters.clearAllFilters(keepDateFilter = false) } else "Add Expense" to nav.add)
                }
                else -> groups.forEach { g ->
                    item(key = "h-${g.date}") {
                        Text((g.dateHeader.uppercase() + (g.dateSubtitle?.let { " • $it" } ?: "")), style = SD.sectionHeader, color = SD.colors.secondaryLabel,
                            modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 6.dp))
                    }
                    items(g.items, key = { it.id }) { item ->
                        SwipeDelete(onDelete = {
                            scope.launch {
                                val t = System.currentTimeMillis()
                                when (item) {
                                    is ActivityItem.ExpenseItem -> container.repository.deleteExpense(item.expense, t)
                                    is ActivityItem.MovementItem -> container.repository.apply(Changes(movements = listOf(item.movement.copy(deletedAt = t, updatedAt = t))))
                                }
                                if (snackbar.showSnackbar("Deleted", actionLabel = "Undo") == SnackbarResult.ActionPerformed) restore(container, s, item)
                            }
                        }) {
                            Box(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(12.dp)).background(SD.colors.card)) {
                                when (item) {
                                    is ActivityItem.ExpenseItem -> ExpenseRow(item.expense, s.sharesOf(item.expense.id), item.expense.payerId?.let(peopleNames::get)) { nav.openExpense(item.expense.id) }
                                    is ActivityItem.MovementItem -> MovementRow(item.movement, { id -> id?.let(accountNames::get) }, item.movement.personId?.let(peopleNames::get), timelineStyle = true) { nav.openMovement(item.movement.id) }
                                }
                            }
                        }
                        Spacer(Modifier.height(4.dp))
                    }
                }
            }
            item { Spacer(Modifier.height(32.dp)) }
        }
        if (showFilters) FilterSheet(filters, engine.availableFundingAccounts, { container.filters.value = it }, { showFilters = false })
    }
}

/** Undo a swipe-delete: the same records come back (shares too), with a new edit time so sync/backups keep them. */
private suspend fun restore(container: AppContainer, s: FinanceSnapshot, item: ActivityItem) {
    val t = System.currentTimeMillis()
    when (item) {
        is ActivityItem.ExpenseItem -> container.repository.saveExpense(item.expense.copy(deletedAt = null, updatedAt = t), s.sharesOf(item.expense.id))
        is ActivityItem.MovementItem -> container.repository.apply(Changes(movements = listOf(item.movement.copy(deletedAt = null, updatedAt = t))))
    }
}

@Composable
fun SwipeDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { if (it == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false })
    SwipeToDismissBox(state, enableDismissFromStartToEnd = false, backgroundContent = {
        Box(Modifier.fillMaxSize().padding(horizontal = 16.dp).clip(RoundedCornerShape(12.dp)).background(SD.colors.red), contentAlignment = Alignment.CenterEnd) {
            Icon(Icons.Filled.Delete, "Delete", tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.padding(end = 20.dp))
        }
    }) { content() }
}
