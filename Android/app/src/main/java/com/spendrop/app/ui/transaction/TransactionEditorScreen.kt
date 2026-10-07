package com.spendrop.app.ui.transaction

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.ui.components.ChipRow
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.DateTimeField
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.components.color
import com.spendrop.app.ui.components.icon
import com.spendrop.app.ui.components.tintName
import com.spendrop.app.ui.paybook.Dropdown
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Money
import com.spendrop.core.accounts.AccountLinker
import com.spendrop.core.ledger.TransactionEntryType
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.parser.CategoryDetector
import com.spendrop.core.parser.ParsingConfidence
import com.spendrop.core.split.SplitDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** How the editor was opened. */
sealed interface EditorMode {
    data class New(val entryType: String = "expense", val quickCash: Boolean = false, val purpose: String? = null, val kind: String? = null,
                   val personId: String? = null, val currency: String? = null, val amountMinor: Long? = null) : EditorMode
    data class EditExpense(val id: String) : EditorMode
    data class EditMovement(val id: String) : EditorMode
    /** Review of an imported item; the view model is started by the caller. */
    object Review : EditorMode
}

/**
 * Add / edit a transaction, or review an imported screenshot (iOS AddExpenseView, EditExpenseView, ExpenseReviewView,
 * ShareExtensionView). Funding account (where the money came from) and payment channel (how it was paid) are separate.
 */
