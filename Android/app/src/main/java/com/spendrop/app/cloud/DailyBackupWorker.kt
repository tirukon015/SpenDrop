package com.spendrop.app.cloud

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.spendrop.app.container
import com.spendrop.app.data.Preferences
import com.spendrop.core.cloud.DailyBackupSchedule
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * Optional daily cloud backup (iOS BGProcessingTask equivalent). Only ever one pending request: it waits for the
 * chosen time and a network connection, runs at most one automatic backup per day, then schedules the next one.
 * No permanent background service and no polling.
 */
class DailyBackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val c = applicationContext.container
        runIfDue(applicationContext)
        schedule(applicationContext)
        return Result.success()
    }

    companion object {
        private const val NAME = "spendrop-daily-backup"

        suspend fun settings(context: Context): Triple<Boolean, Int, Long?> {
            val p = context.container.preferences
            val daily = p.get(Preferences.Keys.dailyBackupEnabled) ?: true
            val minutes = p.get(Preferences.Keys.dailyBackupMinutes) ?: DailyBackupSchedule.DEFAULT_MINUTES
            val last = p.get(Preferences.Keys.lastAutoBackupDay)?.toLongOrNull()
            return Triple(daily, minutes, last)
        }

        /** Catch-up (app start / foreground) and the worker itself. */
        suspend fun runIfDue(context: Context) {
            val c = context.container
            val (daily, minutes, last) = settings(context)
            val due = DailyBackupSchedule.isDue(System.currentTimeMillis(), minutes, last, ZoneId.systemDefault(),
                c.auth.currentUser != null, c.cloudBackup.isEnabled(), daily)
            if (due) c.cloudBackup.backUp(automatic = true)
        }

        suspend fun schedule(context: Context) {
            val c = context.container
            val wm = WorkManager.getInstance(context)
            val (daily, minutes, last) = settings(context)
            if (!DailyBackupSchedule.shouldSchedule(c.auth.isConfigured, c.auth.currentUser != null, c.cloudBackup.isEnabled(), daily)) {
                wm.cancelUniqueWork(NAME); return
            }
            val next = DailyBackupSchedule.nextRun(System.currentTimeMillis(), minutes, last, ZoneId.systemDefault())
            val delay = (next - System.currentTimeMillis()).coerceAtLeast(60_000)
            val req = OneTimeWorkRequestBuilder<DailyBackupWorker>()
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            wm.enqueueUniqueWork(NAME, ExistingWorkPolicy.REPLACE, req)
        }
    }
}
