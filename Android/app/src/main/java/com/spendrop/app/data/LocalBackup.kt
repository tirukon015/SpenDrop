package com.spendrop.app.data

import android.content.Context
import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.BackupPayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

/**
 * Automatic local backup (iOS UserDataBackupService auto-backup): 2 s after any change, the whole data set is written
 * as `SpenDrop_AutoBackup.json` (same JSON as cloud backup, readable by iOS), plus one copy per day (7 kept) and a
 * "before-shrink" copy whenever records would disappear (5 kept). App-private storage; never uploaded.
 */
class LocalBackup(private val context: Context, private val repository: FinanceRepository, private val accountName: () -> String) {
    private val dir get() = File(context.filesDir, "backup").apply { mkdirs() }
    private val historyDir get() = File(context.filesDir, "SpenDropBackupHistory").apply { mkdirs() }
    val latestFile: File get() = File(dir, "SpenDrop_AutoBackup.json")

    @OptIn(FlowPreview::class)
    fun start(scope: CoroutineScope) {
        scope.launch(Dispatchers.IO) {
            repository.snapshot.filterNotNull().drop(1).debounce(2_000).collect { runCatching { write() } }
        }
    }

    suspend fun write() {
        val snapshot = repository.fullSnapshot(includeDeleted = false)
        val payload = BackupCodec.makePayload(snapshot, accountName(), System.currentTimeMillis())
        val previous = latest()
        val target = latestFile
        if (target.exists()) {
            val day = LocalDate.now(ZoneId.systemDefault()).toString()
            if (previous != null && payload.recordCount.isSmaller(previous.recordCount)) {
                target.copyTo(File(historyDir, "before-shrink-${System.currentTimeMillis()}.json"), overwrite = true)
                prune("before-shrink-", 5)
            }
            val daily = File(historyDir, "daily-$day.json")
            if (!daily.exists()) { target.copyTo(daily); prune("daily-", 7) }
        }
        val tmp = File(dir, "SpenDrop_AutoBackup.json.tmp")
        tmp.writeBytes(BackupCodec.encodeToBytes(payload))
        tmp.renameTo(target)
    }

    fun latest(): BackupPayload? = runCatching { if (latestFile.exists()) BackupCodec.decode(latestFile.readBytes()) else null }.getOrNull()

    private fun prune(prefix: String, keep: Int) {
        historyDir.listFiles { f -> f.name.startsWith(prefix) }?.sortedByDescending { it.name }?.drop(keep)?.forEach { it.delete() }
    }
}
