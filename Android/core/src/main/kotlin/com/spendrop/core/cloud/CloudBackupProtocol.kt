package com.spendrop.core.cloud

import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.BackupException
import com.spendrop.core.backup.BackupPayload
import com.spendrop.core.backup.SwiftDateSerializer
import com.spendrop.core.backup.SwiftDates
import com.spendrop.core.backup.SwiftJsonWriter
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.MessageDigest

/**
 * Metadata row for one cloud backup: table `public.backups` (migration 20260929000000_spendrop_cloud_backup.sql).
 * `user_id` is never sent (the server assigns `auth.uid()`); it is ignored when read back with `select=*`.
 * [id] is a lower-case UUID in Kotlin; it is SENT upper case like iOS (`UUID.uuidString`).
 */
@Serializable
data class CloudBackupRecord(
    val id: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("device_name") val deviceName: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("schema_version") val schemaVersion: String,
    @SerialName("backup_version") val backupVersion: Int,
    @SerialName("created_at") @Serializable(with = SwiftDateSerializer::class) val createdAt: Long,
    @SerialName("object_path") val objectPath: String,
    @SerialName("expenses_count") val expensesCount: Int,
    @SerialName("people_count") val peopleCount: Int,
    @SerialName("accounts_count") val accountsCount: Int,
    @SerialName("movements_count") val movementsCount: Int,
    @SerialName("size_bytes") val sizeBytes: Int,
)

/** One HTTP call for the Android HTTP layer to execute (relative to the Supabase project URL). */
data class HttpCall(
    val method: String,
    /** Path + query, relative to the project URL, e.g. `rest/v1/backups?select=*&order=created_at.desc&limit=30`. */
    val path: String,
    /** Extra headers. ALWAYS add `apikey: <anon key>` and `Authorization: Bearer <access token>` as well. */
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
) {
    val bodyText: String? get() = body?.toString(Charsets.UTF_8)
    override fun equals(other: Any?): Boolean = other is HttpCall && method == other.method && path == other.path &&
        headers == other.headers && (body?.contentEquals(other.body ?: ByteArray(0)) ?: (other.body == null))
    override fun hashCode(): Int = method.hashCode() * 31 + path.hashCode()
}

/** The device that makes backups. [id] is created once and stored (iOS: `SpenDrop.cloudDeviceID`, an upper-case UUID). */
data class BackupDevice(val id: String, val name: String, val appVersion: String)

/**
 * The cloud backup protocol, exactly as iOS `CloudBackupService` speaks it. Pure: builds requests and decides; the
 * Android HTTP layer sends them. Every request carries `apikey: <anon key>` and `Authorization: Bearer <access token>`
 * (the user's JWT, never a service key) plus the headers listed below. Non-2xx = failure.
 *
 * Backup (`backupNow`):
 *  1. payload = full snapshot; hash = [contentHash]. Automatic run and hash == last verified hash -> nothing to do
 *     ("up to date", counts as success). Manual ("Back Up Now") always uploads.
 *  2. `POST storage/v1/object/backups/<user id>/<device id>/<NEW UUID>.json`, headers `Content-Type: application/json`,
 *     `x-upsert: false`, body = the pretty-printed backup bytes ([uploadObject]). Files are never overwritten.
 *  3. `POST rest/v1/backups`, `Content-Type: application/json`, `Prefer: return=minimal`, body = [CloudBackupRecord]
 *     JSON (sorted keys, compact) with created_at = now ([insertRow]).
 *  4. Verify ([verifyRowCall] + [verifyDownloadCall] + [verifyUpload]): `GET rest/v1/backups?select=id,object_path&id=eq.<ID>`
 *     must contain the row (id compared case-insensitively, object_path equal); `GET storage/v1/object/authenticated/backups/<path>`
 *     must be byte-identical to what was sent AND decode as a supported backup.
 *  5. Only then: store hash, last backup date, size; status "up to date"; prune ([pruneListCall] -> [selectExpired] ->
 *     [deleteObjects] + [deleteRows]); prune errors are ignored.
 *  On ANY failure after step 2: delete the uploaded file ([deleteObjects]) and, if inserted, the row
 *  ([deleteRow]: `DELETE rest/v1/backups?id=eq.<ID>`), then report failure; earlier backups are untouched and
 *  nothing is recorded as success.
 *
 * List: `GET rest/v1/backups?select=*&order=created_at.desc&limit=30` ([listCall]) — the 30 newest across ALL the
 *  user's devices; decode with [decodeList].
 * Download: `GET storage/v1/object/authenticated/backups/<object_path>` ([downloadCall]) then [decodeDownloaded]
 *  (damaged -> invalid response; newer format -> unsupported). A restore saves a LOCAL safety copy first.
 * Delete all (account deletion, step 1): `GET rest/v1/backups?select=id,object_path` ([deleteAllListCall]);
 *  if any paths: `DELETE storage/v1/object/backups` body `{"prefixes":[paths]}` ([deleteObjects]); then
 *  `DELETE rest/v1/backups?id=not.is.null` ([deleteAllRowsCall]); forget last hash/date.
 * Account deletion (step 2, AuthService): `POST rest/v1/rpc/delete_my_account`, `Content-Type: application/json`,
 *  body `{}` ([deleteAccountCall]); then clear the local session. Local data is never touched.
 */
