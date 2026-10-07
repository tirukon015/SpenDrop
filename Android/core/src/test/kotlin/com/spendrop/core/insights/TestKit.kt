package com.spendrop.core.insights

import com.spendrop.core.Money
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/** Test fixtures mirroring the iOS initialisers' defaults (iOS/SpenDrop/Data/Tests/TestKit.swift is store-based). */
object TK {
    val KL: ZoneId = ZoneId.of("Asia/Kuala_Lumpur")
    val cal = CalendarContext(KL)

    fun at(y: Int, mo: Int, d: Int, h: Int = 12, mi: Int = 0, s: Int = 0, zone: ZoneId = KL): Long =
        LocalDateTime.of(y, mo, d, h, mi, s).atZone(zone).toInstant().toEpochMilli()

    /** Wednesday 7 Oct 2026, 12:00 Kuala Lumpur. */
    val NOW = at(2026, 10, 7)
    const val HOUR = 3_600_000L
    const val DAY = 24 * HOUR

    fun id(): String = UUID.randomUUID().toString()

    fun expense(
        amount: Double, merchant: String = "Unknown", date: Long = NOW, currency: String = "RM",
        category: ExpenseCategory = ExpenseCategory.OTHER, fundingAccount: String = "Unknown", accountId: String? = null,
        channel: PaymentChannel = PaymentChannel.UNKNOWN, notes: String? = null, reference: String? = null,
        paymentSource: PaymentSource = PaymentSource.UNKNOWN, createdAt: Long = NOW, isSample: Boolean = false,
    ) = Expense(
        id = id(), amountMinor = Money.minorUnits(amount), currency = currency, merchant = merchant, categoryRaw = category.raw,
        fundingAccount = if (fundingAccount == "Unknown" && !paymentSource.isChannelLike) paymentSource.raw else fundingAccount,
        accountId = accountId, paymentChannelRaw = channel.raw, paymentSourceRaw = paymentSource.raw,
        paymentMethodRaw = paymentSource.defaultPaymentMethod, date = date, notes = notes, transactionReference = reference,
        isSampleData = isSample, createdAt = createdAt, updatedAt = createdAt,
    )

    fun account(name: String, type: AccountType = AccountType.OTHER, sortIndex: Int = 0, archived: Boolean = false, createdAt: Long = NOW) =
        Account(id(), name.trim(), type.raw, sortIndex = sortIndex, isArchived = archived, createdAt = createdAt, updatedAt = createdAt)

    fun person(name: String) = Person(id(), name, createdAt = NOW, updatedAt = NOW)

    fun movement(
        kind: MoneyMovementKind, amountMinor: Long, date: Long = NOW, person: Person? = null, accountId: String? = null,
        counterAccountId: String? = null, note: String? = null, reference: String? = null, linkedExpense: Expense? = null,
        currency: String = "RM",
    ) = MoneyMovement(
        id = id(), kindRaw = kind.raw, directionRaw = kind.direction.raw, amountMinor = amountMinor, currency = currency, date = date,
        personId = person?.id, personNameSnapshot = person?.name, linkedExpenseId = linkedExpense?.id, accountId = accountId,
        counterAccountId = counterAccountId, note = note, transactionReference = reference, createdAt = NOW, updatedAt = NOW,
    )

    /**
     * Equal split of [e] between Me and [people] (iOS SplitDraft.add + apply; odd sen go to Me when I paid, list order otherwise).
     * [payer] non-null = that person paid.
     */
    fun equalSplit(e: Expense, people: List<Person>, payer: Person? = null): Pair<Expense, List<ExpenseShare>> {
        val n = people.size + 1
        val base = e.amountMinor / n
        var rem = (e.amountMinor % n).toInt()
        val amounts = LongArray(n) { base }
        if (payer == null) { amounts[0] += rem.toLong(); rem = 0 }
        var i = 0
        while (rem > 0) { amounts[i++] += 1; rem-- }
        val shares = (listOf<Person?>(null) + people).mapIndexed { idx, p ->
            ExpenseShare(id(), e.id, p?.id, isMe = p == null, nameSnapshot = p?.name ?: "Me", amountMinor = amounts[idx], sortIndex = idx)
        }
        val updated = e.copy(splitMethodRaw = SplitMethod.EQUAL.raw, paidByMe = payer == null, payerId = payer?.id, payerNameSnapshot = payer?.name)
        return updated to shares
    }

    fun sharesFn(shares: List<ExpenseShare>): (String) -> List<ExpenseShare> {
        val map = shares.groupBy { it.expenseId }
        return { map[it].orEmpty() }
    }
}
