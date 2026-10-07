package com.spendrop.core.sample

import com.spendrop.core.Ids
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentMethodType
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SampleRecord
import com.spendrop.core.model.SettlementAllocation
import com.spendrop.core.model.SettlementKind
import com.spendrop.core.model.SplitMethod

/** iOS SampleDataRecord.Entity raw values (`SampleRecord.entityRaw`). */
enum class SampleEntity(val raw: String) {
    EXPENSE("expense"), PERSON("person"), PAYMENT_METHOD("paymentMethod"), ACCOUNT("account"),
    MOVEMENT("movement"), ALLOCATION("allocation"), RULE("rule");

    companion object { fun fromRaw(raw: String?): SampleEntity? = entries.firstOrNull { it.raw == raw } }
}

/** The records "Load Sample Data" inserts (all new; nothing existing is changed). */
data class SampleDataSet(
    val people: List<Person>,
    val paymentMethods: List<PersonPaymentMethod>,
    val accounts: List<Account>,
    val expenses: List<Expense>,
    val shares: List<ExpenseShare>,
    val movements: List<MoneyMovement>,
    val allocations: List<SettlementAllocation>,
    /** The register: one entry per sample record (shares are not registered; they go with their expense). */
    val sampleRecords: List<SampleRecord>,
) {
    /** The snapshot with these records added. */
    fun addTo(s: FinanceSnapshot): FinanceSnapshot = s.copy(
        expenses = s.expenses + expenses, shares = s.shares + shares, accounts = s.accounts + accounts, people = s.people + people,
        paymentMethods = s.paymentMethods + paymentMethods, movements = s.movements + movements,
        allocations = s.allocations + allocations, sampleRecords = s.sampleRecords + sampleRecords,
    )
}

data class RemovalReport(
    val expensesRemoved: Int = 0,
    val peopleRemoved: Int = 0,
    /** Sample people kept because real records now use them (they become normal people). */
    val peopleKept: Int = 0,
    val movementsRemoved: Int = 0,
    val settlementsRemoved: Int = 0,
    val accountsRemoved: Int = 0,
    val paymentMethodsRemoved: Int = 0,
) {
    val total: Int get() = expensesRemoved + peopleRemoved + movementsRemoved + settlementsRemoved + accountsRemoved + paymentMethodsRemoved
}

/** What "Remove Sample Data" deletes (ids), plus real movements whose link to a removed sample expense is cleared. */
data class SampleRemovalPlan(
    val expenseIds: Set<String>,
    /** Shares of the removed expenses (cascade). */
    val shareIds: Set<String>,
    val movementIds: Set<String>,
    val allocationIds: Set<String>,
    val paymentMethodIds: Set<String>,
    val personIds: Set<String>,
    val accountIds: Set<String>,
    /** Every register entry goes (kept records become normal records). */
    val sampleRecordIds: Set<String>,
    /** Remaining movements linked to a removed expense, with `linkedExpenseId` cleared (iOS nullify). */
    val unlinkedMovements: List<MoneyMovement>,
    val report: RemovalReport,
) {
    /** The snapshot after the removal (hard delete). Callers that sync may tombstone the same ids instead. */
    fun applyTo(s: FinanceSnapshot): FinanceSnapshot {
        val unlinked = unlinkedMovements.associateBy { it.id }
        return s.copy(
            expenses = s.expenses.filter { it.id !in expenseIds },
            shares = s.shares.filter { it.id !in shareIds },
            movements = s.movements.filter { it.id !in movementIds }.map { unlinked[it.id] ?: it },
            allocations = s.allocations.filter { it.id !in allocationIds },
            paymentMethods = s.paymentMethods.filter { it.id !in paymentMethodIds },
            people = s.people.filter { it.id !in personIds },
            accounts = s.accounts.filter { it.id !in accountIds },
            sampleRecords = s.sampleRecords.filter { it.recordId !in sampleRecordIds },
        )
    }
}

/**
 * Optional demo data ("Load Sample Data" in Settings), port of iOS SampleData. Every record created is listed in the
 * register (and sample expenses also carry `isSampleData`), so removal deletes exactly those records and never anything
 * identified by name, amount or date. People and accounts are marked "(Sample)". All amounts are fictional.
 */
object SampleData {
    val peopleNames = listOf("Aiman (Sample)", "Mei Ling (Sample)", "Ravi (Sample)")
    const val BANK_NAME = "Demo Bank (Sample)"
    const val WALLET_NAME = "Demo Wallet (Sample)"

