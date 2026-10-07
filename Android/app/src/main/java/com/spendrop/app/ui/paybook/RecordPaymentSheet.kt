package com.spendrop.app.ui.paybook

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.components.AmountField
import com.spendrop.app.ui.components.DateTimeField
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Money
import com.spendrop.core.ledger.Debt
import com.spendrop.core.ledger.SettlementService
import com.spendrop.core.model.Person

/** What the payment sheet should record (iOS PaymentSheetRequest). */
data class PaymentRequest(val direction: Int, val currency: String, val debts: List<Debt>, val creditMinor: Long? = null)

/**
 * Receive / make a payment (or apply existing credit) and apply it to transactions — automatically (oldest first)
 * or by entering each amount. Shows exactly what will happen before saving (iOS RecordPaymentSheet).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordPaymentSheet(
    person: Person,
    request: PaymentRequest,
    onDismiss: () -> Unit,
    onSave: (amountMinor: Long, plan: List<Pair<Debt, Long>>, date: Long) -> String?,
) {
    val open = remember(request) { request.debts.filter { it.direction == request.direction && it.outstandingMinor > 0 } }
    val isCredit = request.creditMinor != null
    var amountText by remember { mutableStateOf(if (!isCredit && open.size == 1) Money.plain(open[0].outstandingMinor) else "") }
    var auto by remember { mutableStateOf(true) }
    val manual = remember { mutableStateMapOf<String, String>() }
    var date by remember { mutableStateOf(System.currentTimeMillis()) }
    var error by remember { mutableStateOf<String?>(null) }
    fun f(m: Long) = Money.format(m, request.currency)

    val amountMinor = request.creditMinor ?: (Money.parseMinor(amountText) ?: 0)
    val totalOutstanding = open.sumOf { it.outstandingMinor }
    val plan = if (auto) SettlementService.autoAllocate(amountMinor, open)
    else open.map { it to (Money.parseMinor(manual[it.id].orEmpty()) ?: 0) }.filter { it.second > 0 }
    val applied = plan.sumOf { it.second }
    val problem = when {
        amountMinor <= 0 -> "Enter the amount paid."
        plan.any { it.second > it.first.outstandingMinor } -> plan.first { it.second > it.first.outstandingMinor }.let { (d, a) ->
            "${f(a - d.outstandingMinor)} more than what's left on ${d.title} (${f(d.outstandingMinor)}). Lower it; any extra stays as credit."
        }
        applied > amountMinor -> "The amounts applied are ${f(applied - amountMinor)} more than the ${if (isCredit) "credit available" else "payment"} (${f(amountMinor)})."
        isCredit && applied == 0L -> "Choose how much credit to apply."
        else -> null
    }
    val title = if (isCredit) "Apply Credit" else if (request.direction > 0) "Receive Payment" else "Pay ${person.name}"

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = SD.colors.groupedBackground) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                TextButton(enabled = problem == null, onClick = { error = onSave(amountMinor, plan, date); if (error == null) onDismiss() }) { Text("Save", fontWeight = FontWeight.SemiBold) }
            }
            SectionHeader(
                if (isCredit) (if (request.direction > 0) "Earlier payments from ${person.name} not yet applied" else "Earlier payments to ${person.name} not yet applied")
                else if (request.direction > 0) "${person.name} paid you" else "You paid ${person.name}",
            )
            SDCard(padding = 12.dp) {
                if (isCredit) {
                    Row { Text("Credit available", Modifier.weight(1f)); Text(f(amountMinor), fontWeight = FontWeight.SemiBold) }
                } else {
                    AmountField(amountText, { amountText = it }, "Amount", prefix = request.currency)
                    Spacer(Modifier.height(8.dp))
                    DateTimeField(date, { date = it }, "Date")
                }
            }
            SectionFooter("Outstanding on the selected transactions: ${f(totalOutstanding)}")
            if (open.size > 1) {
                Segmented(listOf(true, false), auto, { if (it) "Auto Apply" else "Choose Amounts" }, { auto = it })
                SectionFooter(if (auto) "Oldest transactions are paid first." else "Enter how much of the payment goes to each transaction.")
            }
            SectionHeader("What will happen")
            SDCard {
                open.forEachIndexed { i, d ->
                    val a = plan.firstOrNull { it.first.id == d.id }?.second ?: 0
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(d.title, fontWeight = FontWeight.Medium)
                            Text("${Fmt.date(d.date)} · left ${f(d.outstandingMinor)}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        }
                        if (!auto && open.size > 1) {
                            AmountField(manual[d.id].orEmpty(), { manual[d.id] = it }, "Amount for ${d.title}", modifier = Modifier.width(150.dp), prefix = request.currency)
                        } else Column(horizontalAlignment = Alignment.End) {
                            Text(if (a > 0) "−${f(a)}" else "—", fontWeight = FontWeight.SemiBold)
                            Text("then ${f(d.outstandingMinor - a)}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        }
                    }
                    if (i < open.lastIndex) RowDivider()
                }
                RowDivider(0.dp)
                Row(Modifier.padding(16.dp)) { Text(if (isCredit) "Credit applied" else "Applied", Modifier.weight(1f)); Text(f(applied), fontWeight = FontWeight.SemiBold) }
                if (amountMinor > applied && problem == null) {
                    Row(Modifier.padding(horizontal = 16.dp)) { Text(if (isCredit) "Credit left" else "Remaining credit", Modifier.weight(1f)); Text(f(amountMinor - applied), fontWeight = FontWeight.SemiBold) }
                    Text(
                        "${f(amountMinor - applied)} isn't applied to a transaction. It's kept as credit with ${person.name}: it still counts in your balance, and you can apply it later.",
                        style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp),
                    )
                }
                problem?.let { Text(it, color = SD.colors.orange, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp)) }
                error?.let { Text(it, color = SD.colors.red, modifier = Modifier.padding(16.dp)) }
            }
            Button(onClick = { error = onSave(amountMinor, plan, date); if (error == null) onDismiss() }, enabled = problem == null, modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp)) {
                Text("Save")
            }
        }
    }
}
