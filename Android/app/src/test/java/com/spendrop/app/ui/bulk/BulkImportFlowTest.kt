package com.spendrop.app.ui.bulk

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.container
import com.spendrop.app.importing.IntakeItem
import com.spendrop.app.ui.theme.SpenDropTheme
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
 * Bulk Import end to end (with shared text standing in for screenshots, since ML Kit can't run on the JVM):
 * three items → three separate drafts; the repeat inside the batch is a Possible duplicate and skipped by default;
 * "Add 2 Transactions" saves two normal expenses through the usual save path.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BulkImportFlowTest {
    @get:Rule val rule = createComposeRule()

    private val tng = "Touch 'n Go eWallet\nPayment Successful\nRM18.50\nPaid to: McDonald's\n16 Sep 2026 9:42 PM\nRef No: TNG992837194"
    private val grab = "Grab\nPayment Successful\nRM12.30\nPaid to: GrabFood\n16 Sep 2026 1:05 PM\nRef No: GRB55120931"

    /** The main looper is paused under Robolectric: let posted/delayed work (the sequential saves) run. */
    private fun advance() = org.robolectric.shadows.ShadowLooper.idleMainLooper(200, java.util.concurrent.TimeUnit.MILLISECONDS)

    @Test fun separateDraftsDuplicateSkippedAndAddNSavesEach() {
        val ctx = ApplicationProvider.getApplicationContext<android.app.Application>()
        val c = ctx.container
        val items = listOf(
            IntakeItem.SharedText("a", tng),
            IntakeItem.SharedText("b", grab),
            IntakeItem.SharedText("c", tng),
        )
        var closedWith = -1
        rule.setContent { SpenDropTheme { BulkImportScreen(c, load = { items }, onClose = { closedWith = it }) } }

        rule.waitUntil(15_000) { rule.onAllNodesWithText("3 screenshots · 3 transactions detected").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("● 1 possible duplicate").assertExists()
        rule.onNodeWithTag("addAll").assertIsEnabled()
        rule.onNodeWithText("Add 2 Transactions").assertExists()

        // Expanding a card shows the full normal editor (e.g. the Split Money section).
        rule.onAllNodesWithText("GrabFood")[0].performClick()
        rule.onNodeWithTag("bulkList").performScrollToNode(hasText("Split Transaction"))

        rule.onNodeWithTag("addAll").performClick()
        val refs = setOf("TNG992837194", "GRB55120931")
        rule.waitUntil(15_000) { advance(); closedWith >= 0 }
        val s = runBlocking { withTimeout(10_000) { c.repository.snapshot.filterNotNull().first { s -> s.expenses.count { it.deletedAt == null && it.transactionReference in refs } >= 2 } } }
        assertEquals(2, closedWith)
        val live = s.expenses.filter { it.deletedAt == null && it.transactionReference in refs }
        assertEquals(2, live.size)
        assertEquals(setOf(1850L, 1230L), live.map { it.amountMinor }.toSet())
    }

    @Test fun addAnywayIncludesTheDuplicate() {
        val ctx = ApplicationProvider.getApplicationContext<android.app.Application>()
        val c = ctx.container
        // Different payment from the other test (they share one database in this JVM).
        val shopee = "ShopeePay\nPayment Successful\nRM44.90\nPaid to: Shopee\n17 Sep 2026 8:15 PM\nRef No: SPY7781200"
        val items = listOf(IntakeItem.SharedText("a", shopee), IntakeItem.SharedText("c", shopee))
        var closedWith = -1
        rule.setContent { SpenDropTheme { BulkImportScreen(c, load = { items }, onClose = { closedWith = it }) } }
        rule.waitUntil(15_000) { rule.onAllNodesWithText("Add 1 Transaction").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Add Anyway").performClick()
        rule.waitUntil(5_000) { rule.onAllNodesWithText("Add 2 Transactions").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("addAll").performClick()
        rule.waitUntil(15_000) { advance(); closedWith >= 0 }
        assertEquals(2, closedWith)
    }
}
