package com.spendrop.core.backup

import com.spendrop.core.Ids
import com.spendrop.core.model.FinanceSnapshot
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Which part of a full backup to restore (iOS `RestoreRange`). Ranges are whole calendar days ending on the backup's
 * own day (its `exportDate`), so the same backup always gives the same range no matter when the restore runs.
 */
sealed class RestoreRange {
    data object Everything : RestoreRange()
    data class LastDays(val days: Int) : RestoreRange()
    data class LastMonths(val months: Int) : RestoreRange()
    /** Inclusive start and end days (time of day ignored); epoch ms instants, read in the zone passed to [interval]. */
    data class Custom(val start: Long, val end: Long) : RestoreRange()

    val title: String
        get() = when (this) {
            Everything -> "Everything"
            is LastDays -> "Last $days days"
            is LastMonths -> "Last $months months"
            is Custom -> "Custom range"
        }

    /**
     * Half-open [start, end) covering whole days in [zone]; null = no date filter (Everything) or an invalid custom range.
     * - Last N days: the backup day and the N − 1 days before it (7 days from 5 Oct = 29 Sep – 5 Oct).
     * - Last N months: from the day after the same date N months earlier (2 months from 5 Oct = 6 Aug – 5 Oct;
     *   from 31 Mar = 1 Feb – 31 Mar: month ends clamp, leap days respected).
     */
    fun interval(reference: Long, zone: ZoneId): RestoreInterval? {
        val referenceDay = day(reference, zone)
        val end = startOf(referenceDay.plusDays(1), zone)
        return when (this) {
            Everything -> null
            is LastDays -> RestoreInterval(startOf(referenceDay.minusDays((maxOf(days, 1) - 1).toLong()), zone), end)
            is LastMonths -> RestoreInterval(startOf(referenceDay.minusMonths(maxOf(months, 1).toLong()).plusDays(1), zone), end)
            is Custom -> {
                val s = startOf(day(start, zone), zone)
                val e = startOf(day(this.end, zone).plusDays(1), zone)
                if (s < e) RestoreInterval(s, e) else null
            }
        }
    }

    /** Custom ranges: start must not be after end. Other ranges are always valid. */
    fun validationProblem(zone: ZoneId): String? {
        if (this !is Custom) return null
        return if (day(start, zone) > day(end, zone)) "The start date must be on or before the end date." else null
    }

    companion object {
        val LAST_7_DAYS = LastDays(7)
        val LAST_30_DAYS = LastDays(30)
        val LAST_2_MONTHS = LastMonths(2)
        val LAST_3_MONTHS = LastMonths(3)
        /** The choices iOS offers (plus Custom). */
        val presets: List<RestoreRange> = listOf(Everything, LAST_7_DAYS, LAST_30_DAYS, LAST_2_MONTHS, LAST_3_MONTHS)

        private fun day(ms: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        private fun startOf(day: LocalDate, zone: ZoneId): Long = day.atStartOfDay(zone).toInstant().toEpochMilli()
    }
}

/** Half-open day interval built by [RestoreRange] (the end instant belongs to the next day). Epoch ms. */
data class RestoreInterval(val start: Long, val end: Long) {
    fun contains(date: Long): Boolean = date >= start && date < end
    val durationMillis: Long get() = end - start

