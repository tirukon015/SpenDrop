package com.spendrop.core.split

import com.spendrop.core.model.SplitMethod

/** A success value or a typed failure (no exceptions for expected validation outcomes). */
sealed class Outcome<out T, out E> {
    data class Ok<out T>(val value: T) : Outcome<T, Nothing>()
    data class Err<out E>(val error: E) : Outcome<Nothing, E>()

    fun valueOrNull(): T? = (this as? Ok)?.value
    fun errorOrNull(): E? = (this as? Err)?.error
    val isOk: Boolean get() = this is Ok
}

/**
 * Divides an expense total between participants in integer minor units (iOS `SplitCalculator`). Pure logic.
 * The result always adds up exactly to the total, or the calculation fails with a validation error.
 */
object SplitCalculator {
    data class Participant(
        val isMe: Boolean = false,
        /** Parts method: a whole number from 1 to 99. */
        val parts: Int? = null,
        /** Amounts method: the exact share in minor units (0 allowed). */
        val enteredMinor: Long? = null,
    )

    sealed class SplitError {
        data object NonPositiveTotal : SplitError()
        data object TooFewParticipants : SplitError()
        data object MissingMe : SplitError()
        data object MoreThanOneMe : SplitError()
        data class InvalidParts(val index: Int) : SplitError()
        data class MissingAmount(val index: Int) : SplitError()
        data class NegativeAmount(val index: Int) : SplitError()
        /** Positive = shares add up to MORE than the total; negative = less. Never silently adjusted. */
        data class AmountsDoNotMatchTotal(val differenceMinor: Long) : SplitError()
    }

    const val MAX_PARTS = 99

    /**
     * @param iPaid when true, leftover sen from rounding go to Me first so friends never owe an extra sen.
     * @param requireMe false for "paid for someone": the people I paid for share the whole total (one person is
     *   enough) and I am not part of it.
     */
    fun calculate(
        totalMinor: Long,
        method: SplitMethod,
        participants: List<Participant>,
        iPaid: Boolean = true,
        requireMe: Boolean = true,
    ): Outcome<List<Long>, SplitError> {
        if (totalMinor <= 0) return Outcome.Err(SplitError.NonPositiveTotal)
        if (participants.size < (if (requireMe) 2 else 1)) return Outcome.Err(SplitError.TooFewParticipants)
        val meCount = participants.count { it.isMe }
        if (requireMe) {
            if (meCount == 0) return Outcome.Err(SplitError.MissingMe)
            if (meCount != 1) return Outcome.Err(SplitError.MoreThanOneMe)
        } else if (meCount > 0) {
            return Outcome.Err(SplitError.MoreThanOneMe)
        }
        return when (method) {
            SplitMethod.EQUAL -> Outcome.Ok(largestRemainder(totalMinor, participants.map { 1L }, participants, iPaid))
            SplitMethod.PARTS -> {
                val weights = ArrayList<Long>()
                for ((index, p) in participants.withIndex()) {
                    val parts = p.parts
                    if (parts == null || parts !in 1..MAX_PARTS) return Outcome.Err(SplitError.InvalidParts(index))
                    weights.add(parts.toLong())
                }
                Outcome.Ok(largestRemainder(totalMinor, weights, participants, iPaid))
            }
            SplitMethod.AMOUNTS -> {
                val amounts = ArrayList<Long>()
                for ((index, p) in participants.withIndex()) {
                    val entered = p.enteredMinor ?: return Outcome.Err(SplitError.MissingAmount(index))
                    if (entered < 0) return Outcome.Err(SplitError.NegativeAmount(index))
                    amounts.add(entered)
                }
                val difference = amounts.sum() - totalMinor
                if (difference != 0L) Outcome.Err(SplitError.AmountsDoNotMatchTotal(difference)) else Outcome.Ok(amounts)
            }
        }
    }

    /**
     * Floor of each proportional share, then the leftover sen one by one to the largest fractional remainders.
     * Ties: Me first (when I paid), then list order. Deterministic for the same input.
     */
    private fun largestRemainder(totalMinor: Long, weights: List<Long>, participants: List<Participant>, iPaid: Boolean): List<Long> {
        val weightSum = weights.sum()
        val shares = weights.map { totalMinor * it / weightSum }.toMutableList()
        val remainders = weights.map { (totalMinor * it) % weightSum }
        var leftover = totalMinor - shares.sum()
        val order = participants.indices.sortedWith { a, b ->
            when {
                remainders[a] != remainders[b] -> remainders[b].compareTo(remainders[a])
                iPaid && participants[a].isMe != participants[b].isMe -> if (participants[a].isMe) -1 else 1
                else -> a.compareTo(b)
            }
        }
        var position = 0
        while (leftover > 0) {
            shares[order[position % order.size]] += 1
            leftover -= 1
            position += 1
        }
        return shares
    }
}
