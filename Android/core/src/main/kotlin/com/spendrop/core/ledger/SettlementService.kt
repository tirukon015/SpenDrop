package com.spendrop.core.ledger

import com.spendrop.core.Ids
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.model.SettlementAllocation
import com.spendrop.core.model.SettlementKind
import kotlin.math.min

/** Why a settlement was refused. [message] is user-readable (the same words as iOS). Nothing is written. */
sealed class SettlementError(message: String) : Exception(message) {
    data object InvalidAmount : SettlementError("Enter an amount greater than zero.")
    data class ExceedsOutstanding(val debtTitle: String) : SettlementError("That's more than what's left on $debtTitle.")
    data object AllocationExceedsPayment : SettlementError("The amounts applied are more than the payment.")
    data object MixedPeopleOrDirections : SettlementError("These transactions can't be paid together.")
    data object NothingToSettle : SettlementError("Nothing is outstanding.")
    data class NotEnoughCredit(val availableMinor: Long, val currency: String) :
        SettlementError("Only ${PersonLedger.format(availableMinor, currency)} of credit is available. Apply less, or record a new payment.")
}

/**
 * The records one settlement action writes (or, for undo, removes). Insert [newMovements] and [newAllocations];
 * tombstone (set `deletedAt`) the ids in [tombstoneMovementIds] and [tombstoneAllocationIds].
 */
data class SettlementChange(
    val groupId: String,
    val newMovements: List<MoneyMovement> = emptyList(),
    val newAllocations: List<SettlementAllocation> = emptyList(),
    val tombstoneMovementIds: List<String> = emptyList(),
    val tombstoneAllocationIds: List<String> = emptyList(),
) {
    /** The snapshot after this change (tombstoned records dropped, since a snapshot holds live records only). */
    fun applyTo(s: FinanceSnapshot): FinanceSnapshot {
        val goneM = tombstoneMovementIds.toSet()
        val goneA = tombstoneAllocationIds.toSet()
        return s.copy(
            movements = s.movements.filter { it.id !in goneM } + newMovements,
            allocations = s.allocations.filter { it.id !in goneA } + newAllocations,
        )
    }
}

/**
 * Records settlements (iOS `SettlementService`) as pure functions: each returns a [SettlementChange] and throws a
 * [SettlementError] when invalid. Every action is one group that can be undone as a whole. Original expenses,
 * shares and loans are never modified; payments are normal Repayment Received / Repayment Made records.
 */
object SettlementService {
    private fun repayment(direction: Int, amountMinor: Long, currency: String, date: Long, person: Person, accountId: String?, note: String?, now: Long): MoneyMovement {
        val kind = if (direction > 0) MoneyMovementKind.REPAYMENT_RECEIVED else MoneyMovementKind.REPAYMENT_MADE
        return MoneyMovement(
            id = Ids.new(), kindRaw = kind.raw, directionRaw = kind.direction.raw, amountMinor = amountMinor, currency = currency,
            date = date, personId = person.id, personNameSnapshot = person.name, accountId = accountId, note = note,
            sourceTypeRaw = ExpenseSourceType.MANUAL.raw, createdAt = now, updatedAt = now,
        )
    }

    private fun allocation(group: String, kind: SettlementKind, paymentId: String?, debt: Debt, person: Person, direction: Int,
                           amount: Long, currency: String, date: Long, now: Long) = SettlementAllocation(
        id = Ids.new(), groupId = group, kindRaw = kind.raw, paymentId = paymentId, expenseId = debt.expenseId, loanId = debt.loanId,
        personId = person.id, direction = direction, amountMinor = amount, currency = currency, date = date, createdAt = now, updatedAt = now,
    )

