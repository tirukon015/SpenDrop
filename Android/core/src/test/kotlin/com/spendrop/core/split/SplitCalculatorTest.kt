package com.spendrop.core.split

import com.spendrop.core.model.SplitMethod
import com.spendrop.core.split.SplitCalculator.Participant
import com.spendrop.core.split.SplitCalculator.SplitError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS FinancialModelTests "Split calculator" + DebtSettlementTests rounding cases. */
class SplitCalculatorTest {
    private val me = Participant(isMe = true)
    private val other = Participant()

    private fun split(total: Long, method: SplitMethod, ps: List<Participant>, iPaid: Boolean = true) =
        SplitCalculator.calculate(total, method, ps, iPaid)

    private fun ok(vararg v: Long) = Outcome.Ok(v.toList())

    @Test fun equalRm30By4() = assertEquals(ok(750, 750, 750, 750), split(3000, SplitMethod.EQUAL, listOf(me, other, other, other)))

    @Test fun oddSenGoesToMeWhenIPaid() = assertEquals(ok(333, 334, 333), split(1000, SplitMethod.EQUAL, listOf(other, me, other)))

    @Test fun oddSenInListOrderWhenSomeoneElsePaid() =
        assertEquals(ok(334, 333, 333), split(1000, SplitMethod.EQUAL, listOf(other, me, other), iPaid = false))

    @Test fun sevenWayRm100TotalsExactly() {
        val r = split(10000, SplitMethod.EQUAL, listOf(me) + List(6) { other })
        assertEquals(ok(1429, 1429, 1429, 1429, 1428, 1428, 1428), r)
        assertEquals(10000L, r.valueOrNull()!!.sum())
    }

    @Test fun parts1121() = assertEquals(ok(600, 600, 1200, 600),
        split(3000, SplitMethod.PARTS, listOf(Participant(true, parts = 1), Participant(parts = 1), Participant(parts = 2), Participant(parts = 1))))

    @Test fun partsWithRemainder() = assertEquals(ok(333, 667),
        split(1000, SplitMethod.PARTS, listOf(Participant(true, parts = 1), Participant(parts = 2))))

    @Test fun exactAmounts() = assertEquals(ok(800, 700, 800, 700), split(3000, SplitMethod.AMOUNTS,
        listOf(Participant(true, enteredMinor = 800), Participant(enteredMinor = 700), Participant(enteredMinor = 800), Participant(enteredMinor = 700))))

    @Test fun totalMismatchIsAnErrorNotAdjusted() = assertEquals(Outcome.Err(SplitError.AmountsDoNotMatchTotal(-1)),
        split(3000, SplitMethod.AMOUNTS, listOf(Participant(true, enteredMinor = 800), Participant(enteredMinor = 2199))))

    @Test fun meMayHaveZero() = assertEquals(ok(0, 3000),
        split(3000, SplitMethod.AMOUNTS, listOf(Participant(true, enteredMinor = 0), Participant(enteredMinor = 3000))))

    @Test fun validationErrors() {
        val errors = listOf(
            split(3000, SplitMethod.EQUAL, listOf(me)),
            split(3000, SplitMethod.EQUAL, listOf(other, other)),
            split(3000, SplitMethod.EQUAL, listOf(me, me)),
            split(0, SplitMethod.EQUAL, listOf(me, other)),
            split(3000, SplitMethod.PARTS, listOf(Participant(true, parts = 0), Participant(parts = 1))),
            split(3000, SplitMethod.AMOUNTS, listOf(Participant(true, enteredMinor = -1), Participant(enteredMinor = 3001))),
        )
        assertEquals(
            listOf(SplitError.TooFewParticipants, SplitError.MissingMe, SplitError.MoreThanOneMe, SplitError.NonPositiveTotal,
                SplitError.InvalidParts(0), SplitError.NegativeAmount(0)).map { Outcome.Err(it) },
            errors,
        )
    }

    @Test fun missingAmountAndPartsOver99() {
        assertEquals(Outcome.Err(SplitError.MissingAmount(1)), split(100, SplitMethod.AMOUNTS, listOf(Participant(true, enteredMinor = 100), other)))
        assertEquals(Outcome.Err(SplitError.InvalidParts(1)), split(100, SplitMethod.PARTS, listOf(Participant(true, parts = 1), Participant(parts = 100))))
    }

    @Test fun requireMeFalse_paidForSomeone() {
        assertEquals(ok(10000), SplitCalculator.calculate(10000, SplitMethod.EQUAL, listOf(other), requireMe = false))
        assertEquals(Outcome.Err(SplitError.MoreThanOneMe), SplitCalculator.calculate(10000, SplitMethod.EQUAL, listOf(me, other), requireMe = false))
        assertEquals(Outcome.Err(SplitError.TooFewParticipants), SplitCalculator.calculate(10000, SplitMethod.EQUAL, emptyList(), requireMe = false))
    }

    // DebtSettlementTests: "Equal (2, 3, 5 people) and parts (1:2) always add up exactly; leftover sen are deterministic"
    @Test fun equalAndPartsAlwaysAddUp() {
        fun s(total: Long, method: SplitMethod, count: Int, parts: List<Int>? = null) =
            SplitCalculator.calculate(total, method, (0 until count).map { Participant(isMe = it == 0, parts = parts?.get(it)) }).valueOrNull()
        assertEquals(listOf(5000L, 5000L), s(10000, SplitMethod.EQUAL, 2))
        assertEquals(listOf(334L, 333L, 333L), s(1000, SplitMethod.EQUAL, 3))
        assertEquals(listOf(2001L, 2001L, 2001L, 2000L, 2000L), s(10003, SplitMethod.EQUAL, 5))
        assertEquals(listOf(3333L, 6667L), s(10000, SplitMethod.PARTS, 2, listOf(1, 2)))
    }

    // "Tiny amounts (RM0.01–RM0.03 split between 2 and 3 people) still add up exactly, never negative"
    @Test fun tinyAmounts() {
        for (total in 1L..3L) for (count in 2..3) {
            val r = SplitCalculator.calculate(total, SplitMethod.EQUAL, (0 until count).map { Participant(isMe = it == 0) }).valueOrNull()!!
            assertEquals(total, r.sum())
            assertTrue(r.all { it >= 0 })
        }
    }
}