object CloudBackupProtocol {
    const val BUCKET = "backups"
    /** iOS `SpenDropSchemaV5.versionIdentifier` as written to `schema_version`. */
    const val SCHEMA_VERSION = "5.0.0"
    const val LIST_LIMIT = 30
    val RETENTION_CHOICES = listOf(30, 90)
    const val DEFAULT_RETENTION_DAYS = 30

    private val rowJson = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    /** `<user id>/<device id>/<BACKUP UUID>.json` (backup id upper case like iOS `uuidString`). */
    fun objectPath(userId: String, deviceId: String, backupId: String): String = "$userId/$deviceId/${backupId.uppercase()}.json"

    /** Retention setting: 30 or 90; anything else reads as 30. */
    fun retentionDays(stored: Int?): Int = if (stored != null && stored in RETENTION_CHOICES) stored else DEFAULT_RETENTION_DAYS

    fun makeRecord(backupId: String, device: BackupDevice, userId: String, payload: BackupPayload, sizeBytes: Int, createdAt: Long) =
        CloudBackupRecord(
            id = backupId.lowercase(), deviceId = device.id, deviceName = device.name, appVersion = device.appVersion,
            schemaVersion = SCHEMA_VERSION, backupVersion = payload.version, createdAt = createdAt,
            objectPath = objectPath(userId, device.id, backupId), expensesCount = payload.expenses.size,
            peopleCount = payload.paybookProfiles.size, accountsCount = payload.accounts?.size ?: 0,
            movementsCount = payload.moneyMovements?.size ?: 0, sizeBytes = sizeBytes,
        )

    /** Row JSON exactly like iOS `CloudJSON.encoder()` (sorted keys, compact, whole-second dates, upper-case id). */
    fun encodeRecord(record: CloudBackupRecord): String {
        val obj = rowJson.encodeToJsonElement(record).jsonObject
        val withUpperId = JsonObject(obj + ("id" to JsonPrimitive(record.id.uppercase())))
        return SwiftJsonWriter.write(withUpperId, pretty = false)
    }

    /** Decodes `select=*` rows (timestamps with microseconds and offsets accepted). Ids normalised to lower case. */
    fun decodeList(body: String): List<CloudBackupRecord> =
        rowJson.decodeFromString(ListSerializer(CloudBackupRecord.serializer()), body).map { it.copy(id = it.id.lowercase()) }

    /** Newest first (the server already orders; this is for merged/cached lists). */
    fun sortForList(records: List<CloudBackupRecord>): List<CloudBackupRecord> =
        records.sortedByDescending { it.createdAt }.take(LIST_LIMIT)

