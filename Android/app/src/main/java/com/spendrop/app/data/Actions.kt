package com.spendrop.app.data

import com.spendrop.core.ledger.SettlementChange
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.Person

/** Converts pure-logic results into repository writes. Deletes are tombstones. */
suspend fun FinanceRepository.applySettlement(change: SettlementChange, s: FinanceSnapshot, now: Long = System.currentTimeMillis()) {
    val goneM = change.tombstoneMovementIds.toSet()
    val goneA = change.tombstoneAllocationIds.toSet()
    apply(
        Changes(
            movements = change.newMovements + s.movements.filter { it.id in goneM }.map { it.copy(deletedAt = now, updatedAt = now) },
            allocations = change.newAllocations + s.allocations.filter { it.id in goneA }.map { it.copy(deletedAt = now, updatedAt = now) },
        ),
    )
}

/** Deletes a person and their payment methods. History keeps their name through the records' name snapshots. */
suspend fun FinanceRepository.deletePerson(person: Person, s: FinanceSnapshot, now: Long = System.currentTimeMillis()) {
    apply(
        Changes(
            people = listOf(person.copy(deletedAt = now, updatedAt = now)),
            paymentMethods = s.paymentMethods.filter { it.personId == person.id }.map { it.copy(deletedAt = now, updatedAt = now) },
        ),
    )
}

/** Writes the result of a backup import / restore merge: upserts, plus tombstones for shares the backup replaced. */
suspend fun FinanceRepository.applyMerge(result: com.spendrop.core.backup.BackupMergeResult, now: Long = System.currentTimeMillis()) {
    val c = result.changes
    val removed = result.removedShareIds.toSet()
    val tombstones = if (removed.isEmpty()) emptyList() else fullSnapshot(includeDeleted = true).shares
        .filter { it.id in removed && it.deletedAt == null }.map { it.copy(deletedAt = now, updatedAt = now) }
    apply(
        Changes(
            expenses = c.expenses, shares = c.shares + tombstones, accounts = c.accounts, people = c.people, paymentMethods = c.paymentMethods,
            movements = c.movements, allocations = c.allocations, classificationRules = c.classificationRules, channelRules = c.channelRules,
            sampleRecords = c.sampleRecords,
        ),
    )
}
