package com.spendrop.app.ui.audit

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.isToggleable
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.data.Changes
import com.spendrop.app.testContainer
import com.spendrop.app.ui.SpenDropRoot
import com.spendrop.app.ui.theme.SpenDropTheme
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.sample.SampleData
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * Renders every main screen at the OPPO CPH2269's size (720×1600 px, 320 dpi = 360×800 dp) with sample data and
 * saves PNGs for visual review. Run with -Pspendrop.audit=true; skipped otherwise.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [30], qualifiers = "w360dp-h800dp-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScreenAudit {
    @get:Rule val rule = createComposeRule()
    private val out = File(System.getProperty("spendrop.auditDir") ?: "build/audit").apply { mkdirs() }

    private fun shot(name: String) {
        rule.waitForIdle()
        val bmp = rule.onRoot().captureToImage().asAndroidBitmap()
        File(out, "$name.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun wait(text: String) = rule.waitUntil(10_000) { rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun allScreens() {
        assumeTrue(System.getProperty("spendrop.audit") == "true")
        val c = testContainer()
        runBlocking {
            val set = SampleData.load(FinanceSnapshot(), System.currentTimeMillis(), CalendarContext.device())!!
            c.repository.apply(Changes(people = set.people, paymentMethods = set.paymentMethods, accounts = set.accounts, expenses = set.expenses,
                shares = set.shares, movements = set.movements, allocations = set.allocations, sampleRecords = set.sampleRecords))
        }
        rule.setContent { SpenDropTheme { SpenDropRoot(c) } }
        wait("Today"); shot("01_home")
        rule.onNodeWithText("Transactions").performClick(); wait("SPENT"); shot("02_transactions")
        rule.onAllNodesWithText("PayBook").onFirst().performClick(); wait("Owed to you"); shot("03_paybook")
        rule.onNodeWithText("Breakdown").performClick(); wait("TOTAL SPENT"); shot("04_breakdown")
        rule.onNodeWithText("More").performClick(); wait("Settings"); shot("05_more")
        rule.onNodeWithText("Settings").performClick(); wait("Stored Transactions"); shot("06_settings")
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onNodeWithText("Accounts").performClick(); wait("My accounts".uppercase()); shot("07_accounts")
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onNodeWithText("Account").performClick(); wait("Sign In"); shot("08_account")
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onNodeWithText("Home").performClick(); wait("Today")
        rule.onNodeWithContentDescription("Add").performClick(); wait("ENTER AMOUNT"); shot("09_add_expense")
        rule.onNodeWithText("Groceries").performScrollTo(); shot("10_add_expense_category")
        rule.onNodeWithText("Split Transaction").performScrollTo(); shot("11_add_expense_split_off")
        rule.onNodeWithTag("amount").performTextInput("120")
        rule.onNode(isToggleable()).performScrollTo().performClick()
        rule.onNodeWithText("Add Person").performScrollTo().performClick(); wait("Choose Person")
        rule.onNodeWithText("Mei Ling (Sample)").performClick()
        rule.waitForIdle(); rule.onNodeWithText("Total").performScrollTo(); shot("12_add_expense_split_on")
        rule.onNodeWithText("Paid by").performScrollTo(); shot("12b_add_expense_split_bottom")
        rule.onNodeWithContentDescription("Back").performClick()
        if (rule.onAllNodesWithText("Discard").fetchSemanticsNodes().isNotEmpty()) rule.onNodeWithText("Discard").performClick()
        rule.onNodeWithText("Transactions").performClick(); wait("SPENT")
        rule.onAllNodesWithText("Grocer (Sample)").onFirst().performClick(); wait("Expense Details"); shot("13_expense_detail")
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onAllNodesWithText("PayBook").onFirst().performClick(); wait("Owed to you")
        rule.onAllNodesWithText("(Sample)", substring = true).onFirst().performClick(); wait("NET BALANCE"); shot("14_person")
        rule.onNodeWithContentDescription("Back").performClick()
        rule.onNodeWithText("More").performClick(); rule.onNodeWithText("Settings").performClick(); wait("Stored Transactions")
        rule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Permissions & Access"))
        rule.onNodeWithText("Permissions & Access").performClick(); wait("Camera"); shot("15_permissions")
    }
}