    /** "29 Sep 2026 – 5 Oct 2026" (the last included day, not the exclusive end). */
    fun description(zone: ZoneId, locale: Locale = Locale.getDefault()): String {
        val f = DateTimeFormatter.ofPattern("d MMM yyyy", locale)
        val first = Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
        val last = Instant.ofEpochMilli(end).atZone(zone).toLocalDate().minusDays(1)
        return "${f.format(first)} – ${f.format(last)}"
    }
}

/** iOS `RecordCounts` (restore plan counts). */
data class RecordCounts(
    val expenses: Int = 0,
    val accounts: Int = 0,
    val movements: Int = 0,
    val profiles: Int = 0,
    val rules: Int = 0,
) {
    val total: Int get() = expenses + accounts + movements + profiles + rules
}

/** Ids already on this device (iOS `LocalRecordIDs`); tombstoned records don't count. */
data class LocalRecordIds(
    val expenses: Set<String> = emptySet(),
    val accounts: Set<String> = emptySet(),
    val accountNames: Set<String> = emptySet(),
    val movements: Set<String> = emptySet(),
    val profiles: Set<String> = emptySet(),
) {
    companion object {
        fun from(local: FinanceSnapshot): LocalRecordIds {
            val accounts = local.accounts.filter { it.deletedAt == null }
            return LocalRecordIds(
                expenses = local.expenses.filter { it.deletedAt == null }.map { Ids.normalize(it.id) }.toSet(),
                accounts = accounts.map { Ids.normalize(it.id) }.toSet(),
                accountNames = accounts.mapNotNull { BackupKeys.accountKey(it.name) }.toSet(),
                movements = local.movements.filter { it.deletedAt == null }.map { Ids.normalize(it.id) }.toSet(),
                profiles = local.people.filter { it.deletedAt == null }.map { Ids.normalize(it.id) }.toSet(),
            )
        }
    }
}

/** What a restore will write, computed before anything is written. */
data class RestorePlan(
    val range: RestoreRange,
    val interval: RestoreInterval?,
    /** The filtered backup handed to the id-based merge. */
    val payload: BackupPayload,
    val counts: RecordCounts,
    /** Of those, records whose id (or, for accounts, name) is already on this device: merged, never duplicated. */
    val alreadyOnDevice: RecordCounts,
    /** Money records in the range that point to an expense outside it. */
    val linksOutsideRange: Int,
) {
    val isEmpty: Boolean get() = counts.total == 0
}

data class RestoreResult(val plan: RestorePlan, val merge: BackupMergeResult) {
    val summary: ImportSummary get() = merge.summary
    /** New records written to this device. */
    val added: RecordCounts
        get() = RecordCounts(
            expenses = summary.expensesAdded, accounts = summary.accountsAdded, movements = summary.movementsAdded,
            profiles = summary.profilesAdded, rules = summary.rulesRestored,
        )
}

object BackupRestore {
    /**
     * iOS `makeRestorePlan`. Expenses and money records are filtered by their own date; everything they depend on
     * (funding accounts by id or name, payers and split people, money-record people and accounts, learned
     * categories/channels for the restored merchants, settlements, sample markers) comes along whatever its date.
     *
     * @param ruleKey iOS `TransactionClassifier.ruleKey` (the recognised merchant's key). Pass the merchant detector's
     *   version when available; the default ([BackupKeys.merchantKey]) covers rules saved under the merchant text.
     */
    fun makeRestorePlan(
        backup: BackupPayload,
        range: RestoreRange,
        zone: ZoneId = ZoneId.systemDefault(),
        localIds: LocalRecordIds = LocalRecordIds(),
        ruleKey: (String?) -> String? = BackupKeys::merchantKey,
    ): RestorePlan {
        val interval = range.interval(backup.exportDate, zone)
        var linksOutside = 0
        val payload: BackupPayload = if (range == RestoreRange.Everything) {
            backup
        } else if (interval != null) {
            val expenses = backup.expenses.filter { interval.contains(it.date) }
            val movements = backup.moneyMovements.orEmpty().filter { interval.contains(it.date) }
            val expenseIds = expenses.map { it.id }.toSet()
            linksOutside = movements.count { m -> m.linkedExpenseId?.let { it !in expenseIds } ?: false }

            val accountIds = HashSet<String>()
            expenses.mapNotNullTo(accountIds) { it.accountId }
            movements.mapNotNullTo(accountIds) { it.accountId }
            movements.mapNotNullTo(accountIds) { it.counterAccountId }
            val fundingNames = expenses.mapNotNull { BackupKeys.accountKey(it.fundingAccount) }.toSet()

            val merchantKeys = expenses.flatMap { listOfNotNull(ruleKey(it.merchant), BackupKeys.merchantKey(it.merchant)) }.toSet()
            val rules = backup.classificationRules.orEmpty().filter { it.merchantKey in merchantKeys }
            rules.mapNotNullTo(accountIds) { it.accountId }

            val accounts = backup.accounts.orEmpty().filter { a ->
                a.id in accountIds || (BackupKeys.accountKey(a.name)?.let { it in fundingNames } ?: false)
            }
            val personIds = HashSet<String>()
            expenses.mapNotNullTo(personIds) { it.payerId }
            expenses.forEach { e -> e.shares.orEmpty().mapNotNullTo(personIds) { it.personId } }
            movements.mapNotNullTo(personIds) { it.personId }
            val profiles = backup.paybookProfiles.filter { it.id in personIds }

            val movementIds = movements.map { it.id }.toSet()
            val allocations = backup.settlementAllocations?.filter { a ->
                a.paymentID?.let { it in movementIds }
                    ?: ((a.expenseID?.let { it in expenseIds } ?: false) || (a.loanID?.let { it in movementIds } ?: false))
            }
            val kept = HashSet<String>().apply {
                addAll(expenseIds); addAll(movementIds); accounts.mapTo(this) { it.id }; profiles.mapTo(this) { it.id }
                rules.mapTo(this) { it.id }; allocations?.mapTo(this) { it.id }
            }
            backup.copy(
                expenses = expenses,
                paybookProfiles = profiles,
                accounts = if (backup.accounts == null) null else accounts,
                moneyMovements = if (backup.moneyMovements == null) null else movements,
                classificationRules = if (backup.classificationRules == null) null else rules,
                channelRules = backup.channelRules?.filter { it.merchantKey in merchantKeys },
                settlementAllocations = allocations,
                sampleRecords = backup.sampleRecords?.filter { it.recordID in kept },
            )
        } else {
            // Invalid custom range: restore nothing.
            BackupPayload(version = backup.version, appName = backup.appName, accountName = backup.accountName,
                exportDate = backup.exportDate, expenses = emptyList(), paybookProfiles = emptyList())
        }

        val counts = RecordCounts(
            expenses = payload.expenses.size, accounts = payload.accounts?.size ?: 0, movements = payload.moneyMovements?.size ?: 0,
            profiles = payload.paybookProfiles.size, rules = payload.classificationRules?.size ?: 0,
        )
        val existing = RecordCounts(
            expenses = payload.expenses.count { it.id in localIds.expenses },
            accounts = payload.accounts.orEmpty().count { a ->
                a.id in localIds.accounts || (BackupKeys.accountKey(a.name)?.let { it in localIds.accountNames } ?: false)
            },
            movements = payload.moneyMovements.orEmpty().count { it.id in localIds.movements },
            profiles = payload.paybookProfiles.count { it.id in localIds.profiles },
            rules = 0,
        )
        return RestorePlan(range, interval, payload, counts, existing, linksOutside)
    }

    /**
     * iOS `applyRestorePlan`: merges the plan with the id-based merge. Nothing is ever deleted: records outside the
     * range and records only on this device are untouched. The caller writes `result.merge.changes` in ONE
     * transaction (and must save a local safety copy first, as iOS does before a cloud restore).
     */
    fun applyRestorePlan(plan: RestorePlan, local: FinanceSnapshot, now: Long, zone: ZoneId = ZoneId.systemDefault()): RestoreResult {
        if (!plan.payload.isSupportedVersion) throw BackupException.UnsupportedVersion(plan.payload.version)
        return RestoreResult(plan, BackupMerge.apply(plan.payload, local, now, zone))
    }

    /**
     * iOS `importFromJSON` (manual file import): decode, refuse newer formats, merge everything by id.
     * Throws [BackupException] before anything is merged.
     */
    fun importFromJson(text: String, local: FinanceSnapshot, now: Long, zone: ZoneId = ZoneId.systemDefault()): BackupMergeResult =
        BackupMerge.apply(BackupCodec.decode(text), local, now, zone)
}