    /** True while any sample record exists (registered records or flagged expenses). */
    fun isLoaded(s: FinanceSnapshot): Boolean = s.sampleRecords.isNotEmpty() || count(s) > 0

    /** Number of sample expenses currently stored. */
    fun count(s: FinanceSnapshot): Int = s.expenses.count { it.isSampleData }

    /** The demo set to insert, or null (nothing to add) when sample data is already loaded. */
    fun load(s: FinanceSnapshot, now: Long, calendar: CalendarContext = CalendarContext(), newId: () -> String = Ids::new): SampleDataSet? =
        if (isLoaded(s)) null else build(now, calendar, newId)

    /** Builds the demo set. Dates are relative to the local start of today (iOS `day(daysAgo, hour)`). */
    fun build(now: Long, calendar: CalendarContext = CalendarContext(), newId: () -> String = Ids::new): SampleDataSet {
        val register = mutableListOf<SampleRecord>()
        fun reg(id: String, e: SampleEntity) { register += SampleRecord(id, e.raw, now) }
        val startOfToday = calendar.startOfDay(now)
        fun day(daysAgo: Int, hour: Int = 12): Long = startOfToday + (hour - daysAgo * 24) * 3_600_000L

        // People and a payment method
        val people = peopleNames.mapIndexed { i, name ->
            Person(newId(), name, notes = "Example person added by Load Sample Data", isFrequent = i == 0, createdAt = now, updatedAt = now)
        }
        people.forEach { reg(it.id, SampleEntity.PERSON) }
        val (aiman, meiLing, ravi) = people
        val method = PersonPaymentMethod(newId(), aiman.id, PaymentMethodType.E_WALLET.raw, "Touch 'n Go", accountIdentifier = "0123456789",
            label = "Sample", createdAt = now, updatedAt = now)
        reg(method.id, SampleEntity.PAYMENT_METHOD)

        // Funding accounts used only by the samples (so real expenses are never linked to them)
        val bank = Account(newId(), BANK_NAME, AccountType.BANK.raw, sortIndex = 900, createdAt = now, updatedAt = now)
        val wallet = Account(newId(), WALLET_NAME, AccountType.E_WALLET.raw, sortIndex = 901, createdAt = now, updatedAt = now)
        listOf(bank, wallet).forEach { reg(it.id, SampleEntity.ACCOUNT) }

        val expenses = mutableListOf<Expense>()
        val shares = mutableListOf<ExpenseShare>()
        fun expense(merchant: String, minor: Long, category: ExpenseCategory, date: Long, account: Account, channel: PaymentChannel,
                    notes: String, split: SplitMethod? = null, payer: Person? = null): Expense {
            val e = Expense(
                id = newId(), amountMinor = minor, merchant = merchant, categoryRaw = category.raw, fundingAccount = account.name,
                accountId = account.id, paymentChannelRaw = channel.raw, paymentSourceRaw = PaymentSource.UNKNOWN.raw,
                paymentMethodRaw = PaymentSource.UNKNOWN.defaultPaymentMethod, date = date, notes = "$notes [Sample]",
                sourceTypeRaw = ExpenseSourceType.MANUAL.raw, isSampleData = true, splitMethodRaw = split?.raw,
                paidByMe = payer == null, payerId = payer?.id, payerNameSnapshot = payer?.name, createdAt = now, updatedAt = now,
            )
            expenses += e
            reg(e.id, SampleEntity.EXPENSE)
            return e
        }
        fun share(e: Expense, person: Person?, minor: Long, index: Int, parts: Int? = null, entered: Long? = null) {
            shares += ExpenseShare(newId(), e.id, person?.id, isMe = person == null, nameSnapshot = person?.name ?: "Me", amountMinor = minor,
                parts = parts, enteredMinor = entered, sortIndex = index, createdAt = now, updatedAt = now)
        }

        // 1. Normal expense (not shared)
        expense("Grocer (Sample)", 4590, ExpenseCategory.GROCERIES, day(1, 18), bank, PaymentChannel.QR_PAYMENT, "Normal expense")

        // 2. Equal split, I paid: RM120 / 3 → Aiman and Mei Ling owe RM40 each
        val dinner = expense("Team Dinner (Sample)", 12000, ExpenseCategory.FOOD, day(6, 20), bank, PaymentChannel.CARD, "Equal split", SplitMethod.EQUAL)
        share(dinner, null, 4000, 0); share(dinner, aiman, 4000, 1); share(dinner, meiLing, 4000, 2)

        // 3. Parts split, I paid: RM300, Me 1 part, Ravi 2 parts → Ravi owes RM200
        val villa = expense("Holiday Villa (Sample)", 30000, ExpenseCategory.ENTERTAINMENT, day(20, 15), bank, PaymentChannel.BANK_TRANSFER, "Parts split", SplitMethod.PARTS)
        share(villa, null, 10000, 0, parts = 1); share(villa, ravi, 20000, 1, parts = 2)

        // 4. Amount split with Auto Calculate: RM7.00, Me RM0.01 → Aiman RM6.99 (calculated)
        val coffee = expense("Coffee Run (Sample)", 700, ExpenseCategory.FOOD, day(3, 9), wallet, PaymentChannel.QR_PAYMENT, "Amounts, Auto Calculate", SplitMethod.AMOUNTS)
        share(coffee, null, 1, 0, entered = 1); share(coffee, aiman, 699, 1, entered = 699)

        // 5. Paid for someone: I paid RM150 for Ravi (my share is an automatic 0)
        val ticket = expense("Concert Ticket for Ravi (Sample)", 15000, ExpenseCategory.ENTERTAINMENT, day(10, 19), bank, PaymentChannel.APPLE_PAY, "Paid for someone", SplitMethod.EQUAL)
        share(ticket, null, 0, 0); share(ticket, ravi, 15000, 1)

        // 6. Someone paid for me: Mei Ling paid RM25 for my taxi → I owe her RM25
        val taxi = expense("Taxi paid by Mei Ling (Sample)", 2500, ExpenseCategory.TRANSPORT, day(4, 23), wallet, PaymentChannel.UNKNOWN, "Someone paid for me", SplitMethod.EQUAL, payer = meiLing)
        share(taxi, null, 2500, 0)

        // 7. Two identical transactions (both legitimate): parking RM10 for Aiman, twice
        for (hour in listOf(9, 17)) {
            val parking = expense("Parking (Sample)", 1000, ExpenseCategory.TRANSPORT, day(2, hour), wallet, PaymentChannel.QR_PAYMENT, "Same amount, separate payment", SplitMethod.EQUAL)
            share(parking, null, 0, 0); share(parking, aiman, 1000, 1)
        }

        // 8. Direct transfer: I gave Aiman RM60 (a loan, not an expense)
        val movements = mutableListOf<MoneyMovement>()
        fun movement(kind: MoneyMovementKind, minor: Long, date: Long, person: Person, note: String) =
            MoneyMovement(newId(), kind.raw, kind.direction.raw, minor, date = date, personId = person.id, personNameSnapshot = person.name,
                accountId = bank.id, note = note, sourceTypeRaw = ExpenseSourceType.MANUAL.raw, createdAt = now, updatedAt = now)
                .also { movements += it; reg(it.id, SampleEntity.MOVEMENT) }
        movement(MoneyMovementKind.LOAN_GIVEN, 6000, day(15, 11), aiman, "Lent for books (Sample)")

        // Settlements: one payment can go to one or several transactions; any extra stays as credit.
        val allocations = mutableListOf<SettlementAllocation>()
        fun payment(person: Person, minor: Long, date: Long, note: String, allocs: List<Pair<Expense, Long>>) {
            val p = movement(MoneyMovementKind.REPAYMENT_RECEIVED, minor, date, person, "$note (Sample)")
            val group = newId()
            for ((e, amount) in allocs) {
                val a = SettlementAllocation(newId(), group, SettlementKind.PAYMENT.raw, paymentId = p.id, expenseId = e.id, loanId = null,
                    personId = person.id, direction = 1, amountMinor = amount, currency = "RM", date = date, createdAt = now)
                allocations += a
                reg(a.id, SampleEntity.ALLOCATION)
            }
        }
        // 9. Partial settlement: Ravi paid RM100 towards the villa (RM200) → RM100 left
        payment(ravi, 10000, day(12, 10), "Part of the villa", listOf(villa to 10000L))
        // 10. Full settlement: Aiman paid the coffee (RM6.99) → settled
        payment(aiman, 699, day(2, 12), "Coffee", listOf(coffee to 699L))
        // 11. Payment larger than the debt: Mei Ling paid RM50 for the dinner (RM40) → RM10 credit
        payment(meiLing, 5000, day(5, 21), "Dinner, rounded up", listOf(dinner to 4000L))

        return SampleDataSet(people, listOf(method), listOf(bank, wallet), expenses, shares, movements, allocations, register)
    }

