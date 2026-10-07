package com.spendrop.app.ui.transaction

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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
        if (draft.purpose == SplitDraft.Purpose.SHARED && !draft.isHybrid) {
            Segmented(listOf(SplitMethod.EQUAL, SplitMethod.PARTS, SplitMethod.AMOUNTS), draft.method, {
                when (it) { SplitMethod.EQUAL -> "Equally"; SplitMethod.AMOUNTS -> "Amounts"; SplitMethod.PARTS -> "Parts" }
            }, { m ->
                onChange(when (m) { SplitMethod.EQUAL -> draft.useEqualSplit(); SplitMethod.PARTS -> draft.useParts(); SplitMethod.AMOUNTS -> draft.useCustomAmounts(totalMinor) })
            })
        }

        Text(when {
            draft.purpose == SplitDraft.Purpose.PAID_FOR && draft.payer == null -> "You paid for"
            draft.isHybrid -> "People in this split"
            else -> "Split between"
        },
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
        // Hybrid Split comes after the people: add who's in the split, then choose how the money is allocated.
        if (draft.purpose == SplitDraft.Purpose.SHARED) HybridToggle(draft, onChange)
        if (draft.isHybrid) HybridLayers(draft, totalMinor, currency, onChange)

        if (!draft.isHybrid) draft.participants.forEachIndexed { index, p ->
            val inGroup = draft.sharingParticipants.any { it.id == p.id }
            if (!inGroup && !p.isMe) return@forEachIndexed
            ParticipantRow(draft, p, totalMinor, currency, index, onChange, onFixed = { fixedFor = p })
            RowDivider()
        }

        if (draft.isHybrid) {
            // Totals are inside the Final Calculation card.
        } else if (draft.method == SplitMethod.AMOUNTS && !draft.paidForMe && draft.purpose == SplitDraft.Purpose.SHARED) {
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

/** "Hybrid Split" switch (Shared splits only). */
@Composable
private fun HybridToggle(draft: SplitDraft, onChange: (SplitDraft) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Hybrid Split", fontWeight = FontWeight.Medium)
            Text("Group and individual fixed amounts first, then the rest split equally", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
        Switch(draft.isHybrid, { onChange(draft.setHybridEnabled(it)) }, modifier = Modifier.testTag("hybridToggle").semantics { contentDescription = "Hybrid Split" })
    }
}

@Composable
private fun LayerTitle(text: String) =
    Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))

@Composable
private fun MoneyField(value: String, label: String, tag: String, currency: String, modifier: Modifier = Modifier, onValue: (String) -> Unit) =
    OutlinedTextField(
        value = value, onValueChange = { t -> if (t.all { it.isDigit() || it == '.' }) onValue(t) },
        label = { Text(label) }, prefix = { Text("$currency ") }, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = modifier.testTag(tag),
    )

/** One layer of a Hybrid Split: a soft card with a numbered header and the layer's allocation on the right. */
@Composable
private fun LayerCard(step: String, title: String, amount: String?, amountColor: androidx.compose.ui.graphics.Color = SD.colors.label, content: @Composable () -> Unit) {
    Column(
        Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(SD.colors.groupedBackground).padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(SD.colors.blue), contentAlignment = Alignment.Center) {
                Text(step, color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp).weight(1f))
            amount?.let { Text(it, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = amountColor) }
        }
        content()
    }
}

@Composable
private fun PeopleChips(draft: SplitDraft, selected: Set<String>, tagPrefix: String, onToggle: (String, Boolean) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.participants.forEach { p ->
            val name = if (p.isMe) "You" else p.name
            val on = p.id in selected
            FilterChip(on, { onToggle(p.id, !on) }, { Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                modifier = Modifier.testTag("$tagPrefix-$name"), leadingIcon = if (on) ({ Icon(Icons.Filled.Check, null, Modifier.size(16.dp)) }) else null)
        }
    }
}

@Composable
private fun Caption(text: String) = Text(text, style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp))

