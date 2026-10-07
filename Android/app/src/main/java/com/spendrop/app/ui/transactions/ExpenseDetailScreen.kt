package com.spendrop.app.ui.transactions

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Input
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.spendrop.app.AppContainer
import com.spendrop.app.data.applySettlement
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.EmptyState
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.IconBadge
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.PhotoStore
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.color
import com.spendrop.app.ui.components.icon
import com.spendrop.app.ui.paybook.PaymentRequest
import com.spendrop.app.ui.paybook.RecordPaymentSheet
import com.spendrop.app.ui.theme.SD
import com.spendrop.app.ui.transaction.ImageViewerDialog
import com.spendrop.core.Money
import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.ledger.Debt
import com.spendrop.core.ledger.DebtLedger
import com.spendrop.core.ledger.SettlementService
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.SettlementKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun ExpenseDetailScreen(container: AppContainer, expenseId: String, onBack: () -> Unit, onEdit: (String) -> Unit) {
    val snapshot by container.repository.snapshot.collectAsState()
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var showImage by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val s = snapshot
    val e = s?.expenses?.firstOrNull { it.id == expenseId }
    SDScreen(title = "Expense Details", onBack = onBack, actions = { if (e != null) TextButton(onClick = { onEdit(e.id) }) { Text("Edit") } }) { padding ->
        if (s == null) return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        if (e == null) return@SDScreen EmptyState(Icons.Filled.Delete, "Expense not found", "It may have been deleted.", Modifier.padding(padding))
        val shares = s.sharesOf(e.id)
        val people = s.people.associateBy { it.id }
        val debts = remember(s, e.id) { DebtLedger.debts(s, e).sortedBy { it.personName } }
        val imageFile = e.imageRelativePath?.let { File(PhotoStore.receiptsDir(context), it) }?.takeIf { it.exists() }
        LazyColumn(contentPadding = padding) {
            item {
                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    IconBadge(e.category.icon, e.category.color, 64.dp)
                    Spacer(Modifier.height(8.dp))
                    Text(e.merchant, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(Fmt.money(e.amountMinor, e.currency), fontSize = 34.sp, fontWeight = FontWeight.Bold)
                    if (shares.isNotEmpty()) Text("Your share ${Fmt.money(ExpenseMath.myShareMinor(e, shares), e.currency)}", color = SD.colors.secondaryLabel)
                }
            }
            item {
                SDCard {
                    ListRow("Category", icon = e.category.icon, iconTint = e.category.color, value = e.category.displayName); RowDivider(52.dp)
                    ListRow("Funding Account", icon = Icons.Filled.AccountBalance, value = e.effectiveFundingAccount); RowDivider(52.dp)
                    ListRow("Payment Channel", icon = e.paymentChannel.icon, iconTint = e.paymentChannel.color, value = e.paymentChannel.displayName)
                    e.fundingInstrument?.let { RowDivider(52.dp); ListRow("Funding Instrument", icon = Icons.Filled.CreditCard, iconTint = SD.colors.orange, value = it) }
                    if (e.isReconciled) { RowDivider(52.dp); ListRow("Status", icon = Icons.Filled.Verified, value = "Reconciled") }
                    RowDivider(52.dp); ListRow("Date", icon = Icons.Filled.CalendarMonth, value = Fmt.date(e.date))
                    RowDivider(52.dp); ListRow("Time", icon = Icons.Filled.Schedule, iconTint = SD.colors.teal, value = Fmt.time(e.date))
                    RowDivider(52.dp); ListRow("Source", icon = Icons.Filled.Input, iconTint = SD.colors.indigo, value = e.sourceType.displayName)
                    e.transactionReference?.let { RowDivider(52.dp); ListRow("Reference", icon = Icons.Filled.Numbers, iconTint = SD.colors.gray, value = it) }
                }
            }
            item {
                SectionHeader("Split", trailing = { TextButton(onClick = { onEdit(e.id) }) { Text(if (shares.isEmpty()) "Split with others" else "Edit Split") } })
                SDCard {
                    ListRow("Paid by", value = if (e.paidByMe) "Me" else (e.payerId?.let { people[it]?.name } ?: e.payerNameSnapshot ?: "Someone"))
                    shares.forEach { sh ->
                        RowDivider()
                        ListRow(if (sh.isMe) "Me" else (sh.personId?.let { people[it]?.name } ?: sh.nameSnapshot), value = Fmt.money(sh.amountMinor, e.currency))
                    }
                    if (!ExpenseMath.sharesMatchAmount(e, shares)) { RowDivider(); ListRow("Needs attention", icon = Icons.Filled.Warning, iconTint = SD.colors.orange, value = "Shares don't add up") }
                }
            }
            if (debts.isNotEmpty()) {
                item { SectionHeader("Who owes whom") }
                debts.forEach { d -> item { DebtCard(container, s, d); Spacer(Modifier.height(12.dp)) } }
            }
            e.notes?.takeIf { it.isNotBlank() }?.let { n -> item { SectionHeader("Notes"); SDCard(padding = 16.dp) { Text(n) } } }
            if (imageFile != null) item {
                SectionHeader("Original receipt / screenshot")
                SDCard(padding = 8.dp) {
                    val bmp by produceState<Bitmap?>(null, imageFile) { value = withContext(Dispatchers.IO) { ImageTools.decodeOriented(imageFile, 1000) } }
                    bmp?.let { Image(it.asImageBitmap(), "Receipt screenshot", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp).clip(RoundedCornerShape(10.dp)).clickable { showImage = true }) }
                }
            }
            item {
                Spacer(Modifier.height(16.dp))
                SDCard { ListRow("Delete Expense", icon = Icons.Filled.Delete, iconTint = SD.colors.red, titleColor = SD.colors.red, onClick = { confirmDelete = true }) }
                Spacer(Modifier.height(32.dp))
            }
        }
        if (confirmDelete) ConfirmDialog("Delete Expense?", "Are you sure you want to delete this expense of ${Fmt.money(e.amountMinor, e.currency)}?", "Delete", destructive = true,
            onConfirm = { scope.launch { container.repository.deleteExpense(e); onBack() } }, onDismiss = { confirmDelete = false })
        if (showImage) ImageViewerDialog(imageFile) { showImage = false }
    }
}

