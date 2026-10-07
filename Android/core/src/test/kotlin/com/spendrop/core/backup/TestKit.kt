package com.spendrop.core.backup

import com.spendrop.core.Money
import com.spendrop.core.model.Account
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

object TestKit {
    val MYT: ZoneId = ZoneId.of("Asia/Kuala_Lumpur")
    val UTC: ZoneId = ZoneId.of("UTC")
    val NEW_YORK: ZoneId = ZoneId.of("America/New_York")

    fun date(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0, s: Int = 0, zone: ZoneId = MYT): Long =
        LocalDateTime.of(y, m, d, h, min, s).atZone(zone).toInstant().toEpochMilli()

    fun id(): String = UUID.randomUUID().toString()

    fun resource(name: String): String =
        TestKit::class.java.classLoader.getResource(name)!!.readText()

    fun expense(
        merchant: String, amount: Double, date: Long = date(2026, 10, 1), funding: String = "Unknown", accountId: String? = null,
        category: String = "Other", channel: String = "UNKNOWN", source: String = "Unknown", ref: String? = null,
        updatedAt: Long = date, id: String = id(),
    ) = Expense(
        id = id, amountMinor = Money.minorUnits(amount), merchant = merchant, categoryRaw = category, fundingAccount = funding,
        accountId = accountId, paymentChannelRaw = channel, paymentSourceRaw = source, date = date, transactionReference = ref,
        createdAt = date, updatedAt = updatedAt,
    )

    fun account(name: String, type: String = "bank", created: Long = date(2025, 1, 1), id: String = id()) =
        Account(id = id, name = name, typeRaw = type, createdAt = created, updatedAt = created)

    fun person(name: String, created: Long = date(2025, 6, 1), id: String = id()) =
        Person(id = id, name = name, createdAt = created, updatedAt = created)

    /** Like iOS SplitDraft: equal split of [e] between me and [people], paid by [payer]. */
    fun split(e: Expense, people: List<Person>, payer: Person?): Pair<Expense, List<ExpenseShare>> {
        val n = people.size + 1
        val base = e.amountMinor / n
        var rest = e.amountMinor - base * n
        val shares = mutableListOf<ExpenseShare>()
        fun amt(): Long = base + if (rest > 0) { rest--; 1 } else 0
        shares += ExpenseShare(id = id(), expenseId = e.id, isMe = true, nameSnapshot = "Me", amountMinor = amt(), sortIndex = 0, createdAt = e.createdAt, updatedAt = e.updatedAt)
        people.forEachIndexed { i, p ->
            shares += ExpenseShare(id = id(), expenseId = e.id, personId = p.id, nameSnapshot = p.name, amountMinor = amt(), sortIndex = i + 1,
                createdAt = e.createdAt, updatedAt = e.updatedAt)
        }
        val updated = e.copy(paidByMe = payer == null, payerId = payer?.id, payerNameSnapshot = payer?.name, splitMethodRaw = "equal")
        return updated to shares
    }

    fun movement(kind: MoneyMovementKind, amountMinor: Long, date: Long, personId: String? = null, accountId: String? = null,
                 counterAccountId: String? = null, linkedExpenseId: String? = null) = MoneyMovement(
        id = id(), kindRaw = kind.raw, directionRaw = kind.direction.raw, amountMinor = amountMinor, date = date, personId = personId,
        accountId = accountId, counterAccountId = counterAccountId, linkedExpenseId = linkedExpenseId, createdAt = date, updatedAt = date,
    )

    fun rule(merchantKey: String, category: String, at: Long = date(2026, 9, 1)) =
        ClassificationRule(id = id(), merchantKey = merchantKey, categoryRaw = category, createdAt = at, updatedAt = at)

    /** iOS RestoreRangeTests.fixture(): a realistic history around 5 Oct 2026 (Malaysia time). */
    class RangeFixture {
        val reference = date(2026, 10, 5, 1, 32)
        val maybank = account("Maybank", created = date(2025, 1, 1))
        val cimb = account("CIMB", created = date(2025, 2, 1))
        val wise = account("Wise", created = date(2025, 3, 1))
        val tng = account("Touch 'n Go", "eWallet", created = date(2025, 4, 1))
        val bijoy = person("Bijoy"); val ali = person("Ali"); val oldFriend = person("Old Friend")
        val mcd = expense("McDonald's", 18.5, date(2026, 10, 5, 0, 10), "Maybank", maybank.id, "Food", "APPLE_PAY", "Apple Pay")
        private val dinnerSplit = split(expense("Dinner", 90.0, date(2026, 10, 1, 20), "Maybank", maybank.id, "Food"), listOf(bijoy, ali), bijoy)
        val dinner = dinnerSplit.first
        val grab = expense("Grab", 14.8, date(2026, 9, 10, 9), "CIMB", null, "Transport")
        val uniqlo = expense("Uniqlo", 120.0, date(2026, 1, 15), "Wise", wise.id, "Shopping")
        private val lunchSplit = split(expense("Old Lunch", 40.0, date(2026, 2, 2)), listOf(oldFriend), oldFriend)
        val oldLunch = lunchSplit.first
        val snapshot = FinanceSnapshot(
            expenses = listOf(mcd, dinner, grab, uniqlo, oldLunch),
            shares = dinnerSplit.second + lunchSplit.second,
            accounts = listOf(maybank, cimb, wise, tng),
            people = listOf(bijoy, ali, oldFriend),
            movements = listOf(
                movement(MoneyMovementKind.OWN_TRANSFER, 20000, date(2026, 10, 3), accountId = maybank.id, counterAccountId = tng.id),
                movement(MoneyMovementKind.REFUND, 500, date(2026, 10, 4), linkedExpenseId = uniqlo.id),
                movement(MoneyMovementKind.INCOME, 300000, date(2026, 6, 1), accountId = wise.id),
            ),
            classificationRules = listOf(rule("mcdonald's", "Food"), rule("uniqlo", "Shopping")),
        )
        val payload = BackupCodec.makePayload(snapshot, "me@example.com", reference)
    }
}
