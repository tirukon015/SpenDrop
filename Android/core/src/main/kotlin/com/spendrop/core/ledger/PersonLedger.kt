package com.spendrop.core.ledger

import com.spendrop.core.Money
import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Expense
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.Person
import kotlin.math.abs

/**
 * Per-person balances and history (iOS `PersonLedger`), always calculated from shares, expense payers and money
 * movements in a [FinanceSnapshot]. Positive = they owe me; negative = I owe them. Nothing is stored.
 */
object PersonLedger {
    data class Entry(
        val id: String,
        val date: Long,
        val title: String,
        val detail: String,
        /** Change to "what they owe me" in minor units (0 = recorded but does not affect our balance). */
        val effectMinor: Long,
        val currency: String,
        val source: Source,
    ) {
        sealed class Source {
            data class OfExpense(val expense: Expense) : Source()
            data class OfMovement(val movement: MoneyMovement) : Source()
        }
    }

    data class Summary(
        /** Currency → total others owe me (positive). */
        val owedToMe: Map<String, Long> = emptyMap(),
        /** Currency → total I owe others (positive). */
        val iOwe: Map<String, Long> = emptyMap(),
        /** People with history whose balances are all zero. */
        val settledCount: Int = 0,
        val owingMeCount: Int = 0,
        val iOweCount: Int = 0,
    ) {
        val isEmpty: Boolean get() = owedToMe.isEmpty() && iOwe.isEmpty() && settledCount == 0
    }

    /** One person in an outstanding list: the amount is always positive; the filter says who owes whom. */
    data class OutstandingPerson(val person: Person, val amountMinor: Long, val currency: String, val lastActivity: Long) {
        val id: String get() = person.id
    }

    // MARK: Relations (iOS person.shares / person.paidExpenses / person.movements)

    /** Expenses the person has a share in, then expenses they paid; each once. */
    internal fun relatedExpenses(s: FinanceSnapshot, personId: String): List<Expense> {
        val byId = s.expenses.filter { it.deletedAt == null }.associateBy { it.id }
        val seen = LinkedHashSet<String>()
        val result = ArrayList<Expense>()
        val viaShares = s.shares.filter { it.deletedAt == null && it.personId == personId }.mapNotNull { byId[it.expenseId] }
        val paid = s.expenses.filter { it.deletedAt == null && it.payerId == personId }
        for (e in viaShares + paid) if (seen.add(e.id)) result += e
        return result
    }

    internal fun movements(s: FinanceSnapshot, personId: String): List<MoneyMovement> =
        s.movements.filter { it.deletedAt == null && it.personId == personId }

    // MARK: Balances

    /** Currency → balance with this person. Zero balances are omitted. */
    fun balances(s: FinanceSnapshot, person: Person): Map<String, Long> {
        val expenses = relatedExpenses(s, person.id)
        val movements = movements(s, person.id)
        val currencies = (expenses.map { it.currency } + movements.map { it.currency }).toSet()
        val result = LinkedHashMap<String, Long>()
        for (currency in currencies) {
            val value = FinancialCalculator.personBalances(expenses, s::sharesOf, movements, currency)[person.id] ?: 0
            if (value != 0L) result[currency] = value
        }
        return result
    }

    fun hasHistory(s: FinanceSnapshot, person: Person): Boolean =
        s.shares.any { it.deletedAt == null && it.personId == person.id } ||
            s.expenses.any { it.deletedAt == null && it.payerId == person.id } ||
            movements(s, person.id).isNotEmpty()

    /** Deleting is only allowed when nothing is owed either way. History survives through snapshots. */
    fun canDelete(s: FinanceSnapshot, person: Person): Boolean = balances(s, person).isEmpty()

    fun summary(s: FinanceSnapshot, people: List<Person>): Summary {
        val owedToMe = LinkedHashMap<String, Long>()
        val iOwe = LinkedHashMap<String, Long>()
        var settled = 0; var owingMe = 0; var iOweCount = 0
        for (person in people) {
            val balances = balances(s, person)
            if (balances.isEmpty()) {
                if (hasHistory(s, person)) settled += 1
                continue
            }
            if (balances.values.any { it > 0 }) owingMe += 1
            if (balances.values.any { it < 0 }) iOweCount += 1
            for ((currency, value) in balances) {
                if (value > 0) owedToMe[currency] = (owedToMe[currency] ?: 0) + value
                if (value < 0) iOwe[currency] = (iOwe[currency] ?: 0) - value
            }
        }
        return Summary(owedToMe, iOwe, settled, owingMe, iOweCount)
    }

    // MARK: History