@Composable
private fun DebtCard(container: AppContainer, s: FinanceSnapshot, debt: Debt) {
    val person = s.people.firstOrNull { it.id == debt.personId }
    val scope = rememberCoroutineScope()
    var confirm by remember { mutableStateOf(false) }
    var payment by remember { mutableStateOf(false) }
    var undo by remember { mutableStateOf<DebtLedger.SettlementGroup?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    fun f(m: Long) = Money.format(m, debt.currency)
    fun run(block: () -> com.spendrop.core.ledger.SettlementChange) {
        try { val c = block(); scope.launch { container.repository.applySettlement(c, s) } } catch (e: Exception) { error = e.message ?: "Couldn't record the payment." }
    }
    SDCard {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (debt.isSettled) Icons.Filled.CheckCircle else if (debt.direction > 0) Icons.AutoMirrored.Filled.CallReceived else Icons.AutoMirrored.Filled.CallMade, null,
                tint = if (debt.isSettled) SD.colors.green else if (debt.direction > 0) SD.colors.green else SD.colors.orange)
            Spacer(Modifier.width(10.dp))
            Text(if (debt.isSettled) "Settled with ${debt.personName}" else debt.statusText, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(if (debt.isSettled) "Settled" else if (debt.isPartiallyPaid) "Partly paid" else "Outstanding", style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel)
        }
        RowDivider()
        ListRow(if (debt.direction > 0) "${debt.personName}'s share" else "Your share (${debt.personName} paid)", value = f(debt.originalMinor))
        ListRow("Paid", value = f(debt.settledMinor))
        ListRow("Outstanding", value = f(debt.outstandingMinor), valueColor = SD.colors.label)
        if (!debt.isSettled && person != null) {
            RowDivider()
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { confirm = true }, modifier = Modifier.weight(1f)) { Text("Mark as Paid") }
                OutlinedButton(onClick = { payment = true }, modifier = Modifier.weight(1f)) { Text("Record Payment") }
            }
        }
        val groups = DebtLedger.settlementGroups(s, personId = debt.personId, expenseId = debt.expenseId, loanId = debt.loanId)
        if (groups.isNotEmpty()) {
            RowDivider()
            Text("PAYMENTS", style = SD.sectionHeader, color = SD.colors.secondaryLabel, modifier = Modifier.padding(start = 16.dp, top = 10.dp))
            groups.forEach { g ->
                val title = when {
                    g.totalMinor == 0L && g.offsetMinor > 0 -> "Offset ${f(g.offsetMinor)} (no money moved)"
                    g.payment != null -> (if (g.direction > 0) "Received " else "Paid ") + f(g.payment!!.amountMinor)
                    else -> "Applied ${f(g.totalMinor)} of earlier payments (credit)"
                }
                ListRow(title, subtitle = Fmt.dateTime(g.date), trailing = { TextButton(onClick = { undo = g }) { Text("Undo") } })
            }
        }
    }
    if (confirm && person != null) ConfirmDialog("Mark as paid?",
        if (debt.direction > 0) "${debt.personName} paid you ${f(debt.outstandingMinor)} for ${debt.title}. Only this transaction is settled."
        else "You paid ${debt.personName} ${f(debt.outstandingMinor)} for ${debt.title}. Only this transaction is settled.",
        "Mark ${f(debt.outstandingMinor)} as Paid", onConfirm = { run { SettlementService.markPaid(debt, person, System.currentTimeMillis()) } }, onDismiss = { confirm = false })
    if (payment && person != null) RecordPaymentSheet(person, PaymentRequest(debt.direction, debt.currency, listOf(debt)), onDismiss = { payment = false }) { amount, plan, date ->
        try {
            val c = SettlementService.recordPayment(person, debt.direction, amount, plan, debt.currency, System.currentTimeMillis(), date)
            scope.launch { container.repository.applySettlement(c, s) }; null
        } catch (e: Exception) { e.message ?: "Couldn't record the payment." }
    }
    undo?.let { g -> ConfirmDialog("Undo this settlement?", "The amount becomes outstanding again. The original transaction is not changed.", "Undo Settlement", destructive = true,
        onConfirm = { run { SettlementService.undo(s, g.id) } }, onDismiss = { undo = null }) }
    error?.let { MessageDialog("Couldn't Record Payment", it) { error = null } }
}
