package com.spendrop.app.cloud

import com.spendrop.app.data.Changes
import com.spendrop.app.data.FinanceRepository
import com.spendrop.app.data.Preferences
import com.spendrop.core.cloud.AccountRow
import com.spendrop.core.cloud.ChannelRuleRow
import com.spendrop.core.cloud.ClassificationRuleRow
import com.spendrop.core.cloud.CloudPull
import com.spendrop.core.cloud.CloudRows
import com.spendrop.core.cloud.CloudTables
import com.spendrop.core.cloud.ExpenseRow
import com.spendrop.core.cloud.ExpenseShareRow
import com.spendrop.core.cloud.MoneyMovementRow
import com.spendrop.core.cloud.PersonPaymentMethodRow
import com.spendrop.core.cloud.PersonRow
import com.spendrop.core.cloud.SettlementAllocationRow
import com.spendrop.core.cloud.SyncMerge
import com.spendrop.core.model.FinanceSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class SyncReport(val succeeded: Boolean, val message: String, val at: Long, val pulled: Int = 0, val pushed: Int = 0, val skipped: Int = 0)

/**
 * Live sync with the SpenDrop cloud records (the same tables the Web App uses), following Docs/Sync-Architecture.md:
 * - identity = the record's UUID (never merchant/amount/date);
 * - pull per table with keyset pagination on `server_updated_at` (cursor stored per table), merged last-writer-wins on
 *   `updated_at`, tombstones included;
 * - push changed records: upsert on `id`; an expense and its split through `save_expense_with_shares` (atomic);
 * - deletes are tombstones (`deleted_at`); nothing is ever hard-deleted on either side.
 * Opt-in per account. Sample data stays on this phone. iOS doesn't sync yet: it reaches the cloud only via backups.
 */