/** Group fixed amounts, individual fixed amounts, the remaining amount and the final calculation. All live. */
@Composable
private fun HybridLayers(draft: SplitDraft, totalMinor: Long, currency: String, onChange: (SplitDraft) -> Unit) {
    val h = draft.hybrid ?: return
    fun f(m: Long) = Money.format(m, currency)
    fun label(p: SplitDraft.Participant) = if (p.isMe) "You" else p.name

    // ① Group fixed amounts — a TOTAL divided between the selected people
    LayerCard("1", if (h.groups.size > 1) "Group Fixed Amounts" else "Group Fixed Amount", f(draft.groupAllocationMinor)) {
        h.groups.forEachIndexed { index, g ->
            if (index > 0) HorizontalDivider(Modifier.padding(vertical = 12.dp), color = SD.colors.separator.copy(alpha = 0.4f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                MoneyField(g.amountText, if (h.groups.size > 1) "Group ${index + 1} total" else "Total for the group", "groupAmount-$index", currency, Modifier.weight(1f)) {
                    onChange(draft.setGroupAmountText(g.id, it))
                }
                if (h.groups.size > 1) IconButton(onClick = { onChange(draft.removeGroup(g.id)) }) { Icon(Icons.Filled.Close, "Remove group ${index + 1}", tint = SD.colors.secondaryLabel) }
            }
            Caption("Divide this amount between")
            PeopleChips(draft, g.memberIds, "group$index") { id, on -> onChange(draft.setGroupMember(g.id, id, on)) }
            val preview = draft.groupPreview(g.id)
            if (preview.isNotEmpty()) Column(Modifier.padding(top = 6.dp)) {
                draft.participants.filter { it.id in preview }.forEach { p ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 1.dp)) {
                        Text(label(p), style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
                        Text(f(preview.getValue(p.id)), style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                    }
                }
            }
        }
        TextButton(onClick = { onChange(draft.addGroup()) }, contentPadding = PaddingValues(horizontal = 4.dp)) {
            Icon(Icons.Filled.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Add Another Group")
        }
    }

    // ② Individual fixed amounts — one person each, never divided
    LayerCard("2", "Individual Fixed Amounts", f(draft.individualAllocationMinor)) {
        if (h.individuals.isEmpty()) Text("An extra amount for one person only, on top of any group amount.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        h.individuals.forEachIndexed { index, ind ->
            var open by remember { mutableStateOf(false) }
            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    val who = draft.participants.firstOrNull { it.id == ind.participantId }
                    OutlinedButton(
                        onClick = { open = true }, contentPadding = PaddingValues(start = 12.dp, end = 4.dp), shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth().height(56.dp).testTag("individualPerson-$index")
                            .semantics { contentDescription = "Person for individual fixed amount ${index + 1}" },
                    ) {
                        Text(who?.let(::label) ?: "Person", maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                            color = if (who == null) SD.colors.secondaryLabel else SD.colors.label)
                        Icon(Icons.Filled.ArrowDropDown, null, tint = SD.colors.secondaryLabel)
                    }
                    DropdownMenu(open, { open = false }) {
                        draft.participants.forEach { p -> DropdownMenuItem({ Text(label(p)) }, { onChange(draft.setIndividualPerson(ind.id, p.id)); open = false }) }
                    }
                }
                Spacer(Modifier.width(8.dp))
                MoneyField(ind.amountText, "Amount", "individualAmount-$index", currency, Modifier.width(118.dp)) { onChange(draft.setIndividualAmountText(ind.id, it)) }
                IconButton(onClick = { onChange(draft.removeIndividual(ind.id)) }, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.Filled.Close, "Remove individual fixed amount", tint = SD.colors.secondaryLabel)
                }
            }
        }
        TextButton(onClick = { onChange(draft.addIndividual()) }, contentPadding = PaddingValues(horizontal = 4.dp)) {
            Icon(Icons.Filled.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Add Individual Fixed Amount")
        }
    }

    // ③ Remaining amount — split equally between the selected people
    val remaining = draft.hybridRemainingMinor(totalMinor)
    LayerCard("3", "Remaining Amount", f(remaining), if (remaining < 0) SD.colors.orange else SD.colors.label) {
        Text("${f(totalMinor)} total − ${f(draft.groupAllocationMinor + draft.individualAllocationMinor)} fixed", style = MaterialTheme.typography.bodySmall,
            color = SD.colors.secondaryLabel, modifier = Modifier.testTag("hybridRemaining").semantics { contentDescription = f(remaining) })
        Caption("Split remaining between")
        PeopleChips(draft, h.remainderIds, "rest") { id, on -> onChange(draft.setInRemainder(id, on)) }
        Text("Auto Calculate: ON · split equally", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp))
    }

    // Final calculation — one row per person, then the totals
    val allocated = draft.assignedMinor(totalMinor)
    LayerCard("✓", "Final Calculation", null) {
        draft.participants.forEachIndexed { i, p ->
            if (i > 0) HorizontalDivider(color = SD.colors.separator.copy(alpha = 0.35f))
            HybridResultRow(draft, p, totalMinor, currency, onChange)
        }
        HorizontalDivider(Modifier.padding(top = 4.dp), color = SD.colors.separator.copy(alpha = 0.6f))
        Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
            Text("Total allocated", modifier = Modifier.weight(1f)); Text(f(allocated), fontWeight = FontWeight.SemiBold)
        }
        Row(Modifier.fillMaxWidth().padding(top = 2.dp)) {
            Text("Remaining", color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
            Text(f(totalMinor - allocated), fontWeight = FontWeight.SemiBold, color = if (totalMinor - allocated != 0L) SD.colors.orange else SD.colors.green)
        }
    }
}

/** One final row per person: their total, and how it's made up. */
@Composable
private fun HybridResultRow(draft: SplitDraft, p: SplitDraft.Participant, totalMinor: Long, currency: String, onChange: (SplitDraft) -> Unit) {
    val name = if (p.isMe) "You" else p.name
    val line = draft.hybridLines(totalMinor).valueOrNull()?.firstOrNull { it.participantId == p.id }
    fun f(m: Long) = Money.format(m, currency)
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.Medium)
            val parts = line?.let {
                listOfNotNull(
                    it.groupMinor.takeIf { v -> v > 0 }?.let { v -> "${f(v)} group" },
                    it.individualMinor.takeIf { v -> v > 0 }?.let { v -> "${f(v)} individual" },
                    it.remainingMinor.takeIf { v -> v > 0 }?.let { v -> "${f(v)} remaining" },
                )
            }
            // Non-breaking spaces keep each "RM 15.00 remaining" together when the line wraps.
            if (!parts.isNullOrEmpty()) Text(parts.joinToString(" + ") { it.replace(' ', '\u00A0') }, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
            if (draft.payer?.id == p.person?.id && p.person != null || (p.isMe && draft.payer == null)) Text("paid", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        }
        Text(line?.let { f(it.totalMinor) } ?: "—", fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("share-$name"))
        if (!p.isMe) IconButton(onClick = { onChange(draft.remove(p.id)) }) { Icon(Icons.Filled.Close, "Remove ${p.name}", tint = SD.colors.secondaryLabel) }
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
