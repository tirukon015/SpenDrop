package com.spendrop.app.ui.account

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.cloud.CloudError
import com.spendrop.app.data.applyMerge
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.DayField
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.BackupPayload
import com.spendrop.core.backup.BackupRestore
import com.spendrop.core.backup.LocalRecordIds
import com.spendrop.core.backup.RecordCounts
import com.spendrop.core.backup.RestoreRange
import com.spendrop.core.classify.TransactionClassifier
import com.spendrop.core.cloud.CloudBackupRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

/** A backup to restore from: a cloud record (downloaded on demand) or an already-read JSON file. */
data class RestoreSource(val title: String, val detail: String?, val cloud: CloudBackupRecord? = null, val payload: BackupPayload? = null)

/** List of cloud backups (all of this account's devices, newest first). */
@Composable
fun CloudRestoreScreen(container: AppContainer, onBack: () -> Unit, onChoose: () -> Unit) {
    var records by remember { mutableStateOf<List<CloudBackupRecord>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        try { records = container.cloudBackup.list() } catch (e: Exception) { error = (e as? CloudError)?.message ?: "Couldn't load backups."; records = emptyList() }
    }
    SDScreen(title = "Restore from Cloud Backup", onBack = onBack) { padding ->
        val list = records ?: return@SDScreen LoadingState("Loading backups…", Modifier.padding(padding))
        LazyColumn(contentPadding = padding) {
            error?.let { item { Text(it, color = SD.colors.orange, modifier = Modifier.padding(16.dp)) } }
            if (list.isEmpty() && error == null) item { Text("No cloud backups yet.", color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp)) }
            itemsIndexed(list) { i, r ->
                SDCard(padding = 0.dp) {
                    ListRow(
                        Fmt.dateTime(r.createdAt),
                        subtitle = "${if (i == 0) "Latest Backup" else "Older Backup"} · ${r.deviceName} · app ${r.appVersion} · format ${r.backupVersion}\n" +
                            "${r.expensesCount} expenses · ${r.accountsCount} accounts · ${r.movementsCount} money records · ${r.peopleCount} PayBook",
                        chevron = true,
                        onClick = {
                            container.restoreSource.value = RestoreSource("Backup from ${Fmt.dateTime(r.createdAt)}", "${r.deviceName} · format ${r.backupVersion}", cloud = r)
                            onChoose()
                        },
                    )
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

private enum class RangeOption(val title: String) {
    EVERYTHING("Everything"), LAST_7("Last 7 days"), LAST_30("Last 30 days"), LAST_2M("Last 2 months"), LAST_3M("Last 3 months"), CUSTOM("Custom range")
}

/** Choose what to restore, preview it, then merge (iOS RestoreRangeView). */
@Composable
fun RestoreRangeScreen(container: AppContainer, onBack: () -> Unit, onDone: () -> Unit) {
    val source by container.restoreSource.collectAsState()
    val src = source
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    var payload by remember { mutableStateOf(src?.payload) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var option by remember { mutableStateOf(RangeOption.EVERYTHING) }
    var start by remember { mutableStateOf(LocalDate.now(zone).minusDays(30)) }
    var end by remember { mutableStateOf(LocalDate.now(zone)) }
    var confirming by remember { mutableStateOf(false) }
    var resultText by remember { mutableStateOf<String?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(src) {
        if (payload == null && src?.cloud != null) {
            try { payload = container.cloudBackup.download(src.cloud) } catch (e: Exception) { loadError = (e as? CloudError)?.message ?: "Couldn't download this backup." }
        }
    }
    val range = when (option) {
        RangeOption.EVERYTHING -> RestoreRange.Everything
        RangeOption.LAST_7 -> RestoreRange.LAST_7_DAYS
        RangeOption.LAST_30 -> RestoreRange.LAST_30_DAYS
        RangeOption.LAST_2M -> RestoreRange.LAST_2_MONTHS
        RangeOption.LAST_3M -> RestoreRange.LAST_3_MONTHS
        RangeOption.CUSTOM -> RestoreRange.Custom(start.atStartOfDay(zone).toInstant().toEpochMilli(), end.atStartOfDay(zone).toInstant().toEpochMilli())
    }
    val problem = range.validationProblem(zone)
    // Computed only when the backup or the chosen range changes (not on every recomposition).
    val plan = remember(payload, option, start, end) {
        val p = payload
        if (problem == null && p != null) BackupRestore.makeRestorePlan(p, range, zone, LocalRecordIds.from(container.repository.snapshot.value ?: com.spendrop.core.model.FinanceSnapshot()), TransactionClassifier::ruleKey) else null
    }
    SDScreen(title = "Restore", onBack = { if (!working) onBack() }) { padding ->
        if (src == null) return@SDScreen Text("Nothing selected.", Modifier.padding(padding).padding(16.dp))
        LazyColumn(contentPadding = padding) {
            item {
                SectionHeader(src.title)
                src.detail?.let { SectionFooter(it) }
                payload?.let { p ->
                    val c = p.recordCount
                    SectionFooter("Backup contains ${describe(RecordCounts(c.expenses, c.accounts, c.movements, c.profiles, c.rules))}.")
                }
            }
            loadError?.let { item { Text(it, color = SD.colors.orange, modifier = Modifier.padding(16.dp)) } }
            val p = payload
            if (p == null && loadError == null) item { LoadingState("Loading backup…") }
            if (p != null) {
                item {
                    SectionHeader("Restore")
                    SDCard {
                        RangeOption.entries.forEachIndexed { i, o ->
                            ListRow(o.title, onClick = { option = o }, trailing = { RadioButton(option == o, { option = o }) })
                            if (i < RangeOption.entries.lastIndex) RowDivider()
                        }
                    }
                    if (option == RangeOption.CUSTOM) {
                        SectionHeader("Custom range")
                        SDCard { DayField(start, { start = it }, "From"); DayField(end, { end = it }, "To") }
                    }
                }
                item {
                    SectionHeader("Selected range")
                    SDCard(padding = 16.dp) {
                        Text(plan?.interval?.description(zone) ?: range.title)
                        when {
                            problem != null -> Text(problem, color = SD.colors.orange)
                            plan == null || plan.isEmpty -> Text("No records in this range.", color = SD.colors.secondaryLabel)
                            else -> Text("Records found: " + describe(plan.counts), color = SD.colors.secondaryLabel)
                        }
                    }
                    SectionFooter("Restoring adds and merges records by ID. Nothing on this phone is deleted or duplicated. Receipt screenshots aren't part of backups.")
                    Button(onClick = { confirming = true }, enabled = plan != null && !plan.isEmpty && !working, modifier = Modifier.padding(16.dp)) { Text(if (working) "Restoring…" else "Continue") }
                }
                if (confirming && plan != null) {
                    item {
                        ConfirmDialog(
                            "Restore ${describe(plan.counts)}?",
                            "Date range: ${plan.interval?.description(zone) ?: "Everything"}\n\n" +
                                (if (plan.alreadyOnDevice.total > 0) "${describe(plan.alreadyOnDevice)} already on this phone will be merged, not duplicated.\n" else "") +
                                "A safety copy of your current data is saved first.",
                            "Restore",
                            onConfirm = {
                                working = true
                                // App scope: a restore that has started finishes even if the user leaves this screen.
                                container.appScope.launch {
                                    try {
                                        withContext(Dispatchers.IO) { saveSafetyCopy(context, container) }
                                        val local = container.repository.fullSnapshot(includeDeleted = true)
                                        val result = withContext(Dispatchers.Default) { BackupRestore.applyRestorePlan(plan, local, System.currentTimeMillis(), zone) }
                                        container.repository.applyMerge(result.merge)
                                        resultText = "Added ${describe(result.added)}. ${result.summary.expensesUpdated} expenses updated; ${result.summary.expensesKeptNewer} kept because this phone's copy is newer."
                                    } catch (e: Exception) {
                                        failure = if (e is SafetyCopyFailed) CloudError.SafetyBackupFailed.message else "Restore failed: ${e.message ?: "unknown error"}. Nothing was changed."
                                    } finally { working = false }
                                }
                            },
                            onDismiss = { confirming = false },
                        )
                    }
                }
            }
        }
    }
    resultText?.let { MessageDialog("Restore Complete", it) { resultText = null; container.restoreSource.value = null; onDone() } }
    failure?.let { MessageDialog("Restore Failed", it) { failure = null } }
}

class SafetyCopyFailed(cause: Throwable) : Exception(cause)

/** Before any restore/import: the current local data as a backup file in app storage (newest 5 kept). */
suspend fun saveSafetyCopy(context: Context, container: AppContainer) {
    try {
        val dir = File(context.filesDir, "SpenDropBackupHistory").apply { mkdirs() }
        val bytes = BackupCodec.encodeToBytes(container.cloudBackup.makePayload())
        File(dir, "before-restore-${System.currentTimeMillis()}.json").writeBytes(bytes)
        dir.listFiles { f -> f.name.startsWith("before-restore-") }?.sortedByDescending { it.name }?.drop(5)?.forEach { it.delete() }
    } catch (e: Exception) { throw SafetyCopyFailed(e) }
}

fun describe(c: RecordCounts): String {
    fun item(n: Int, one: String, many: String) = "$n ${if (n == 1) one else many}"
    return listOf(
        item(c.expenses, "expense", "expenses"), item(c.movements, "money record", "money records"),
        item(c.accounts, "account", "accounts"), item(c.profiles, "person", "people"),
    ).joinToString(", ")
}
