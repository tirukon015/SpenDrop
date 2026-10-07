package com.spendrop.core.ledger

import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.model.Expense
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import com.spendrop.core.model.SettlementAllocation
import com.spendrop.core.model.SettlementKind
import kotlin.math.max

/**
 * One debt between me and one person, coming from one transaction (iOS `Debt`). Nothing is stored: the original
 * amount comes from the expense/loan, what has been paid comes from [SettlementAllocation]s.
 */
data class Debt(
    val id: String,
    val source: Source,
    val personId: String,
    val personName: String,
    val date: Long,
    val title: String,
    val currency: String,
    /** +1: the person owes me. -1: I owe the person. */
    val direction: Int,
    /** The share/loan amount this debt came from, in minor units. */
    val originalMinor: Long,
    /** Paid towards this debt so far (all settlements), in minor units. */
    val settledMinor: Long,
    /** e.g. "You paid · their share RM 6.99" */
    val detail: String,
    val expense: Expense? = null,
    val loan: MoneyMovement? = null,
) {
    sealed class Source {
        data class OfExpense(val id: String) : Source()
        data class OfLoan(val id: String) : Source()
    }

    val outstandingMinor: Long get() = max(0, originalMinor - settledMinor)
    val isSettled: Boolean get() = outstandingMinor == 0L
    val isPartiallyPaid: Boolean get() = settledMinor > 0 && !isSettled
    /** Positive when they owe me, negative when I owe them. */
    val signedOutstandingMinor: Long get() = direction * outstandingMinor
    val expenseId: String? get() = (source as? Source.OfExpense)?.id
    val loanId: String? get() = (source as? Source.OfLoan)?.id

    /** "Bijoy owes you RM 6.99" / "You owe Bijoy RM 20.00" / "Settled" */
    val statusText: String
        get() = if (isSettled) "Settled" else PersonLedger.directionText(personName, signedOutstandingMinor, currency)
}

/** Sort order used everywhere for debts: oldest first, then id. */
internal val debtOrder: Comparator<Debt> = compareBy<Debt> { it.date }.thenBy { it.id }

/**
 * Turns expenses, loans and settlements into per-transaction debts (iOS `DebtLedger`).
 * The net balance stays [com.spendrop.core.finance.FinancialCalculator.personBalances]; debts explain it.
 */
object DebtLedger {
    /** Every live allocation, oldest first. */
    fun allocations(s: FinanceSnapshot): List<SettlementAllocation> =
        s.allocations.filter { it.deletedAt == null }.sortedBy { it.date }

    /** Allocations that still count: offsets always; payments/assignments only while their payment exists. */
    fun active(allocations: List<SettlementAllocation>, paymentIds: Set<String>): List<SettlementAllocation> =
        allocations.filter { it.kind == SettlementKind.OFFSET || (it.paymentId?.let(paymentIds::contains) ?: false) }

    private fun isRepayment(m: MoneyMovement) = m.kind == MoneyMovementKind.REPAYMENT_RECEIVED || m.kind == MoneyMovementKind.REPAYMENT_MADE

    private fun liveMovements(s: FinanceSnapshot) = s.movements.filter { it.deletedAt == null }

    private fun repaymentIds(s: FinanceSnapshot): Set<String> = liveMovements(s).filter(::isRepayment).map { it.id }.toSet()

    /** The debt between me and [person] created by [expense], if any. */
    fun expenseDebt(s: FinanceSnapshot, expense: Expense, person: Person, allocations: List<SettlementAllocation>): Debt? {
        val shares = s.sharesOf(expense.id)
        val direction: Int
        val original: Long
        val detail: String
        if (expense.paidByMe) {
            val share = shares.firstOrNull { !it.isMe && it.personId == person.id } ?: return null
            direction = 1
            original = share.amountMinor
            detail = "You paid · their share ${PersonLedger.format(original, expense.currency)}"
        } else if (expense.payerId == person.id) {
            direction = -1
            original = ExpenseMath.myShareMinor(expense, shares)
            detail = "${person.name} paid · your share ${PersonLedger.format(original, expense.currency)}"
        } else {
            return null
        }
        if (original <= 0) return null
        val settled = allocations.filter { it.expenseId == expense.id && it.personId == person.id && it.direction == direction }.sumOf { it.amountMinor }
        return Debt(
            id = "expense:${expense.id}:${person.id}", source = Debt.Source.OfExpense(expense.id), personId = person.id,
            personName = person.name, date = expense.date, title = expense.merchant, currency = expense.currency,
            direction = direction, originalMinor = original, settledMinor = settled, detail = detail, expense = expense,
        )
    }

    /** A loan given (they owe me) or received (I owe them) is a debt too. */
    fun loanDebt(loan: MoneyMovement, person: Person, allocations: List<SettlementAllocation>): Debt? {
        val direction = when (loan.kind) {
            MoneyMovementKind.LOAN_GIVEN -> 1
            MoneyMovementKind.LOAN_RECEIVED -> -1
            else -> return null
        }
        if (loan.amountMinor <= 0) return null
        val settled = allocations.filter { it.loanId == loan.id && it.direction == direction }.sumOf { it.amountMinor }
        val title = if (!loan.note.isNullOrEmpty()) loan.note!! else if (direction > 0) "Money you gave" else "Money you received"
        return Debt(
            id = "loan:${loan.id}", source = Debt.Source.OfLoan(loan.id), personId = person.id, personName = person.name,
            date = loan.date, title = title, currency = loan.currency, direction = direction, originalMinor = loan.amountMinor,
            settledMinor = settled, detail = if (direction > 0) "You gave money" else "${person.name} gave you money", loan = loan,
        )
    }

