package com.spendrop.app.ui.breakdown

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import com.spendrop.app.data.Preferences
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.IconBadge
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.components.icon
import com.spendrop.app.ui.components.tintName
import com.spendrop.app.ui.theme.SD
import com.spendrop.app.ui.transactions.FilterSheet
import com.spendrop.core.insights.BreakdownAnalytics
import com.spendrop.core.insights.BreakdownMode
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.insights.DailySpendingRange
import com.spendrop.core.insights.InsightRow
import com.spendrop.core.insights.MetricCard
import com.spendrop.core.insights.PeriodGrouping
import com.spendrop.core.insights.TransactionFilterEngine
import com.spendrop.core.insights.TrendCard
import kotlinx.coroutines.launch

/** Breakdown (iOS AnalyticsView): Spending and Cash Flow modes over the shared filters. */
@Composable
fun BreakdownScreen(container: AppContainer) {
    val snapshot by container.repository.snapshot.collectAsState()
    val filters by container.filters.collectAsState()
    val modeRaw by container.preferences.string(Preferences.Keys.breakdownMode, BreakdownMode.SPENDING.name).collectAsState(BreakdownMode.SPENDING.name)
    val mode = BreakdownMode.entries.firstOrNull { it.name == modeRaw } ?: BreakdownMode.SPENDING
    var granularity by rememberSaveable { mutableStateOf(PeriodGrouping.Granularity.WEEKLY) }
    var showFilters by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    SDScreen(title = "Breakdown", actions = {
        Box {
            IconButton(onClick = { showFilters = true }) { Icon(Icons.Filled.FilterList, "Filters") }
            if (filters.hasActiveDimensionFilters) Box(Modifier.padding(10.dp).size(8.dp).clip(CircleShape).background(SD.colors.blue).align(Alignment.TopEnd))
        }
    }) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val now = System.currentTimeMillis()
        val engine = remember(s, filters, now / 60_000) { TransactionFilterEngine.of(s, filters, now, CalendarContext.device()) }
        LazyColumn(contentPadding = padding) {
            item { Segmented(BreakdownMode.entries, mode, { it.displayName }, { m -> scope.launch { container.preferences.set(Preferences.Keys.breakdownMode, m.name) } }) }
            item {
                Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    AssistChip(onClick = { showFilters = true }, label = { Text(filters.dateFilter.displayName + " ▾") })
                    Text(engine.currentSubtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(start = 8.dp))
                }
                filters.activeDimensionSummary?.let { Text(it, color = SD.colors.blue, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp)) }
            }
            if (mode == BreakdownMode.SPENDING) spending(engine, granularity, { granularity = it }) { f -> container.filters.value = filters.copy(dailySpendingRange = f) }.invoke(this) { name -> container.filters.value = filters.toggleFundingAccount(name) }
            else cashFlow(engine, granularity) { granularity = it }.invoke(this)
            item { Spacer(Modifier.height(32.dp)) }
        }
        if (showFilters) FilterSheet(filters, engine.availableFundingAccounts, { container.filters.value = it }, { showFilters = false })
    }
}

