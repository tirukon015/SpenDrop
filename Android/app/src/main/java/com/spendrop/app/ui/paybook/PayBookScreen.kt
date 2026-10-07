package com.spendrop.app.ui.paybook

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Contacts
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.platform.testTag
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.InitialsAvatar
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.ledger.PayBookBalanceFilter
import com.spendrop.core.ledger.PayBookGrouping
import com.spendrop.core.ledger.PersonLedger
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.Person

@Composable
fun PayBookScreen(container: AppContainer, openPerson: (String) -> Unit, addPerson: () -> Unit) {
    val snapshot by container.repository.snapshot.collectAsState()
    var search by rememberSaveable { mutableStateOf("") }
    var filterRaw by rememberSaveable { mutableStateOf(PayBookBalanceFilter.THEY_OWE_ME.name) }
    var showArchived by rememberSaveable { mutableStateOf(false) }
    val filter = PayBookBalanceFilter.valueOf(filterRaw)

    SDScreen(
        title = "PayBook",
        floatingActionButton = {
            // Solid Material button in the app's blue (the default tonal container was see-through over the list).
            ExtendedFloatingActionButton(
                onClick = addPerson,
                icon = { Icon(Icons.Filled.PersonAdd, null) },
                text = { Text("Add Person", fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold) },
                containerColor = com.spendrop.app.ui.theme.SD.colors.blue,
                contentColor = androidx.compose.ui.graphics.Color.White,
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.testTag("addPerson"),
            )
        },
    ) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val people = s.people
        val term = search.trim().lowercase()
        val filtered = remember(s, term) {
            if (term.isEmpty()) people else people.filter { p ->
                p.name.lowercase().contains(term) || s.paymentMethods.any { m ->
                    m.personId == p.id && (m.displayProvider.lowercase().contains(term) || m.accountIdentifier.contains(term) || m.label?.lowercase()?.contains(term) == true)
                }
            }
        }
        // Extra space at the end so the last person can scroll clear of the Add Person button.
        LazyColumn(contentPadding = PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 96.dp)) {
            item {
                OutlinedTextField(
                    search, { search = it }, placeholder = { Text("Search people, banks, accounts...", maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) },
                    leadingIcon = { Icon(Icons.Filled.Search, null) }, singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), shape = RoundedCornerShape(Radius.field),
                )
            }
            when {
                people.isEmpty() -> item {
                    EmptyState(Icons.Outlined.Contacts, "Your PayBook is empty", "Save people and their payment details so you can quickly reuse them later.")
                }
                filtered.isEmpty() -> item {
                    EmptyState(Icons.Filled.Search, "No matching profiles", "No person or account found matching '$search'.")
                }
                else -> {
                    if (term.isEmpty()) {
                        item { Segmented(PayBookBalanceFilter.entries, filter, { it.title }, { filterRaw = it.name }) }
                        val summary = PersonLedger.summary(s, people)
                        if (!summary.isEmpty) item { SummaryCard(summary) }
                    }
                    if (term.isEmpty() && filter != PayBookBalanceFilter.ALL) {
                        outstanding(s, people, filter, openPerson)
                    } else {
                        val groups = PayBookGrouping.groups(filtered)
                        if (groups.frequent.isNotEmpty()) peopleSection("Frequent", groups.frequent, s, openPerson)
                        if (groups.other.isNotEmpty()) peopleSection(if (groups.frequent.isEmpty()) "People" else "Other People", groups.other, s, openPerson)
                        if (groups.archived.isNotEmpty()) {
                            item {
                                TextButton(onClick = { showArchived = !showArchived }, modifier = Modifier.padding(horizontal = 8.dp)) {
                                    Text(if (showArchived) "Hide Archived (${groups.archived.size})" else "Show Archived (${groups.archived.size})")
                                }
                            }
                            if (showArchived) peopleSection(null, groups.archived, s, openPerson)
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(96.dp)) }
        }
    }
}

private fun LazyListScope.outstanding(s: FinanceSnapshot, people: List<Person>, filter: PayBookBalanceFilter, open: (String) -> Unit) {
    val rows = PersonLedger.outstanding(s, people, filter)
    val totals = rows.groupBy { it.currency }.toSortedMap().map { (c, r) -> PersonLedger.format(r.sumOf { it.amountMinor }, c) }
    item {
        SectionHeader(filter.title, trailing = { if (totals.isNotEmpty()) Text(totals.joinToString(" + "), style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel) })
    }
    item {
        SDCard {
            if (rows.isEmpty()) Text(
                if (filter == PayBookBalanceFilter.THEY_OWE_ME) "Nobody owes you money right now." else "You don't owe anyone right now.",
                color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp),
            )
            rows.forEachIndexed { i, r ->
                PersonRow(r.person, s) { open(r.person.id) }
                if (i < rows.lastIndex) RowDivider(76.dp)
            }
        }
    }
}

private fun LazyListScope.peopleSection(title: String?, list: List<Person>, s: FinanceSnapshot, open: (String) -> Unit) {
    if (title != null) item { SectionHeader(title) }
    item {
        SDCard {
            list.forEachIndexed { i, p ->
                PersonRow(p, s) { open(p.id) }
                if (i < list.lastIndex) RowDivider(76.dp)
            }
        }
    }
}

@Composable
fun PersonRow(person: Person, s: FinanceSnapshot, onClick: () -> Unit) {
    val methods = s.paymentMethods.filter { it.personId == person.id }
    val balances = remember(s, person.id) { PersonLedger.balances(s, person) }
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        InitialsAvatar(person.initials, 46.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(person.name, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (person.isArchived) Text("  Archived", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
            }
            val count = if (methods.size == 1) "1 payment method" else "${methods.size} payment methods"
            Text(
                if (methods.isEmpty()) count else "$count • ${methods.joinToString(", ") { it.displayProvider }}",
                style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        balances.toSortedMap().entries.firstOrNull()?.let { (currency, value) ->
            Column(horizontalAlignment = Alignment.End) {
                Text(if (value > 0) "owes you" else "you owe", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
                Text(
                    PersonLedger.format(kotlin.math.abs(value), currency) + if (balances.size > 1) " +" else "",
                    fontWeight = FontWeight.SemiBold, color = if (value > 0) SD.colors.green else SD.colors.orange,
                )
            }
        }
    }
}

@Composable
private fun SummaryCard(summary: PersonLedger.Summary) {
    SDCard(padding = 16.dp, modifier = Modifier.padding(top = 8.dp)) {
        Row(Modifier.fillMaxWidth()) {
            SummaryColumn("Owed to you", summary.owedToMe, summary.owingMeCount, SD.colors.green, Modifier.weight(1f))
            SummaryColumn("You owe", summary.iOwe, summary.iOweCount, SD.colors.orange, Modifier.weight(1f))
            Column(Modifier.weight(0.7f)) {
                Text("Settled", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
                Text("${summary.settledCount}", fontWeight = FontWeight.SemiBold)
                Text("people", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
            }
        }
    }
}

@Composable
private fun SummaryColumn(title: String, totals: Map<String, Long>, count: Int, color: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        Text(
            if (totals.isEmpty()) PersonLedger.format(0, "RM") else totals.toSortedMap().map { PersonLedger.format(it.value, it.key) }.joinToString("\n"),
            fontWeight = FontWeight.SemiBold, color = color,
        )
        Text("$count ${if (count == 1) "person" else "people"}", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
    }
}

