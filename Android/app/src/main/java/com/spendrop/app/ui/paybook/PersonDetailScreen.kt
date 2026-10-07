package com.spendrop.app.ui.paybook

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.data.applySettlement
import com.spendrop.app.data.deletePerson
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.InitialsAvatar
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Money
import com.spendrop.core.ledger.Debt
import com.spendrop.core.ledger.DebtLedger
import com.spendrop.core.ledger.PersonLedger
import com.spendrop.core.ledger.SettlementService
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SettlementKind
import kotlinx.coroutines.launch
import kotlin.math.abs

/** Navigation callbacks out of the person screen. */
class PersonNav(
    val back: () -> Unit,
    val edit: (String) -> Unit,
    val editMethod: (personId: String, methodId: String?) -> Unit,
    val openExpense: (String) -> Unit,
    val openMovement: (String) -> Unit,
    val newMovement: (kind: MoneyMovementKind, personId: String, currency: String?, amountMinor: Long?) -> Unit,
)

@Composable
fun PersonDetailScreen(container: AppContainer, personId: String, nav: PersonNav) {
    val snapshot by container.repository.snapshot.collectAsState()
    val scope = rememberCoroutineScope()
    val repo = container.repository
    var payment by remember { mutableStateOf<PaymentRequest?>(null) }
    var debtToSettle by remember { mutableStateOf<Debt?>(null) }
    var settleAllCurrency by remember { mutableStateOf<String?>(null) }
    var selected by rememberSaveable { mutableStateOf(setOf<String>()) }
    var confirmSelected by remember { mutableStateOf(false) }
    var undoGroup by remember { mutableStateOf<DebtLedger.SettlementGroup?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var deleteAsk by remember { mutableStateOf(false) }
    var blockedDelete by remember { mutableStateOf(false) }
    var methodToDelete by remember { mutableStateOf<PersonPaymentMethod?>(null) }
    var showSettled by rememberSaveable { mutableStateOf(false) }

    val s = snapshot
    val person = s?.people?.firstOrNull { it.id == personId }
    SDScreen(title = person?.name ?: "Person", onBack = nav.back, actions = {
        if (person != null) TextButton(onClick = { nav.edit(person.id) }) { Text("Edit") }
    }) { padding ->
        if (s == null) return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        if (person == null) return@SDScreen EmptyState(Icons.Filled.Delete, "Person not found", "This person was deleted.", Modifier.padding(padding))
        val now = System.currentTimeMillis()
        fun run(block: () -> com.spendrop.core.ledger.SettlementChange) {
            try {
                val change = block()
                scope.launch { repo.applySettlement(change, s) }
            } catch (e: Exception) {
                error = e.message ?: "Couldn't record the payment."
            }
        }
        val balances = remember(s, personId) { PersonLedger.balances(s, person) }
        val debts = remember(s, personId) { DebtLedger.debts(s, person) }
        val methods = s.paymentMethods.filter { it.personId == person.id }

        LazyColumn(contentPadding = padding) {
            item { Header(person) }
            item { MoneyActions(person, debts, onPayment = { payment = it }, onLoan = { kind -> nav.newMovement(kind, person.id, null, null) }) }
            if (balances.isNotEmpty() || PersonLedger.hasHistory(s, person)) {
                item { SectionHeader("Net balance") }
                item {
                    SDCard(padding = 14.dp) {
                        if (balances.isEmpty()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.CheckCircle, null, tint = SD.colors.green); Spacer(Modifier.width(8.dp))
                                Text("Settled — nothing owed either way")
                            }
                        }
                        balances.toSortedMap().forEach { (currency, value) ->
                            BalanceBlock(s, person, currency, value, debts, onPayment = { payment = it }, onSettleAll = { settleAllCurrency = currency }, onRepayment = {
                                val d = PersonLedger.repaymentDraft(s, person, currency, now)
                                if (d != null) nav.newMovement(d.kind, person.id, currency, d.amountMinor)
                            })
                        }
                    }
                }
                val open = debts.filter { !it.isSettled }.sortedByDescending { it.date }
                if (open.isNotEmpty()) {
                    item { SectionHeader("Outstanding transactions") }
                    item {
                        SDCard {
                            open.forEachIndexed { i, d ->
                                DebtRow(d, selected = d.id in selected,
                                    onToggle = { selected = if (d.id in selected) selected - d.id else selected + d.id },
                                    onOpen = { d.expenseId?.let(nav.openExpense) ?: d.loanId?.let(nav.openMovement) },
                                    onSettle = { debtToSettle = d })
                                if (i < open.lastIndex) RowDivider(52.dp)
                            }
                            val sel = open.filter { it.id in selected }
                            if (sel.isNotEmpty()) {
                                RowDivider(0.dp)
                                val total = sel.sumOf { it.outstandingMinor }
                                val oneWay = sel.map { it.direction }.toSet().size <= 1 && sel.map { it.currency }.toSet().size <= 1
                                Column(Modifier.padding(16.dp)) {
                                    Text("Selected: ${sel.size} · ${PersonLedger.format(total, sel.first().currency)}", fontWeight = FontWeight.SemiBold)
                                    if (oneWay) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                                        FilledTonalButton(onClick = { confirmSelected = true }) { Text("Settle Selected") }
                                        OutlinedButton(onClick = { payment = PaymentRequest(sel.first().direction, sel.first().currency, sel) }) { Text("Different Amount…") }
                                    } else Text("Choose transactions in one direction (all owed to you, or all owed by you).", color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall)
                                }
                                if (confirmSelected) ConfirmDialog(
                                    "Settle selected?",
                                    "Records one payment of ${PersonLedger.format(total, sel.first().currency)} for the ${sel.size} selected transactions. Others stay outstanding.",
                                    "Settle ${PersonLedger.format(total, sel.first().currency)}",
                                    onConfirm = {
                                        run { SettlementService.recordPayment(person, sel.first().direction, total, sel.map { it to it.outstandingMinor }, sel.first().currency, now, note = "Settled ${sel.size} transactions") }
                                        selected = emptySet()
                                    },
                                    onDismiss = { confirmSelected = false },
                                )
                            }
                        }
                    }
                }
                val settled = debts.filter { it.isSettled }.sortedByDescending { it.date }
                if (settled.isNotEmpty()) {
                    item {
                        TextButton(onClick = { showSettled = !showSettled }, modifier = Modifier.padding(horizontal = 8.dp)) {
                            Text((if (showSettled) "Hide" else "Show") + " settled transactions (${settled.size})")
                        }
                    }
                    if (showSettled) item {
                        SDCard {
                            settled.forEachIndexed { i, d ->
                                ListRow(d.title, subtitle = Fmt.date(d.date), value = "Settled ${PersonLedger.format(d.originalMinor, d.currency)}", valueColor = SD.colors.green,
                                    onClick = { d.expenseId?.let(nav.openExpense) ?: d.loanId?.let(nav.openMovement) })
                                if (i < settled.lastIndex) RowDivider()
                            }
                        }
                    }
                }
                val groups = DebtLedger.settlementGroups(s, personId = person.id)
                if (groups.isNotEmpty()) {
                    item { SectionHeader("Settlement history") }
                    item {
                        SDCard {
                            groups.forEachIndexed { i, g ->
                                ListRow(settlementTitle(s, g), subtitle = Fmt.dateTime(g.date), trailing = { TextButton(onClick = { undoGroup = g }) { Text("Undo") } })
                                if (i < groups.lastIndex) RowDivider()
                            }
                        }
                    }
                }
                val entries = PersonLedger.entries(s, person)
                if (entries.isNotEmpty()) {
                    item { SectionHeader("History") }
                    item {
                        SDCard {
                            entries.forEachIndexed { i, e ->
                                ListRow(
                                    e.title, subtitle = "${Fmt.date(e.date)} · ${e.detail}",
                                    value = if (e.effectMinor != 0L) (if (e.effectMinor > 0) "+" else "−") + PersonLedger.format(abs(e.effectMinor), e.currency) else null,
                                    valueColor = if (e.effectMinor > 0) SD.colors.green else SD.colors.orange,
                                    onClick = {
                                        when (val src = e.source) {
                                            is PersonLedger.Entry.Source.OfExpense -> nav.openExpense(src.expense.id)
                                            is PersonLedger.Entry.Source.OfMovement -> nav.openMovement(src.movement.id)
                                        }
                                    },
                                )
                                if (i < entries.lastIndex) RowDivider()
                            }
                        }
                    }
                    item { SectionFooter("+ means ${person.name} owes you more; − means you owe ${person.name} more (or they owe you less).") }
                }
            }
            item {
                SectionHeader("Payment accounts", trailing = {
                    TextButton(onClick = { nav.editMethod(person.id, null) }) { Icon(Icons.Filled.AddCircle, null); Spacer(Modifier.width(4.dp)); Text("Add Method") }
                })
            }
            item { PaymentMethods(person, methods, onEdit = { nav.editMethod(person.id, it.id) }, onDelete = { methodToDelete = it }, onAdd = { nav.editMethod(person.id, null) }) }
            item {
                SectionHeader("Profile")
                SDCard {
                    ListRow("Frequent", icon = Icons.Filled.Star, iconTint = SD.colors.yellow, trailing = {
                        Switch(person.isFrequent, { v -> scope.launch { repo.apply(Changes(people = listOf(person.copy(isFrequent = v, updatedAt = System.currentTimeMillis())))) } })
                    })
                    RowDivider(52.dp)
                    ListRow("Archived", icon = Icons.Filled.Archive, iconTint = SD.colors.gray, trailing = {
                        Switch(person.isArchived, { v -> scope.launch { repo.apply(Changes(people = listOf(person.copy(isArchived = v, updatedAt = System.currentTimeMillis())))) } })
                    })
                }
                Spacer(Modifier.height(16.dp))
                SDCard {
                    ListRow("Delete Person Profile", icon = Icons.Filled.Delete, iconTint = SD.colors.red, titleColor = SD.colors.red, onClick = {
                        if (PersonLedger.canDelete(s, person)) deleteAsk = true else blockedDelete = true
                    })
                }
                Spacer(Modifier.height(32.dp))
            }
        }

        payment?.let { req ->
            RecordPaymentSheet(person, req, onDismiss = { payment = null }) { amount, plan, date ->
                try {
                    val change = if (req.creditMinor != null) SettlementService.applyCredit(s, person, req.direction, plan, req.currency, System.currentTimeMillis())
                    else SettlementService.recordPayment(person, req.direction, amount, plan, req.currency, System.currentTimeMillis(), date)
                    scope.launch { repo.applySettlement(change, s) }
                    null
                } catch (e: Exception) { e.message ?: "Couldn't record the payment." }
            }
        }
        debtToSettle?.let { d ->
            ConfirmDialog("Mark as paid?", "Only ${d.title} is settled. Other transactions stay outstanding.",
                "Mark ${PersonLedger.format(d.outstandingMinor, d.currency)} as Paid",
                onConfirm = { run { SettlementService.markPaid(d, person, System.currentTimeMillis()) } }, onDismiss = { debtToSettle = null })
        }
        settleAllCurrency?.let { c ->
            val v = balances[c] ?: 0
            ConfirmDialog("Settle everything with ${person.name}?",
                "Debts in both directions are cancelled against each other and one payment of ${PersonLedger.format(abs(v), c)} is recorded (${if (v > 0) "${person.name} paid you" else "you paid ${person.name}"}). Every transaction is kept; you can undo this.",
                "Settle All", onConfirm = { run { SettlementService.settleAll(s, person, c, System.currentTimeMillis()) } }, onDismiss = { settleAllCurrency = null })
        }
        undoGroup?.let { g ->
            ConfirmDialog("Undo this settlement?", "The amount becomes outstanding again. The original transaction is not changed.", "Undo Settlement",
                destructive = true, onConfirm = { run { SettlementService.undo(s, g.id) } }, onDismiss = { undoGroup = null })
        }
        if (deleteAsk) ConfirmDialog("Delete ${person.name}?", "This removes the profile and its saved payment methods. Past shared expenses and money records are kept under their saved name.",
            "Delete", destructive = true, onConfirm = { scope.launch { repo.deletePerson(person, s); nav.back() } }, onDismiss = { deleteAsk = false })
        if (blockedDelete) ConfirmDialog("${person.name} still has a balance", "Settle up first, or archive ${person.name} to hide them while keeping the balance and history.",
            "Archive Instead", onConfirm = { scope.launch { repo.apply(Changes(people = listOf(person.copy(isArchived = true, updatedAt = System.currentTimeMillis())))) } },
            onDismiss = { blockedDelete = false })
        methodToDelete?.let { m ->
            ConfirmDialog("Delete this payment method?", "Delete ${m.displayProvider} (${m.accountIdentifier})?", "Delete", destructive = true,
                onConfirm = { scope.launch { val t = System.currentTimeMillis(); repo.apply(Changes(paymentMethods = listOf(m.copy(deletedAt = t, updatedAt = t)))) } },
                onDismiss = { methodToDelete = null })
        }
        error?.let { MessageDialog("Couldn't Record Payment", it) { error = null } }
    }
}