class SyncService(
    private val http: SupabaseHttp?,
    private val auth: AuthService,
    private val repository: FinanceRepository,
    private val prefs: Preferences,
) {
    private val mutex = Mutex()
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running
    private val _last = MutableStateFlow<SyncReport?>(null)
    val last: StateFlow<SyncReport?> = _last
    private val json = CloudRows.json

    suspend fun isEnabled(): Boolean {
        val u = auth.currentUser ?: return false
        return prefs.get(Preferences.Keys.syncUser) == u.id
    }

    /** The account this phone's data was last synced with (null = never synced). */
    suspend fun owner(): String? = prefs.get(Preferences.Keys.ownerUserId)

    /** Starts syncing for the signed-in user. Returns false (nothing changed) if the phone's data belongs to another account. */
    suspend fun enable(): Boolean {
        val u = auth.currentUser ?: return false
        val owner = owner()
        if (owner != null && owner != u.id) return false
        if (owner == null) {
            // First sync of this phone: every live local record is pushed once, then only changes.
            prefs.set(Preferences.Keys.syncPushWatermark, "0")
            CloudTables.pushOrder.forEach { prefs.set(Preferences.Keys.syncCursor(it), null) }
        }
        prefs.set(Preferences.Keys.ownerUserId, u.id)
        prefs.set(Preferences.Keys.syncUser, u.id)
        return true
    }

    suspend fun disable() = prefs.set(Preferences.Keys.syncUser, null)

    /** "Start fresh": erase this phone's local copy, then sync with the signed-in account. Local photos/receipts stay. */
    suspend fun startFreshForCurrentUser() {
        repository.eraseAll()
        prefs.set(Preferences.Keys.ownerUserId, null)
        enable()
    }

    suspend fun syncNow(): SyncReport = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { syncLocked() }

    private suspend fun syncLocked(): SyncReport = mutex.withLock {
        if (!isEnabled()) return SyncReport(false, "Sync is off.", System.currentTimeMillis())
        _running.value = true
        val started = System.currentTimeMillis()
        val report = try {
            val token = auth.validAccessToken()
            val (pulled, appliedIds) = pull(token)
            val (pushed, skipped) = push(token, appliedIds, started)
            prefs.set(Preferences.Keys.syncPushWatermark, nextWatermark.toString())
            prefs.set(Preferences.Keys.syncLastAt, started.toString())
            SyncReport(true, if (skipped > 0) "Synced. $skipped records couldn't be uploaded and will be retried." else "Up to date.", started, pulled, pushed, skipped)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            SyncReport(false, (e as? CloudError)?.message ?: "Sync failed. Your data is safe on this phone; it will retry.", started)
        } finally {
            _running.value = false
        }
        prefs.set(Preferences.Keys.syncLastMessage, "${if (report.succeeded) "ok" else "fail"}|${report.at}|${report.message}")
        _last.value = report
        report
    }

    suspend fun lastReport(): SyncReport? = _last.value ?: prefs.get(Preferences.Keys.syncLastMessage)?.split("|", limit = 3)?.takeIf { it.size == 3 }?.let {
        SyncReport(it[0] == "ok", it[2], it[1].toLongOrNull() ?: 0)
    }

    // ------------------------------------------------------------------------------------------------- pull

    private suspend fun pull(token: String): Pair<Int, Set<String>> {
        val pullData = CloudPull(
            accounts = pullTable(token, CloudTables.ACCOUNTS, AccountRow.serializer()),
            people = pullTable(token, CloudTables.PEOPLE, PersonRow.serializer()),
            paymentMethods = pullTable(token, CloudTables.PERSON_PAYMENT_METHODS, PersonPaymentMethodRow.serializer()),
            expenses = pullTable(token, CloudTables.EXPENSES, ExpenseRow.serializer()),
            shares = pullTable(token, CloudTables.EXPENSE_SHARES, ExpenseShareRow.serializer()),
            movements = pullTable(token, CloudTables.MONEY_MOVEMENTS, MoneyMovementRow.serializer()),
            allocations = pullTable(token, CloudTables.SETTLEMENT_ALLOCATIONS, SettlementAllocationRow.serializer()),
            classificationRules = pullTable(token, CloudTables.CLASSIFICATION_RULES, ClassificationRuleRow.serializer()),
            channelRules = pullTable(token, CloudTables.CHANNEL_RULES, ChannelRuleRow.serializer()),
        )
        val local = repository.fullSnapshot(includeDeleted = true)
        val result = SyncMerge.merge(local, pullData)
        val a = result.applied
        // A learned rule is unique per key: if the cloud has one under another id, the cloud's replaces ours.
        val replacedRules = a.classificationRules.flatMap { r -> local.classificationRules.filter { it.merchantKey == r.merchantKey && it.id != r.id }.map { it.id } }
        val replacedChannel = a.channelRules.flatMap { r -> local.channelRules.filter { it.merchantKey == r.merchantKey && it.fundingKey == r.fundingKey && it.id != r.id }.map { it.id } }
        repository.applyPulled(
            Changes(expenses = a.expenses, shares = a.shares, accounts = a.accounts, people = a.people, paymentMethods = a.paymentMethods,
                movements = a.movements, allocations = a.allocations, classificationRules = a.classificationRules, channelRules = a.channelRules),
            replacedRules, replacedChannel,
        )
        // Cursors only move after the data is safely written.
        cursorsToSave.forEach { (t, c) -> prefs.set(Preferences.Keys.syncCursor(t), c) }
        cursorsToSave.clear()
        val ids = (a.expenses.map { it.id } + a.shares.map { it.id } + a.accounts.map { it.id } + a.people.map { it.id } + a.paymentMethods.map { it.id } +
            a.movements.map { it.id } + a.allocations.map { it.id } + a.classificationRules.map { it.id } + a.channelRules.map { it.id }).toSet()
        return ids.size to ids
    }

    private val cursorsToSave = HashMap<String, String>()

    private suspend fun <T> pullTable(token: String, table: String, ser: KSerializer<T>): List<T> {
        val h = http ?: throw CloudError.NotConfigured
        val since = prefs.get(Preferences.Keys.syncCursor(table))
        val out = ArrayList<JsonObject>()
        var cursor = since
        while (true) {
            val q = linkedMapOf("select" to "*", "order" to "server_updated_at.asc,id.asc", "limit" to PAGE.toString())
            if (cursor != null) q["server_updated_at"] = "gt.$cursor"
            val page = (json.parseToJsonElement(h.send("GET", "/rest/v1/$table", q, token).decodeToString()) as JsonArray).map { it.jsonObject }
            out += page
            if (page.size < PAGE) break
            val last = page.last()["server_updated_at"]?.jsonPrimitive?.contentOrNull ?: break
            // Rows sharing the boundary timestamp are fetched together so none are skipped.
            val same = (json.parseToJsonElement(h.send("GET", "/rest/v1/$table", mapOf("select" to "*", "server_updated_at" to "eq.$last"), token).decodeToString()) as JsonArray).map { it.jsonObject }
            val seen = out.map { it["id"]?.jsonPrimitive?.contentOrNull }.toSet()
            out += same.filter { it["id"]?.jsonPrimitive?.contentOrNull !in seen }
            cursor = last
        }
        val max = out.mapNotNull { it["server_updated_at"]?.jsonPrimitive?.contentOrNull }.maxByOrNull { com.spendrop.core.backup.SwiftDates.parse(it) ?: Long.MIN_VALUE }
        if (max != null) cursorsToSave[table] = max
        return out.mapNotNull { runCatching { json.decodeFromJsonElement(ser, it) }.getOrNull() }
    }

    // ------------------------------------------------------------------------------------------------- push

    private suspend fun push(token: String, justPulled: Set<String>, started: Long): Pair<Int, Int> {
        val watermark = prefs.get(Preferences.Keys.syncPushWatermark)?.toLongOrNull() ?: 0L
        val all = repository.fullSnapshot(includeDeleted = true)
        val sampleIds = all.sampleRecords.map { it.recordId }.toSet()
        fun keep(id: String, updatedAt: Long, sample: Boolean = false) = updatedAt > watermark &&
            id !in justPulled && id !in sampleIds && !sample
        val s = Sanitize.snapshot(all)
        var pushed = 0
        var skipped = 0
        var oldestSkipped = Long.MAX_VALUE
        suspend fun <T> upsert(table: String, rows: List<Pair<T, Long>>, ser: KSerializer<T>) {
            for (batch in rows.chunked(500)) {
                val ok = runCatching { upsertBatch(token, table, batch.map { it.first }, ser) }.isSuccess
                if (ok) { pushed += batch.size; continue }
                // Isolate a bad row so it can't block the others; it is retried on the next sync.
                for ((row, at) in batch) {
                    if (runCatching { upsertBatch(token, table, listOf(row), ser) }.isSuccess) pushed++
                    else { skipped++; oldestSkipped = minOf(oldestSkipped, at) }
                }
            }
        }
        upsert(CloudTables.ACCOUNTS, s.accounts.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, AccountRow.serializer())
        upsert(CloudTables.PEOPLE, s.people.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, PersonRow.serializer())
        upsert(CloudTables.PERSON_PAYMENT_METHODS, s.paymentMethods.filter { keep(it.id, it.updatedAt) && it.personId !in sampleIds }.map { CloudRows.toRow(it) to it.updatedAt }, PersonPaymentMethodRow.serializer())
        // Expenses with their split, atomically. A changed share means its expense is pushed with all its shares.
        val changedShareExpenses = s.shares.filter { keep(it.id, it.updatedAt) }.map { it.expenseId }.toSet()
        for (e in s.expenses) {
            if (!(keep(e.id, e.updatedAt, e.isSampleData) || (e.id in changedShareExpenses && e.id !in sampleIds && !e.isSampleData))) continue
            if (e.amountMinor <= 0) continue // can't exist in the cloud (amount must be > 0)
            val shares = s.shares.filter { it.expenseId == e.id && it.deletedAt == null }
            val ok = runCatching {
                http!!.sendJson("POST", "/rest/v1/rpc/save_expense_with_shares", CloudRows.saveExpenseArgs(e, shares).toString(), token = token)
            }.isSuccess
            if (ok) pushed++ else { skipped++; oldestSkipped = minOf(oldestSkipped, e.updatedAt) }
        }
        upsert(CloudTables.MONEY_MOVEMENTS, s.movements.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, MoneyMovementRow.serializer())
        upsert(CloudTables.SETTLEMENT_ALLOCATIONS, s.allocations.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, SettlementAllocationRow.serializer())
        upsert(CloudTables.CLASSIFICATION_RULES, s.classificationRules.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, ClassificationRuleRow.serializer())
        upsert(CloudTables.CHANNEL_RULES, s.channelRules.filter { keep(it.id, it.updatedAt) }.map { CloudRows.toRow(it) to it.updatedAt }, ChannelRuleRow.serializer())
        nextWatermark = if (oldestSkipped == Long.MAX_VALUE) started else minOf(started, oldestSkipped - 1)
        return pushed to skipped
    }

    private var nextWatermark = 0L

    private suspend fun <T> upsertBatch(token: String, table: String, rows: List<T>, ser: KSerializer<T>) {
        if (rows.isEmpty()) return
        val body = json.encodeToString(ListSerializer(ser), rows)
        http!!.sendJson("POST", "/rest/v1/$table", body, mapOf("on_conflict" to "id"), token,
            mapOf("Prefer" to "resolution=merge-duplicates,return=minimal"))
    }

    companion object { const val PAGE = 1000 }
}

/** Keeps text within the cloud's column limits so a long OCR note can't block a whole upload. */
object Sanitize {
    private fun String.cap(n: Int) = if (length > n) take(n) else this
    private fun String?.capN(n: Int) = this?.cap(n)
    fun snapshot(s: FinanceSnapshot) = s.copy(
        expenses = s.expenses.map { it.copy(merchant = it.merchant.cap(200).ifBlank { "Unknown" }, fundingAccount = it.fundingAccount.cap(80),
            notes = it.notes.capN(4000), transactionReference = it.transactionReference.capN(120)) },
        accounts = s.accounts.map { it.copy(name = it.name.trim().cap(80).ifBlank { "Account" }) },
        people = s.people.map { it.copy(name = it.name.trim().cap(80).ifBlank { "Person" }, notes = it.notes.capN(2000)) },
        paymentMethods = s.paymentMethods.map { it.copy(accountIdentifier = it.accountIdentifier.cap(120)) },
        movements = s.movements.map { it.copy(note = it.note.capN(4000)) },
    )
}