    /** "Mark as Paid": one payment for exactly what's left on this debt. */
    fun markPaid(debt: Debt, person: Person, now: Long, date: Long = now, accountId: String? = null): SettlementChange {
        if (debt.outstandingMinor <= 0) throw SettlementError.NothingToSettle
        return recordPayment(person, debt.direction, debt.outstandingMinor, listOf(debt to debt.outstandingMinor), debt.currency,
            now, date, accountId, note = "Settled: ${debt.title}")
    }

    /**
     * One real payment between me and [person], applied to the chosen debts. Any part not applied stays as a
     * payment without a transaction (credit). Validated before anything is produced.
     */
    fun recordPayment(
        person: Person, direction: Int, amountMinor: Long, allocations: List<Pair<Debt, Long>>, currency: String,
        now: Long, date: Long = now, accountId: String? = null, note: String? = null,
    ): SettlementChange {
        if (amountMinor <= 0 || (direction != 1 && direction != -1)) throw SettlementError.InvalidAmount
        val applied = allocations.filter { it.second > 0 }
        for ((debt, amount) in applied) {
            if (debt.personId != person.id || debt.direction != direction || debt.currency != currency) throw SettlementError.MixedPeopleOrDirections
            if (amount > debt.outstandingMinor) throw SettlementError.ExceedsOutstanding(debt.title)
        }
        if (applied.sumOf { it.second } > amountMinor) throw SettlementError.AllocationExceedsPayment

        val group = Ids.new()
        val payment = repayment(direction, amountMinor, currency, date, person, accountId, note, now)
        val rows = applied.map { (debt, amount) -> allocation(group, SettlementKind.PAYMENT, payment.id, debt, person, direction, amount, currency, date, now) }
        return SettlementChange(group, listOf(payment), rows)
    }

    /**
     * Applies existing credit (unlinked parts of earlier repayments, oldest first) to the chosen debts. No new money
     * moves; undo removes only these allocations and the repayments stay.
     */
    fun applyCredit(
        s: FinanceSnapshot, person: Person, direction: Int, allocations: List<Pair<Debt, Long>>, currency: String,
        now: Long, date: Long = now,
    ): SettlementChange {
        val applied = allocations.filter { it.second > 0 }
        if (applied.isEmpty()) throw SettlementError.InvalidAmount
        for ((debt, amount) in applied) {
            if (debt.personId != person.id || debt.direction != direction || debt.currency != currency) throw SettlementError.MixedPeopleOrDirections
            if (amount > debt.outstandingMinor) throw SettlementError.ExceedsOutstanding(debt.title)
        }
        val available = DebtLedger.creditMinor(s, person, currency, direction)
        if (applied.sumOf { it.second } > available) throw SettlementError.NotEnoughCredit(available, currency)

        val group = Ids.new()
        val sources = DebtLedger.paymentUses(s, person)
            .filter { it.payment.currency == currency && it.direction == direction && it.unallocatedMinor > 0 }
            .map { it.payment.id to it.unallocatedMinor }.toMutableList()
        val rows = ArrayList<SettlementAllocation>()
        var index = 0
        for ((debt, amount) in applied) {
            var left = amount
            while (left > 0 && index < sources.size) {
                val take = min(left, sources[index].second)
                rows += allocation(group, SettlementKind.ASSIGN, sources[index].first, debt, person, direction, take, currency, date, now)
                sources[index] = sources[index].first to sources[index].second - take
                left -= take
                if (sources[index].second == 0L) index += 1
            }
        }
        return SettlementChange(group, newAllocations = rows)
    }

    /** Oldest first: fills each debt before moving to the next. Shown to the user before anything is recorded. */
    fun autoAllocate(amountMinor: Long, debts: List<Debt>): List<Pair<Debt, Long>> {
        var left = amountMinor
        val plan = ArrayList<Pair<Debt, Long>>()
        for (debt in debts.filter { it.outstandingMinor > 0 }.sortedWith(debtOrder)) {
            if (left <= 0) continue
            val amount = min(left, debt.outstandingMinor)
            plan += debt to amount
            left -= amount
        }
        return plan
    }

