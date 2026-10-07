package com.spendrop.app.ui.importing

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.spendrop.app.AppContainer
import com.spendrop.app.container
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.importing.ImportOutcome
import com.spendrop.app.importing.ImportProcessor
import com.spendrop.app.importing.Intake
import com.spendrop.app.importing.IntakeItem
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.theme.SD
import com.spendrop.app.ui.transaction.EditorMode
import com.spendrop.app.ui.transaction.EditorViewModel
import com.spendrop.app.ui.transaction.TransactionEditorScreen
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.parser.ParsedTransaction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

sealed interface ImportPhase {
    object Receiving : ImportPhase
    data class Processing(val item: IntakeItem) : ImportPhase
    data class Review(val key: String, val parsed: ParsedTransaction, val imageFile: File?, val sourceType: ExpenseSourceType) : ImportPhase
    data class NoDetails(val outcome: ImportOutcome.NoDetails) : ImportPhase
    data class Failed(val outcome: ImportOutcome.Failed) : ImportPhase
    data class Done(val saved: Int, val total: Int) : ImportPhase
}

data class ImportUi(val phase: ImportPhase = ImportPhase.Receiving, val index: Int = 0, val total: Int = 0, val saved: Int = 0)

/** Holds the queue of shared / picked items across configuration changes; items are processed one at a time. */
class ImportFlowViewModel(app: Application) : AndroidViewModel(app) {
    private val processor = ImportProcessor(app)
    private var items: List<IntakeItem> = emptyList()
    private val _ui = MutableStateFlow(ImportUi())
    val ui: StateFlow<ImportUi> = _ui
    private var started = false

    /** Idempotent: a re-delivered intent / recreated activity does not process the same items twice. */
    fun start(load: suspend () -> List<IntakeItem>) {
        if (started) return
        started = true
        viewModelScope.launch {
            items = withContext(Dispatchers.IO) { load() }
            if (items.isEmpty()) {
                _ui.value = ImportUi(ImportPhase.Failed(ImportOutcome.Failed(IntakeItem.Unreadable("none", null, "Nothing to import"), "SpenDrop didn't receive a screenshot, PDF or text. Try sharing again.")), 0, 0)
                return@launch
            }
            _ui.value = ImportUi(index = 0, total = items.size)
            processCurrent()
        }
    }

    private fun processCurrent() {
        val i = _ui.value.index
        val item = items.getOrNull(i) ?: return finish()
        _ui.value = _ui.value.copy(phase = ImportPhase.Processing(item))
        viewModelScope.launch {
            _ui.value = _ui.value.copy(phase = when (val out = processor.process(item)) {
                is ImportOutcome.Parsed -> ImportPhase.Review("${item.id}-$i", out.parsed, out.imageFile, out.sourceType)
                is ImportOutcome.NoDetails -> ImportPhase.NoDetails(out)
                is ImportOutcome.Failed -> ImportPhase.Failed(out)
            })
        }
    }

    fun retry() = processCurrent()

    fun enterManually(o: ImportOutcome.NoDetails) {
        _ui.value = _ui.value.copy(phase = ImportPhase.Review("${o.item.id}-manual", ParsedTransaction(), o.imageFile,
            if (o.item is IntakeItem.Pdf) ExpenseSourceType.RECEIPT else ExpenseSourceType.SCREENSHOT))
    }

    fun next(saved: Boolean) {
        val u = _ui.value
        items.getOrNull(u.index)?.let { Intake.discard(it) }
        val nextIndex = u.index + 1
        _ui.value = u.copy(index = nextIndex, saved = u.saved + if (saved) 1 else 0)
        if (nextIndex >= items.size) finish() else processCurrent()
    }

    private fun finish() { _ui.value = _ui.value.copy(phase = ImportPhase.Done(_ui.value.saved, items.size)) }

    override fun onCleared() { items.forEach { Intake.discard(it) } }
}

/**
 * The import flow (share target and in-app import): "SpenDrop received your screenshot" → reading → review → save.
 * [onFinished] is called when every item has been saved, skipped or cancelled.
 */
