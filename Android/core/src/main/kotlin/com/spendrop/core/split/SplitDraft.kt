package com.spendrop.core.split

import com.spendrop.core.Ids
import com.spendrop.core.Money
import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** What saving a split writes: the updated expense, the new share rows, and the old share ids to tombstone. */
data class SplitSave(
    val expense: Expense,
    val newShares: List<ExpenseShare>,
    val tombstoneShareIds: List<String>,
)

/** Result of [SplitDraft.recalculateAfterAmountChange]: whether shares now match, and what to write (if anything). */
data class RecalculateResult(val sharesMatch: Boolean, val save: SplitSave?)

/**
 * Editable state of an expense split (iOS `SplitDraft`): participants, purpose, method, payer, Auto Calculate.
 * Immutable: every edit returns a new draft (suits a Compose ViewModel's StateFlow). A split is stored as
 * [ExpenseShare] rows on the one [Expense]. Amounts are integer sen.
 */
data class SplitDraft(
    val method: SplitMethod = SplitMethod.EQUAL,
    val purpose: Purpose = Purpose.SHARED,
    /**
     * Amounts method only, and only for THIS split (never a saved preference: every new split starts ON).
     * ON: typed amounts are kept exactly; what's left (after typed and fixed amounts) is shared equally by everyone
     * not typed for — Me included — plus each person's fixed amount. OFF: typed amounts must add up to the total.
     */
    val autoCalculate: Boolean = true,
    /** Me is always first and can never be removed. */
    val participants: List<Participant> = listOf(Participant.me()),
    /** null = I paid. */
    val payer: Person? = null,
    /** Participants whose amount the user typed, oldest first (drives Auto Calculate). */
    val typedOrder: List<String> = emptyList(),
) {
    data class Participant(
        val id: String = Ids.new(),
        val person: Person? = null,
        val isMe: Boolean = false,
        val name: String,
        /** Parts method: 1…99. */
        val parts: Int = 1,
        /** Amounts method: what the user typed (kept as text). For calculated people it only mirrors the value. */
        val amountText: String = "",
        /** Amounts + Auto Calculate: base amount added to this person's equal part of the remainder. null = none. */
        val fixedMinor: Long? = null,
    ) {
        companion object {
            fun me(id: String = Ids.new()) = Participant(id = id, isMe = true, name = "Me")
        }
    }

    /**
     * SHARED: everyone in the list (including me) shares the cost.
     * PAID_FOR: one side paid entirely for the other — I paid for the people listed (my share is 0), or the payer
     * paid entirely for me (my share is the whole total).
     */
    enum class Purpose { SHARED, PAID_FOR }

    /** Why a split can't be saved yet. */
    sealed class Problem {
        data class Calculator(val error: SplitCalculator.SplitError) : Problem()
        /** Fixed amounts alone are more than the total (by this many sen). */
        data class FixedExceedTotal(val overMinor: Long) : Problem()
        /** Money is left over and Auto Calculate has nobody to give it to (everyone has a typed amount). */
        data class NoOneForRemainder(val remainingMinor: Long) : Problem()
    }

    // MARK: Derived

    /** I paid entirely for the people in the list. */
    val iPaidForOthers: Boolean get() = purpose == Purpose.PAID_FOR && payer == null
    /** Someone paid entirely for me. */
    val paidForMe: Boolean get() = purpose == Purpose.PAID_FOR && payer != null
    val iPaid: Boolean get() = payer == null

    /** The people whose shares are calculated: everyone (shared), the people I paid for, or only me. */
    val sharingParticipants: List<Participant>
        get() = when {
            iPaidForOthers -> others
            paidForMe -> participants.filter { it.isMe }
            else -> participants
        }

    val others: List<Participant> get() = participants.filter { !it.isMe }

    fun contains(person: Person): Boolean = participants.any { it.person?.id == person.id }

    // MARK: Editing (each returns the new draft)

    /** Adds a person once. Returns this same instance when they were already in the split. */
    fun add(person: Person): SplitDraft {
        if (contains(person)) return this
        return copy(participants = participants + Participant(person = person, name = person.name))
    }

    /** Removes a participant. Me cannot be removed. A payer who is not a participant is allowed and kept. */
    fun remove(id: String): SplitDraft {
        val p = participants.firstOrNull { it.id == id } ?: return this
        if (p.isMe) return this
        return copy(participants = participants.filter { it.id != id }, typedOrder = typedOrder.filter { it != id })
    }

    fun setParts(parts: Int, id: String): SplitDraft =
        mapParticipant(id) { it.copy(parts = min(max(parts, 1), SplitCalculator.MAX_PARTS)) }

    fun setPurpose(purpose: Purpose): SplitDraft = copy(purpose = purpose)
    fun setPayer(payer: Person?): SplitDraft = copy(payer = payer)

    /**
     * Sets a typed amount: kept exactly as typed (replaces any fixed amount for that person). Clearing the box hands
     * the person back to Auto Calculate. With Auto Calculate on, when every person now has a typed amount, the one
     * typed longest ago is handed back to Auto Calculate so the total still works out.
     */
    fun setAmountText(text: String, id: String, totalMinor: Long? = null): SplitDraft {
        if (participants.none { it.id == id }) return this
        var d = mapParticipant(id) { it.copy(amountText = text) }.let { it.copy(typedOrder = it.typedOrder.filter { t -> t != id }) }
        if (text.isBlank()) {
            return if (totalMinor != null) d.refreshCalculatedText(totalMinor) else d
        }
        d = d.copy(typedOrder = d.typedOrder + id).mapParticipant(id) { it.copy(fixedMinor = null) }
        if (!d.autoCalculate || d.method != SplitMethod.AMOUNTS || totalMinor == null) return d
        val group = d.sharingParticipants
        if (group.size >= 2 && group.any { it.id == id } && group.all { d.typedOrder.contains(it.id) }) {
            val oldest = d.typedOrder.firstOrNull { typed -> typed != id && group.any { it.id == typed } }
            if (oldest != null) d = d.copy(typedOrder = d.typedOrder.filter { it != oldest })
        }
        return d.refreshCalculatedText(totalMinor)
    }

    /**
     * Sets (or clears, with null) a person's fixed amount. Returns null when refused (negative amount or unknown id).
     * A person with a fixed amount is calculated: fixed + their equal part of the remainder.
     */
    fun setFixed(minor: Long?, id: String, totalMinor: Long? = null): SplitDraft? {
        if (participants.none { it.id == id }) return null
        if (minor != null && minor < 0) return null
        val d = mapParticipant(id) { it.copy(fixedMinor = if ((minor ?: 0) > 0) minor else null) }
            .let { it.copy(typedOrder = it.typedOrder.filter { t -> t != id }) }
        return if (totalMinor != null) d.refreshCalculatedText(totalMinor) else d
    }

    /**
     * Turns Auto Calculate on or off for this split. Off keeps every amount exactly as currently shown (they become
     * the typed amounts); on again recalculates everyone the user didn't type for.
     */
    fun setAutoCalculate(on: Boolean, totalMinor: Long): SplitDraft {
        if (on == autoCalculate) return this
        var d = this
        if (!on && method == SplitMethod.AMOUNTS) {
            val shown = shares(totalMinor)
            if (shown != null) {
                val sharing = sharingParticipants.map { it.id }.toSet()
                d = d.copy(participants = participants.mapIndexed { i, p ->
                    if (p.id in sharing) p.copy(amountText = text(shown[i])) else p
                })
            }
        }
        d = d.copy(autoCalculate = on)
        return if (on) d.refreshCalculatedText(totalMinor) else d
    }

    /** "Split Equally". */
    fun useEqualSplit(): SplitDraft = copy(method = SplitMethod.EQUAL)

    /** "Parts". */
    fun useParts(): SplitDraft = copy(method = SplitMethod.PARTS)

    /**
     * "Custom Amount": switches to amounts. With Auto Calculate on, everyone not typed for is calculated; with it
     * off, empty boxes start from the current shares so they already add up and the user only adjusts.
     */
    fun useCustomAmounts(totalMinor: Long): SplitDraft {
        if (method == SplitMethod.AMOUNTS) return this
        val current = shares(totalMinor)
        var d = copy(method = SplitMethod.AMOUNTS)
        val sharing = d.sharingParticipants.map { it.id }.toSet()
        val nothingTyped = d.participants.filter { it.id in sharing }.all { (Money.parseMinor(it.amountText) ?: 0L) == 0L }
        if (current != null && nothingTyped) {
            d = d.copy(
                participants = d.participants.mapIndexed { i, p -> if (p.id in sharing) p.copy(amountText = text(current[i])) else p },
                typedOrder = emptyList(),
            )
        }
        return d.refreshCalculatedText(totalMinor)
    }

    /** True when Auto Calculate works out this person's amount (nothing typed for them). */
    fun isCalculated(id: String): Boolean = autoCalculate && method == SplitMethod.AMOUNTS && !paidForMe && !typedOrder.contains(id)

    /** The amount to show in a person's box: what they typed, or the calculated amount. */
    fun displayAmountText(id: String, totalMinor: Long): String {
        val index = participants.indexOfFirst { it.id == id }
        if (index < 0) return ""
        if (!isCalculated(id)) return participants[index].amountText
        return autoAmounts(totalMinor).valueOrNull()?.let { text(it[index]) } ?: ""
    }

    /** Fixed amounts of the people Auto Calculate works out (the "Fixed" line of the summary). */
    val fixedTotalMinor: Long
        get() {
            if (!autoCalculate || method != SplitMethod.AMOUNTS) return 0
            return sharingParticipants.filter { isCalculated(it.id) }.sumOf { it.fixedMinor ?: 0L }
        }

    /** Amounts method: what the typed boxes add up to (iOS `assignedMinor()`). */
    fun assignedTypedMinor(): Long = sharingParticipants.sumOf { Money.parseMinor(it.amountText) ?: 0L }

    /** What the shares add up to for this total: typed amounts, fixed amounts and the calculated remainder. */
    fun assignedMinor(totalMinor: Long): Long {
        if (!autoCalculate || method != SplitMethod.AMOUNTS || paidForMe) return assignedTypedMinor()
        val group = sharingParticipants
        val typed = group.filter { !isCalculated(it.id) }.sumOf { Money.parseMinor(it.amountText) ?: 0L }
        val floating = group.filter { isCalculated(it.id) }
        val fixed = floating.sumOf { it.fixedMinor ?: 0L }
        return if (floating.isEmpty()) typed else max(typed + fixed, totalMinor)
    }

    fun remainingMinor(totalMinor: Long): Long = totalMinor - assignedMinor(totalMinor)

    // MARK: Calculation

    /** One amount per entry in [participants] (people outside the sharing group get 0). */
    fun calculate(totalMinor: Long): Outcome<List<Long>, Problem> {
        if (method == SplitMethod.AMOUNTS && autoCalculate && !paidForMe) return autoAmounts(totalMinor)
        return when (val r = plainCalculate(totalMinor)) {
            is Outcome.Ok -> r
            is Outcome.Err -> Outcome.Err(Problem.Calculator(r.error))
        }
    }

    /**
     * Auto Calculate: typed amounts as typed; total − typed − fixed shared equally (exact sen, same rule as Split
     * Equally) by everyone not typed for; each of them also gets their fixed amount.
     */
    internal fun autoAmounts(totalMinor: Long): Outcome<List<Long>, Problem> {
        if (totalMinor <= 0) return Outcome.Err(Problem.Calculator(SplitCalculator.SplitError.NonPositiveTotal))
        val group = sharingParticipants
        val requireMe = !iPaidForOthers
        if (group.size < (if (requireMe) 2 else 1)) return Outcome.Err(Problem.Calculator(SplitCalculator.SplitError.TooFewParticipants))
        val result = MutableList(participants.size) { 0L }
        var typedSum = 0L
        val floating = ArrayList<Int>()
        for ((groupIndex, p) in group.withIndex()) {
            val index = participants.indexOfFirst { it.id == p.id }
            if (isCalculated(p.id)) {
                floating.add(index)
            } else {
                val minor = Money.parseMinor(p.amountText)
                    ?: return Outcome.Err(Problem.Calculator(SplitCalculator.SplitError.MissingAmount(groupIndex)))
                if (minor < 0) return Outcome.Err(Problem.Calculator(SplitCalculator.SplitError.NegativeAmount(groupIndex)))
                result[index] = minor
                typedSum += minor
            }
        }
        val fixedSum = floating.sumOf { participants[it].fixedMinor ?: 0L }
        if (fixedSum > totalMinor) return Outcome.Err(Problem.FixedExceedTotal(fixedSum - totalMinor))
        val remainder = totalMinor - typedSum - fixedSum
        if (remainder < 0) return Outcome.Err(Problem.Calculator(SplitCalculator.SplitError.AmountsDoNotMatchTotal(-remainder)))
        if (floating.isEmpty()) {
            return if (remainder == 0L) Outcome.Ok(result) else Outcome.Err(Problem.NoOneForRemainder(remainder))
        }
        var parts: List<Long> = floating.map { 0L }
        if (remainder > 0) {
            val inputs = floating.map { SplitCalculator.Participant(isMe = participants[it].isMe) }
            val hasMe = inputs.any { it.isMe }
            if (inputs.size == 1) {
                parts = listOf(remainder)
            } else {
                SplitCalculator.calculate(remainder, SplitMethod.EQUAL, inputs, iPaid = iPaid, requireMe = hasMe).valueOrNull()?.let { parts = it }
            }
        }
        for ((position, index) in floating.withIndex()) {
            result[index] = parts[position] + (participants[index].fixedMinor ?: 0L)
        }
        return Outcome.Ok(result)
    }

    private fun plainCalculate(totalMinor: Long): Outcome<List<Long>, SplitCalculator.SplitError> {
        if (paidForMe) {
            if (totalMinor <= 0) return Outcome.Err(SplitCalculator.SplitError.NonPositiveTotal)
            return Outcome.Ok(participants.map { if (it.isMe) totalMinor else 0L })
        }
        val group = sharingParticipants
        val inputs = group.map { SplitCalculator.Participant(isMe = it.isMe, parts = it.parts, enteredMinor = enteredMinor(it.amountText)) }
        return when (val r = SplitCalculator.calculate(totalMinor, method, inputs, iPaid = iPaid, requireMe = !iPaidForOthers)) {
            is Outcome.Err -> r
            is Outcome.Ok -> Outcome.Ok(participants.map { p ->
                val gi = group.indexOfFirst { it.id == p.id }
                if (gi >= 0) r.value[gi] else 0L
            })
        }
    }

    fun shares(totalMinor: Long): List<Long>? = calculate(totalMinor).valueOrNull()

    fun myShareMinor(totalMinor: Long): Long? {
        val s = shares(totalMinor) ?: return null
        val me = participants.indexOfFirst { it.isMe }
        return if (me >= 0) s[me] else null
    }

    /** A readable problem (same words as iOS), or null when the split is valid for this total. */
    fun problem(totalMinor: Long): String? {
        fun money(minor: Long) = Money.format(abs(minor))
        val error = calculate(totalMinor).errorOrNull() ?: return null
        return when (error) {
            is Problem.FixedExceedTotal -> "Fixed amounts exceed the expense total by ${money(error.overMinor)}."
            is Problem.NoOneForRemainder ->
                "${money(error.remainingMinor)} remains unassigned. Select at least one participant for the remaining amount (clear someone's amount)."
            is Problem.Calculator -> when (val e = error.error) {
                SplitCalculator.SplitError.NonPositiveTotal -> "Enter the expense amount first."
                SplitCalculator.SplitError.TooFewParticipants -> if (iPaidForOthers) "Choose who you paid for." else "Add at least one other person."
                SplitCalculator.SplitError.MissingMe, SplitCalculator.SplitError.MoreThanOneMe -> "A split must include you exactly once."
                is SplitCalculator.SplitError.InvalidParts -> "Parts must be whole numbers from 1 to ${SplitCalculator.MAX_PARTS}."
                is SplitCalculator.SplitError.MissingAmount -> "Enter a valid amount for ${sharingParticipants[e.index].let { if (it.isMe) "You" else it.name }}."
                is SplitCalculator.SplitError.NegativeAmount -> "${sharingParticipants[e.index].name}'s amount can't be negative."
                is SplitCalculator.SplitError.AmountsDoNotMatchTotal ->
                    if (e.differenceMinor > 0) "Shares exceed the total by ${money(e.differenceMinor)}." else "${money(e.differenceMinor)} remains unassigned."
            }
        }
    }

    fun isValid(totalMinor: Long): Boolean = problem(totalMinor) == null

    // MARK: Saving

    /**
     * Replaces the expense's shares with this split. Returns null (nothing to write) when invalid.
     * [currentShares] are the expense's live shares (all are tombstoned; new rows get new ids, like iOS).
     */
    fun apply(expense: Expense, currentShares: List<ExpenseShare>, now: Long): SplitSave? {
        val amounts = shares(expense.amountMinor) ?: return null
        val sharing = sharingParticipants.map { it.id }.toSet()
        val rows = ArrayList<ExpenseShare>()
        for ((index, p) in participants.withIndex()) {
            // Someone paid entirely for me: only my share is stored. I paid for others: my share is an automatic 0.
            if (paidForMe && !p.isMe) continue
            val inGroup = p.id in sharing
            rows += ExpenseShare(
                id = Ids.new(),
                expenseId = expense.id,
                personId = if (p.isMe) null else p.person?.id,
                isMe = p.isMe,
                nameSnapshot = if (p.isMe) "Me" else (p.person?.name ?: p.name),
                amountMinor = amounts[index],
                parts = if (method == SplitMethod.PARTS && inGroup && !paidForMe) p.parts else null,
                enteredMinor = if (method == SplitMethod.AMOUNTS && inGroup && !paidForMe) amounts[index] else null,
                sortIndex = index,
                createdAt = now,
                updatedAt = now,
            )
        }
        val updated = expense.copy(
            splitMethodRaw = method.raw,
            paidByMe = payer == null,
            payerId = payer?.id,
            payerNameSnapshot = payer?.name,
            updatedAt = now,
        )
        return SplitSave(updated, rows, currentShares.map { it.id })
    }

    private fun mapParticipant(id: String, f: (Participant) -> Participant): SplitDraft =
        copy(participants = participants.map { if (it.id == id) f(it) else it })

    /** Keeps the boxes of calculated people showing the calculated value. */
    private fun refreshCalculatedText(totalMinor: Long): SplitDraft {
        if (!autoCalculate || method != SplitMethod.AMOUNTS) return this
        val amounts = autoAmounts(totalMinor).valueOrNull() ?: return this
        return copy(participants = participants.mapIndexed { i, p -> if (isCalculated(p.id)) p.copy(amountText = text(amounts[i])) else p })
    }

    companion object {
        /**
         * Custom amounts: an empty box is RM 0.00 (what the box shows), never "missing" — e.g. You (empty) + Riyad 100
         * of RM100 is a complete split. Text that isn't a number is reported instead of being guessed. (iOS 2026-10-07)
         */
        fun enteredMinor(text: String): Long? = if (text.isBlank()) 0L else Money.parseMinor(text)

        /** 750 -> "7.50" (iOS `String(format: "%.2f")`). */
        fun text(minor: Long): String = Money.plain(minor)

        /**
         * Loads the split stored on an expense (null when the expense is not shared). [shares] are its live shares;
         * [people] resolves share/payer person ids (a deleted person resolves to nothing, like iOS).
         */
        fun fromExpense(expense: Expense, shares: List<ExpenseShare>, people: List<Person>): SplitDraft? {
            if (shares.isEmpty()) return null
            val byId = people.associateBy { it.id }
            val mine = shares.firstOrNull { it.isMe }
            var purpose = Purpose.SHARED
            // "Paid for someone" is recognised from the data: I paid and my share is an automatic 0, or someone else
            // paid and I am the only participant.
            if (expense.paidByMe && mine != null && mine.amountMinor == 0L && mine.enteredMinor == null && mine.parts == null && shares.size > 1) {
                purpose = Purpose.PAID_FOR
            } else if (!expense.paidByMe && shares.size == 1 && mine != null) {
                purpose = Purpose.PAID_FOR
            }
            val ordered = shares.sortedWith(compareBy<ExpenseShare> { if (it.isMe) 0 else 1 }.thenBy { it.sortIndex })
            val participants = ordered.map { share ->
                val person = share.personId?.let { byId[it] }
                Participant(
                    id = share.id,
                    person = person,
                    isMe = share.isMe,
                    name = if (share.isMe) "Me" else (person?.name ?: share.nameSnapshot),
                    parts = share.parts ?: 1,
                    amountText = text(share.enteredMinor ?: share.amountMinor),
                ).let { if (it.isMe) it.copy(person = null) else it }
            }.toMutableList()
            if (participants.none { it.isMe }) participants.add(0, Participant.me())
            return SplitDraft(
                method = expense.splitMethod ?: SplitMethod.AMOUNTS,
                purpose = purpose,
                // Existing typed amounts are kept exactly as they are.
                autoCalculate = false,
                participants = participants,
                payer = if (expense.paidByMe) null else expense.payerId?.let { byId[it] },
            )
        }

        /** Makes the expense a normal (unshared) expense again: shares removed, I paid. */
        fun removeSplit(expense: Expense, shares: List<ExpenseShare>, now: Long): SplitSave =
            SplitSave(
                expense.copy(splitMethodRaw = null, paidByMe = true, payerId = null, payerNameSnapshot = null, updatedAt = now),
                emptyList(),
                shares.map { it.id },
            )

        /**
         * After the amount of a shared expense changed ([expense] carries the new amount): Equal and Parts are
         * recalculated; Amounts are left untouched and reported as needing attention.
         * `sharesMatch` is true when the stored shares (after [RecalculateResult.save], if any) match the amount.
         */
        fun recalculateAfterAmountChange(expense: Expense, shares: List<ExpenseShare>, people: List<Person>, now: Long): RecalculateResult {
            if (!ExpenseMath.isShared(shares)) return RecalculateResult(true, null)
            val draft = fromExpense(expense, shares, people) ?: return RecalculateResult(true, null)
            if (draft.method == SplitMethod.AMOUNTS) return RecalculateResult(ExpenseMath.sharesMatchAmount(expense, shares), null)
            val save = draft.apply(expense, shares, now)
            return RecalculateResult(save != null, save)
        }

        /**
         * "Same as last time": the people (and method) of the most recent shared expense — preferring one at the same
         * merchant. Only people that still exist and are not archived are suggested. null when there's no useful history.
         */
        fun lastTimeSuggestion(merchant: String?, snapshot: FinanceSnapshot, excludingExpenseId: String? = null): SplitDraft? {
            val people = snapshot.people.filter { it.deletedAt == null }.associateBy { it.id }
            val recent = snapshot.expenses.filter { it.deletedAt == null }
                .sortedByDescending { it.date }
                .take(200)
                .filter { ExpenseMath.isShared(snapshot.sharesOf(it.id)) && it.id != excludingExpenseId }
            val merchantKey = merchant?.trim()?.lowercase()
            val source = recent.firstOrNull { !merchantKey.isNullOrEmpty() && it.merchant.lowercase() == merchantKey } ?: recent.firstOrNull()
                ?: return null
            val sourceShares = snapshot.sharesOf(source.id)
            var draft = SplitDraft(method = if (source.splitMethod == SplitMethod.PARTS) SplitMethod.PARTS else SplitMethod.EQUAL)
            val suggested = sourceShares.sortedBy { it.sortIndex }
                .mapNotNull { if (it.isMe) null else it.personId?.let { id -> people[id] } }
                .filter { !it.isArchived }
            for (person in suggested) {
                draft = draft.add(person)
                if (draft.method == SplitMethod.PARTS) {
                    sourceShares.firstOrNull { it.personId == person.id }?.parts?.let { draft = draft.setParts(it, draft.participants.last().id) }
                }
            }
            if (draft.method == SplitMethod.PARTS) {
                sourceShares.firstOrNull { it.isMe }?.parts?.let { draft = draft.setParts(it, draft.participants[0].id) }
            }
            return if (draft.others.isEmpty()) null else draft
        }
    }
}
