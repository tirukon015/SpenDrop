package com.spendrop.core.finance

import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind

/** Per-expense values in sen (iOS `Expense` extension in FinancialCalculator.swift). `shares` = that expense's live shares. */
object ExpenseMath {
    fun isShared(shares: List<ExpenseShare>): Boolean = shares.isNotEmpty()

    /** My share: the full amount when not shared, otherwise the "Me" share (0 if missing). */
    fun myShareMinor(e: Expense, shares: List<ExpenseShare>): Long =
        if (shares.isEmpty()) e.amountMinor else shares.firstOrNull { it.isMe }?.amountMinor ?: 0

    /** Spending: the full amount if I paid, my share if someone else paid. */
    fun spendingMinor(e: Expense, shares: List<ExpenseShare>): Long =
        if (e.paidByMe) e.amountMinor else myShareMinor(e, shares)

    /** Cash out: the full amount if I paid, nothing if someone else paid. */
    fun cashOutMinor(e: Expense): Long = if (e.paidByMe) e.amountMinor else 0

    fun sharesMatchAmount(e: Expense, shares: List<ExpenseShare>): Boolean =
        shares.isEmpty() || shares.sumOf { it.amountMinor } == e.amountMinor
}

/** Deterministic totals in sen. Different currencies are never added together. Own transfers are excluded. */
object FinancialCalculator {
    data class Summary(
        val spendingMinor: Long = 0,
        val refundsMinor: Long = 0,
        val moneyInMinor: Long = 0,
        val moneyOutMinor: Long = 0,
    ) {
        val netSpendingMinor: Long get() = spendingMinor - refundsMinor
        val netCashFlowMinor: Long get() = moneyInMinor - moneyOutMinor
    }

    fun summary(
        expenses: List<Expense>,
        sharesOf: (String) -> List<ExpenseShare>,
        movements: List<MoneyMovement>,
        currency: String = "RM",
    ): Summary {
        var spending = 0L; var refunds = 0L; var moneyIn = 0L; var moneyOut = 0L
        for (e in expenses) if (e.currency == currency) {
            spending += ExpenseMath.spendingMinor(e, sharesOf(e.id))
            moneyOut += ExpenseMath.cashOutMinor(e)
        }
        for (m in movements) if (m.currency == currency) {
            when (m.kind.direction) {
                MoneyDirection.IN -> {
                    moneyIn += m.amountMinor
                    if (m.kind == MoneyMovementKind.REFUND) refunds += m.amountMinor
                }
                MoneyDirection.OUT -> moneyOut += m.amountMinor
                MoneyDirection.INTERNAL -> Unit
            }
        }
        return Summary(spending, refunds, moneyIn, moneyOut)
    }

    fun summary(snapshot: FinanceSnapshot, expenses: List<Expense>, movements: List<MoneyMovement>, currency: String = "RM") =
        summary(expenses, snapshot::sharesOf, movements, currency)

    /** Recorded money through one account. NOT a bank balance. */
    data class AccountActivity(val inMinor: Long = 0, val outMinor: Long = 0) {
        val netMinor: Long get() = inMinor - outMinor
    }

    fun accountActivity(accountId: String, accountCurrency: String, expenses: List<Expense>, movements: List<MoneyMovement>): AccountActivity {
        var inM = 0L; var outM = 0L
        for (e in expenses) if (e.accountId == accountId && e.currency == accountCurrency) outM += ExpenseMath.cashOutMinor(e)
        for (m in movements) if (m.currency == accountCurrency) {
            if (m.accountId == accountId) {
                when (m.kind.direction) {
                    MoneyDirection.IN -> inM += m.amountMinor
                    MoneyDirection.OUT, MoneyDirection.INTERNAL -> outM += m.amountMinor
                }
            }
            if (m.counterAccountId == accountId && m.kind == MoneyMovementKind.OWN_TRANSFER) inM += m.amountMinor
        }
        return AccountActivity(inM, outM)
    }

    /**
     * What each person owes me, keyed by person id. Positive = they owe me; negative = I owe them.
     * Records whose person was deleted are skipped.
     */
    fun personBalances(
        expenses: List<Expense>,
        sharesOf: (String) -> List<ExpenseShare>,
        movements: List<MoneyMovement>,
        currency: String = "RM",
    ): Map<String, Long> {
        val balances = HashMap<String, Long>()
        for (e in expenses) if (e.currency == currency) {
            val shares = sharesOf(e.id)
            if (e.paidByMe) {
                for (s in shares) if (!s.isMe) s.personId?.let { balances[it] = (balances[it] ?: 0) + s.amountMinor }
            } else {
                e.payerId?.let { balances[it] = (balances[it] ?: 0) - ExpenseMath.myShareMinor(e, shares) }
            }
        }
        for (m in movements) if (m.currency == currency) {
            val sign = m.kind.personBalanceSign
            val pid = m.personId
            if (sign != 0 && pid != null) balances[pid] = (balances[pid] ?: 0) + sign * m.amountMinor
        }
        return balances
    }
}