    /**
     * Exactly the registered sample records (and expenses flagged `isSampleData`). Real expenses, people, repayments,
     * settlements and accounts are never removed. A sample person (or account) that real records now use is kept and
     * becomes a normal record.
     */
    fun removalPlan(s: FinanceSnapshot, now: Long): SampleRemovalPlan {
        fun ids(e: SampleEntity) = s.sampleRecords.filter { it.entityRaw == e.raw }.map { it.recordId }.toSet()

        // Expenses: registered ones plus any flagged as sample (older demo data).
        val sampleExpenseIds = ids(SampleEntity.EXPENSE)
        val expenses = s.expenses.filter { it.isSampleData || it.id in sampleExpenseIds }
        val removedExpenseIds = expenses.map { it.id }.toSet()
        val accountsById = s.accounts.associateBy { it.id }
        val flaggedAccounts = expenses.mapNotNull { e -> e.accountId?.let { accountsById[it] } }
        val firstFlagged = expenses.minOfOrNull { it.createdAt }
        val shareIds = s.shares.filter { it.expenseId in removedExpenseIds }.map { it.id }.toSet()

        // Money records (sample repayments and loans)
        val movementIds = ids(SampleEntity.MOVEMENT).intersect(s.movements.map { it.id }.toSet())

        // Settlements: registered ones, and any that only pointed at removed sample records.
        val allocationIdsRegistered = ids(SampleEntity.ALLOCATION)
        val allocationIds = s.allocations.filter { a ->
            a.id in allocationIdsRegistered || a.paymentId in movementIds || a.expenseId in removedExpenseIds || a.loanId in movementIds
        }.map { it.id }.toSet()

        // Payment methods
        val methodIds = ids(SampleEntity.PAYMENT_METHOD).intersect(s.paymentMethods.map { it.id }.toSet())

        val remainingExpenses = s.expenses.filter { it.id !in removedExpenseIds }
        val remainingShares = s.shares.filter { it.id !in shareIds }
        val remainingMovements = s.movements.filter { it.id !in movementIds }
        val remainingMethods = s.paymentMethods.filter { it.id !in methodIds }

        // People: removed only when nothing real refers to them any more.
        val personIdsRegistered = ids(SampleEntity.PERSON)
        val removedPeople = mutableSetOf<String>()
        var kept = 0
        for (person in s.people) if (person.id in personIdsRegistered) {
            val inUse = remainingShares.any { it.personId == person.id } || remainingExpenses.any { it.payerId == person.id } ||
                remainingMovements.any { it.personId == person.id } || remainingMethods.any { it.personId == person.id }
            if (inUse) kept++ else removedPeople += person.id
        }

        // Accounts: registered ones without real records; plus (older demo data) accounts that only held flagged samples.
        val accountIdsRegistered = ids(SampleEntity.ACCOUNT)
        var candidates = s.accounts.filter { it.id in accountIdsRegistered }
        if (firstFlagged != null) candidates = candidates + flaggedAccounts.filter { it.id !in accountIdsRegistered && it.createdAt >= firstFlagged }
        val removedAccounts = mutableSetOf<String>()
        for (account in candidates.distinctBy { it.id }) {
            val inUse = remainingExpenses.any { it.accountId == account.id } ||
                remainingMovements.any { it.accountId == account.id || it.counterAccountId == account.id }
            if (!inUse) removedAccounts += account.id
        }

        val unlinked = remainingMovements.filter { it.linkedExpenseId != null && it.linkedExpenseId in removedExpenseIds }
            .map { it.copy(linkedExpenseId = null, updatedAt = now) }

        return SampleRemovalPlan(
            expenseIds = removedExpenseIds, shareIds = shareIds, movementIds = movementIds, allocationIds = allocationIds,
            paymentMethodIds = methodIds, personIds = removedPeople, accountIds = removedAccounts,
            sampleRecordIds = s.sampleRecords.map { it.recordId }.toSet(), unlinkedMovements = unlinked,
            report = RemovalReport(
                expensesRemoved = expenses.size, peopleRemoved = removedPeople.size, peopleKept = kept,
                movementsRemoved = movementIds.size, settlementsRemoved = allocationIds.size,
                accountsRemoved = removedAccounts.size, paymentMethodsRemoved = methodIds.size,
            ),
        )
    }
}
