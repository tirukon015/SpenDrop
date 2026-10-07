package com.spendrop.app.ui.account

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
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
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.cloud.AuthService
import com.spendrop.app.cloud.AuthState
import com.spendrop.app.cloud.BackupReport
import com.spendrop.app.cloud.DailyBackupWorker
import com.spendrop.app.data.Preferences
import com.spendrop.app.ui.components.ConfirmDialog
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.paybook.Dropdown
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.cloud.CloudBackupProtocol
import com.spendrop.core.cloud.DailyBackupSchedule
import kotlinx.coroutines.launch

class AccountNav(val back: () -> Unit, val email: (EmailAuthMode) -> Unit, val restore: () -> Unit)

/** More → Account (iOS AccountView): optional sign-in, used only for Cloud Backup. Local data never depends on it. */
@Composable
fun AccountScreen(container: AppContainer, nav: AccountNav) {
    val auth = container.auth
    val state by auth.state.collectAsState()
    val cloud = container.cloudBackup
    val running by cloud.running.collectAsState()
    val progress by cloud.progress.collectAsState()
    val prefsData by container.preferences.data.collectAsState(initial = null)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf<BackupReport?>(null) }
    var confirmEnable by remember { mutableStateOf(false) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val sync = container.sync
    val syncing by sync.running.collectAsState()
    val syncLast by sync.last.collectAsState()
    var syncOn by remember { mutableStateOf(false) }
    var syncReport by remember { mutableStateOf<com.spendrop.app.cloud.SyncReport?>(null) }
    var confirmSync by remember { mutableStateOf(false) }
    var otherOwner by remember { mutableStateOf(false) }
    LaunchedEffect(state, running, syncing, syncLast) { enabled = cloud.isEnabled(); report = cloud.lastReport(); syncOn = sync.isEnabled(); syncReport = sync.lastReport() }
    val daily = prefsData?.get(Preferences.Keys.dailyBackupEnabled) ?: true
    val minutes = prefsData?.get(Preferences.Keys.dailyBackupMinutes) ?: DailyBackupSchedule.DEFAULT_MINUTES
    val retention = CloudBackupProtocol.retentionDays(prefsData?.get(Preferences.Keys.retentionDays))
    val timeText = "%02d:%02d".format(minutes / 60, minutes % 60)

    SDScreen(title = "Account", onBack = nav.back) { padding ->
        LazyColumn(contentPadding = padding) {
            when (val s = state) {
                AuthState.NotConfigured -> item {
                    SDCard {
                        ListRow("Cloud backup isn't set up in this build", icon = Icons.Filled.CloudOff, iconTint = SD.colors.gray)
                    }
                    SectionFooter("Everything works on this phone without an account. Developer: add supabase.url and supabase.publishableKey to Android/local.properties (see Android/README.md).")
                }
                is AuthState.SignedOut -> {
                    item {
                        SDCard(padding = 16.dp) {
                            Text("Sign in to enable cloud backup", style = MaterialTheme.typography.titleMedium)
                            Text("Your data stays on this phone either way. Signing in never replaces or deletes local data.", color = SD.colors.secondaryLabel)
                            s.message?.let { Text(it, color = SD.colors.orange, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp)) }
                        }
                        Spacer(Modifier.height(16.dp))
                        SDCard {
                            ListRow("Continue with Google", icon = Icons.Filled.AccountCircle, onClick = {
                                runCatching {
                                    val url = auth.beginGoogleSignIn()
                                    CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url))
                                }.onFailure { error = AuthService.friendlyMessage(it) }
                            })
                            RowDivider(52.dp)
                            ListRow("Sign In with Email", icon = Icons.Filled.Email, onClick = { nav.email(EmailAuthMode.SIGN_IN) })
                            RowDivider(52.dp)
                            ListRow("Create Account", icon = Icons.Filled.PersonAdd, onClick = { nav.email(EmailAuthMode.CREATE) })
                        }
                    }
                }
                is AuthState.SignedIn -> {
                    item {
                        SectionHeader("Profile")
                        SDCard {
                            s.user.name?.let { ListRow("Name", value = it); RowDivider() }
                            ListRow("Email", value = s.user.email ?: "—"); RowDivider()
                            ListRow("Signed in with", value = s.user.providerDisplayName)
                        }
                    }
                    item {
                        SectionHeader("Sync")
                        SDCard {
                            ListRow("Sync with SpenDrop Cloud", subtitle = "Same data here and in SpenDrop on the web", icon = Icons.Filled.Sync, trailing = {
                                Switch(syncOn, { on -> if (on) confirmSync = true else container.appScope.launch { sync.disable(); syncOn = false } })
                            })
                            if (syncOn) {
                                RowDivider()
                                if (syncing) ListRow("Syncing…", trailing = { CircularProgressIndicator(Modifier.height(20.dp)) })
                                else ListRow("Sync Now", titleColor = SD.colors.blue, onClick = { container.appScope.launch { syncReport = sync.syncNow() } })
                                syncReport?.let { r ->
                                    Text("${if (r.succeeded) "Last sync" else "Last attempt"}: ${Fmt.dateTime(r.at)} — ${r.message}",
                                        style = MaterialTheme.typography.bodySmall, color = if (r.succeeded) SD.colors.secondaryLabel else SD.colors.orange,
                                        modifier = Modifier.padding(16.dp))
                                }
                            }
                        }
                        SectionFooter(if (syncOn) "Changes on this phone and on the web appear on both, a few seconds after you're online. Deletes and edits sync too; nothing is lost when offline. iPhone joins through Cloud Backup until it syncs too."
                            else "Off. Turn on to use the same transactions, PayBook and accounts on this phone and on the web.")
                    }
                    item {
                        SectionHeader("Cloud backup")
                        SDCard {
                            ListRow("Cloud Backup", icon = Icons.Filled.CloudUpload, trailing = {
                                Switch(enabled, { on ->
                                    if (on) confirmEnable = true else container.appScope.launch { cloud.setEnabled(false); enabled = false; DailyBackupWorker.schedule(context) }
                                })
                            })
                            if (enabled) {
                                RowDivider()
                                ListRow("Automatic Daily Backup", trailing = {
                                    Switch(daily, { v -> container.appScope.launch { container.preferences.set(Preferences.Keys.dailyBackupEnabled, v); DailyBackupWorker.schedule(context) } })
                                })
                                if (daily) {
                                    RowDivider()
                                    Column(Modifier.padding(horizontal = 16.dp)) {
                                        Dropdown("Backup Time", (0 until 24).map { it * 60 }, (minutes / 60) * 60, { "%02d:00".format(it / 60) }) { m ->
                                            container.appScope.launch { container.preferences.set(Preferences.Keys.dailyBackupMinutes, m); DailyBackupWorker.schedule(context) }
                                        }
                                        Dropdown("Keep Backups For", CloudBackupProtocol.RETENTION_CHOICES.toList(), retention, { "$it days" }) { d ->
                                            container.appScope.launch { container.preferences.set(Preferences.Keys.retentionDays, d) }
                                        }
                                        Spacer(Modifier.height(8.dp))
                                    }
                                }
                                RowDivider()
                                if (running) ListRow(progress ?: "Backing up…", trailing = { CircularProgressIndicator(Modifier.height(20.dp)) })
                                else ListRow(if (report?.succeeded == false) "Retry Backup" else "Back Up Now", titleColor = SD.colors.blue, onClick = {
                                    container.appScope.launch { report = cloud.backUp(automatic = false) }
                                })
                                report?.let { r ->
                                    Text("${if (r.succeeded) "Last backup" else "Last attempt"}: ${Fmt.dateTime(r.at)} — ${r.message}",
                                        style = MaterialTheme.typography.bodySmall, color = if (r.succeeded) SD.colors.secondaryLabel else SD.colors.orange,
                                        modifier = Modifier.padding(16.dp))
                                }
                            }
                            RowDivider()
                            ListRow("Restore from Cloud Backup", icon = Icons.Filled.Restore, chevron = true, onClick = nav.restore)
                        }
                        SectionFooter(
                            if (enabled) "Backs up daily around $timeText when connected. Backups from iPhone and Android with this account can be restored on either. Receipt screenshots aren't part of backups."
                            else "Off. Turn on to keep a private copy of your SpenDrop data in your cloud account. Only you can access it.",
                        )
                    }
                    item {
                        Spacer(Modifier.height(12.dp))
                        SDCard { ListRow("Sign Out", titleColor = SD.colors.blue, onClick = { confirmSignOut = true }) }
                        SectionFooter("Signing out stops cloud backup. Local data remains on this phone.")
                        SDCard { ListRow(if (busy) "Deleting…" else "Delete Cloud Account", titleColor = SD.colors.red, onClick = { if (!busy) confirmDelete = true }) }
                        SectionFooter("Deletes your SpenDrop account and its cloud backups. It does not delete data on this phone.")
                        Spacer(Modifier.height(32.dp))
                    }
                }
            }
        }
    }
    if (confirmEnable) ConfirmDialog(
        "Enable Cloud Backup?",
        "Your SpenDrop data will be securely backed up to your private cloud account: the first backup starts now, then daily around $timeText. Only you can access it. Receipt screenshots are not uploaded. Nothing on this phone is deleted.",
        "Enable Cloud Backup",
        onConfirm = {
            container.appScope.launch {
                cloud.setEnabled(true); enabled = true
                report = cloud.backUp(automatic = false)
                DailyBackupWorker.schedule(context)
            }
        },
        onDismiss = { confirmEnable = false },
    )
    if (confirmSync) ConfirmDialog(
        "Sync this phone with your SpenDrop account?",
        "Your SpenDrop records on this phone are uploaded to your private cloud account, and records from the web come here. Records keep their identity, so nothing is duplicated, and nothing on this phone is deleted. Sample data and receipt screenshots stay on this phone.",
        "Start Syncing",
        onConfirm = {
            container.appScope.launch {
                if (sync.enable()) { syncOn = true; syncReport = sync.syncNow() } else otherOwner = true
            }
        },
        onDismiss = { confirmSync = false },
    )
    if (otherOwner) ConfirmDialog(
        "This phone is synced with another account",
        "The data on this phone already belongs to a different SpenDrop account, so it can't be mixed with this one. Sign in with that account, or start fresh: this phone's records are removed and this account's records are downloaded. (Make an export in Settings first if you want a copy.)",
        "Start Fresh", destructive = true,
        onConfirm = { container.appScope.launch { sync.startFreshForCurrentUser(); syncOn = true; syncReport = sync.syncNow() } },
        onDismiss = { otherOwner = false },
    )
    if (confirmSignOut) ConfirmDialog("Sign out?", "Local data remains on this phone. Cloud backup stops until you sign in again.", "Sign Out", destructive = true,
        onConfirm = { container.appScope.launch { sync.disable(); auth.signOut(); DailyBackupWorker.schedule(context) } }, onDismiss = { confirmSignOut = false })
    if (confirmDelete) ConfirmDialog("Delete your cloud account?", "This permanently deletes your SpenDrop account and all cloud backups. Data on this phone is NOT deleted.",
        "Delete Cloud Account", destructive = true,
        onConfirm = {
            busy = true
            container.appScope.launch {
                try { auth.deleteAccount { cloud.deleteAllCloudData() }; cloud.setEnabled(false); DailyBackupWorker.schedule(context) }
                catch (e: Exception) { error = (e as? com.spendrop.app.cloud.CloudError)?.message ?: "Couldn't delete the account. Please try again." }
                finally { busy = false }
            }
        }, onDismiss = { confirmDelete = false })
    error?.let { MessageDialog("Couldn't complete", it) { error = null } }
}
