package com.spendrop.app.ui

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.testContainer
import com.spendrop.app.ui.theme.SpenDropTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * End-to-end flows on the real screens (Robolectric, in-memory database): add an expense split with a new PayBook
 * person, see it on Home, PayBook and Breakdown; settle it; load and remove sample data.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class MainFlowsTest {
    @get:Rule val rule = createComposeRule()

    private fun waitText(text: String, substring: Boolean = false) =
        rule.waitUntil(10_000) { rule.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty() }

    @Test fun addSplitExpense_showsEverywhere_thenSettle() {
        val c = testContainer()
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        waitText("No expenses recorded today")

        rule.onNodeWithContentDescription("Add").performClick()
        waitText("ENTER AMOUNT")
        rule.onNodeWithTag("amount").performTextInput("120")
        rule.onNodeWithTag("merchant").performScrollTo().performTextInput("Team Dinner")
        // Split with a new PayBook person, equally
        rule.onNode(isToggleable() and hasContentDescription("", substring = true).not()).performScrollTo().performClick()
        rule.onNodeWithText("Add Person").performScrollTo().performClick()
        waitText("Choose Person")
        rule.onNodeWithText("Search or type a new name").performTextInput("Vijay")
        rule.onNodeWithText("Add \"Vijay\" to PayBook").performClick()
        waitText("✓ Balanced · Your share RM 60.00")
        rule.onNodeWithText("You paid RM 120.00. Others owe you RM 60.00.").assertExists()
        rule.onNodeWithTag("saveButton").performScrollTo().performClick()

        // Home: today's expense and the balance card
        waitText("Team Dinner")
        waitText("Owed to you")
        // PayBook
        rule.onNodeWithText("PayBook").performClick()
        waitText("Vijay")
        rule.onAllNodesWithText("RM 60.00", substring = true).onFirst().assertExists()
        // Person detail → Settle All
        rule.onNodeWithText("Vijay").performClick()
        waitText("Vijay owes you RM 60.00")
        rule.onNodeWithText("Settle All").performScrollTo().performClick()
        rule.onAllNodesWithText("Settle All").onFirst().assertExists()
        rule.onNodeWithText("Settle everything with Vijay?").assertExists()
        rule.onNode(hasText("Settle All") and hasAnyAncestor(isDialog())).performClick()
        waitText("Settled — nothing owed either way")
        // Breakdown
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onNodeWithText("Breakdown").performClick()
        waitText("TOTAL SPENT")
        rule.onAllNodesWithText("RM 120.00").onFirst().assertExists()
    }

    @Test fun sampleData_loadAndRemove() {
        val c = testContainer()
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        waitText("Home")
        rule.onNodeWithText("More").performClick()
        rule.onNodeWithText("Settings").performClick()
        waitText("Backup & data recovery".uppercase())
        rule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Load Sample Data"))
        rule.onNodeWithText("Load Sample Data").performClick()
        rule.onNode(hasText("Load Sample Data") and hasAnyAncestor(isDialog())).performClick()
        waitText("Sample Data Loaded")
        rule.onNodeWithText("OK").performClick()
        rule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Remove Sample Data"))
        rule.onNodeWithText("Remove Sample Data").performClick()
        rule.onNode(hasText("Remove Sample Data") and hasAnyAncestor(isDialog())).performClick()
        waitText("Sample Data Removed")
    }
}
