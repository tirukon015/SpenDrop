package com.spendrop.app.ui.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.components.DayField
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.icon
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.insights.QuickDateFilter
import com.spendrop.core.insights.TransactionFilters
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.PaymentChannel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Date range + multi-select categories, payment channels and funding accounts (OR within, AND across). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterSheet(filters: TransactionFilters, fundingAccounts: List<String>, onChange: (TransactionFilters) -> Unit, onDismiss: () -> Unit) {
    val zone = ZoneId.systemDefault()
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = SD.colors.groupedBackground) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Filters", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                if (filters.hasActiveDimensionFilters) TextButton(onClick = { onChange(filters.clearDimensionFilters()) }) { Text("Clear") }
                TextButton(onClick = onDismiss) { Text("Done") }
            }
            SectionHeader("Date range")
            FlowRow(Modifier.padding(horizontal = 32.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                QuickDateFilter.entries.forEach { f ->
                    FilterChip(filters.dateFilter == f, {
                        if (f == QuickDateFilter.CUSTOM) {
                            val today = LocalDate.now(zone)
                            onChange(filters.copy(dateFilter = f,
                                customStart = filters.customStart ?: today.minusDays(6).atStartOfDay(zone).toInstant().toEpochMilli(),
                                customEnd = filters.customEnd ?: today.atStartOfDay(zone).toInstant().toEpochMilli()))
                        } else onChange(filters.copy(dateFilter = f))
                    }, { Text(f.displayName) })
                }
            }
            if (filters.dateFilter == QuickDateFilter.CUSTOM) {
                fun day(ms: Long?) = Instant.ofEpochMilli(ms ?: System.currentTimeMillis()).atZone(zone).toLocalDate()
                DayField(day(filters.customStart), { onChange(filters.copy(customStart = it.atStartOfDay(zone).toInstant().toEpochMilli())) }, "From")
                DayField(day(filters.customEnd), { onChange(filters.copy(customEnd = it.atStartOfDay(zone).toInstant().toEpochMilli())) }, "To")
            }
            if (fundingAccounts.isNotEmpty()) {
                SectionHeader("Funding accounts")
                FlowRow(Modifier.padding(horizontal = 32.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    fundingAccounts.forEach { a -> FilterChip(a in filters.fundingAccounts, { onChange(filters.toggleFundingAccount(a)) }, { Text(a) }) }
                }
            }
            SectionHeader("Categories")
            FlowRow(Modifier.padding(horizontal = 32.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ExpenseCategory.entries.forEach { c -> FilterChip(c in filters.categories, { onChange(filters.toggleCategory(c)) }, { Text(c.displayName) }, leadingIcon = { Icon(c.icon, null) }) }
            }
            if (filters.categories.isNotEmpty()) Text("A category filter shows expenses only.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 32.dp))
            SectionHeader("Payment channels")
            FlowRow(Modifier.padding(horizontal = 32.dp).padding(bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PaymentChannel.pickerOrder.forEach { c -> FilterChip(c in filters.paymentChannels, { onChange(filters.toggleChannel(c)) }, { Text(c.displayName) }, leadingIcon = { Icon(c.icon, null) }) }
            }
        }
    }
}