    /** Every debt with this person (settled and outstanding), oldest first. */
    fun debts(s: FinanceSnapshot, person: Person): List<Debt> {
        val active = active(allocations(s).filter { it.personId == person.id }, repaymentIds(s))
        val result = ArrayList<Debt>()
        for (expense in PersonLedger.relatedExpenses(s, person.id)) expenseDebt(s, expense, person, active)?.let { result += it }
        for (loan in PersonLedger.movements(s, person.id)) loanDebt(loan, person, active)?.let { result += it }
        return result.sortedWith(debtOrder)
    }

    /** The debts an expense created (one per person involved with me). */
    fun debts(s: FinanceSnapshot, expense: Expense): List<Debt> {
        val active = active(allocations(s).filter { it.expenseId == expense.id }, repaymentIds(s))
        val people = s.people.filter { it.deletedAt == null }.associateBy { it.id }
        val involved: List<Person> = if (expense.paidByMe) {
            s.sharesOf(expense.id).mapNotNull { if (it.isMe) null else it.personId?.let(people::get) }
        } else {
            listOfNotNull(expense.payerId?.let(people::get))
        }
        return involved.mapNotNull { expenseDebt(s, expense, it, active) }
    }

    /** Payments (or parts) not linked to any transaction, signed so that `net == Σ signedOutstanding + unassigned`. */
    fun unassignedMinor(s: FinanceSnapshot, person: Person, currency: String): Long {
        val net = PersonLedger.balances(s, person)[currency] ?: 0
        val outstanding = debts(s, person).filter { it.currency == currency }.sumOf { it.signedOutstandingMinor }
        return net - outstanding
    }

    /** One repayment and how much of it is applied to transactions. `unallocatedMinor` is credit. */
    data class PaymentUse(val payment: MoneyMovement, val allocatedMinor: Long) {
        val id: String get() = payment.id
        /** +1 they paid me, -1 I paid them. */
        val direction: Int get() = if (payment.kind == MoneyMovementKind.REPAYMENT_RECEIVED) 1 else -1
        val unallocatedMinor: Long get() = max(0, payment.amountMinor - allocatedMinor)
    }

    /** Every repayment with this person and how much of it is applied (payment = applied + credit), oldest first. */
    fun paymentUses(s: FinanceSnapshot, person: Person): List<PaymentUse> {
        val payments = PersonLedger.movements(s, person.id).filter(::isRepayment)
        val active = active(allocations(s).filter { it.personId == person.id }, payments.map { it.id }.toSet())
        return payments.sortedBy { it.date }.map { p -> PaymentUse(p, active.filter { it.paymentId == p.id }.sumOf { it.amountMinor }) }
    }

    /** Credit: repayments (or parts) not applied to any transaction, in one direction (+1 they paid me, -1 I paid). */
    fun creditMinor(s: FinanceSnapshot, person: Person, currency: String, direction: Int): Long =
        paymentUses(s, person).filter { it.payment.currency == currency && it.direction == direction }.sumOf { it.unallocatedMinor }

    /** One settlement action (payment, assignment, settle-all) as shown in history. */
    data class SettlementGroup(
        val id: String,
        val date: Long,
        val allocations: List<SettlementAllocation>,
        val payment: MoneyMovement?,
    ) {
        val totalMinor: Long get() = allocations.filter { it.kind != SettlementKind.OFFSET }.sumOf { it.amountMinor }
        val offsetMinor: Long get() = allocations.filter { it.kind == SettlementKind.OFFSET && it.direction > 0 }.sumOf { it.amountMinor }
        val currency: String get() = allocations.firstOrNull()?.currency ?: payment?.currency ?: "RM"
        /** +1 money came to me, -1 I paid, 0 offset only. */
        val direction: Int get() = allocations.firstOrNull { it.kind != SettlementKind.OFFSET }?.direction ?: 0
    }

    /** Settlement actions involving a person / an expense / a loan, newest first. */
    fun settlementGroups(s: FinanceSnapshot, personId: String? = null, expenseId: String? = null, loanId: String? = null): List<SettlementGroup> {
        val byId = liveMovements(s).associateBy { it.id }
        val all = active(allocations(s), byId.keys)
        val matching = all.filter { a ->
            (personId == null || a.personId == personId) && (expenseId == null || a.expenseId == expenseId) && (loanId == null || a.loanId == loanId)
        }
        val matchingIds = matching.map { it.id }.toSet()
        return matching.map { it.groupId }.distinct().map { gid ->
            val items = all.filter { it.groupId == gid }
            val shown = items.filter { it.id in matchingIds }
            val payment = items.firstNotNullOfOrNull { if (it.kind == SettlementKind.PAYMENT) it.paymentId else null }?.let(byId::get)
            SettlementGroup(gid, shown.maxOfOrNull { it.date } ?: 0L, shown, payment)
        }.sortedByDescending { it.date }
    }
}
