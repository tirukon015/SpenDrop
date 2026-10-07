package com.spendrop.app.permissions

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Central place for Android permissions. The state always comes from Android (`checkSelfPermission`,
 * `shouldShowRequestPermissionRationale`, hardware features); SpenDrop only remembers whether it already asked and
 * whether the last answer was permanent, which Android itself doesn't report.
 */
class PermissionManager(private val context: Context) {
    private val prefs = context.getSharedPreferences("spendrop_permissions", Context.MODE_PRIVATE)

    fun facts(item: AccessItem, sdkInt: Int = Build.VERSION.SDK_INT): PermissionFacts? {
        val permission = item.permission ?: return null
        val granted = sdkInt >= item.introducedIn && ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        if (granted && prefs.getBoolean("permanent_$permission", false)) prefs.edit().remove("permanent_$permission").apply() // granted in Settings
        return PermissionFacts(
            sdkInt = sdkInt,
            introducedIn = item.introducedIn,
            hardwarePresent = item.hardwareFeature?.let { context.packageManager.hasSystemFeature(it) } ?: true,
            granted = granted,
            requestedBefore = prefs.getBoolean("requested_$permission", false),
            permanentlyDenied = prefs.getBoolean("permanent_$permission", false),
        )
    }

    fun status(item: AccessItem): PermissionStatus? = facts(item)?.let { f ->
        // Install-time permissions are granted by Android at install; if one isn't, it's simply not granted.
        if (!item.runtime) (if (f.granted) PermissionStatus.GRANTED else PermissionStatus.DENIED) else PermissionRules.status(f)
    }

    fun status(permission: String): PermissionStatus =
        status(SpenDropAccess.items.firstOrNull { it.permission == permission } ?: AccessItem(permission, "", permission, runtime = true))!!

    /** Call with Android's result. Reads `shouldShowRequestPermissionRationale` now, as Android recommends. */
    fun recordResult(activity: Activity, permission: String, granted: Boolean): RequestOutcome {
        val outcome = PermissionRules.outcome(granted, ActivityCompat.shouldShowRequestPermissionRationale(activity, permission))
        prefs.edit()
            .putBoolean("requested_$permission", true)
            .putBoolean("permanent_$permission", outcome == RequestOutcome.PERMANENTLY_DENIED)
            .apply()
        return outcome
    }

    /** SpenDrop's page in the system Settings (Permissions are one tap away), for permanently denied permissions. */
    fun settingsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Test / support helper: forget SpenDrop's request history (Android's own state is unchanged). */
    fun clearHistory() = prefs.edit().clear().apply()
}

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
