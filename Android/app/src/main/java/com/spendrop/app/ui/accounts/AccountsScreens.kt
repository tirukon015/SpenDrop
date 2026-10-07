package com.spendrop.app.ui.accounts

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MovementRow
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.icon
import com.spendrop.app.ui.paybook.Dropdown
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Ids
import com.spendrop.core.accounts.AccountFormValidation
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovementKind
import kotlinx.coroutines.launch

class AccountsNav(val back: () -> Unit, val detail: (String) -> Unit, val unlinked: () -> Unit, val openExpense: (String) -> Unit, val openMovement: (String) -> Unit)

/** More → Accounts (iOS AccountsView): RECORDED activity per funding account. Not a bank balance. */
@Composable
fun AccountsScreen(container: AppContainer, nav: AccountsNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    var editing by remember { mutableStateOf<Account?>(null) }
    var adding by remember { mutableStateOf(false) }
    SDScreen(title = "Accounts", onBack = nav.back, actions = { IconButton(onClick = { adding = true }) { Icon(Icons.Filled.Add, "Add account") } }) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val active = s.accounts.filter { !it.isArchived }
        val archived = s.accounts.filter { it.isArchived }
        val unlinked = s.movements.filter { it.accountId == null && it.counterAccountId == null }
        LazyColumn(contentPadding = padding) {
            item {
                SectionHeader("My accounts")
                SDCard {
                    if (active.isEmpty()) Text("No accounts yet. Accounts are created automatically from your expenses, or add one with +.", color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp))
                    active.forEachIndexed { i, a -> AccountSummary(s, a) { nav.detail(a.id) }; if (i < active.lastIndex) RowDivider() }
                }
                SectionFooter("Totals are what you have recorded in SpenDrop. They are not your real bank balance.")
            }
            if (unlinked.isNotEmpty()) item {
                SDCard { ListRow("${unlinked.size} not linked to an account", icon = Icons.Filled.Inbox, chevron = true, onClick = nav.unlinked) }
            }
            if (archived.isNotEmpty()) item {
                SectionHeader("Archived")
                SDCard { archived.forEachIndexed { i, a -> AccountSummary(s, a, dim = true) { nav.detail(a.id) }; if (i < archived.lastIndex) RowDivider() } }
            }
            item { Spacer(Modifier.height(32.dp)) }
        }
        if (adding || editing != null) AccountForm(container, s, editing) { adding = false; editing = null }
    }
}

@Composable
private fun AccountSummary(s: FinanceSnapshot, a: Account, dim: Boolean = false, onClick: () -> Unit) {
    val act = FinancialCalculator.accountActivity(a.id, a.currency, s.expenses, s.movements)
    Column(Modifier.fillMaxWidth().let { if (dim) it else it }) {
        ListRow(a.name, icon = a.type.icon, value = a.type.displayName, chevron = true, onClick = onClick, titleColor = if (dim) SD.colors.secondaryLabel else null)
        Row(Modifier.padding(start = 52.dp, end = 16.dp, bottom = 10.dp)) {
            Labeled("Recorded In", Fmt.money(act.inMinor, a.currency), SD.colors.green, Modifier.weight(1f))
            Labeled("Recorded Out", Fmt.money(act.outMinor, a.currency), SD.colors.label, Modifier.weight(1f))
            Labeled("Recorded Net", Fmt.money(act.netMinor, a.currency), if (act.netMinor < 0) SD.colors.orange else SD.colors.label, Modifier.weight(1f))
        }
    }
}