@Composable
fun TransactionEditorScreen(
    container: AppContainer,
    mode: EditorMode,
    onClose: () -> Unit,
    vm: EditorViewModel = viewModel(factory = EditorViewModel.Factory(container)),
    onSaved: () -> Unit = onClose,
    onScanInstead: (() -> Unit)? = null,
) {
    val st by vm.state.collectAsState()
    val snapshot by container.repository.snapshot.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(mode, snapshot != null) {
        if (snapshot == null) return@LaunchedEffect
        when (mode) {
            is EditorMode.New -> vm.startNew(mode.entryType, mode.quickCash, mode.purpose, mode.kind, mode.personId, mode.currency, mode.amountMinor)
            is EditorMode.EditExpense -> vm.startEditExpense(mode.id)
            is EditorMode.EditMovement -> vm.startEditMovement(mode.id)
            EditorMode.Review -> Unit
        }
    }
    LaunchedEffect(st.saved) { if (st.saved) onSaved() }
    var confirmDiscard by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf<String?>(null) } // "split", "payer", "movement"
    val dirty = st.loaded && (st.amountText.isNotEmpty() || st.merchant.isNotEmpty() || st.isReview) && !st.saved
    BackHandler(enabled = dirty) { confirmDiscard = true }

    val title = when {
        st.isReview -> "Review"
        st.editingExpenseId != null -> "Edit Expense"
        st.editingMovementId != null -> st.movement.kind.displayName
        else -> when (st.entryType) { TransactionEntryType.EXPENSE -> "Add Expense"; else -> "Add ${st.entryType.title}" }
    }
    val s = snapshot
    SDScreen(title = title, onBack = { if (dirty) confirmDiscard = true else onClose() }, actions = {
        TextButton(enabled = st.isValid && !st.saving, onClick = { vm.onSave(context) }) { Text("Save", fontWeight = FontWeight.SemiBold) }
    }) { padding ->
        if (!st.loaded || s == null) return@SDScreen
        Column(Modifier.padding(padding).imePadding().verticalScroll(rememberScrollState())) {
            if (st.isReview) ReviewBanner(st)
            // Record type
            if (st.editingExpenseId == null && st.editingMovementId == null) {
                val types = if (st.isReview) listOf(TransactionEntryType.EXPENSE, TransactionEntryType.MONEY_IN, TransactionEntryType.MONEY_OUT) else TransactionEntryType.entries
                Segmented(types, st.entryType, { it.title }, vm::setEntryType)
                if (st.isReview) {
                    val p = st.parsed!!
                    val caption = if (p.suggestedMovementKind == MoneyMovementKind.OWN_TRANSFER) "Looks like a top-up between your own accounts. Record it as a Transfer from Add → Transfer."
                    else p.directionReason?.let { "Suggested from the screenshot: $it. Please confirm." }
                    caption?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp)) }
                }
            }
            if (st.isReview && st.imageFile != null) ScreenshotThumb(st)
            AmountCard(st, onAmount = vm::setAmount, showQuick = !st.isReview && st.editingExpenseId == null && st.editingMovementId == null)
            if (st.isReview) PossibleAmounts(st, vm::setAmount)

            if (st.isExpense) ExpenseFields(st, s, vm, onPickPayBook = { picker = "merchant" })
            else MovementFields(st, s, vm, onPickPerson = { picker = "movement" })

            SectionHeader("Date & time")
            SDCard(padding = 12.dp) { DateTimeField(st.date, { d -> vm.update { it.copy(date = d) } }, "Transaction time") }
            SectionHeader(if (st.isExpense) "Description" else "Note", trailing = { Text("Optional", style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel) })
            SDCard(padding = 12.dp) {
                OutlinedTextField(
                    if (st.isExpense) st.notes else st.movement.note,
                    { t -> vm.update { if (it.isExpense) it.copy(notes = t) else it.copy(movement = it.movement.copy(note = t)) } },
                    placeholder = { Text(if (st.isExpense) "e.g. Lunch with team, monthly groceries" else "Add a note") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (st.isExpense) {
                SectionHeader("Split money")
                SDCard {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Group, null, tint = SD.colors.blue); Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("Split Transaction", fontWeight = FontWeight.SemiBold)
                            Text("Share this amount with people in PayBook", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        }
                        Switch(st.split != null, vm::setSplitEnabled)
                    }
                    val split = st.split
                    if (split != null) {
                        SplitSection(split, st.amountMinor, st.currency, s.people, SplitDraft.lastTimeSuggestion(st.merchant, s, st.editingExpenseId),
                            onChange = { d -> vm.update { it.copy(split = d) } }, onPickPerson = { forPayer -> picker = if (forPayer) "payer" else "split" },
                            onRemoveSplit = { vm.setSplitEnabled(false) })
                    } else {
                        TextButton(onClick = vm::setPaidForSomeone, modifier = Modifier.padding(horizontal = 8.dp)) {
                            Column {
                                Text("Paid for Someone", fontWeight = FontWeight.SemiBold)
                                Text("You paid for them, or they paid for you", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                            }
                        }
                    }
                }
            }
            st.splitProblem?.takeIf { st.isExpense && st.amountMinor > 0 }?.let { /* shown inside the split section */ }
            if (!st.isExpense) {
                val issues = st.movement.copy(amountText = st.amountText, date = st.date).issues
                if (issues.isNotEmpty() && st.amountText.isNotEmpty()) Text(issues.first().message, color = SD.colors.orange, modifier = Modifier.padding(16.dp))
            }
            Button(
                onClick = { vm.onSave(context) }, enabled = st.isValid && !st.saving,
                modifier = Modifier.fillMaxWidth().padding(16.dp).height(52.dp).testTag("saveButton"), shape = RoundedCornerShape(Radius.field),
            ) {
                if (st.saving) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
                else {
                    Icon(Icons.Filled.CheckCircle, null); Spacer(Modifier.width(8.dp))
                    Text(if (st.isExpense) "Save Expense" else "Save ${st.entryType.title}", fontWeight = FontWeight.Bold)
                }
            }
            if (st.editingMovementId != null) {
                var askDelete by remember { mutableStateOf(false) }
                TextButton(onClick = { askDelete = true }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Delete ${st.movement.kind.displayName}", color = SD.colors.red) }
                if (askDelete) ConfirmDialog("Delete this record?", "Settlements that used it stop counting it. This can't be undone here.", "Delete", destructive = true,
                    onConfirm = {
                        scope.launch {
                            val t = System.currentTimeMillis()
                            s.movements.firstOrNull { it.id == st.editingMovementId }?.let { m -> container.repository.apply(Changes(movements = listOf(m.copy(deletedAt = t, updatedAt = t)))) }
                            onClose()
                        }
                    }, onDismiss = { askDelete = false })
            }
            if (onScanInstead != null && !st.isReview && st.editingExpenseId == null && st.editingMovementId == null) {
                TextButton(onClick = onScanInstead, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Scan a screenshot, receipt or PDF instead") }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    // Pickers
    val people = s?.people.orEmpty()
    when (picker) {
        "split", "payer", "movement", "merchant" -> PersonPickerSheet(
            people, exclude = if (picker == "split") st.split?.participants?.mapNotNull { it.person?.id }.orEmpty().toSet() else emptySet(),
            onDismiss = { picker = null },
        ) { person, isNew ->
            val which = picker
            picker = null
            scope.launch {
                if (isNew) container.repository.apply(Changes(people = listOf(person)))
                vm.update {
                    when (which) {
                        "split" -> it.copy(split = (it.split ?: SplitDraft()).add(person))
                        "payer" -> it.copy(split = (it.split ?: SplitDraft()).setPayer(person))
                        "movement" -> it.copy(movement = it.movement.copy(person = person))
                        else -> it.copy(merchant = person.name)
                    }
                }
            }
        }
    }
    if (confirmDiscard) ConfirmDialog(
        if (st.isReview) "Discard this import?" else "Discard changes?", "Nothing will be saved.", "Discard", destructive = true,
        onConfirm = onClose, onDismiss = { confirmDiscard = false }, dismissText = "Keep Editing",
    )
    if (st.askDuplicate) {
        val d = st.duplicate
        AlertDialog(
            onDismissRequest = vm::dismissDialogs,
            title = { Text(if (d?.isStrong == true) "Already Recorded?" else "Possible Duplicate") },
            text = { Text(d?.reason ?: "This may already be recorded. If it's a separate payment, add it anyway.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    // "Add Anyway" always saves a NEW expense; it never merges into the matched one.
                    TextButton(onClick = { vm.saveExpense(context, null) }) { Text("Add Anyway") }
                    if (d?.isStrong == true && d.matchedExpense != null) TextButton(onClick = { vm.saveExpense(context, d.matchedExpense) }) { Text("Merge with Existing") }
                    TextButton(onClick = vm::dismissDialogs) { Text("Cancel") }
                }
            },
        )
    }
    st.movementDuplicateMessage?.let { msg ->
        ConfirmDialog("Possible Duplicate", msg, "Add Anyway", onConfirm = { vm.saveMovement() }, onDismiss = vm::dismissDialogs)
    }
    st.error?.let { MessageDialog(if (st.notFound) "Not found" else "Couldn't save", it) { vm.dismissDialogs(); if (st.notFound) onClose() } }
}

@Composable
private fun ReviewBanner(st: EditorState) {
    val p = st.parsed ?: return
    val (icon, color, title, subtitle) = when {
        p.isFailedTransaction -> Quad(Icons.Filled.Error, SD.colors.red, "Payment Appears to Have Failed", "Screenshot indicates a declined or unsuccessful transaction.")
        p.isBalanceOrLimitOnly -> Quad(Icons.Filled.Info, SD.colors.orange, "Account Balance / Credit Limit", "This looks like an available balance rather than an expense.")
        st.duplicate?.isDuplicate == true -> Quad(Icons.Filled.Warning, SD.colors.yellow, "Possible Duplicate Detected", st.duplicate.reason ?: "This transaction may already exist in SpenDrop.")
        p.confidence == ParsingConfidence.HIGH -> Quad(Icons.Filled.CheckCircle, SD.colors.green, "Payment Detected", "Verified from your transaction screenshot.")
        else -> Quad(Icons.Filled.CheckCircle, SD.colors.blue, "Payment Details", "Review and confirm details below.")
    }
    Row(
        Modifier.padding(16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(color.copy(alpha = 0.12f)).padding(12.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = color); Spacer(Modifier.width(12.dp))
        Column { Text(title, fontWeight = FontWeight.Bold); Text(subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel) }
    }
}

private data class Quad(val a: ImageVector, val b: Color, val c: String, val d: String)

@Composable
private fun ScreenshotThumb(st: EditorState) {
    val bitmap by produceState<Bitmap?>(null, st.imageFile) { value = withContext(Dispatchers.IO) { st.imageFile?.let { ImageTools.decodeOriented(it, 400) } } }
    var full by remember { mutableStateOf(false) }
    Row(
        Modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(SD.colors.card)
            .clickable { full = true }.padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        bitmap?.let { Image(it.asImageBitmap(), "Transaction screenshot", contentScale = ContentScale.Crop, modifier = Modifier.size(60.dp, 72.dp).clip(RoundedCornerShape(10.dp))) }
        Spacer(Modifier.width(12.dp))
        Column {
            Text("Transaction Screenshot", fontWeight = FontWeight.SemiBold)
            Text(st.reference?.takeIf { it.isNotEmpty() }?.let { "Ref: $it" } ?: "Attached to this expense", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
    }
    if (full) ImageViewerDialog(st.imageFile) { full = false }
}

@Composable
fun ImageViewerDialog(file: java.io.File?, onDismiss: () -> Unit) {
    val bitmap by produceState<Bitmap?>(null, file) { value = withContext(Dispatchers.IO) { file?.let { ImageTools.decodeOriented(it, 2000) } } }
    AlertDialog(onDismissRequest = onDismiss, confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } }, text = {
        bitmap?.let { Image(it.asImageBitmap(), "Screenshot", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth()) }
    })
}

@Composable
private fun AmountCard(st: EditorState, onAmount: (String) -> Unit, showQuick: Boolean) {
    Column(
        Modifier.padding(16.dp).fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(SD.colors.card).padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("ENTER AMOUNT", style = SD.sectionHeader, color = SD.colors.secondaryLabel)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(st.currency, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = SD.colors.secondaryLabel)
            Spacer(Modifier.width(6.dp))
            BasicTextField(
                value = st.amountText,
                onValueChange = { t -> if (t.all { it.isDigit() || it == '.' || it == ',' } && t.count { it == '.' } <= 1) onAmount(t) },
                textStyle = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = SD.colors.label, textAlign = TextAlign.Center),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true, cursorBrush = SolidColor(SD.colors.blue),
                modifier = Modifier.width(220.dp).testTag("amount").semantics { contentDescription = "Amount" },
                decorationBox = { inner -> Box(contentAlignment = Alignment.Center) { if (st.amountText.isEmpty()) Text("0.00", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = SD.colors.tertiaryLabel); inner() } },
            )
        }
        if (st.amountMinor == 0L) Text("Enter amount to save", style = MaterialTheme.typography.labelSmall, color = SD.colors.red)
        if (showQuick) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
            listOf(5L, 10L, 20L, 50L).forEach { inc ->
                AssistChip(onClick = { onAmount(Money.plain(st.amountMinor + inc * 100)) }, label = { Text("+${st.currency}$inc") })
            }
        }
    }
}

@Composable
private fun PossibleAmounts(st: EditorState, onAmount: (String) -> Unit) {
    val candidates = st.parsed?.amountCandidates.orEmpty().filter { !it.semanticType.isExcludedFromTransactionAmount }
        .distinctBy { it.amountMinor }
    if (candidates.size <= 1) return
    Text("POSSIBLE AMOUNTS", style = SD.sectionHeader, color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 20.dp))
    ChipRow(candidates, { Money.parseMinor(st.amountText) == it.amountMinor }, { c ->
        Money.format(c.amountMinor, st.currency) + if (c.semanticType.raw != "unknown") " (${c.semanticType.displayName})" else ""
    }, { onAmount(Money.plain(it.amountMinor)) }, modifier = Modifier.padding(vertical = 6.dp))
}

@Composable
private fun ExpenseFields(st: EditorState, s: com.spendrop.core.model.FinanceSnapshot, vm: EditorViewModel, onPickPayBook: () -> Unit) {
    val options = remember(s.accounts) { AccountLinker.fundingOptions(COMMON_FUNDING_ACCOUNTS, s.accounts) }
    val shownFunding = if (st.fundingAccount in options || st.fundingAccount == "Unknown") options else listOf(st.fundingAccount) + options
    SectionHeader("Funding account (where money came from)")
    ChipRow(shownFunding, { it == st.fundingAccount }, { it }, { f -> vm.update { it.copy(fundingAccount = f) } })
    if (st.isReview && (st.fundingAccount == "Unknown" || st.fundingAccount.isBlank())) {
        Text("We couldn't confidently identify the funding account. Choose where the money came from.", style = MaterialTheme.typography.bodySmall, color = SD.colors.orange, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
    }
    SectionHeader("Payment channel (how payment was made)")
    val palette = SD.colors
    ChipRow(PaymentChannel.pickerOrder, { it == st.channel }, { it.displayName }, { c -> vm.update { it.copy(channel = c) } },
        icon = { it.icon }, selectedColor = { if (it == PaymentChannel.APPLE_PAY) null else palette.named(it.tintName) })
    st.channelHint?.takeIf { st.isReview && it.reason.isNotEmpty() }?.let {
        Text(if (it.channel == PaymentChannel.UNKNOWN) it.reason else "${it.reason}. Please confirm.", style = MaterialTheme.typography.bodySmall,
            color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
    }
    SectionHeader("Category")
    FlowRow(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ExpenseCategory.entries.forEach { c ->
            FilterChip(
                selected = st.category == c, onClick = { vm.update { it.copy(category = c, categoryTouched = true) } },
                label = { Text(c.displayName) }, leadingIcon = { Icon(c.icon, null) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = c.color, selectedLabelColor = Color.White, selectedLeadingIconColor = Color.White, containerColor = SD.colors.card),
            )
        }
    }
    st.categoryHint?.takeIf { st.isReview && it.confidence < CategoryDetector.REVIEW_THRESHOLD }?.let {
        Text("${it.reason}. Please check the category.", style = MaterialTheme.typography.bodySmall, color = SD.colors.orange, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
    }
    SectionHeader("Merchant / recipient", trailing = { TextButton(onClick = onPickPayBook) { Icon(Icons.Filled.Person, null); Spacer(Modifier.width(4.dp)); Text("Select from PayBook") } })
    SDCard(padding = 12.dp) {
        OutlinedTextField(st.merchant, vm::setMerchant, placeholder = { Text("e.g. McDonald's, Mamak, Rahim (optional)") }, singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words), modifier = Modifier.fillMaxWidth().testTag("merchant"))
        st.fundingInstrument?.let { Text("Funding instrument: $it", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp)) }
    }
}

@Composable
private fun MovementFields(st: EditorState, s: com.spendrop.core.model.FinanceSnapshot, vm: EditorViewModel, onPickPerson: () -> Unit) {
    val m = st.movement
    val accounts = s.accounts.filter { !it.isArchived }
    SectionHeader("Type")
    SDCard(padding = 12.dp) {
        if (st.entryType.kinds.size > 1) Dropdown("Type", st.entryType.kinds, m.kind, { it.displayName }) { k -> vm.update { it.copy(movement = it.movement.copy(kind = k)) } }
        if (m.kind.requiresPerson) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Person", modifier = Modifier.weight(1f))
                TextButton(onClick = onPickPerson) { Text(m.person?.name ?: "Choose…") }
            }
        }
        val noAccount = "No account"
        val acctNames = listOf(noAccount) + accounts.map { it.name }
        fun nameOf(id: String?) = accounts.firstOrNull { it.id == id }?.name ?: noAccount
        fun idOf(name: String) = accounts.firstOrNull { it.name == name }?.id
        if (st.entryType == TransactionEntryType.TRANSFER) {
            Dropdown("From account", acctNames, nameOf(m.accountId), { it }) { n -> vm.update { it.copy(movement = it.movement.copy(accountId = idOf(n))) } }
            Dropdown("To account", acctNames, nameOf(m.counterAccountId), { it }) { n -> vm.update { it.copy(movement = it.movement.copy(counterAccountId = idOf(n))) } }
            if (accounts.size < 2) Text("Add your accounts in More → Accounts to record transfers between them.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 6.dp))
        } else if (!st.isReview) {
            Dropdown(if (st.entryType == TransactionEntryType.MONEY_IN) "Into account" else "From account", acctNames, nameOf(m.accountId), { it }) { n ->
                vm.update { it.copy(movement = it.movement.copy(accountId = idOf(n))) }
            }
        } else {
            Text("Account: ${st.fundingAccount}", color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 8.dp))
        }
    }
}