    // ---- Requests ----------------------------------------------------------------------------------------

    fun uploadObject(path: String, data: ByteArray) = HttpCall(
        "POST", "storage/v1/object/$BUCKET/$path", mapOf("Content-Type" to "application/json", "x-upsert" to "false"), data,
    )

    fun insertRow(record: CloudBackupRecord) = HttpCall(
        "POST", "rest/v1/backups", mapOf("Content-Type" to "application/json", "Prefer" to "return=minimal"),
        encodeRecord(record).toByteArray(),
    )

    fun verifyRowCall(backupId: String) = HttpCall("GET", "rest/v1/backups?select=id,object_path&id=eq.${backupId.uppercase()}")

    fun verifyDownloadCall(path: String) = downloadCallForPath(path)

    fun listCall() = HttpCall("GET", "rest/v1/backups?select=*&order=created_at.desc&limit=$LIST_LIMIT")

    fun downloadCall(record: CloudBackupRecord) = downloadCallForPath(record.objectPath)

    private fun downloadCallForPath(path: String) = HttpCall("GET", "storage/v1/object/authenticated/$BUCKET/$path")

    /** Removes files: `DELETE storage/v1/object/backups` with `{"prefixes":[...]}`. */
    fun deleteObjects(paths: List<String>) = HttpCall(
        "DELETE", "storage/v1/object/$BUCKET", mapOf("Content-Type" to "application/json"),
        SwiftJsonWriter.write(buildJsonObject { put("prefixes", JsonArray(paths.map { JsonPrimitive(it) })) }, pretty = false).toByteArray(),
    )

    fun deleteRow(backupId: String) = HttpCall("DELETE", "rest/v1/backups?id=eq.${backupId.uppercase()}")

    fun pruneListCall(deviceId: String) =
        HttpCall("GET", "rest/v1/backups?select=id,object_path,created_at&device_id=eq.$deviceId&order=created_at.desc")

    fun deleteRows(ids: List<String>) = HttpCall("DELETE", "rest/v1/backups?id=in.(${ids.joinToString(",")})")

    fun deleteAllListCall() = HttpCall("GET", "rest/v1/backups?select=id,object_path")

    fun deleteAllRowsCall() = HttpCall("DELETE", "rest/v1/backups?id=not.is.null")

    fun deleteAccountCall() = HttpCall("POST", "rest/v1/rpc/delete_my_account", mapOf("Content-Type" to "application/json"), "{}".toByteArray())

    // ---- Verification ------------------------------------------------------------------------------------

    /**
     * iOS `verifyUpload`: the row is readable (id case-insensitive, object_path equal), the stored file is
     * byte-for-byte what was sent, and it reads back as a supported backup.
     * @param rowsBody body of [verifyRowCall]; @param stored body of [verifyDownloadCall].
     */
    fun verifyUpload(backupId: String, path: String, sent: ByteArray, rowsBody: String, stored: ByteArray): Boolean {
        val rows = try { Json.parseToJsonElement(rowsBody).jsonArray } catch (_: Exception) { return false }
        val rowOk = rows.any { r ->
            val o = r as? JsonObject ?: return@any false
            o["id"]?.jsonPrimitive?.contentOrNull?.lowercase() == backupId.lowercase() &&
                o["object_path"]?.jsonPrimitive?.contentOrNull == path
        }
        if (!rowOk || !stored.contentEquals(sent)) return false
        return try { BackupCodec.decode(stored); true } catch (_: BackupException) { false }
    }

    /** Download validation: damaged -> [BackupException.Unreadable], newer -> [BackupException.UnsupportedVersion]. */
    fun decodeDownloaded(data: ByteArray): BackupPayload = BackupCodec.decode(data)

    // ---- Retention ---------------------------------------------------------------------------------------

    data class PruneSelection(val ids: List<String>, val paths: List<String>) {
        val isEmpty: Boolean get() = ids.isEmpty()
    }

