package com.spendrop.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.spendrop.app.data.Preferences
import com.spendrop.app.importing.Intake
import com.spendrop.app.ui.SpenDropRoot
import com.spendrop.app.ui.theme.Appearance
import com.spendrop.app.ui.theme.SpenDropTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val links get() = container.links

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A recreated activity (rotation, process death) must not handle the same link twice.
        if (savedInstanceState == null) handle(intent)
        lifecycleScope.launch(Dispatchers.IO) {
            Intake.cleanup(applicationContext)
            container.auth.refreshSessionIfNeeded()
        }
        setContent {
            val appearance by container.preferences.string(Preferences.Keys.appearance, "system").collectAsState(initial = "system")
            SpenDropTheme(Appearance.fromRaw(appearance)) { SpenDropRoot(container) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val uri = intent?.data ?: return
        if (container.auth.isAuthCallback(uri)) {
            // App scope: the one-time code must be exchanged even if the activity is recreated meanwhile.
            container.appScope.launch { links.deliver(container.auth.handleAuthCallback(uri)) }
            intent.data = null
        }
    }
}
