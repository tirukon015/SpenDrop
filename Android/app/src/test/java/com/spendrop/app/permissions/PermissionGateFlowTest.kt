package com.spendrop.app.permissions

import android.Manifest
import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A feature that needs the camera, run through the real gate UI. Android's system dialog is replaced by a fake
 * requester that answers like Android would (and updates Robolectric's permission state accordingly).
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PermissionGateFlowTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val camera = SpenDropAccess.items.first { it.permission == Manifest.permission.CAMERA }
    private var featureRuns = 0
    private var fallbackRuns = 0
    private var requests = 0

    @Before fun setUp() {
        PermissionManager(app).clearHistory()
        shadowOf(app.packageManager).setSystemFeature("android.hardware.camera.any", true)
        shadowOf(app).denyPermissions(Manifest.permission.CAMERA)
    }

    private fun show(answer: (String) -> Boolean) {
        rule.setContent {
            val gate = rememberPermissionGate(camera, PermissionRationale("Allow camera?", "Explain", "Denied text", "Choose a Photo Instead"),
                onFallback = { fallbackRuns++ },
                requester = { p, done -> requests++; val ok = answer(p); if (ok) shadowOf(app).grantPermissions(p); done(ok) })
            Button(onClick = { gate.run { featureRuns++ } }) { Text("Take Photo") }
        }
    }

    @Test fun grantedDuringFeatureFlow_continuesAutomatically() {
        show { true }
        rule.onNodeWithText("Take Photo").performClick()
        rule.onNodeWithText("Allow camera?").assertExists()      // explanation first
        rule.onNodeWithText("Continue").performClick()          // → Android dialog → Allow
        rule.waitForIdle()
        assertEquals(1, requests)
        assertEquals(1, featureRuns)                            // the camera opens without a second tap
        assertEquals(PermissionStatus.GRANTED, PermissionManager(app).status(camera))
        rule.onNodeWithText("Take Photo").performClick()        // already allowed: no dialog, no request
        assertEquals(1, requests); assertEquals(2, featureRuns)
    }

    @Test fun deniedDuringFeatureFlow_offersFallback_andNeverRunsFeature() {
        shadowOf(app.packageManager).setShouldShowRequestPermissionRationale(Manifest.permission.CAMERA, true)
        show { false }
        rule.onNodeWithText("Take Photo").performClick()
        rule.onNodeWithText("Continue").performClick()
        rule.onNodeWithText("Denied text").assertExists()
        rule.onNodeWithText("Choose a Photo Instead").performClick()
        assertEquals(0, featureRuns); assertEquals(1, fallbackRuns)
        assertEquals(PermissionStatus.DENIED, PermissionManager(app).status(camera))
        rule.onNodeWithText("Take Photo").performClick()        // can ask again: explanation shown again
        rule.onNodeWithText("Allow camera?").assertExists()
    }

    @Test fun permanentlyDenied_sendsToSettings_withoutAskingAndroid() {
        val activity = rule.activity
        PermissionManager(app).recordResult(activity, Manifest.permission.CAMERA, granted = false) // rationale false → permanent
        show { error("Android must not be asked") }
        rule.onNodeWithText("Take Photo").performClick()
        rule.onNodeWithText("Open Settings").assertExists()
        rule.onNodeWithText("Open Settings").performClick()
        assertEquals(0, requests); assertEquals(0, featureRuns)
        assertEquals(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, shadowOf(app).nextStartedActivity.action)
    }

    @Test fun cancelledExplanation_doesNothing() {
        show { true }
        rule.onNodeWithText("Take Photo").performClick()
        rule.onNodeWithText("Not Now").performClick()
        assertEquals(0, requests); assertEquals(0, featureRuns)
        assertEquals(PermissionStatus.NOT_REQUESTED, PermissionManager(app).status(camera))
    }

    @Test fun noCamera_showsNotAvailable_andFallback() {
        shadowOf(app.packageManager).setSystemFeature("android.hardware.camera.any", false)
        show { true }
        rule.onNodeWithText("Take Photo").performClick()
        rule.onNodeWithText("Camera not available").assertExists()
        rule.onNodeWithText("Choose a Photo Instead").performClick()
        assertEquals(0, requests); assertEquals(1, fallbackRuns)
    }
}
