package com.spendrop.app

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

class SpenDropApplication : Application() {
    lateinit var container: AppContainer
        private set

    @OptIn(FlowPreview::class)
    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.localBackup.start(container.appScope)
        container.appScope.launch {
            runCatching { com.spendrop.app.cloud.DailyBackupWorker.runIfDue(this@SpenDropApplication) }
            runCatching { com.spendrop.app.cloud.DailyBackupWorker.schedule(this@SpenDropApplication) }
        }
        // Live sync (opt-in): a few seconds after local changes, and whenever the app comes to the foreground.
        container.appScope.launch {
            container.repository.snapshot.filterNotNull().drop(1).debounce(3_000).collect { syncIfEnabled() }
        }
        runCatching {
            ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) { container.appScope.launch { syncIfEnabled() } }
            })
        }
    }

    private suspend fun syncIfEnabled() {
        runCatching { if (container.sync.isEnabled()) container.sync.syncNow() }
    }
}

val android.content.Context.container: AppContainer
    get() = (applicationContext as SpenDropApplication).container
