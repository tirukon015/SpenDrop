package com.spendrop.app.permissions

/** What Android currently says about one permission, as SpenDrop shows it. Never inferred from app features. */
enum class PermissionStatus {
    /** Android reports the permission as granted. */
    GRANTED,
    /** Declared, but SpenDrop has not asked yet (Android shows nothing in App info until the first request). */
    NOT_REQUESTED,
    /** Asked and refused; Android will still show its dialog if asked again. */
    DENIED,
    /** Refused with "Don't ask again" (or twice on Android 11+): only the system Settings page can grant it now. */
    PERMANENTLY_DENIED,
    /** Doesn't exist on this Android version, or this phone lacks the hardware (e.g. no camera). */
    NOT_AVAILABLE,
}

/** Raw facts read from Android plus SpenDrop's record of past requests. */
data class PermissionFacts(
    val sdkInt: Int,
    /** First Android API level where the permission exists (e.g. 33 for POST_NOTIFICATIONS). */
    val introducedIn: Int = 1,
    val hardwarePresent: Boolean = true,
    val granted: Boolean,
    /** SpenDrop asked at least once and the user answered. */
    val requestedBefore: Boolean,
    /** The last answer was a refusal Android will no longer show a dialog for. */
    val permanentlyDenied: Boolean,
)

/** What to remember after Android returns a permission result. */
enum class RequestOutcome { GRANTED, DENIED, PERMANENTLY_DENIED }

/**
 * Pure rules (unit-tested). Android doesn't expose "not requested yet" vs "permanently denied" directly; the standard
 * way is: granted → GRANTED; otherwise use SpenDrop's own record of past answers, which is updated from
 * `shouldShowRequestPermissionRationale` right after each request (false after a refusal = no more dialogs).
 */
object PermissionRules {
    fun status(f: PermissionFacts): PermissionStatus = when {
        f.sdkInt < f.introducedIn || !f.hardwarePresent -> PermissionStatus.NOT_AVAILABLE
        f.granted -> PermissionStatus.GRANTED
        f.permanentlyDenied -> PermissionStatus.PERMANENTLY_DENIED
        f.requestedBefore -> PermissionStatus.DENIED
        else -> PermissionStatus.NOT_REQUESTED
    }

    /** [canAskAgain] = `shouldShowRequestPermissionRationale` read immediately after the result. */
    fun outcome(granted: Boolean, canAskAgain: Boolean): RequestOutcome = when {
        granted -> RequestOutcome.GRANTED
        canAskAgain -> RequestOutcome.DENIED
        else -> RequestOutcome.PERMANENTLY_DENIED
    }
}

/** How SpenDrop gets each kind of access, for the Permissions & Access screen. */
data class AccessItem(
    val title: String,
    val usedFor: String,
    /** Null = handled without any Android permission (photo picker, file picker, share sheet). */
    val permission: String?,
    val runtime: Boolean,
    val introducedIn: Int = 1,
    val hardwareFeature: String? = null,
    val noPermissionReason: String? = null,
)

object SpenDropAccess {
    const val CAMERA = android.Manifest.permission.CAMERA

    val items = listOf(
        AccessItem("Camera", "Take Photo of Receipt (in-app camera)", CAMERA, runtime = true, hardwareFeature = "android.hardware.camera.any"),
        AccessItem("Photos & screenshots", "Scan a screenshot, Share → SpenDrop", null, runtime = false,
            noPermissionReason = "No permission needed: you pick each photo with the Android photo picker or share it to SpenDrop, so SpenDrop never reads your gallery."),
        AccessItem("Files & PDFs", "PDF receipts, backup import/export", null, runtime = false,
            noPermissionReason = "No permission needed: you choose each file with the Android file picker."),
        AccessItem("Internet", "Sign-in, sync, cloud backup", android.Manifest.permission.INTERNET, runtime = false),
    )
}
