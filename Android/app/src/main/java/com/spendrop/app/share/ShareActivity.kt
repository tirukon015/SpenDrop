package com.spendrop.app.share

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.spendrop.app.container
import com.spendrop.app.data.Preferences
import com.spendrop.app.importing.Intake
import com.spendrop.app.ui.bulk.BulkImportScreen
import com.spendrop.app.ui.importing.ImportFlowScreen
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.app.ui.theme.Appearance
import com.spendrop.app.ui.theme.SpenDropTheme

/**
 * "Share → SpenDrop" from any app. Like the iOS Share Extension, it runs on top of the app the user shared from,
 * reads the content, shows the review, saves into SpenDrop's local store, then returns the user to where they were.
 * Unsaved work in the main SpenDrop window is never touched. Works when SpenDrop isn't running.
 */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Copy the shared content right away: URI read permission only lasts while this activity is alive. The import
        // view model survives rotation, so the same share is never processed twice.
        val shared = Intent(intent)
        val bulk = Intake.isBulkShare(shared)
        setContent {
            val appearance by container.preferences.string(Preferences.Keys.appearance, "system").collectAsState(initial = "system")
            SpenDropTheme(Appearance.fromRaw(appearance)) {
                val done: (Int) -> Unit = { saved ->
                    if (saved > 0) Toast.makeText(this, if (saved == 1) "Saved to SpenDrop" else "$saved transactions saved to SpenDrop", Toast.LENGTH_SHORT).show()
                    finish()
                }
                if (bulk) BulkImportScreen(container, load = { Intake.fromIntent(applicationContext, shared, Intake.MAX_BULK_ITEMS) },
                    source = ExpenseSourceType.SHARE_EXTENSION, onClose = done)
                else ImportFlowScreen(container, load = { Intake.fromIntent(applicationContext, shared) }, fromShare = true, onFinished = done)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A second share while one is open: start a fresh review on top so the current one isn't replaced.
        startActivity(Intent(intent).setClass(this, ShareActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK))
    }
}