private fun settlementTitle(s: FinanceSnapshot, g: DebtLedger.SettlementGroup): String {
    fun f(m: Long) = Money.format(m, g.currency)
    if (g.totalMinor == 0L && g.offsetMinor > 0) return "Offset ${f(g.offsetMinor)} (no money moved)"
    val p = g.payment ?: return "Applied ${f(g.totalMinor)} of earlier payments (credit)"
    val verb = if (g.direction > 0) "Received" else "Paid"
    val applied = DebtLedger.allocations(s).filter { it.paymentId == p.id && it.kind != SettlementKind.OFFSET }.sumOf { it.amountMinor }
    val credit = p.amountMinor - applied
    return if (credit > 0) "$verb ${f(p.amountMinor)} · applied ${f(applied)} · ${f(credit)} credit" else "$verb ${f(p.amountMinor)}"
}

@Composable
private fun Header(person: Person) {
    val clipboard = LocalClipboardManager.current
    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        InitialsAvatar(person.initials, 84.dp)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(person.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            IconButton(onClick = { clipboard.setText(AnnotatedString(person.name)) }) { Icon(Icons.Filled.ContentCopy, "Copy name", Modifier.size(18.dp)) }
        }
        person.notes?.let { Text(it, color = SD.colors.secondaryLabel, textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
    }
}

@Composable
private fun MoneyActions(person: Person, debts: List<Debt>, onPayment: (PaymentRequest) -> Unit, onLoan: (MoneyMovementKind) -> Unit) {
    val open = debts.filter { !it.isSettled }
    val currency = open.firstOrNull()?.currency ?: "RM"
    var receive by remember { mutableStateOf(false) }
    var give by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            FilledTonalButton(onClick = { receive = true }, modifier = Modifier.fillMaxWidth().height(48.dp), contentPadding = PaddingValues(horizontal = 10.dp)) {
                Icon(Icons.AutoMirrored.Filled.CallReceived, null, Modifier.size(20.dp)); Spacer(Modifier.width(6.dp)); Text("Receive Money", maxLines = 1, softWrap = false)
            }
            DropdownMenu(receive, { receive = false }) {
                DropdownMenuItem({ Text("Payment from ${person.name}") }, { receive = false; onPayment(PaymentRequest(1, currency, open)) })
                DropdownMenuItem({ Text("I borrowed from ${person.name}") }, { receive = false; onLoan(MoneyMovementKind.LOAN_RECEIVED) })
            }
        }
        Column(Modifier.weight(1f)) {
            FilledTonalButton(onClick = { give = true }, modifier = Modifier.fillMaxWidth().height(48.dp), contentPadding = PaddingValues(horizontal = 10.dp)) {
                Icon(Icons.AutoMirrored.Filled.CallMade, null, Modifier.size(20.dp)); Spacer(Modifier.width(6.dp)); Text("Give Money", maxLines = 1, softWrap = false)
            }
            DropdownMenu(give, { give = false }) {
                DropdownMenuItem({ Text("Pay back what I owe") }, { give = false; onPayment(PaymentRequest(-1, currency, open)) })
                DropdownMenuItem({ Text("Lend to ${person.name} (they'll owe you)") }, { give = false; onLoan(MoneyMovementKind.LOAN_GIVEN) })
            }
        }
    }
}