    fun entries(s: FinanceSnapshot, person: Person): List<Entry> {
        val people = s.people.associateBy { it.id }
        val accounts = s.accounts.associateBy { it.id }
        val entries = ArrayList<Entry>()
        for (expense in relatedExpenses(s, person.id)) {
            val shares = s.sharesOf(expense.id)
            val theirShare = shares.firstOrNull { it.personId == person.id }
            val effect: Long
            val detail: String
            val mine = ExpenseMath.myShareMinor(expense, shares)
            if (expense.paidByMe) {
                effect = theirShare?.amountMinor ?: 0
                detail = "You paid · their share ${format(effect, expense.currency)}"
            } else if (expense.payerId == person.id) {
                effect = -mine
                detail = "${person.name} paid · your share ${format(mine, expense.currency)}"
            } else {
                effect = 0
                val payerName = expense.payerId?.let { people[it]?.name } ?: expense.payerNameSnapshot ?: "someone else"
                detail = "Paid by $payerName · not between you"
            }
            entries += Entry(expense.id, expense.date, expense.merchant, detail, effect, expense.currency, Entry.Source.OfExpense(expense))
        }
        for (m in movements(s, person.id)) {
            entries += Entry(
                m.id, m.date, m.kind.displayName, m.note ?: (m.accountId?.let { accounts[it]?.name } ?: ""),
                m.kind.personBalanceSign * m.amountMinor, m.currency, Entry.Source.OfMovement(m),
            )
        }
        return entries.sortedByDescending { it.date }
    }

    // MARK: Record payment

    /** Prefilled repayment for settling a balance: Repayment Received when they owe me, Repayment Made when I owe them. */
    fun repaymentDraft(s: FinanceSnapshot, person: Person, currency: String, now: Long): MoneyMovementDraft? {
        val balance = balances(s, person)[currency] ?: return null
        if (balance == 0L) return null
        val type = if (balance > 0) TransactionEntryType.MONEY_IN else TransactionEntryType.MONEY_OUT
        return MoneyMovementDraft.new(type, now).copy(
            kind = if (balance > 0) MoneyMovementKind.REPAYMENT_RECEIVED else MoneyMovementKind.REPAYMENT_MADE,
            person = person,
            currency = currency,
            amountText = Money.plain(abs(balance)),
        )
    }

    /** "Shadin owes you RM 100.00" / "You owe Bijoy RM 7.50" / "Settled with X". */
    fun directionText(name: String, balanceMinor: Long, currency: String): String = when {
        balanceMinor > 0 -> "$name owes you ${format(balanceMinor, currency)}"
        balanceMinor < 0 -> "You owe $name ${format(-balanceMinor, currency)}"
        else -> "Settled with $name"
    }

    fun format(minor: Long, currency: String): String = Money.format(minor, currency)

    // MARK: Outstanding (PayBook filter)

    /**
     * People with a positive (They Owe Me) or negative (I Owe Them) net balance, largest amount first; ties by most
     * recent activity, then name. Settled people (exactly 0) are in neither list; [PayBookBalanceFilter.ALL] gives [].
     * With balances in more than one currency, their largest balance in that direction is used.
     */
    fun outstanding(s: FinanceSnapshot, people: List<Person>, filter: PayBookBalanceFilter): List<OutstandingPerson> {
        if (filter == PayBookBalanceFilter.ALL) return emptyList()
        val sign = if (filter == PayBookBalanceFilter.THEY_OWE_ME) 1 else -1
        return people.mapNotNull { person ->
            val matching = balances(s, person).filter { it.value * sign > 0 }
            val largest = matching.maxByOrNull { abs(it.value) } ?: return@mapNotNull null
            val last = entries(s, person).maxOfOrNull { it.date } ?: person.updatedAt
            OutstandingPerson(person, abs(largest.value), largest.key, last)
        }.sortedWith { a, b ->
            when {
                a.amountMinor != b.amountMinor -> b.amountMinor.compareTo(a.amountMinor)
                a.lastActivity != b.lastActivity -> b.lastActivity.compareTo(a.lastActivity)
                else -> String.CASE_INSENSITIVE_ORDER.compare(a.person.name, b.person.name)
            }
        }
    }
}

/** PayBook's "They Owe Me / I Owe Them" filter; membership comes only from the net balance. */
enum class PayBookBalanceFilter(val raw: String, val title: String) {
    ALL("all", "All"), THEY_OWE_ME("theyOweMe", "They Owe Me"), I_OWE_THEM("iOweThem", "I Owe Them")
}

/** How PayBook groups people: Frequent, Other People, Archived. */
object PayBookGrouping {
    data class Groups(val frequent: List<Person>, val other: List<Person>, val archived: List<Person>)

    fun groups(people: List<Person>): Groups = Groups(
        people.filter { it.isFrequent && !it.isArchived },
        people.filter { !it.isFrequent && !it.isArchived },
        people.filter { it.isArchived },
    )
}
