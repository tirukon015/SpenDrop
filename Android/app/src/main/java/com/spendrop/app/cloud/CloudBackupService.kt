package com.spendrop.app.cloud

import android.content.Context
import android.os.Build
import com.spendrop.app.BuildConfig
import com.spendrop.app.data.FinanceRepository
import com.spendrop.app.data.Preferences
import com.spendrop.core.Ids
import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.BackupPayload
import com.spendrop.core.cloud.BackupDevice
import com.spendrop.core.cloud.CloudBackupProtocol
import com.spendrop.core.cloud.CloudBackupRecord
import com.spendrop.core.cloud.HttpCall
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/** Result of one backup run, shown on the Account screen. */
data class BackupReport(val succeeded: Boolean, val message: String, val at: Long)

/**
 * Cloud Backup — the same feature and storage as iOS: a JSON snapshot (format v4, readable by iOS) in the private
 * Supabase Storage bucket `backups` at `<user id>/<device id>/<id>.json` plus a metadata row in `public.backups`.
 * Off by default; signing in never uploads anything. Uploads are verified before they count; nothing local is deleted.
 * Receipt screenshots and person photos are not uploaded (same as iOS).
 */
class CloudBackupService(
    private val context: Context,
    private val http: SupabaseHttp?,
    private val auth: AuthService,
    private val repository: FinanceRepository,
    private val prefs: Preferences,
) {
    private val mutex = Mutex()
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running
    private val _progress = MutableStateFlow<String?>(null)
    val progress: StateFlow<String?> = _progress

    private suspend fun execute(call: HttpCall, token: String): ByteArray {
        val h = http ?: throw CloudError.NotConfigured
        val contentType = call.headers["Content-Type"]
        val body = call.body?.toRequestBody(contentType?.toMediaType())
        return h.send(call.method, "/" + call.path, token = token, body = body, headers = call.headers)
    }

    suspend fun device(): BackupDevice = BackupDevice(
        prefs.deviceId(),
        listOfNotNull(Build.MANUFACTURER?.replaceFirstChar { it.uppercase() }, Build.MODEL).joinToString(" ").ifBlank { "Android" },
        "${BuildConfig.VERSION_NAME} (Android)",
    )

    suspend fun isEnabled(): Boolean {
        val user = auth.currentUser ?: return false
        return prefs.get(Preferences.Keys.cloudBackupUser) == user.id
    }

    suspend fun setEnabled(on: Boolean) {
        val user = auth.currentUser
        prefs.set(Preferences.Keys.cloudBackupUser, if (on && user != null) user.id else null)
    }

    /** Builds the iOS-compatible payload from every live local record. */
    suspend fun makePayload(now: Long = System.currentTimeMillis()): BackupPayload =
        BackupCodec.makePayload(repository.fullSnapshot(includeDeleted = false), auth.currentUser?.email ?: BackupCodec.DEFAULT_ACCOUNT_NAME, now)

    /**
     * Upload → insert row → verify (row readable, downloaded bytes identical, decodes) → record success → prune
     * this device's expired backups. An automatic run with unchanged content counts as done without uploading.
     */
    suspend fun backUp(automatic: Boolean): BackupReport = withContext(Dispatchers.Default) { mutex.withLock {
        _running.value = true
        try {
            val user = auth.currentUser ?: throw CloudError.NotSignedIn
            val token = auth.validAccessToken()
            _progress.value = "Preparing backup…"
            val now = System.currentTimeMillis()
            val payload = makePayload(now)
            val hash = CloudBackupProtocol.contentHash(payload)
            if (!CloudBackupProtocol.shouldUpload(force = !automatic, hash = hash, lastVerifiedHash = prefs.get(Preferences.Keys.lastBackupHash))) {
                return@withContext record(BackupReport(true, "Backed up — nothing changed since the last backup.", now), automatic)
            }
            val bytes = BackupCodec.encodeToBytes(payload)
            val id = Ids.new()
            val dev = device()
            val path = CloudBackupProtocol.objectPath(user.id, dev.id, id)
            _progress.value = "Uploading…"
            execute(CloudBackupProtocol.uploadObject(path, bytes), token)
            var rowInserted = false
            try {
                val rec = CloudBackupProtocol.makeRecord(id, dev, user.id, payload, bytes.size, now)
                execute(CloudBackupProtocol.insertRow(rec), token)
                rowInserted = true
                _progress.value = "Verifying…"
                val rows = execute(CloudBackupProtocol.verifyRowCall(id), token).decodeToString()
                val stored = execute(CloudBackupProtocol.verifyDownloadCall(path), token)
                if (!CloudBackupProtocol.verifyUpload(id, path, bytes, rows, stored)) throw CloudError.InvalidResponse
            } catch (e: Throwable) {
                // Remove the unverified copy (even if the user left the screen); older backups are left alone.
                withContext(NonCancellable) {
                    runCatching { execute(CloudBackupProtocol.deleteObjects(listOf(path)), token) }
                    if (rowInserted) runCatching { execute(CloudBackupProtocol.deleteRow(id), token) }
                }
                throw e
            }
            prefs.set(Preferences.Keys.lastBackupHash, hash)
            prefs.set(Preferences.Keys.lastBackupAt, now.toString())
            prune(token, dev.id, id, now)
            val c = payload.recordCount
            record(BackupReport(true, "Backed up ${c.expenses} expenses, ${c.movements} money records, ${c.accounts} accounts and ${c.profiles} people.", now), automatic)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val msg = (e as? CloudError)?.message ?: "Backup failed. Your data is safe on this phone."
            record(BackupReport(false, msg, System.currentTimeMillis()), automatic = false)
        } finally {
            _running.value = false
            _progress.value = null
        }
    } }

    private suspend fun record(r: BackupReport, automatic: Boolean): BackupReport {
        prefs.set(Preferences.Keys.lastBackupMessage, "${if (r.succeeded) "ok" else "fail"}|${r.at}|${r.message}")
        if (r.succeeded && automatic) prefs.set(Preferences.Keys.lastAutoBackupDay, r.at.toString())
        return r
    }

    suspend fun lastReport(): BackupReport? = prefs.get(Preferences.Keys.lastBackupMessage)?.split("|", limit = 3)?.takeIf { it.size == 3 }?.let {
        BackupReport(it[0] == "ok", it[2], it[1].toLongOrNull() ?: 0)
    }

    private suspend fun prune(token: String, deviceId: String, newestId: String, now: Long) = runCatching {
        val days = CloudBackupProtocol.retentionDays(prefs.get(Preferences.Keys.retentionDays))
        val rows = execute(CloudBackupProtocol.pruneListCall(deviceId), token).decodeToString()
        val sel = CloudBackupProtocol.selectExpired(rows, newestId, now, days)
        if (!sel.isEmpty) {
            execute(CloudBackupProtocol.deleteObjects(sel.paths), token)
            execute(CloudBackupProtocol.deleteRows(sel.ids), token)
        }
    }

    /** The 30 most recent backups from all of this user's devices (iOS and Android). */
    suspend fun list(): List<CloudBackupRecord> {
        val token = auth.validAccessToken()
        return CloudBackupProtocol.sortForList(CloudBackupProtocol.decodeList(execute(CloudBackupProtocol.listCall(), token).decodeToString()))
    }

    suspend fun download(record: CloudBackupRecord): BackupPayload = withContext(Dispatchers.Default) {
        val token = auth.validAccessToken()
        val data = execute(CloudBackupProtocol.downloadCall(record), token)
        try { CloudBackupProtocol.decodeDownloaded(data) } catch (e: com.spendrop.core.backup.BackupException.UnsupportedVersion) {
            throw CloudError.UnsupportedBackup(e.version)
        } catch (e: Exception) { throw CloudError.InvalidResponse }
    }

    /** Account deletion step 1: every backup file and row of this user. */
    suspend fun deleteAllCloudData() {
        val token = auth.validAccessToken()
        val rows = execute(CloudBackupProtocol.deleteAllListCall(), token).decodeToString()
        val paths = CloudBackupProtocol.objectPaths(rows)
        if (paths.isNotEmpty()) execute(CloudBackupProtocol.deleteObjects(paths), token)
        execute(CloudBackupProtocol.deleteAllRowsCall(), token)
        prefs.set(Preferences.Keys.lastBackupHash, null)
        deleteReceipts(token)
    }

    /** Receipt images the Web App stored at `receipts/<user>/<expense>/<file>` (same clean-up as the Web client). */
    private suspend fun deleteReceipts(token: String) {
        val h = http ?: return
        val user = auth.currentUser?.id ?: return
        suspend fun list(prefix: String): List<String> = runCatching {
            val body = buildJsonObject { put("prefix", prefix); put("limit", 1000); put("offset", 0) }.toString()
            (CloudError.json.parseToJsonElement(h.sendJson("POST", "/storage/v1/object/list/receipts", body, token = token).decodeToString()) as JsonArray)
                .mapNotNull { (it as? JsonObject)?.get("name")?.jsonPrimitive?.contentOrNull }
        }.getOrDefault(emptyList())
        val paths = list("$user/").flatMap { folder -> list("$user/$folder/").map { "$user/$folder/$it" } }
        paths.chunked(500).forEach { chunk ->
            val body = buildJsonObject { put("prefixes", JsonArray(chunk.map { JsonPrimitive(it) })) }.toString()
            runCatching { h.sendJson("DELETE", "/storage/v1/object/receipts", body, token = token) }
        }
    }
}
