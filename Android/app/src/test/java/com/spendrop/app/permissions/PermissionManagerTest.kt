package com.spendrop.app.permissions

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** The manager reads Android's real state (Robolectric's PackageManager) and records request answers. */
@RunWith(AndroidJUnit4::class)
/** Android 11 (API 30), the OPPO's version. */
@Config(sdk = [30])
open class PermissionManagerTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val camera = SpenDropAccess.items.first { it.permission == Manifest.permission.CAMERA }
    private lateinit var manager: PermissionManager

    @Before fun setUp() {
        manager = PermissionManager(app).also { it.clearHistory() }
        shadowOf(app.packageManager).setSystemFeature("android.hardware.camera.any", true)
        shadowOf(app).denyPermissions(Manifest.permission.CAMERA)
    }

    @Test fun lifecycle_notRequested_denied_permanent_granted() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        assertEquals(PermissionStatus.NOT_REQUESTED, manager.status(camera))

        shadowOf(app.packageManager).setShouldShowRequestPermissionRationale(Manifest.permission.CAMERA, true)
        assertEquals(RequestOutcome.DENIED, manager.recordResult(activity, Manifest.permission.CAMERA, granted = false))
        assertEquals(PermissionStatus.DENIED, manager.status(camera))

        shadowOf(app.packageManager).setShouldShowRequestPermissionRationale(Manifest.permission.CAMERA, false)
        assertEquals(RequestOutcome.PERMANENTLY_DENIED, manager.recordResult(activity, Manifest.permission.CAMERA, granted = false))
        assertEquals(PermissionStatus.PERMANENTLY_DENIED, manager.status(camera))

        // The user allows it in the system Settings page: Android's state wins, the old record is cleared.
        shadowOf(app).grantPermissions(Manifest.permission.CAMERA)
        assertEquals(PermissionStatus.GRANTED, manager.status(camera))
        shadowOf(app).denyPermissions(Manifest.permission.CAMERA)
        assertEquals(PermissionStatus.DENIED, manager.status(camera)) // revoked later: asked before, can ask again
    }

    @Test fun noCameraHardwareIsNotAvailable() {
        shadowOf(app.packageManager).setSystemFeature("android.hardware.camera.any", false)
        assertEquals(PermissionStatus.NOT_AVAILABLE, manager.status(camera))
    }

    @Test fun internetIsGrantedAtInstall() {
        shadowOf(app).grantPermissions(Manifest.permission.INTERNET)
        assertEquals(PermissionStatus.GRANTED, manager.status(SpenDropAccess.items.first { it.permission == Manifest.permission.INTERNET }))
        assertEquals(PackageManager.PERMISSION_GRANTED, app.checkSelfPermission(Manifest.permission.INTERNET))
    }

    @Test fun settingsIntentOpensSpenDropsAppPage() {
        val i = manager.settingsIntent()
        assertEquals(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, i.action)
        assertEquals("package:${app.packageName}", i.data.toString())
    }
}

/** Same checks on Android 15 (API 35). */
@Config(sdk = [35])
class PermissionManagerApi35Test : PermissionManagerTest()
