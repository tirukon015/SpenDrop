package com.spendrop.app.ui.transaction

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Money
import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import com.spendrop.core.split.SplitDraft
import kotlin.math.abs

/**
 * Split Money inside the transaction form (iOS InlineSplitSection): who shares the cost, how (equally, by parts or
 * custom amounts with Auto Calculate and fixed amounts), who paid, and whether it adds up — before anything is saved.
 */
@Composable
fun SplitSection(
    draft: SplitDraft,
    totalMinor: Long,
    currency: String,
    people: List<Person>,
    lastTime: SplitDraft?,
    onChange: (SplitDraft) -> Unit,
    onPickPerson: (forPayer: Boolean) -> Unit,
    onRemoveSplit: () -> Unit,
) {
    fun f(m: Long) = Money.format(m, currency)
    var fixedFor by remember { mutableStateOf<SplitDraft.Participant?>(null) }
    Column(Modifier.padding(vertical = 8.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Total", color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
            Text(f(totalMinor), fontWeight = FontWeight.SemiBold)
        }
        Segmented(listOf(SplitDraft.Purpose.SHARED, SplitDraft.Purpose.PAID_FOR), draft.purpose,
            { if (it == SplitDraft.Purpose.SHARED) "Shared Expense" else "Paid for Someone" }, { onChange(draft.setPurpose(it)) })
        if (draft.purpose == SplitDraft.Purpose.SHARED) {
            Segmented(listOf(SplitMethod.EQUAL, SplitMethod.PARTS, SplitMethod.AMOUNTS), draft.method, {
                when (it) { SplitMethod.EQUAL -> "Equally"; SplitMethod.AMOUNTS -> "Amounts"; SplitMethod.PARTS -> "Parts" }
            }, { m ->
                onChange(when (m) { SplitMethod.EQUAL -> draft.useEqualSplit(); SplitMethod.PARTS -> draft.useParts(); SplitMethod.AMOUNTS -> draft.useCustomAmounts(totalMinor) })
            })
        }

        Text(if (draft.purpose == SplitDraft.Purpose.PAID_FOR && draft.payer == null) "You paid for" else "Split between",
            style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
        if (lastTime != null && draft.others.isEmpty() && lastTime.others.isNotEmpty()) {
            AssistChip(onClick = { onChange(lastTime) }, label = { Text("Same as last time: ${lastTime.others.joinToString(", ") { it.name }}") },
                leadingIcon = { Icon(Icons.Filled.History, null) }, modifier = Modifier.padding(horizontal = 16.dp))
        }
        val quick = people.filter { !it.isArchived && it.isFrequent && !draft.contains(it) }.take(6)
        FlowRow(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            quick.forEach { p -> FilterChip(false, { onChange(draft.add(p)) }, { Text(p.name) }, leadingIcon = { Icon(Icons.Filled.Add, null, Modifier.size(16.dp)) }) }
            AssistChip(onClick = { onPickPerson(false) }, label = { Text("Add Person") }, leadingIcon = { Icon(Icons.Filled.PersonAdd, null) })
        }

        draft.participants.forEachIndexed { index, p ->
            val inGroup = draft.sharingParticipants.any { it.id == p.id }
            if (!inGroup && !p.isMe) return@forEachIndexed
            ParticipantRow(draft, p, totalMinor, currency, index, onChange, onFixed = { fixedFor = p })
            RowDivider()
        }

        if (draft.method == SplitMethod.AMOUNTS && !draft.paidForMe && draft.purpose == SplitDraft.Purpose.SHARED) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Auto Calculate")
                    Text("Share what's left equally among people without an amount", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                }
                Switch(draft.autoCalculate, { onChange(draft.setAutoCalculate(it, totalMinor)) })
            }
            if (draft.autoCalculate && draft.fixedTotalMinor > 0) SummaryLine("Fixed", f(draft.fixedTotalMinor))
            SummaryLine("Total allocated", f(draft.assignedMinor(totalMinor)))
            val remaining = draft.remainingMinor(totalMinor)
            SummaryLine("Remaining", f(remaining), if (remaining != 0L && !draft.autoCalculate) SD.colors.orange else null)
        }

        // Who paid
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Paid by", modifier = Modifier.weight(1f))
            FilterChip(draft.payer == null, { onChange(draft.setPayer(null)) }, { Text("Me") })
            Spacer(Modifier.width(6.dp))
            FilterChip(draft.payer != null, { onPickPerson(true) }, { Text(draft.payer?.name ?: "Someone else…") })
        }
        val problem = draft.problem(totalMinor)
        val mine = draft.myShareMinor(totalMinor)
        if (problem != null && totalMinor > 0) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, null, tint = SD.colors.orange, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                Text(problem, color = SD.colors.orange, style = MaterialTheme.typography.bodyMedium)
            }
        } else if (mine != null && totalMinor > 0) {
            Text("✓ Balanced · Your share ${f(mine)}", color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            val payer = draft.payer
            Text(
                if (payer != null) "${payer.name} paid. You owe ${payer.name} ${f(mine)}. Nothing left your account."
                else "You paid ${f(totalMinor)}. Others owe you ${f(totalMinor - mine)}.",
                style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
        TextButton(onClick = onRemoveSplit, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Remove Split", color = SD.colors.red) }
    }

    fixedFor?.let { p ->
        FixedAmountDialog(p, currency, onDismiss = { fixedFor = null }) { minor -> draft.setFixed(minor, p.id, totalMinor)?.let(onChange); fixedFor = null }
    }
}

@Composable
private fun SummaryLine(title: String, value: String, color: androidx.compose.ui.graphics.Color? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 2.dp)) {
        Text(title, color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.SemiBold, color = color ?: SD.colors.label)
    }
}