private fun spending(
    engine: TransactionFilterEngine, granularity: PeriodGrouping.Granularity, onGranularity: (PeriodGrouping.Granularity) -> Unit,
    onRange: (DailySpendingRange) -> Unit,
): androidx.compose.foundation.lazy.LazyListScope.((String) -> Unit) -> Unit = { toggleFunding ->
    val b = BreakdownAnalytics.spending(engine, granularity)
    if (b.isEmpty) {
        item { EmptyState(Icons.Outlined.BarChart, com.spendrop.core.insights.SpendingBreakdown.EMPTY_TITLE, com.spendrop.core.insights.SpendingBreakdown.EMPTY_MESSAGE) }
    } else {
        item { MetricsRow(b.totalSpent, b.averagePerDay) }
        item {
            val c = b.comparison
            SectionHeader(c.header)
            SDCard(padding = 14.dp) {
                Row(Modifier.padding(bottom = 4.dp)) { Text(c.periodName, Modifier.weight(1f)); Text(c.currentValue, fontWeight = FontWeight.SemiBold) }
                Row(Modifier.padding(bottom = 8.dp)) { Text(c.comparison.previousPeriodSubtitle, Modifier.weight(1f), color = SD.colors.secondaryLabel); Text(com.spendrop.core.Money.format(c.comparison.previousTotalMinor), color = SD.colors.secondaryLabel) }
                RowDivider(0.dp)
                Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Difference", Modifier.weight(1f), color = SD.colors.secondaryLabel)
                    Text(c.comparison.differenceLabel, color = if (c.comparison.isIncreased) SD.colors.orange else SD.colors.green, fontWeight = FontWeight.SemiBold)
                }
                c.comparison.percentageLabel?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.align(Alignment.End))
                }
            }
        }
        item {
            SectionHeader(b.daily.title)
            SDCard(padding = 12.dp) {
                Segmented(DailySpendingRange.entries, b.daily.range, { it.displayName }, onRange, horizontalPadding = 0.dp)
                Text(b.daily.subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(bottom = 8.dp))
                val blue = SD.colors.blue
                BarChart(b.daily.points.map { Bar(it.dayLabel, it.amountMinor, blue, "${it.fullDateString}: ${Fmt.money(it.amountMinor)}, ${it.count} transactions") })
                b.daily.footnote?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp)) }
            }
        }
        if (b.categories.isNotEmpty()) item {
            SectionHeader("By category")
            SDCard(padding = 12.dp) {
                val palette = SD.colors
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Donut(b.categories.map { Slice(it.totalMinor, palette.named(it.category.tintName)) },
                        "Category breakdown: " + b.categories.joinToString { "${it.category.displayName} ${Fmt.money(it.totalMinor)}" })
                    Spacer(Modifier.width(12.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        b.categories.take(6).forEach { c ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(10.dp).clip(CircleShape).background(palette.named(c.category.tintName))); Spacer(Modifier.width(6.dp))
                                Text(c.category.displayName, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                b.categories.forEach { c ->
                    ListRow(c.category.displayName, subtitle = c.detailLabel, icon = c.category.icon, iconTint = palette.named(c.category.tintName), value = Fmt.money(c.totalMinor))
                }
            }
        }
        if (b.channels.isNotEmpty()) item {
            SectionHeader("By payment channel")
            SDCard {
                val palette = SD.colors
                b.channels.forEachIndexed { i, c ->
                    ListRow(c.channel.displayName, subtitle = c.detailLabel, icon = c.channel.icon, iconTint = palette.named(c.channel.tintName), value = Fmt.money(c.totalMinor))
                    if (i < b.channels.lastIndex) RowDivider(52.dp)
                }
            }
        }
        if (b.fundingAccounts.isNotEmpty()) item {
            SectionHeader("By funding account")
            SDCard {
                b.fundingAccounts.forEachIndexed { i, f ->
                    ListRow(f.name, subtitle = f.detailLabel, value = Fmt.money(f.totalMinor), onClick = { toggleFunding(f.name) })
                    if (i < b.fundingAccounts.lastIndex) RowDivider()
                }
            }
            SectionFooter("Tap an account to filter by it.")
        }
        b.sharedAndRefunds?.let { rows -> item { SectionHeader("Shared & refunds"); Rows(rows) } }
        if (b.topMerchants.isNotEmpty()) item { SectionHeader("Top merchants"); Rows(b.topMerchants) }
        item { Trend(b.trend, cashFlow = false, onGranularity) }
    }
}

private fun cashFlow(engine: TransactionFilterEngine, granularity: PeriodGrouping.Granularity, onGranularity: (PeriodGrouping.Granularity) -> Unit): androidx.compose.foundation.lazy.LazyListScope.() -> Unit = {
    val b = BreakdownAnalytics.cashFlow(engine, granularity)
    item { MetricsRow(b.moneyIn, b.moneyOut) }
    item {
        SDCard(padding = 14.dp, modifier = Modifier.padding(top = 12.dp)) {
            Text(b.netCashFlow.title, style = SD.sectionHeader, color = SD.colors.secondaryLabel)
            Text(b.netCashFlow.value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = if (b.isNetPositive) SD.colors.green else SD.colors.orange)
            Text(b.netCashFlow.subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
    }
    if (b.byType.isNotEmpty()) item { SectionHeader("By type"); Rows(b.byType) }
    item { Trend(b.trend, cashFlow = true, onGranularity) }
}

@Composable
private fun MetricsRow(a: MetricCard, b: MetricCard) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(a, b).forEach { m ->
            Column(Modifier.weight(1f).clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp)).background(SD.colors.card).padding(14.dp)) {
                Text(m.title, style = SD.sectionHeader, color = SD.colors.secondaryLabel)
                Text(m.value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
                Text(m.subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
            }
        }
    }
}

@Composable
private fun Rows(rows: List<InsightRow>) {
    SDCard {
        rows.forEachIndexed { i, r ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                Text(r.title, Modifier.weight(1f), fontWeight = if (r.bold) FontWeight.Bold else FontWeight.Normal)
                Text(r.value, fontWeight = if (r.bold) FontWeight.Bold else FontWeight.SemiBold)
            }
            if (i < rows.lastIndex) RowDivider()
        }
    }
}

@Composable
private fun Trend(t: TrendCard, cashFlow: Boolean, onGranularity: (PeriodGrouping.Granularity) -> Unit) {
    SectionHeader(t.title)
    SDCard(padding = 12.dp) {
        Segmented(PeriodGrouping.Granularity.entries, t.granularity, { it.displayName }, onGranularity, horizontalPadding = 0.dp)
        // Same as iOS: spending in blue; cash flow as Money In (green) beside Money Out (gray).
        val green = SD.colors.green; val gray = SD.colors.secondaryLabel; val blue = SD.colors.blue
        BarChart(t.buckets.map { bk ->
            if (cashFlow) Bar(bk.label, listOf(bk.inMinor, bk.outMinor), listOf(green, gray), "${bk.label}: in ${Fmt.money(bk.inMinor)}, out ${Fmt.money(bk.outMinor)}, net ${Fmt.money(bk.netMinor)}")
            else Bar(bk.label, bk.spendingMinor, blue, "${bk.label}: ${Fmt.money(bk.spendingMinor)}")
        }, slotWidth = 44.dp, legend = if (cashFlow) listOf("Money In" to green, "Money Out" to gray) else emptyList())
        Text(t.footnote, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp))
    }
}