@Composable
private fun BalanceBlock(
    s: FinanceSnapshot, person: Person, currency: String, value: Long, debts: List<Debt>,
    onPayment: (PaymentRequest) -> Unit, onSettleAll: () -> Unit, onRepayment: () -> Unit,
) {
    val open = debts.filter { it.currency == currency && !it.isSettled }
    val theyOwe = open.filter { it.direction > 0 }.sumOf { it.outstandingMinor }
    val iOwe = open.filter { it.direction < 0 }.sumOf { it.outstandingMinor }
    val unassigned = DebtLedger.unassignedMinor(s, person, currency)
    val creditFromThem = DebtLedger.creditMinor(s, person, currency, 1)
    val creditFromMe = DebtLedger.creditMinor(s, person, currency, -1)
    Column(Modifier.padding(bottom = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (value > 0) Icons.AutoMirrored.Filled.CallReceived else Icons.AutoMirrored.Filled.CallMade, null, tint = if (value > 0) SD.colors.green else SD.colors.orange, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(10.dp))
            Column {
                Text(PersonLedger.directionText(person.name, value, currency), fontWeight = FontWeight.SemiBold)
                Text("Net ${if (value > 0) "+" else "−"}${PersonLedger.format(abs(value), currency)}", color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall)
            }
        }
        if (theyOwe > 0 && iOwe > 0) Text(
            "${person.name} owes you ${PersonLedger.format(theyOwe, currency)} and you owe ${person.name} ${PersonLedger.format(iOwe, currency)}; the difference is shown above. Both transactions are kept.",
            style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp),
        )
        if (creditFromThem > 0) CreditRow("${PersonLedger.format(creditFromThem, currency)} credit available from ${person.name}", theyOwe > 0) {
            onPayment(PaymentRequest(1, currency, open, creditFromThem))
        }
        if (creditFromMe > 0) CreditRow("${PersonLedger.format(creditFromMe, currency)} you paid ${person.name} not yet applied", iOwe > 0) {
            onPayment(PaymentRequest(-1, currency, open, creditFromMe))
        }
        if (unassigned != 0L && creditFromThem == 0L && creditFromMe == 0L) Text(
            "Includes ${PersonLedger.format(abs(unassigned), currency)} not linked to a transaction.",
            style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
            if (theyOwe > 0) FilledTonalButton(onClick = { onPayment(PaymentRequest(1, currency, open)) }) { Text("Receive Payment") }
            if (iOwe > 0) FilledTonalButton(onClick = { onPayment(PaymentRequest(-1, currency, open)) }) { Text("Pay ${person.name}") }
            if (theyOwe == 0L && iOwe == 0L) OutlinedButton(onClick = onRepayment) { Text(if (value > 0) "Record Repayment Received" else "Record Repayment Made") }
            else OutlinedButton(onClick = onSettleAll) { Text("Settle All") }
        }
    }
}