@Composable
private fun ParticipantRow(
    draft: SplitDraft, p: SplitDraft.Participant, totalMinor: Long, currency: String, index: Int,
    onChange: (SplitDraft) -> Unit, onFixed: () -> Unit,
) {
    val name = if (p.isMe) "You" else p.name
    val shares = draft.shares(totalMinor)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.Medium)
            if (draft.method == SplitMethod.PARTS) Text("${p.parts} × · ${shares?.getOrNull(index)?.let { Money.format(it, currency) } ?: "—"}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
            if (p.fixedMinor != null && draft.isCalculated(p.id)) Text("${Money.format(p.fixedMinor!!, currency)} fixed + equal share", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
            if (draft.payer?.id == p.person?.id && p.person != null || (p.isMe && draft.payer == null)) Text("paid", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        }
        when {
            draft.method == SplitMethod.PARTS -> {
                IconButton(onClick = { onChange(draft.setParts((p.parts - 1).coerceAtLeast(1), p.id)) }) { Icon(Icons.Filled.Remove, "Fewer parts for $name") }
                Text("${p.parts}")
                IconButton(onClick = { onChange(draft.setParts((p.parts + 1).coerceAtMost(99), p.id)) }) { Icon(Icons.Filled.Add, "More parts for $name") }
            }
            draft.method == SplitMethod.AMOUNTS || draft.purpose == SplitDraft.Purpose.PAID_FOR -> {
                val calculated = draft.isCalculated(p.id)
                if (calculated) IconButton(onClick = onFixed) { Icon(Icons.Filled.PushPin, "Fixed amount for $name", tint = if (p.fixedMinor != null) SD.colors.blue else SD.colors.tertiaryLabel) }
                OutlinedTextField(
                    value = draft.displayAmountText(p.id, totalMinor),
                    onValueChange = { t -> if (t.all { it.isDigit() || it == '.' }) onChange(draft.setAmountText(t, p.id, totalMinor)) },
                    singleLine = true, prefix = { Text("$currency ") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    textStyle = MaterialTheme.typography.bodyMedium.copy(color = if (calculated) SD.colors.secondaryLabel else SD.colors.label),
                    modifier = Modifier.width(140.dp).semantics { contentDescription = "$name's amount" },
                )
            }
            else -> Text(shares?.getOrNull(index)?.let { Money.format(it, currency) } ?: "—", fontWeight = FontWeight.SemiBold)
        }
        if (!p.isMe) IconButton(onClick = { onChange(draft.remove(p.id)) }) { Icon(Icons.Filled.Close, "Remove ${p.name}", tint = SD.colors.secondaryLabel) }
    }
}

/** iOS FixedAmountSheet: a fixed amount added to the person's equal share of what's left. */
@Composable
private fun FixedAmountDialog(p: SplitDraft.Participant, currency: String, onDismiss: () -> Unit, onSave: (Long?) -> Unit) {
    var text by remember { mutableStateOf(p.fixedMinor?.let { Money.plain(it) } ?: "") }
    val parsed = Money.parseMinor(text)
    val name = if (p.isMe) "You" else p.name
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Fixed amount") },
        text = {
            Column {
                Text("Added to ${if (name == "You") "your" else "$name's"} equal share of what's left.", color = SD.colors.secondaryLabel)
                OutlinedTextField(text, { text = it }, prefix = { Text("$currency ") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.padding(top = 8.dp))
                if (text.isNotEmpty() && (parsed == null || parsed < 0)) Text("Enter an amount of RM 0.00 or more.", color = SD.colors.orange, style = MaterialTheme.typography.bodySmall)
                if (p.fixedMinor != null) TextButton(onClick = { onSave(null) }) { Text("Remove Fixed Amount", color = SD.colors.red) }
            }
        },
        confirmButton = { TextButton(enabled = parsed != null && parsed >= 0, onClick = { onSave(parsed) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
