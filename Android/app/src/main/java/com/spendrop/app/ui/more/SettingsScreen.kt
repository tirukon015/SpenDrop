package com.spendrop.app.ui.more

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.BuildConfig
import com.spendrop.app.cloud.AuthState
import com.spendrop.app.data.Changes
import com.spendrop.app.data.Preferences
import com.spendrop.app.ui.account.RestoreSource
import com.spendrop.app.ui.account.saveSafetyCopy
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.LoadingState
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.PhotoStore
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.components.Segmented
import com.spendrop.app.ui.theme.Appearance
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.parser.ParserSelfTest
import com.spendrop.core.sample.SampleData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** Settings (iOS SettingsView). */
@Composable
fun SettingsScreen(container: AppContainer, onBack: () -> Unit, openRestore: () -> Unit, openSelfTest: () -> Unit, openPermissions: () -> Unit = {}) {
    val snapshot by container.repository.snapshot.collectAsState()
    val authState by container.auth.state.collectAsState()
    val appearance by container.preferences.string(Preferences.Keys.appearance, "system").collectAsState("system")
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf<Pair<String, String>?>(null) }
    var confirm by remember { mutableStateOf<String?>(null) }
    var storage by remember { mutableStateOf<Pair<Int, Long>?>(null) }
    LaunchedEffect(snapshot) {
        storage = withContext(Dispatchers.IO) { PhotoStore.receiptsDir(context).listFiles()?.let { it.size to it.sumOf { f -> f.length() } } ?: (0 to 0L) }
    }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        if (uri != null) scope.launch {
            val ok = withContext(Dispatchers.IO) { runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(BackupCodec.encodeToBytes(container.cloudBackup.makePayload())) } != null }.getOrDefault(false) }
            message = if (ok) "Backup Exported" to "Your complete SpenDrop backup was saved. It can be imported on Android or iPhone." else "Export Failed" to "The backup file couldn't be written."
        }
    }
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) scope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { context.contentResolver.openInputStream(uri)?.use { BackupCodec.decode(it.readBytes()) } } }
            val payload = result.getOrNull()
            if (payload == null) message = "Import Failed" to (result.exceptionOrNull()?.message ?: "This file isn't a SpenDrop backup or it is damaged. Nothing was imported.")
            else { container.restoreSource.value = RestoreSource("Backup file", "Exported ${Fmt.dateTime(payload.exportDate)} · format ${payload.version}", payload = payload); openRestore() }
        }
    }

    SDScreen(title = "Settings", onBack = onBack) { padding ->
        val s = snapshot ?: return@SDScreen LoadingState(modifier = Modifier.padding(padding))
        val sampleLoaded = SampleData.isLoaded(s)
        LazyColumn(contentPadding = padding) {
            item {
                SectionHeader("Backup & data recovery")
                SDCard {
                    ListRow("Stored Transactions", value = "${s.expenses.size}"); RowDivider()
                    ListRow("Money Records", value = "${s.movements.size}"); RowDivider()
                    ListRow("PayBook Profiles", value = "${s.people.size}"); RowDivider()
                    ListRow("Restore from Local Backup", subtitle = "Merges your newest automatic backup on this phone. Nothing is deleted.", icon = Icons.Filled.Restore, onClick = {
                        scope.launch {
                            val p = withContext(Dispatchers.IO) { container.localBackup.latest() }
                            if (p == null) message = "No Local Backup" to "No automatic backup has been saved on this phone yet."
                            else { container.restoreSource.value = RestoreSource("Local automatic backup", "Saved ${Fmt.dateTime(p.exportDate)}", payload = p); openRestore() }
                        }
                    }); RowDivider()
                    ListRow("Export Backup (JSON)", subtitle = "Save a complete backup file to Files, Drive or another app", icon = Icons.Filled.Upload, onClick = { export.launch("SpenDrop_Backup_${LocalDate.now()}.json") }); RowDivider()
                    ListRow("Import Backup File (JSON)", subtitle = "Restore transactions and PayBook from a saved JSON file (Android or iPhone)", icon = Icons.Filled.Download, onClick = { import.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }); RowDivider()
                    ListRow("Persistent Auto-Backup", value = "Active", valueColor = SD.colors.green)
                }
            }
            item {
                SectionHeader("Preferences")
                SDCard(padding = 8.dp) {
                    Text("Appearance", modifier = Modifier.padding(horizontal = 8.dp))
                    Segmented(Appearance.entries, Appearance.fromRaw(appearance), { it.label }, { a -> scope.launch { container.preferences.set(Preferences.Keys.appearance, a.raw) } })
                }
                SectionFooter("Amounts are recorded in RM, like SpenDrop on iPhone.")
            }
            item {
                SectionHeader("Screenshot storage")
                SDCard {
                    ListRow("Screenshots", value = "${storage?.first ?: 0}"); RowDivider()
                    ListRow("Total size", value = storage?.second?.let { "%.1f MB".format(it / 1_048_576.0) } ?: "—"); RowDivider()
                    ListRow("Average", value = storage?.let { (n, b) -> if (n == 0) "—" else "%.0f KB".format(b / 1024.0 / n) } ?: "—")
                }
                SectionFooter("Screenshots are saved small (long edge 1800 px, JPEG) in SpenDrop's private storage and stay readable. They are not part of backups.")
            }
            item {
                SectionHeader("Sample data")
                SDCard {
                    if (!sampleLoaded) ListRow("Load Sample Data", subtitle = "Explore SpenDrop with example transactions", icon = Icons.Filled.Science, onClick = { confirm = "loadSample" })
                    else ListRow("Remove Sample Data", subtitle = "Remove example transactions and demo data", icon = Icons.Filled.Delete, iconTint = SD.colors.red, titleColor = SD.colors.red, onClick = { confirm = "removeSample" })
                }
                SectionFooter("Sample records are kept separate from your own and can be removed at any time without affecting your real data.")
            }
            item {
                SectionHeader("Testing & diagnostics")
                SDCard {
                    ListRow("Run OCR & Parser Self-Test", icon = Icons.Filled.FactCheck, chevron = true, onClick = openSelfTest); RowDivider()
                    ListRow("Clear All Expenses", icon = Icons.Filled.Delete, iconTint = SD.colors.red, titleColor = SD.colors.red, onClick = { confirm = "clear" })
                }
            }
            item {
                SectionHeader("Privacy & security")
                SDCard { ListRow("Permissions & Access", subtitle = "What SpenDrop can use on this phone, straight from Android", icon = Icons.Filled.Verified, chevron = true, onClick = openPermissions) }
                androidx.compose.foundation.layout.Spacer(Modifier.height(12.dp))
                SDCard(padding = 16.dp) {
                    Text("100% Local-First", fontWeight = FontWeight.SemiBold)
                    Text("SpenDrop never asks for your bank login, passwords, OTPs, or card PINs. OCR and transaction parsing run entirely on your phone. Cloud backup is optional and private to your account.",
                        color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall)
                }
            }
            item {
                SectionHeader("About")
                SDCard {
                    ListRow("App Name", value = "SpenDrop"); RowDivider()
                    ListRow("Developer", subtitle = "SpenDrop is designed and built by Touhidul Islam Rukon.", value = "Touhidul Islam Rukon"); RowDivider()
                    ListRow("Version", value = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"); RowDivider()
                    ListRow("Device", value = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"); RowDivider()
                    ListRow("Storage Engine", value = "Room (on device) + Auto-Backup"); RowDivider()
                    ListRow("OCR Engine", value = "Google ML Kit (on device)")
                }
                Spacer(Modifier.height(32.dp))
            }
        }
        when (confirm) {
            "loadSample" -> ConfirmDialog("Load Sample Data?", "This will add example expenses, people, splits, settlements, and other demonstration data so you can explore how SpenDrop works.",
                "Load Sample Data", onConfirm = {
                    scope.launch {
                        val set = runCatching { SampleData.load(s, System.currentTimeMillis(), CalendarContext.device()) }
                            .onFailure { message = "Couldn't Load Sample Data" to (it.message ?: it.javaClass.simpleName) }.getOrNull()
                        if (set == null) { if (message == null) message = "Sample Data" to "Sample data is already loaded."; return@launch }
                        run {
                            container.repository.apply(Changes(people = set.people, paymentMethods = set.paymentMethods, accounts = set.accounts, expenses = set.expenses,
                                shares = set.shares, movements = set.movements, allocations = set.allocations, sampleRecords = set.sampleRecords))
                            message = "Sample Data Loaded" to "Example people are marked \"(Sample)\". Use \"Remove Sample Data\" in Settings to take everything out again."
                        }
                    }
                }, onDismiss = { confirm = null })
            "removeSample" -> ConfirmDialog("Remove Sample Data?", "This will remove the example data previously added by SpenDrop. Your real transactions and data will not be affected.",
                "Remove Sample Data", destructive = true, onConfirm = {
                    scope.launch {
                        val plan = SampleData.removalPlan(s, System.currentTimeMillis())
                        val t = System.currentTimeMillis()
                        fun <T> gone(list: List<T>, ids: Set<String>, id: (T) -> String, kill: (T) -> T) = list.filter { id(it) in ids }.map(kill)
                        container.repository.apply(Changes(
                            expenses = gone(s.expenses, plan.expenseIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            shares = gone(s.shares, plan.shareIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            movements = gone(s.movements, plan.movementIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) } + plan.unlinkedMovements,
                            allocations = gone(s.allocations, plan.allocationIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            paymentMethods = gone(s.paymentMethods, plan.paymentMethodIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            people = gone(s.people, plan.personIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            accounts = gone(s.accounts, plan.accountIds, { it.id }) { it.copy(deletedAt = t, updatedAt = t) },
                            removeSampleRecordIds = plan.sampleRecordIds.toList(),
                        ))
                        message = "Sample Data Removed" to "${plan.report.total} example records were removed."
                    }
                }, onDismiss = { confirm = null })
            "clear" -> ConfirmDialog("Clear All Expenses?", "This will delete all ${s.expenses.size} expenses stored on this phone. A safety copy is saved first.", "Clear Everything", destructive = true,
                onConfirm = {
                    scope.launch {
                        withContext(Dispatchers.IO) { runCatching { saveSafetyCopy(context, container) } }
                        val t = System.currentTimeMillis()
                        container.repository.apply(Changes(expenses = s.expenses.map { it.copy(deletedAt = t, updatedAt = t) }, shares = s.shares.map { it.copy(deletedAt = t, updatedAt = t) }))
                    }
                }, onDismiss = { confirm = null })
        }
        message?.let { (t, m) -> MessageDialog(t, m) { message = null } }
    }
}

@Composable
fun ParserSelfTestScreen(onBack: () -> Unit) {
    var results by remember { mutableStateOf<List<ParserSelfTest.Result>?>(null) }
    var running by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    SDScreen(title = "Parser Self-Test", onBack = onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            item {
                val r = results
                val all = r != null && r.all { it.passed }
                SDCard(padding = 16.dp) {
                    Text(if (all) "All Tests Passed (${r!!.size}/${r.size})" else "Parser & Duplicate Verification", style = MaterialTheme.typography.titleMedium)
                    Text("Automated validation of Malaysian payment screenshots, false positives, balances, multi-amounts, and duplicate detection.", color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(12.dp))
                SDCard { ListRow(if (running) "Running…" else "Run Tests", titleColor = SD.colors.blue, onClick = {
                    running = true
                    scope.launch { results = withContext(Dispatchers.Default) { ParserSelfTest.run() }; running = false }
                }) }
                SectionHeader("Test results")
            }
            val r = results
            if (r == null) item { Text("No test run yet. Tap 'Run Tests' above.", color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 32.dp)) }
            else r.forEach { res ->
                item {
                    SDCard(padding = 12.dp) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (res.passed) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null, tint = if (res.passed) SD.colors.green else SD.colors.red)
                            Spacer(Modifier.width(8.dp))
                            Text(res.testName, fontWeight = FontWeight.SemiBold)
                        }
                        Text(res.details, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        Text("Actual: ${res.actual}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
    }
}
