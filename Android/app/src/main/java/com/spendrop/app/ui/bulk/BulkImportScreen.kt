package com.spendrop.app.ui.bulk

import android.graphics.Bitmap
import androidx.compose.animation.animateContentSize
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.spendrop.app.AppContainer
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.importing.IntakeItem
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD
import com.spendrop.app.ui.transaction.ImageViewerDialog
import com.spendrop.app.ui.transaction.TransactionEditorFields
import com.spendrop.core.Money
import com.spendrop.core.bulk.BulkReview
import com.spendrop.core.ledger.TransactionEntryType
import com.spendrop.core.model.PaymentChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Bulk Import review queue. Each card is collapsed to a one-line summary; expanding it shows the SAME transaction
 * form as Add / Review (TransactionEditorFields), so every field, Split Money and validation are available.
 */
@Composable
fun BulkImportScreen(
    container: AppContainer,
    load: suspend () -> List<IntakeItem>,
    source: com.spendrop.core.model.ExpenseSourceType = com.spendrop.core.model.ExpenseSourceType.SCREENSHOT,
    onClose: (saved: Int) -> Unit,
) {
    val vm: BulkImportViewModel = viewModel()
    LaunchedEffect(Unit) { vm.start(load, source) }
    val ui by vm.ui.collectAsState()
    val views by vm.views.collectAsState()
    val snapshot by container.repository.snapshot.collectAsState()
    val context = LocalContext.current
    var confirmLeave by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<File?>(null) }
    val toAdd = views.count { it.willSave }

    SDScreen(
        title = "Bulk Import",
        onBack = { if (ui.phase == BulkPhase.REVIEW && views.any { it.willSave }) confirmLeave = true else if (ui.phase != BulkPhase.SAVING) onClose(ui.saved) },
        bottomBar = {
            if (ui.phase == BulkPhase.REVIEW || ui.phase == BulkPhase.SAVING) Surface(color = SD.colors.groupedBackground) {
                Button(
                    onClick = { vm.saveAll(context) { onClose(vm.ui.value.saved) } },
                    enabled = toAdd > 0 && ui.phase == BulkPhase.REVIEW,
                    modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp).height(52.dp).testTag("addAll"),
                    shape = RoundedCornerShape(Radius.field),
                ) {
                    if (ui.phase == BulkPhase.SAVING) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp)); Text("Saving ${ui.saveProgress} of $toAdd…")
                    } else Text(if (toAdd == 1) "Add 1 Transaction" else "Add $toAdd Transactions", fontWeight = FontWeight.Bold)
                }
            }
        },
    ) { padding ->
        val s = snapshot ?: return@SDScreen
        LazyColumn(contentPadding = padding, modifier = Modifier.testTag("bulkList")) {
            if (ui.phase == BulkPhase.LOADING || ui.phase == BulkPhase.PROCESSING) {
                item { Progress(ui) }
                return@LazyColumn
            }
            item { Summary(ui, views) }
            items(views, key = { it.draft.id }) { v -> DraftCard(v, s, container, vm, onView = { viewing = it }) }
            val unable = ui.shots.filter { it.state == ShotState.UNABLE && it.index !in ui.dismissedShots }
            if (unable.isNotEmpty()) {
                item { SectionHeader("Not recognised") }
                items(unable, key = { "shot-${it.index}" }) { shot -> UnableCard(shot, onView = { (shot.item as? IntakeItem.Image)?.file?.let { f -> viewing = f } }, vm) }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    if (confirmLeave) ConfirmDialog("Discard this import?", if (ui.saved > 0) "${ui.saved} already saved stay saved. The rest won't be added." else "Nothing has been saved yet.", "Discard", destructive = true, onConfirm = { onClose(ui.saved) }, onDismiss = { confirmLeave = false }, dismissText = "Keep Reviewing")
    if (ui.phase == BulkPhase.REVIEW && ui.failed > 0) MessageDialog("Some transactions weren't saved",
        "${ui.saved} saved, ${ui.failed} couldn't be saved. They're still in the list: check them and tap Add again.") { vm.clearFailed() }
    viewing?.let { ImageViewerDialog(it) { viewing = null } }
}

@Composable
private fun Progress(ui: BulkUi) {
    val done = ui.shots.count { it.state == ShotState.DONE || it.state == ShotState.UNABLE }
    SectionHeader("Analyzing screenshots")
    SDCard(padding = 16.dp) {
        Text("Reading $done of ${ui.shots.size} on this phone…", fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        LinearProgressIndicator(progress = { if (ui.shots.isEmpty()) 0f else done / ui.shots.size.toFloat() }, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))
        ui.shots.forEach { shot ->
            Row(Modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                when (shot.state) {
                    ShotState.DONE -> Icon(Icons.Filled.CheckCircle, null, tint = SD.colors.green, modifier = Modifier.size(18.dp))
                    ShotState.UNABLE -> Icon(Icons.Filled.Warning, null, tint = SD.colors.orange, modifier = Modifier.size(18.dp))
                    ShotState.PROCESSING -> Icon(Icons.Filled.HourglassTop, null, tint = SD.colors.blue, modifier = Modifier.size(18.dp))
                    ShotState.WAITING -> Icon(Icons.Filled.RadioButtonUnchecked, null, tint = SD.colors.tertiaryLabel, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(10.dp))
                Text("Screenshot ${shot.index + 1}", color = if (shot.state == ShotState.WAITING) SD.colors.secondaryLabel else SD.colors.label)
            }
        }
        if (ui.shots.size >= BulkImportViewModel.MAX) Text("Up to ${BulkImportViewModel.MAX} screenshots per import.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun Summary(ui: BulkUi, views: List<DraftView>) {
    val kept = views.filter { !it.draft.removed && !it.draft.saved }
    val ready = kept.count { it.status == BulkReview.Status.READY }
    val review = kept.count { it.status == BulkReview.Status.NEEDS_REVIEW }
    val dups = kept.count { it.status == BulkReview.Status.POSSIBLE_DUPLICATE }
    val unable = ui.shots.count { it.state == ShotState.UNABLE && it.index !in ui.dismissedShots }
    val total = views.filter { it.willSave && it.state.isExpense }.sumOf { it.state.amountMinor }
    SDCard(padding = 16.dp, modifier = Modifier.padding(top = 4.dp)) {
        Text("${ui.shots.size} screenshot${if (ui.shots.size == 1) "" else "s"} · ${views.size} transaction${if (views.size == 1) "" else "s"} detected", fontWeight = FontWeight.SemiBold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.padding(top = 6.dp)) {
            Text("✓ $ready ready", color = SD.colors.green)
            if (review > 0) Text("⚠ $review need review", color = SD.colors.orange)
            if (dups > 0) Text("● $dups possible duplicate${if (dups == 1) "" else "s"}", color = SD.colors.red)
            if (unable > 0) Text("⚠ $unable screenshot${if (unable == 1) "" else "s"} not recognised", color = SD.colors.orange)
        }
        Row(Modifier.padding(top = 10.dp)) {
            Text("Total to add", color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
            Text(Money.format(total), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DraftCard(v: DraftView, s: com.spendrop.core.model.FinanceSnapshot, container: AppContainer, vm: BulkImportViewModel, onView: (File) -> Unit) {
    val st = v.state
    val d = v.draft
    if (!st.loaded) return
    Column(
        Modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(SD.colors.card).animateContentSize(),
    ) {
        // Collapsed summary — tap to expand
        Row(
            Modifier.fillMaxWidth().clickable(role = Role.Button) { vm.toggle(d.id) }.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        st.merchant.ifBlank { if (st.isExpense) "Unknown merchant" else st.movement.kind.displayName },
                        fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                        color = if (d.removed) SD.colors.tertiaryLabel else SD.colors.label,
                    )
                }
                val pay = when {
                    st.isExpense && st.channel != PaymentChannel.UNKNOWN -> st.channel.displayName
                    st.isExpense && st.fundingAccount.isNotBlank() && st.fundingAccount != "Unknown" -> st.fundingAccount
                    !st.isExpense -> st.entryType.title
                    else -> null
                }
                Text(listOfNotNull(Fmt.date(st.date), Fmt.time(st.date), pay).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Badge(v)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(if (st.amountMinor > 0) (if (st.entryType == TransactionEntryType.MONEY_IN) "+" else "") + Money.format(st.amountMinor, st.currency) else "—",
                    fontWeight = FontWeight.Bold, color = if (d.removed) SD.colors.tertiaryLabel else SD.colors.label)
            }
            Icon(if (d.expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, if (d.expanded) "Collapse" else "Expand", tint = SD.colors.secondaryLabel, modifier = Modifier.padding(start = 6.dp))
        }
        if (d.removed) {
            TextButton(onClick = { vm.restore(d.id) }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Removed · Undo") }
            return@Column
        }
        if (d.saved) return@Column
        if (v.duplicate.isDuplicate) DuplicatePanel(v, vm)
        if (d.expanded) {
            Column(Modifier.background(SD.colors.groupedBackground).padding(bottom = 8.dp)) {
                // The complete, normal transaction form (same fields, split and rules as Add / Review).
                TransactionEditorFields(container, d.vm, st, s)
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
                st.imageFile?.let { f -> TextButton(onClick = { onView(f) }) { Text("View Screenshot") } }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { vm.remove(d.id) }) { Text("Remove", color = SD.colors.red) }
                TextButton(onClick = { vm.toggle(d.id) }) { Text("Done") }
            }
        }
    }
}

@Composable
private fun Badge(v: DraftView) {
    if (v.draft.saved) {
        Text("✓ Saved", style = MaterialTheme.typography.labelMedium, color = SD.colors.green, modifier = Modifier.padding(top = 2.dp)); return
    }
    val (text, color) = when (v.status) {
        BulkReview.Status.READY -> "✓ Ready" to SD.colors.green
        BulkReview.Status.NEEDS_REVIEW -> "⚠ Needs review" to SD.colors.orange
        BulkReview.Status.POSSIBLE_DUPLICATE -> "● Possible duplicate" to SD.colors.red
    }
    val extra = when (v.draft.choice) {
        BulkReview.DuplicateChoice.ADD_ANYWAY -> " · adding anyway"
        BulkReview.DuplicateChoice.MERGE -> " · merging with existing"
        else -> ""
    }
    Text(text + extra, style = MaterialTheme.typography.labelMedium, color = color, modifier = Modifier.padding(top = 2.dp))
}

/** The existing duplicate actions: Add Anyway / Merge with Existing (strong match with a saved one) / Skip. */
@Composable
private fun DuplicatePanel(v: DraftView, vm: BulkImportViewModel) {
    val d = v.duplicate
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 10.dp).clip(RoundedCornerShape(Radius.control)).background(SD.colors.red.copy(alpha = 0.08f)).padding(12.dp)) {
        Text(if (d.isStrong) "Already recorded?" else "Possible duplicate", fontWeight = FontWeight.SemiBold)
        Text(d.reason ?: "This may already be recorded. If it's a separate payment, add it anyway.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
            val c = v.draft.choice
            Choice("Skip", c == null || c == BulkReview.DuplicateChoice.SKIP) { vm.choose(v.draft.id, BulkReview.DuplicateChoice.SKIP) }
            Choice("Add Anyway", c == BulkReview.DuplicateChoice.ADD_ANYWAY) { vm.choose(v.draft.id, BulkReview.DuplicateChoice.ADD_ANYWAY) }
            if (d.isStrong && d.matchedExpense != null) Choice("Merge with Existing", c == BulkReview.DuplicateChoice.MERGE) { vm.choose(v.draft.id, BulkReview.DuplicateChoice.MERGE) }
        }
    }
}

@Composable
private fun Choice(label: String, selected: Boolean, onClick: () -> Unit) {
    if (selected) FilledTonalButton(onClick = onClick) { Text(label) } else OutlinedButton(onClick = onClick) { Text(label) }
}

@Composable
private fun UnableCard(shot: Shot, onView: () -> Unit, vm: BulkImportViewModel) {
    val file = (shot.item as? IntakeItem.Image)?.file
    val bmp by produceState<Bitmap?>(null, file) { value = withContext(Dispatchers.IO) { file?.let { runCatching { ImageTools.decodeOriented(it, 200) }.getOrNull() } } }
    SDCard(padding = 12.dp, modifier = Modifier.padding(vertical = 6.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            bmp?.let { Image(it.asImageBitmap(), "Screenshot ${shot.index + 1}", contentScale = ContentScale.Crop, modifier = Modifier.size(52.dp, 64.dp).clip(RoundedCornerShape(8.dp))) }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("⚠ Unable to detect transaction", fontWeight = FontWeight.SemiBold, color = SD.colors.orange)
                Text("Screenshot ${shot.index + 1}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                Text((shot.item as? IntakeItem.Unreadable)?.reason ?: "We couldn't confidently identify a transaction from this image.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (file != null) TextButton(onClick = onView) { Text("Review Screenshot") }
            if (shot.item !is IntakeItem.Unreadable) TextButton(onClick = { vm.enterManually(shot.index) }) { Text("Enter Manually") }
            TextButton(onClick = { vm.dismissShot(shot.index) }) { Text("Remove", color = SD.colors.red) }
        }
    }
}

