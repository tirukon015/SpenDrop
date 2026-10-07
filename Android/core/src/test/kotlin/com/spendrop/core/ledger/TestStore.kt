package com.spendrop.core.ledger

import com.spendrop.core.Ids
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.split.SplitDraft
import com.spendrop.core.split.SplitSave

/**
 * In-memory stand-in for the iOS in-memory ModelContext used by the iOS suites: holds a live [FinanceSnapshot] and
 * applies the records the pure functions return (inserts, updates, tombstones = removal from the live snapshot).
 */
class TestStore {
    var s = FinanceSnapshot()
    /** "Now" for records without an explicit date; ticks forward so creation order is preserved (like Date()). */
    private var clock = 1_800_000_000_000L
    fun now(): Long = clock++

    companion object {
        /** iOS tests' fixed base: Date(timeIntervalSince1970: 1_790_000_000). */
        const val BASE = 1_790_000_000_000L
        const val DAY = 86_400_000L
    }

    fun person(name: String, archived: Boolean = false, frequent: Boolean = false): Person {
        val t = now()
        val p = Person(id = Ids.new(), name = name, isArchived = archived, isFrequent = frequent, createdAt = t, updatedAt = t)
        s = s.copy(people = s.people + p)
        return p
    }

    fun updatePerson(p: Person) { s = s.copy(people = s.people.map { if (it.id == p.id) p else it }) }

    fun deletePerson(id: String) { s = s.copy(people = s.people.filter { it.id != id }) }

    fun expense(minor: Long, merchant: String, date: Long? = null, currency: String = "RM"): Expense {
        val t = now()
        val e = Expense(id = Ids.new(), amountMinor = minor, merchant = merchant, currency = currency, date = date ?: t, createdAt = t, updatedAt = t)
        s = s.copy(expenses = s.expenses + e)
        return e
    }

    fun expense(id: String): Expense = s.expenses.first { it.id == id }
    fun shares(e: Expense): List<ExpenseShare> = s.sharesOf(e.id)

    fun save(save: SplitSave) {
        val gone = save.tombstoneShareIds.toSet()
        s = s.copy(
            expenses = s.expenses.map { if (it.id == save.expense.id) save.expense else it },
            shares = s.shares.filter { it.id !in gone } + save.newShares,
        )
    }

    /** iOS `draft.apply(to:in:)`: false (nothing written) when invalid. */
    fun apply(draft: SplitDraft, e: Expense): Boolean {
        val current = expense(e.id)
        val save = draft.apply(current, shares(current), now()) ?: return false
        save(save)
        return true
    }

    fun setAmount(e: Expense, minor: Long): Expense {
        val updated = expense(e.id).copy(amountMinor = minor)
        s = s.copy(expenses = s.expenses.map { if (it.id == e.id) updated else it })
        return updated
    }

    /** Deleting an expense deletes its shares (cascade), like iOS. */
    fun deleteExpense(e: Expense) {
        s = s.copy(expenses = s.expenses.filter { it.id != e.id }, shares = s.shares.filter { it.expenseId != e.id })
    }

    fun movement(kind: MoneyMovementKind, minor: Long, person: Person? = null, currency: String = "RM", note: String? = null): MoneyMovement {
        val t = now()
        val m = MoneyMovement(
            id = Ids.new(), kindRaw = kind.raw, directionRaw = kind.direction.raw, amountMinor = minor, currency = currency, date = t,
            personId = person?.id, personNameSnapshot = person?.name, note = note, createdAt = t, updatedAt = t,
        )
        s = s.copy(movements = s.movements + m)
        return m
    }

    fun insert(m: MoneyMovement) { s = s.copy(movements = s.movements + m) }

    fun apply(change: SettlementChange): String {
        s = change.applyTo(s)
        return change.groupId
    }

    fun undo(groupId: String) { apply(SettlementService.undo(s, groupId)) }

    // Shortcuts used by the ported suites
    fun net(p: Person): Long = PersonLedger.balances(s, p)["RM"] ?: 0
    fun debts(p: Person): List<Debt> = DebtLedger.debts(s, p)
    fun debt(title: String, p: Person): Debt = debts(p).first { it.title == title }
    fun outstanding(p: Person): Map<String, Long> =
        debts(p).groupBy { it.title }.mapValues { (_, v) -> v.sumOf { it.outstandingMinor } }

    /** An expense I paid entirely for [person] (their share = amount). iOS `DebtSettlementTests.paidFor`. */
    fun paidFor(person: Person, minor: Long, title: String, daysAgo: Int = 0): Expense {
        val e = expense(minor, title, date = BASE - daysAgo * DAY)
        check(apply(SplitDraft().setPurpose(SplitDraft.Purpose.PAID_FOR).add(person), e))
        return expense(e.id)
    }

    /** [payer] paid [minor] entirely for me. */
    fun paidForMe(payer: Person, minor: Long, title: String, daysAgo: Int = 0): Expense {
        val e = expense(minor, title, date = BASE - daysAgo * DAY)
        check(apply(SplitDraft().setPurpose(SplitDraft.Purpose.PAID_FOR).setPayer(payer), e))
        return expense(e.id)
    }

    fun movementCount(): Int = s.movements.size
    fun allocationCount(): Int = s.allocations.size
}