    /**
     * Settles everything with a person in one currency:
     * 1. earlier payments not linked to a transaction are applied to the oldest debts in their direction;
     * 2. debts in opposite directions cancel each other (no money moves);
     * 3. one payment for what remains, in the net direction.
     * Everything is one group, so [undo] restores the previous state exactly.
     */
    fun settleAll(s: FinanceSnapshot, person: Person, currency: String, now: Long, date: Long = now, accountId: String? = null): SettlementChange {
        val group = Ids.new()
        val debts = DebtLedger.debts(s, person).filter { it.currency == currency && it.outstandingMinor > 0 }.sortedWith(debtOrder)
        if (debts.isEmpty()) throw SettlementError.NothingToSettle
        val outstanding = HashMap<String, Long>().apply { for (d in debts) putIfAbsent(d.id, d.outstandingMinor) }
        val rows = ArrayList<SettlementAllocation>()
        val payments = ArrayList<MoneyMovement>()
        fun add(debt: Debt, amount: Long, kind: SettlementKind, paymentId: String?) {
            if (amount <= 0) return
            rows += allocation(group, kind, paymentId, debt, person, debt.direction, amount, currency, date, now)
            outstanding[debt.id] = (outstanding[debt.id] ?: 0) - amount
        }

        // 1. Earlier unlinked payments.
        val personMovements = PersonLedger.movements(s, person.id)
        val existing = DebtLedger.active(DebtLedger.allocations(s), personMovements.map { it.id }.toSet())
        for (payment in personMovements.sortedBy { it.date }) {
            if (payment.currency != currency) continue
            val direction = when (payment.kind) {
                MoneyMovementKind.REPAYMENT_RECEIVED -> 1
                MoneyMovementKind.REPAYMENT_MADE -> -1
                else -> continue
            }
            var free = payment.amountMinor - existing.filter { it.paymentId == payment.id }.sumOf { it.amountMinor }
            for (debt in debts) {
                if (debt.direction != direction || free <= 0) continue
                val amount = min(free, outstanding[debt.id] ?: 0)
                add(debt, amount, SettlementKind.ASSIGN, payment.id)
                free -= amount
            }
        }

        // 2. Offsets.
        fun total(direction: Int): Long = debts.filter { it.direction == direction }.sumOf { outstanding[it.id] ?: 0 }
        val offset = min(total(1), total(-1))
        if (offset > 0) {
            for (direction in listOf(1, -1)) {
                var left = offset
                for (debt in debts) {
                    if (debt.direction != direction || left <= 0) continue
                    val amount = min(left, outstanding[debt.id] ?: 0)
                    add(debt, amount, SettlementKind.OFFSET, null)
                    left -= amount
                }
            }
        }

        // 3. One payment for the rest.
        for (direction in listOf(1, -1)) {
            val rest = total(direction)
            if (rest <= 0) continue
            val payment = repayment(direction, rest, currency, date, person, accountId, "Settled all with ${person.name}", now)
            payments += payment
            for (debt in debts) if (debt.direction == direction) add(debt, outstanding[debt.id] ?: 0, SettlementKind.PAYMENT, payment.id)
        }
        return SettlementChange(group, payments, rows)
    }

    /**
     * Reverses one settlement action: its allocations are removed and a payment it created is deleted. Earlier
     * payments that were only assigned stay recorded. The original transactions are untouched.
     */
    fun undo(s: FinanceSnapshot, groupId: String): SettlementChange {
        val items = DebtLedger.allocations(s).filter { it.groupId == groupId }
        val created = items.filter { it.kind == SettlementKind.PAYMENT }.mapNotNull { it.paymentId }.toSet()
        val movements = s.movements.filter { it.deletedAt == null && it.id in created }.map { it.id }
        return SettlementChange(groupId, tombstoneMovementIds = movements, tombstoneAllocationIds = items.map { it.id })
    }
}