@Composable
private fun Labeled(t: String, v: String, c: androidx.compose.ui.graphics.Color, m: Modifier) {
    Column(m) {
        Text(t, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        Text(v, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = c, maxLines = 1)
    }
}

/** One account's recorded expenses and money movements, newest first. */
@Composable
fun AccountDetailScreen(container: AppContainer, accountId: String, nav: AccountsNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    var editing by remember { mutableStateOf(false) }
    val s = snapshot
    val a = s?.accounts?.firstOrNull { it.id == accountId }
    SDScreen(title = a?.name ?: "Account", onBack = nav.back, actions = { TextButton(onClick = { editing = true }) { Text("Edit") } }) { padding ->
        if (s == null || a == null) return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val act = FinancialCalculator.accountActivity(a.id, a.currency, s.expenses, s.movements)
        val accountNames = s.accounts.associate { it.id to it.name }
        val people = s.people.associate { it.id to it.name }
        data class Item(val date: Long, val expense: com.spendrop.core.model.Expense?, val movement: com.spendrop.core.model.MoneyMovement?, val incoming: Boolean)
        val items = (s.expenses.filter { it.accountId == a.id }.map { Item(it.date, it, null, false) } +
            s.movements.filter { it.accountId == a.id }.map { Item(it.date, null, it, it.kind.direction == MoneyDirection.IN) } +
            s.movements.filter { it.counterAccountId == a.id && it.kind == MoneyMovementKind.OWN_TRANSFER }.map { Item(it.date, null, it, true) })
            .sortedByDescending { it.date }
        LazyColumn(contentPadding = padding) {
            item {
                SDCard {
                    ListRow("Recorded In", value = Fmt.money(act.inMinor, a.currency)); RowDivider()
                    ListRow("Recorded Out", value = Fmt.money(act.outMinor, a.currency)); RowDivider()
                    ListRow("Recorded Net", value = Fmt.money(act.netMinor, a.currency))
                }
                SectionFooter("Based only on what is recorded in SpenDrop. This is not your real ${a.name} balance.")
            }
            item {
                SectionHeader("Recorded transactions")
                SDCard {
                    if (items.isEmpty()) Text("Nothing recorded for this account yet.", color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp))
                    items.forEachIndexed { i, it ->
                        val e = it.expense
                        if (e != null) ListRow(e.merchant, subtitle = "Expense · ${Fmt.date(e.date)}",
                            value = if (e.paidByMe) "-${Fmt.money(e.amountMinor, e.currency)}" else "Paid by ${e.payerNameSnapshot ?: "someone"}", onClick = { nav.openExpense(e.id) })
                        else it.movement?.let { m -> MovementRow(m, { id -> id?.let(accountNames::get) }, m.personId?.let(people::get), incoming = it.incoming) { nav.openMovement(m.id) } }
                        if (i < items.lastIndex) RowDivider()
                    }
                }
                Spacer(Modifier.height(32.dp))
            }
        }
        if (editing) AccountForm(container, s, a) { editing = false }
    }
}

@Composable
fun UnlinkedMovementsScreen(container: AppContainer, nav: AccountsNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    SDScreen(title = "Not Linked", onBack = nav.back) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val list = s.movements.filter { it.accountId == null && it.counterAccountId == null }
        val people = s.people.associate { it.id to it.name }
        LazyColumn(contentPadding = padding) {
            item {
                SDCard {
                    if (list.isEmpty()) EmptyState(Icons.Filled.Inbox, "All linked", "Every money record has an account.")
                    list.forEachIndexed { i, m ->
                        MovementRow(m, { null }, m.personId?.let(people::get)) { nav.openMovement(m.id) }
                        if (i < list.lastIndex) RowDivider()
                    }
                }
                SectionFooter("Money In and Money Out records saved without an account. Tap one to edit it or add an account.")
            }
        }
    }
}

/** Add / edit / archive a funding account (iOS AccountFormSheet). */
@Composable
fun AccountForm(container: AppContainer, s: FinanceSnapshot, account: Account?, onDone: () -> Unit) {
    var name by remember { mutableStateOf(account?.name ?: "") }
    var type by remember { mutableStateOf(account?.type ?: AccountType.BANK) }
    val scope = rememberCoroutineScope()
    val problem = AccountFormValidation.problem(name, account?.id, s.accounts)
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text(if (account == null) "New Account" else "Edit Account") },
        text = {
            Column {
                OutlinedTextField(name, { name = it }, label = { Text("Name (e.g. Maybank)") }, singleLine = true)
                Dropdown("Type", AccountType.entries, type, { it.displayName }) { type = it }
                if (problem != null && name.isNotEmpty()) Text(problem, color = SD.colors.orange, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp))
                if (account != null) {
                    TextButton(onClick = {
                        scope.launch { container.repository.apply(Changes(accounts = listOf(account.copy(isArchived = !account.isArchived, updatedAt = System.currentTimeMillis())))); onDone() }
                    }) { Text(if (account.isArchived) "Unarchive Account" else "Archive Account") }
                    Text("Archived accounts are hidden from pickers. Their recorded transactions are kept.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                }
            }
        },
        confirmButton = {
            TextButton(enabled = problem == null, onClick = {
                scope.launch {
                    val now = System.currentTimeMillis()
                    val a = account?.copy(name = name.trim(), typeRaw = type.raw, updatedAt = now)
                        ?: Account(Ids.new(), name.trim(), type.raw, sortIndex = (s.accounts.maxOfOrNull { it.sortIndex } ?: -1) + 1, createdAt = now, updatedAt = now)
                    container.repository.apply(Changes(accounts = listOf(a)))
                    onDone()
                }
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDone) { Text("Cancel") } },
    )
}