@Composable
fun ImportFlowScreen(container: AppContainer, load: suspend () -> List<IntakeItem>, fromShare: Boolean, onFinished: (savedCount: Int) -> Unit) {
    val flow: ImportFlowViewModel = viewModel()
    LaunchedEffect(Unit) { flow.start(load) }
    val ui by flow.ui.collectAsState()
    val counter = if (ui.total > 1) " (${(ui.index + 1).coerceAtMost(ui.total)} of ${ui.total})" else ""
    when (val p = ui.phase) {
        ImportPhase.Receiving -> Status("Receiving$counter", { onFinished(ui.saved) }) {
            Progress("Receiving screenshot…", "SpenDrop received your file.")
        }
        is ImportPhase.Processing -> Status("SpenDrop$counter", { onFinished(ui.saved) }) {
            Preview((p.item as? IntakeItem.Image)?.file)
            Progress(if (p.item is IntakeItem.Pdf) "Reading PDF…" else "Reading payment details…", "Extracting merchant, amount & category on-device")
        }
        is ImportPhase.Review -> key(p.key) {
            val vm: EditorViewModel = viewModel(key = p.key, factory = EditorViewModel.Factory(container))
            LaunchedEffect(p.key) { vm.startReview(p.parsed, p.imageFile, if (fromShare) ExpenseSourceType.SHARE_EXTENSION else p.sourceType) }
            TransactionEditorScreen(container, EditorMode.Review, onClose = { flow.next(saved = false) }, vm = vm, onSaved = { flow.next(saved = true) })
        }
        is ImportPhase.NoDetails -> Status("SpenDrop$counter", { flow.next(false) }) {
            Preview(p.outcome.imageFile)
            Icon(Icons.Filled.DocumentScanner, null, tint = SD.colors.orange, modifier = Modifier.size(48.dp))
            Text("Couldn't read payment details", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(p.outcome.message, textAlign = TextAlign.Center, color = SD.colors.secondaryLabel)
            Button(onClick = { flow.enterManually(p.outcome) }, modifier = Modifier.fillMaxWidth()) { Text("Enter Details Manually") }
            OutlinedButton(onClick = flow::retry, modifier = Modifier.fillMaxWidth()) { Text("Retry") }
            TextButton(onClick = { flow.next(false) }) { Text(if (ui.index + 1 < ui.total) "Skip" else "Cancel") }
        }
        is ImportPhase.Failed -> Status("SpenDrop$counter", { flow.next(false) }) {
            Icon(Icons.Filled.ErrorOutline, null, tint = SD.colors.orange, modifier = Modifier.size(48.dp))
            Text(p.outcome.item.let { (it as? IntakeItem.Unreadable)?.displayName } ?: "Couldn't import", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(p.outcome.message, textAlign = TextAlign.Center, color = SD.colors.secondaryLabel)
            Button(onClick = { if (ui.total == 0) onFinished(0) else flow.next(false) }) { Text(if (ui.index + 1 < ui.total) "Skip" else "Close") }
        }
        is ImportPhase.Done -> LaunchedEffect(Unit) { onFinished(p.saved) }
    }
}

@Composable
private fun Status(title: String, onCancel: () -> Unit, content: @Composable () -> Unit) {
    SDScreen(title = title, onBack = onCancel) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        ) { content() }
    }
}

@Composable
private fun Progress(title: String, subtitle: String) {
    CircularProgressIndicator()
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    Text(subtitle, color = SD.colors.secondaryLabel, textAlign = TextAlign.Center)
}

@Composable
private fun Preview(file: File?) {
    val bmp by produceState<Bitmap?>(null, file) { value = withContext(Dispatchers.IO) { file?.let { runCatching { ImageTools.decodeOriented(it, 900) }.getOrNull() } } }
    bmp?.let { Image(it.asImageBitmap(), "Shared screenshot", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth().heightIn(max = 280.dp).clip(RoundedCornerShape(14.dp))) }
    Spacer(Modifier.height(4.dp))
}
