package com.spendrop.app.ui.ask

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.data.AiDefaults
import com.spendrop.app.data.Preferences
import com.spendrop.app.testContainer
import com.spendrop.app.ui.SpenDropRoot
import com.spendrop.app.ui.theme.SpenDropTheme
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The floating robot, the Ask screen's signed-out state and the SpenDrop AI settings, on the real screens. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AskUiTest {
    @get:Rule val rule = createComposeRule()

    private fun waitTag(tag: String) = rule.waitUntil(10_000) { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    @Test fun settingsDefaultToOn() = runBlocking {
        val c = testContainer()
        assertTrue(AiDefaults.FLOATING_ASSISTANT && AiDefaults.SHOW_NAME)
        // DataStore is one file per process (shared by the tests in this class): start from "never set".
        c.preferences.set(Preferences.Keys.aiFloatingAssistant, null)
        c.preferences.set(Preferences.Keys.aiShowName, null)
        assertTrue(c.preferences.aiFloatingAssistant.first())
        assertTrue(c.preferences.aiShowName.first())
        c.preferences.set(Preferences.Keys.aiShowName, false)
        assertFalse(c.preferences.aiShowName.first())
        assertTrue(c.preferences.aiFloatingAssistant.first())
    }

    @Test fun robotOpensAsk_signedOutShowsSignIn_andRobotHides() {
        val c = testContainer()
        runBlocking { c.preferences.set(Preferences.Keys.aiFloatingAssistant, null) }
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        waitTag("floatingRobot")
        rule.onNodeWithContentDescription("Ask SpenDrop AI").performClick()
        waitTag("askSignIn")
        rule.waitForIdle()
        assertTrue(rule.onAllNodesWithTag("floatingRobot").fetchSemanticsNodes().isEmpty())
        // Signed out (or a build without cloud config): never a composer that would send anything.
        assertTrue(rule.onAllNodesWithTag("askInput").fetchSemanticsNodes().isEmpty())
    }

    @Test fun turningOffFloatingAssistantHidesRobot() {
        val c = testContainer()
        runBlocking { c.preferences.set(Preferences.Keys.aiFloatingAssistant, null) }
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        waitTag("floatingRobot")
        runBlocking { c.preferences.set(Preferences.Keys.aiFloatingAssistant, false) }
        rule.waitUntil(10_000) { rule.onAllNodesWithTag("floatingRobot").fetchSemanticsNodes().isEmpty() }
        assertTrue(rule.onAllNodesWithText("Home").fetchSemanticsNodes().isNotEmpty())
    }
}
