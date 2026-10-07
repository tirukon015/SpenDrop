package com.spendrop.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.spendrop.app.AppContainer
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.ExpenseRow
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.importing.ImportMenu
import com.spendrop.app.ui.importing.ImportPickers
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.insights.HomeAnalytics
import com.spendrop.core.insights.SpendingSummaryCard
import com.spendrop.core.model.FinanceSnapshot

class HomeNav(val add: () -> Unit, val quickCash: () -> Unit, val openExpense: (String) -> Unit)

/** Home (iOS DashboardView): Today / This Week / This Month spending, shared, cash flow, balances, today's and recent expenses. */
@Composable
fun HomeScreen(container: AppContainer, pickers: ImportPickers, nav: HomeNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    var importMenu by remember { mutableStateOf(false) }
    SDScreen(
        title = "Home",
        actions = {
            Box {
                IconButton(onClick = { importMenu = true }) { Icon(Icons.Filled.DocumentScanner, "Scan screenshot, receipt or PDF") }
                ImportMenu(importMenu, { importMenu = false }, pickers)
            }
            IconButton(onClick = nav.quickCash) { Icon(Icons.Filled.Payments, "Quick Cash") }
            IconButton(onClick = nav.add) { Icon(Icons.Filled.Add, "Add") }
        },
    ) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val now = System.currentTimeMillis()
        val home = remember(s, now / 60_000) { HomeAnalytics.home(s, now, CalendarContext.device()) }
        LazyColumn(contentPadding = padding) {
            item { Text(home.monthYear, color = SD.colors.secondaryLabel, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp)) }
            item {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SummaryCard(home.today, Icons.Filled.WbSunny, SD.colors.orange, hero = true)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SummaryCard(home.thisWeek, Icons.Filled.CalendarMonth, SD.colors.blue, modifier = Modifier.weight(1f))
                        SummaryCard(home.thisMonth, Icons.Filled.BarChart, SD.colors.green, modifier = Modifier.weight(1f))
                    }
                }
            }
            home.sharedThisMonthLabel?.let { label ->
                item {
                    SDCard(padding = 14.dp) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Group, null, tint = SD.colors.blue); Spacer(Modifier.width(10.dp))
                            Text(label, Modifier.weight(1f))
                            Text(Fmt.money(home.sharedThisMonthMyShareMinor), fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
            home.cashFlowThisMonth?.let { flow ->
                item {
                    HomeCard("CASH FLOW · THIS MONTH", Icons.Filled.SwapHoriz, SD.colors.teal) {
                        Metric("Money In", Fmt.money(flow.moneyInMinor), SD.colors.green, Modifier.weight(1f))
                        Metric("Money Out", Fmt.money(flow.moneyOutMinor), SD.colors.label, Modifier.weight(1f))
                        Metric("Net", (if (flow.netCashFlowMinor >= 0) "+" else "") + Fmt.money(flow.netCashFlowMinor),
                            if (flow.netCashFlowMinor >= 0) SD.colors.green else SD.colors.orange, Modifier.weight(1f))
                    }
                }
            }
            if (home.owedToMeMinor != 0L || home.iOweMinor != 0L) {
                item {
                    HomeCard("BALANCES", Icons.Filled.Group, SD.colors.purple) {
                        if (home.owedToMeMinor != 0L) Metric("Owed to you", Fmt.money(home.owedToMeMinor), SD.colors.green, Modifier.weight(1f))
                        if (home.iOweMinor != 0L) Metric("You owe", Fmt.money(home.iOweMinor), SD.colors.orange, Modifier.weight(1f))
                        if (home.owedToMeMinor == 0L || home.iOweMinor == 0L) Spacer(Modifier.weight(1f))
                    }
                }
            }
            item {
                SectionHeader("Today's expenses", trailing = {
                    if (home.todayExpenses.isNotEmpty()) Text(home.todayCountLabel, style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel)
                })
            }
            item {
                SDCard {
                    if (home.todayExpenses.isEmpty()) {
                        EmptyState(Icons.Outlined.AccountBalanceWallet, "No expenses recorded today", "Add a cash expense or drop a payment screenshot.")
                        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
                            FilledTonalButton(onClick = nav.quickCash) { Icon(Icons.Filled.Payments, null); Spacer(Modifier.width(6.dp)); Text("Quick Cash") }
                            FilledTonalButton(onClick = pickers.photos) { Icon(Icons.Filled.DocumentScanner, null); Spacer(Modifier.width(6.dp)); Text("Drop Screenshot") }
                        }
                    }
                    ExpenseList(s, home.todayExpenses, nav.openExpense)
                }
            }
            if (home.recentNonToday.isNotEmpty()) {
                item { SectionHeader("Recent activity") }
                item { SDCard { ExpenseList(s, home.recentNonToday, nav.openExpense) } }
            }
            item { Spacer(Modifier.height(32.dp)) }
        }
    }
}

@Composable
private fun ExpenseList(s: FinanceSnapshot, list: List<com.spendrop.core.model.Expense>, open: (String) -> Unit) {
    val names = s.people.associate { it.id to it.name }
    list.forEachIndexed { i, e ->
        ExpenseRow(e, s.sharesOf(e.id), e.payerId?.let(names::get)) { open(e.id) }
        if (i < list.lastIndex) RowDivider(70.dp)
    }
}

@Composable
private fun SummaryCard(card: SpendingSummaryCard, icon: ImageVector, tint: Color, hero: Boolean = false, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(SD.colors.card).padding(16.dp).semantics(mergeDescendants = true) {},
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(card.title, color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(tint.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(card.value, fontSize = if (hero) 32.sp else 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
private fun HomeCard(title: String, icon: ImageVector, tint: Color, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    SDCard(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = SD.sectionHeader, color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
            Icon(icon, null, tint = tint)
        }
        Spacer(Modifier.height(8.dp))
        Row(content = content)
    }
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun Metric(title: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        Text(value, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1)
    }
}
