package com.spendrop.app.share

import android.content.Intent
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.container
import com.spendrop.core.model.ExpenseSourceType
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

/** "Share → SpenDrop" from another app while SpenDrop isn't open: review screen, save, record stored. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ShareTargetTest {
    @get:Rule val rule = createEmptyComposeRule()

    @Test fun sharedPaymentTextOpensReviewAndSaves() {
        val ctx = ApplicationProvider.getApplicationContext<android.app.Application>()
        val intent = Intent(Intent.ACTION_SEND).setClass(ctx, ShareActivity::class.java).setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "Touch 'n Go eWallet\nPayment Successful\nRM18.50\nPaid to: McDonald's\n16 Sep 2026 9:42 PM\nRef No: TNG992837194")
        ActivityScenario.launch<ShareActivity>(intent).use {
            rule.waitUntil(15_000) { rule.onAllNodesWithText("Review").fetchSemanticsNodes().isNotEmpty() }
            rule.waitUntil(5_000) { rule.onAllNodesWithText("McDonald's").fetchSemanticsNodes().isNotEmpty() }
            rule.onNodeWithTag("saveButton").performScrollTo().performClick()
            val e = runBlocking {
                withTimeout(10_000) { ctx.container.repository.snapshot.filterNotNull().first { s -> s.expenses.any { it.transactionReference == "TNG992837194" } } }
            }.expenses.first { it.transactionReference == "TNG992837194" }
            assertEquals(1850L, e.amountMinor)
            assertEquals("McDonald's", e.merchant)
            assertEquals(ExpenseSourceType.SHARE_EXTENSION.raw, e.sourceTypeRaw)
            assertEquals("Touch 'n Go", e.effectiveFundingAccount)
        }
    }
}
