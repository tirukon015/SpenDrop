package com.spendrop.core.cloud

import com.spendrop.core.Ids
import com.spendrop.core.model.FinanceSnapshot

/** Rows pulled from the cloud tables (any subset; usually "changed since the cursor"). */
data class CloudPull(
    val accounts: List<AccountRow> = emptyList(),
    val people: List<PersonRow> = emptyList(),
    val paymentMethods: List<PersonPaymentMethodRow> = emptyList(),
    val expenses: List<ExpenseRow> = emptyList(),
    val shares: List<ExpenseShareRow> = emptyList(),
    val movements: List<MoneyMovementRow> = emptyList(),
    val allocations: List<SettlementAllocationRow> = emptyList(),
    val classificationRules: List<ClassificationRuleRow> = emptyList(),
    val channelRules: List<ChannelRuleRow> = emptyList(),
) {
    /** Largest server_updated_at seen (the next pull cursor), as the server's text; null when nothing has one. */
    val maxServerUpdatedAt: String?
        get() = (accounts.map { it.serverUpdatedAt } + people.map { it.serverUpdatedAt } + paymentMethods.map { it.serverUpdatedAt } +
            expenses.map { it.serverUpdatedAt } + shares.map { it.serverUpdatedAt } + movements.map { it.serverUpdatedAt } +
            allocations.map { it.serverUpdatedAt } + classificationRules.map { it.serverUpdatedAt } + channelRules.map { it.serverUpdatedAt })
            .filterNotNull().maxByOrNull { com.spendrop.core.backup.SwiftDates.parse(it) ?: Long.MIN_VALUE }
}

/** Per-type outcome of a last-writer-wins merge. */
data class LwwResult<T>(
    /** Every record after the merge (local records untouched by the pull are kept as they are). */
    val merged: List<T>,
    /** Remote versions that replaced or added a local record: write these locally. */
    val applied: List<T>,
    /** Local records newer than the pulled row: push these (the server would otherwise keep the older one). */
    val localNewer: List<T>,
)

data class SyncMergeResult(val merged: FinanceSnapshot, val applied: FinanceSnapshot, val localNewer: FinanceSnapshot)

/**
 * Last-writer-wins on `updated_at` (the client edit time), tombstones included: a remote row whose updated_at is
 * strictly newer replaces the local record (a remote `deleted_at` therefore deletes locally; a newer local edit
 * survives an older remote tombstone). Equal times keep the local record. Ids compare case-insensitively.
 */
object SyncMerge {
    fun <T> lww(local: List<T>, remote: List<T>, id: (T) -> String, updatedAt: (T) -> Long): LwwResult<T> {
        val merged = LinkedHashMap<String, T>()
        local.forEach { merged[Ids.normalize(id(it))] = it }
        val applied = mutableListOf<T>()
        val localNewer = mutableListOf<T>()
        // If the pull contains the same id twice, the newest version counts.
        val newestRemote = remote.groupBy { Ids.normalize(id(it)) }.mapValues { (_, v) -> v.maxBy(updatedAt) }
        for ((k, r) in newestRemote) {
            val l = merged[k]
            when {
                l == null || updatedAt(r) > updatedAt(l) -> { merged[k] = r; applied += r }
                updatedAt(l) > updatedAt(r) -> localNewer += l
            }
        }
        return LwwResult(merged.values.toList(), applied, localNewer)
    }

    /** Merges a pull into the local data (tombstones included in both). */
    fun merge(local: FinanceSnapshot, pull: CloudPull): SyncMergeResult {
        val localExpenses = local.expenses.associateBy { Ids.normalize(it.id) }
        val accounts = lww(local.accounts, pull.accounts.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val people = lww(local.people, pull.people.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val methods = lww(local.paymentMethods, pull.paymentMethods.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val expenses = lww(local.expenses, pull.expenses.map { CloudRows.fromRow(it, localExpenses[Ids.normalize(it.id)]) }, { it.id }, { it.updatedAt })
        val shares = lww(local.shares, pull.shares.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val movements = lww(local.movements, pull.movements.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val allocations = lww(local.allocations, pull.allocations.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val rules = lww(local.classificationRules, pull.classificationRules.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        val channel = lww(local.channelRules, pull.channelRules.map(CloudRows::fromRow), { it.id }, { it.updatedAt })
        fun pick(sel: (LwwResult<*>) -> List<*>): FinanceSnapshot {
            @Suppress("UNCHECKED_CAST")
            return FinanceSnapshot(
                expenses = sel(expenses) as List<com.spendrop.core.model.Expense>,
                shares = sel(shares) as List<com.spendrop.core.model.ExpenseShare>,
                accounts = sel(accounts) as List<com.spendrop.core.model.Account>,
                people = sel(people) as List<com.spendrop.core.model.Person>,
                paymentMethods = sel(methods) as List<com.spendrop.core.model.PersonPaymentMethod>,
                movements = sel(movements) as List<com.spendrop.core.model.MoneyMovement>,
                allocations = sel(allocations) as List<com.spendrop.core.model.SettlementAllocation>,
                classificationRules = sel(rules) as List<com.spendrop.core.model.ClassificationRule>,
                channelRules = sel(channel) as List<com.spendrop.core.model.ChannelRule>,
            )
        }
        return SyncMergeResult(
            merged = pick { it.merged }.copy(sampleRecords = local.sampleRecords),
            applied = pick { it.applied },
            localNewer = pick { it.localNewer },
        )
    }
}
