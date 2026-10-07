package com.spendrop.app.permissions

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LifecycleResumeEffect

/** The explanation shown before asking (Android recommends explaining in context, before the system dialog). */
data class PermissionRationale(val title: String, val message: String, val deniedMessage: String, val fallbackLabel: String? = null)

/** Runs a feature that needs a permission: checks → explains → asks → continues, or offers Settings / a fallback. */
class PermissionGate internal constructor(private val onRun: (() -> Unit) -> Unit) {
    fun run(action: () -> Unit) = onRun(action)
}

/**
 * [requester] asks Android (the default uses the Activity Result API); tests replace it. [onFallback] is offered when
 * access is refused (e.g. "Choose a Photo Instead").
 */
@Composable
fun rememberPermissionGate(
    item: AccessItem,
    rationale: PermissionRationale,
    onFallback: (() -> Unit)? = null,
    manager: PermissionManager = LocalContext.current.applicationContext.let { ctx -> remember(ctx) { PermissionManager(ctx) } },
    requester: ((String, (Boolean) -> Unit) -> Unit)? = null,
): PermissionGate {
    val context = LocalContext.current
    val permission = item.permission!!
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    var dialog by remember { mutableStateOf<PermissionStatus?>(null) }
    var deniedNow by remember { mutableStateOf(false) }
    var openedSettings by remember { mutableStateOf(false) }

    fun handleResult(granted: Boolean) {
        val activity = context.findActivity()
        val outcome = if (activity != null) manager.recordResult(activity, permission, granted) else PermissionRules.outcome(granted, true)
        if (outcome == RequestOutcome.GRANTED) { pending?.invoke(); pending = null } else deniedNow = true
    }

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { handleResult(it) }
    val ask: (String, (Boolean) -> Unit) -> Unit = requester ?: { p, _ -> launcher.launch(p) }

    // Back from the Settings page: if access was given there, continue the feature automatically.
    LifecycleResumeEffect(openedSettings) {
        if (openedSettings && manager.status(item) == PermissionStatus.GRANTED) { pending?.invoke(); pending = null; openedSettings = false }
        onPauseOrDispose {}
    }

    when (dialog) {
        PermissionStatus.NOT_REQUESTED, PermissionStatus.DENIED -> AlertDialog(
            onDismissRequest = { dialog = null; pending = null },
            title = { Text(rationale.title) },
            text = { Text(rationale.message) },
            confirmButton = { TextButton(onClick = { dialog = null; ask(permission) { handleResult(it) } }) { Text("Continue") } },
            dismissButton = { TextButton(onClick = { dialog = null; pending = null }) { Text("Not Now") } },
        )
        PermissionStatus.PERMANENTLY_DENIED -> AlertDialog(
            onDismissRequest = { dialog = null; pending = null },
            title = { Text("${item.title} access is off") },
            text = { Text("${rationale.deniedMessage}\n\nAndroid won't ask again. Open Settings → Permissions → ${item.title} → Allow, then come back: SpenDrop continues automatically.") },
            confirmButton = { TextButton(onClick = { dialog = null; openedSettings = true; context.startActivity(manager.settingsIntent()) }) { Text("Open Settings") } },
            dismissButton = {
                if (onFallback != null && rationale.fallbackLabel != null) TextButton(onClick = { dialog = null; pending = null; onFallback() }) { Text(rationale.fallbackLabel) }
                else TextButton(onClick = { dialog = null; pending = null }) { Text("Cancel") }
            },
        )
        PermissionStatus.NOT_AVAILABLE -> AlertDialog(
            onDismissRequest = { dialog = null },
            title = { Text("${item.title} not available") },
            text = { Text("This phone doesn't have what this feature needs (${item.title.lowercase()}).") },
            confirmButton = {
                if (onFallback != null && rationale.fallbackLabel != null) TextButton(onClick = { dialog = null; onFallback() }) { Text(rationale.fallbackLabel) }
                else TextButton(onClick = { dialog = null }) { Text("OK") }
            },
        )
        else -> Unit
    }
    if (deniedNow) AlertDialog(
        onDismissRequest = { deniedNow = false; pending = null },
        title = { Text("${item.title} access not allowed") },
        text = { Text(rationale.deniedMessage) },
        confirmButton = {
            if (onFallback != null && rationale.fallbackLabel != null) TextButton(onClick = { deniedNow = false; pending = null; onFallback() }) { Text(rationale.fallbackLabel) }
            else TextButton(onClick = { deniedNow = false; pending = null }) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = { deniedNow = false; pending = null }) { Text("Cancel") } },
    )

    return remember(manager, item) {
        PermissionGate { action ->
            when (val s = manager.status(item)) {
                PermissionStatus.GRANTED -> action()
                else -> { pending = action; deniedNow = false; dialog = s }
            }
        }
    }
}