@Composable
private fun CreditRow(text: String, canApply: Boolean, apply: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        if (canApply) TextButton(onClick = apply) { Text("Apply Credit") }
    }
}

@Composable
private fun DebtRow(d: Debt, selected: Boolean, onToggle: () -> Unit, onOpen: () -> Unit, onSettle: () -> Unit) {
    // Title gets the full width; amount and "Settle" sit in their own column on the right.
    Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 12.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.Top) {
        IconButton(onClick = onToggle, modifier = Modifier.semantics { contentDescription = "Select transaction ${d.title}" }) {
            Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (selected) SD.colors.blue else SD.colors.tertiaryLabel)
        }
        Column(Modifier.weight(1f).clickable(onClick = onOpen).padding(top = 10.dp, end = 8.dp)) {
            Text(d.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            Text("${Fmt.date(d.date)} · ${d.detail}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            if (d.isPartiallyPaid) Text("Paid ${PersonLedger.format(d.settledMinor, d.currency)} of ${PersonLedger.format(d.originalMinor, d.currency)}", style = MaterialTheme.typography.bodySmall, color = SD.colors.blue)
        }
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(top = 10.dp)) {
            Text((if (d.direction > 0) "+" else "−") + PersonLedger.format(d.outstandingMinor, d.currency), fontWeight = FontWeight.SemiBold, color = if (d.direction > 0) SD.colors.green else SD.colors.orange, maxLines = 1)
            Text(if (d.direction > 0) "owes you" else "you owe", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
            TextButton(onClick = onSettle, contentPadding = PaddingValues(horizontal = 8.dp), modifier = Modifier.height(36.dp).semantics { contentDescription = "Mark ${d.title} as paid" }) { Text("Settle") }
        }
    }
}

@Composable
private fun PaymentMethods(person: Person, methods: List<PersonPaymentMethod>, onEdit: (PersonPaymentMethod) -> Unit, onDelete: (PersonPaymentMethod) -> Unit, onAdd: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    SDCard {
        if (methods.isEmpty()) {
            EmptyState(Icons.Filled.AddCircle, "No Payment Accounts", "Add bank accounts, e-wallets, or payment IDs for ${person.name}.", action = "Add Payment Method" to onAdd)
        }
        methods.forEachIndexed { i, m ->
            ListRow(
                m.displayProvider,
                subtitle = listOfNotNull("${m.paymentType.identifierFieldLabel}: ${m.maskedIdentifier}", m.label).joinToString(" • "),
                onClick = { onEdit(m) },
                trailing = {
                    IconButton(onClick = { clipboard.setText(AnnotatedString(m.accountIdentifier)) }) { Icon(Icons.Filled.ContentCopy, "Copy ${m.paymentType.identifierFieldLabel}") }
                    IconButton(onClick = { onDelete(m) }) { Icon(Icons.Filled.Delete, "Delete ${m.displayProvider}", tint = SD.colors.red) }
                },
            )
            if (i < methods.lastIndex) RowDivider()
        }
    }
}
