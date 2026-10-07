package com.spendrop.app.ui.more

import android.os.Build
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.spendrop.app.permissions.AccessItem
import com.spendrop.app.permissions.PermissionManager
import com.spendrop.app.permissions.PermissionRationale
import com.spendrop.app.permissions.PermissionStatus
import com.spendrop.app.permissions.SpenDropAccess
import com.spendrop.app.permissions.rememberPermissionGate
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.theme.SD

/** Label shown for each state. Text and colour come only from Android's real state. */
fun PermissionStatus.label(runtime: Boolean): String = when (this) {
    PermissionStatus.GRANTED -> if (runtime) "✅ Allowed" else "✅ Granted at install"
    PermissionStatus.NOT_REQUESTED -> "⏳ Not requested yet"
    PermissionStatus.DENIED -> if (runtime) "⚠️ Not allowed" else "⚠️ Not granted"
    PermissionStatus.PERMANENTLY_DENIED -> "🚫 Blocked — change in Settings"
    PermissionStatus.NOT_AVAILABLE -> "— Not available on this phone"
}

/**
 * Settings → Permissions & Access. Every row is read from Android each time the screen is shown (and when you come
 * back from the system Settings page). Rows that need no permission say so instead of pretending to be "granted".
 */
@Composable
fun PermissionsScreen(onBack: () -> Unit, openCamera: () -> Unit) {
    val context = LocalContext.current
    val manager = remember { PermissionManager(context.applicationContext) }
    var refresh by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) { refresh++; onPauseOrDispose {} }
    val cameraItem = SpenDropAccess.items.first { it.permission == SpenDropAccess.CAMERA }
    val gate = rememberPermissionGate(
        cameraItem,
        PermissionRationale(
            "Allow camera to photograph receipts?",
            "SpenDrop uses the camera only while you take a photo of a receipt. The photo stays in SpenDrop.",
            "You can allow it later here, or keep using screenshots and the photo picker.",
        ),
        manager = manager,
    )
    SDScreen(title = "Permissions & Access", onBack = onBack) { padding ->
        @Suppress("UNUSED_EXPRESSION") refresh
        LazyColumn(contentPadding = padding) {
            item {
                SectionFooter("Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}. SpenDrop asks only for what a feature needs, when you use it.")
            }
            items(SpenDropAccess.items) { item ->
                val status = remember(refresh) { manager.status(item) }
                SDCard(padding = 16.dp, modifier = Modifier.padding(top = 12.dp)) {
                    Column(Modifier.semantics(mergeDescendants = true) {}) {
                        Text(item.title, style = MaterialTheme.typography.titleMedium)
                        Row(Modifier.padding(top = 2.dp, bottom = 4.dp)) {
                            Text(status?.label(item.runtime) ?: "✅ No permission needed", style = MaterialTheme.typography.labelLarge,
                                color = when (status) {
                                    PermissionStatus.GRANTED, null -> SD.colors.green
                                    PermissionStatus.PERMANENTLY_DENIED, PermissionStatus.DENIED -> SD.colors.orange
                                    else -> SD.colors.secondaryLabel
                                })
                        }
                        Text("Used for: ${item.usedFor}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        item.noPermissionReason?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 4.dp)) }
                        item.permission?.let { Text(it + if (item.runtime) " · runtime" else " · install-time", style = MaterialTheme.typography.labelSmall, color = SD.colors.tertiaryLabel, modifier = Modifier.padding(top = 4.dp)) }
                    }
                    if (item.runtime) Actions(status, onAllow = { gate.run { refresh++; openCamera() } }, onSettings = { context.startActivity(manager.settingsIntent()) })
                }
            }
            item {
                Spacer(Modifier.height(8.dp))
                SectionHeader("Not used")
                SectionFooter("SpenDrop doesn't use notifications, location, contacts, SMS, microphone, or full storage access, so Android lists only Camera under App info → Permissions.")
                Spacer(Modifier.height(32.dp))
            }
        }
    }
}

@Composable
private fun Actions(status: PermissionStatus?, onAllow: () -> Unit, onSettings: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 10.dp)) {
        when (status) {
            PermissionStatus.NOT_REQUESTED -> FilledTonalButton(onClick = onAllow) { Text("Allow", fontWeight = FontWeight.SemiBold) }
            PermissionStatus.DENIED -> FilledTonalButton(onClick = onAllow) { Text("Request Again") }
            PermissionStatus.PERMANENTLY_DENIED -> FilledTonalButton(onClick = onSettings) { Text("Open Settings") }
            PermissionStatus.GRANTED -> OutlinedButton(onClick = onSettings) { Text("Manage in Settings") }
            else -> Unit
        }
    }
}