    /**
     * iOS `pruneOldBackups`: from THIS device's rows ([pruneListCall] body), the ones created before
     * `now − retentionDays·86400 s`, never the newest (just verified) backup, never a row whose date can't be read.
     * Call only after a verified upload. Ids are returned as the server sent them.
     */
    fun selectExpired(rowsBody: String, newestId: String, now: Long, retentionDays: Int): PruneSelection {
        val rows = try { Json.parseToJsonElement(rowsBody).jsonArray } catch (_: Exception) { return PruneSelection(emptyList(), emptyList()) }
        val cutoff = now - retentionDays.toLong() * 86_400_000L
        val expired = rows.mapNotNull { it as? JsonObject }.filter { row ->
            val id = row["id"]?.jsonPrimitive?.contentOrNull ?: return@filter false
            if (id.lowercase() == newestId.lowercase()) return@filter false
            val created = row["created_at"]?.jsonPrimitive?.contentOrNull?.let(SwiftDates::parse) ?: return@filter false
            created < cutoff
        }
        return PruneSelection(
            ids = expired.mapNotNull { it["id"]?.jsonPrimitive?.contentOrNull },
            paths = expired.mapNotNull { it["object_path"]?.jsonPrimitive?.contentOrNull },
        )
    }

    /** Object paths from [deleteAllListCall]'s body. */
    fun objectPaths(rowsBody: String): List<String> =
        Json.parseToJsonElement(rowsBody).jsonArray.mapNotNull { (it as? JsonObject)?.get("object_path")?.jsonPrimitive?.contentOrNull }

    // ---- Change detection --------------------------------------------------------------------------------

    /**
     * iOS `CloudBackupService.contentHash`: lower-case hex SHA-256 of the compact, sorted-keys JSON (Swift
     * `CloudJSON.encoder()`) of `{accounts, channelRules?, expenses, movements, profiles, rules, sample, settlements}`,
     * each list sorted by upper-case UUID string; `channelRules` omitted when empty; exportDate and accountName NOT included.
     */
    fun contentHash(payload: BackupPayload): String {
        val j = BackupCodec.json
        fun <T> arr(items: List<T>, ser: kotlinx.serialization.KSerializer<T>) = j.encodeToJsonElement(ListSerializer(ser), items)
        val content = buildJsonObject {
            put("expenses", arr(payload.expenses.sortedBy { it.id.uppercase() }, com.spendrop.core.backup.ExpenseDto.serializer()))
            put("profiles", arr(payload.paybookProfiles.sortedBy { it.id.uppercase() }, com.spendrop.core.backup.PayBookProfileDto.serializer()))
            put("accounts", arr(payload.accounts.orEmpty().sortedBy { it.id.uppercase() }, com.spendrop.core.backup.AccountDto.serializer()))
            put("movements", arr(payload.moneyMovements.orEmpty().sortedBy { it.id.uppercase() }, com.spendrop.core.backup.MoneyMovementDto.serializer()))
            put("rules", arr(payload.classificationRules.orEmpty().sortedBy { it.id.uppercase() }, com.spendrop.core.backup.ClassificationRuleDto.serializer()))
            put("settlements", arr(payload.settlementAllocations.orEmpty().sortedBy { it.id.uppercase() }, com.spendrop.core.backup.SettlementAllocationDto.serializer()))
            put("sample", arr(payload.sampleRecords.orEmpty().sortedBy { it.recordID.uppercase() }, com.spendrop.core.backup.SampleRecordDto.serializer()))
            val channel = payload.channelRules.orEmpty()
            if (channel.isNotEmpty()) put("channelRules", arr(channel.sortedBy { it.id.uppercase() }, com.spendrop.core.backup.ChannelRuleDto.serializer()))
        }
        val bytes = SwiftJsonWriter.write(content, pretty = false).toByteArray(Charsets.UTF_8)
        return MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }

    /** Manual backups always upload; an automatic one is skipped (counts as done) when nothing changed. */
    fun shouldUpload(force: Boolean, hash: String, lastVerifiedHash: String?): Boolean = force || hash != lastVerifiedHash
}
