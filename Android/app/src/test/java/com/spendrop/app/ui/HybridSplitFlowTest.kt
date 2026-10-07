package com.spendrop.app.ui

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.isPopup
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.testContainer
import com.spendrop.app.ui.theme.SpenDropTheme
import com.spendrop.core.split.SplitDraft
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Hybrid Split in the real Add Expense screen (the request's example): RM200; group fixed RM100 between Riad and Bijoy;
 * Bijoy individual RM20; the rest equally between You, Riad and Bijoy → live amounts, validation, save, stored rule,
 * and reopening the split. Phone and tablet widths.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HybridSplitFlowTest {
    @get:Rule val rule = createComposeRule()

    private fun waitText(text: String) = rule.waitUntil(10_000) { rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    private fun share(name: String) = rule.onNodeWithTag("share-$name", useUnmergedTree = true).performScrollTo()

    private fun addPerson(name: String) {
        rule.onNodeWithText("Add Person").performScrollTo().performClick()
        waitText("Choose Person")
        rule.onNodeWithText("Search or type a new name").performTextInput(name)
        rule.onNodeWithText("Add \"$name\" to PayBook").performClick()
        rule.waitForIdle()
    }

    private fun runFlow() {
        val c = testContainer()
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        waitText("No expenses recorded today")
        rule.onNodeWithContentDescription("Add").performClick()
        waitText("ENTER AMOUNT")
        rule.onNodeWithTag("amount").performTextInput("200")
        rule.onNodeWithTag("merchant").performScrollTo().performTextInput("Team Dinner")
        rule.onNode(isToggleable() and hasContentDescription("", substring = true).not()).performScrollTo().performClick()
        listOf("Riad", "Bijoy").forEach(::addPerson)

        rule.onNodeWithTag("hybridToggle").performScrollTo().performClick()
        rule.onNodeWithText("Add a group fixed amount or an individual fixed amount.").performScrollTo()
        rule.onNodeWithTag("groupAmount-0").performScrollTo().performTextInput("100")
        rule.onNodeWithTag("group0-Riad").performScrollTo().performClick()
        rule.onNodeWithTag("group0-Bijoy").performScrollTo().performClick()
        rule.onNodeWithText("Add Individual Fixed Amount").performScrollTo().performClick()
        rule.onNodeWithTag("individualPerson-0").performScrollTo().performClick()
        rule.onNode(hasText("Bijoy") and hasAnyAncestor(isPopup())).performClick()
        rule.onNodeWithTag("individualAmount-0").performScrollTo().performTextInput("20")

        rule.onNodeWithTag("hybridRemaining").performScrollTo().assertTextEquals("RM 200.00 total − RM 120.00 fixed")
        rule.onNodeWithText("RM 80.00").performScrollTo()
        share("You").assertTextEquals("RM 26.67")
        share("Riad").assertTextEquals("RM 76.67")
        share("Bijoy").assertTextEquals("RM 96.66")
        rule.onNodeWithText("RM 50.00 group + RM 20.00 individual + RM 26.66 remaining".replace(" group", "\u00A0group").replace(" individual", "\u00A0individual").replace(" remaining", "\u00A0remaining").replace("RM ", "RM\u00A0")).performScrollTo()
        rule.onNodeWithText("✓ Balanced · Your share RM 26.67").performScrollTo()

        // Live: the group amount changes
        rule.onNodeWithTag("groupAmount-0").performScrollTo().performTextReplacement("120")
        share("Riad").assertTextEquals("RM 80.00")
        share("Bijoy").assertTextEquals("RM 100.00")
        // Live: more than the total
        rule.onNodeWithTag("individualAmount-0").performScrollTo().performTextReplacement("90")
        rule.onNodeWithText("Fixed allocations exceed the transaction total by RM 10.00.").performScrollTo()
        rule.onNodeWithTag("individualAmount-0").performScrollTo().performTextReplacement("20")
        rule.onNodeWithTag("groupAmount-0").performScrollTo().performTextReplacement("100")
        share("Bijoy").assertTextEquals("RM 96.66")

        rule.onNodeWithTag("saveButton").performScrollTo().performClick()
        val s = runBlocking { withTimeout(10_000) { c.repository.snapshot.filterNotNull().first { s -> s.expenses.any { e -> e.merchant == "Team Dinner" && s.sharesOf(e.id).size == 3 } } } }
        val e = s.expenses.first { it.merchant == "Team Dinner" }
        val shares = s.sharesOf(e.id).sortedBy { it.sortIndex }
        assertEquals(listOf(2667L, 7667L, 9666L), shares.map { it.amountMinor })
        assertEquals(
            """{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}""",
            e.splitRule,
        )
        // Reopening the split restores every layer (what the edit screen loads)
        val back = SplitDraft.fromExpense(e, s.sharesOf(e.id), s.people)!!
        assertEquals("100.00", back.hybrid!!.groups.single().amountText)
        assertEquals(shares.map { it.amountMinor }, back.shares(e.amountMinor))
    }

    @Test @Config(sdk = [35], qualifiers = "w360dp-h780dp-xhdpi") fun phone() = runFlow()
    @Test @Config(sdk = [35], qualifiers = "w840dp-h1280dp-xhdpi") fun tablet() = runFlow()
}
