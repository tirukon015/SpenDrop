package com.spendrop.core.split

import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS change of 2026-10-07: with Auto Calculate OFF, an empty custom-amount box counts as RM 0.00. */
class EmptyBoxRuleTest {
    private val riyad = Person("r", "Riyad", createdAt = 0, updatedAt = 0)

    @Test fun emptyBoxIsZeroWhenAutoCalculateOff() {
        var d = SplitDraft().add(riyad).useCustomAmounts(10000).setAutoCalculate(false, 10000)
        val r = d.participants.first { !it.isMe }
        val me = d.participants.first { it.isMe }
        d = d.setAmountText("", me.id, 10000).setAmountText("100", r.id, 10000)
        assertEquals(SplitMethod.AMOUNTS, d.method)
        assertNull(d.problem(10000))
        assertEquals(listOf(0L, 10000L), d.shares(10000))
    }

    @Test fun textThatIsNotANumberIsReported() {
        var d = SplitDraft().add(riyad).useCustomAmounts(10000).setAutoCalculate(false, 10000)
        val me = d.participants.first { it.isMe }
        d = d.setAmountText("abc", me.id, 10000)
        assertEquals("Enter a valid amount for You.", d.problem(10000))
    }
}
