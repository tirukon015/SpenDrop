package com.spendrop.core.parser

import com.spendrop.core.model.MoneyMovementKind

/**
 * Suggests whether a screenshot is money coming IN, an own-account top-up/transfer, or a refund, only from clear
 * wording. Anything unclear returns no suggestion and stays a normal expense for review. The user confirms.
 */
object DirectionDetector {
    data class Result(
        /** null = no confident suggestion (treat as the usual expense review). */
        val kind: MoneyMovementKind?,
        val reason: String?,
    ) {
        companion object {
            val NONE = Result(null, null)
        }
    }

    private val refundPhrases = listOf("refund", "refunded", "reversal", "reversed transaction")
    private val ownTransferPhrases = listOf("reload", "top up", "top-up", "topup", "transfer to wallet", "add money to", "cash in to wallet")
    private val incomingPhrases = listOf(
        "you have received", "you received", "received from", "money received", "incoming transfer", "credited to your",
        "has been credited", "fund received", "funds received", "payment received from", "transfer received", "duitnow received",
    )
    private val salaryPhrases = listOf("salary", "gaji", "payroll")
    private val outgoingPhrases = listOf(
        "paid to", "payment to", "pay to", "transfer to", "transferred to", "sent to", "you paid", "you sent", "purchase at",
    )

    fun detect(text: String): Result {
        val lower = text.lowercase().collapseWhitespace()
        fun has(phrases: List<String>): String? = phrases.firstOrNull { lower.contains(it) }

        val incoming = has(incomingPhrases)
        val outgoing = has(outgoingPhrases)

        has(refundPhrases)?.let { return Result(MoneyMovementKind.REFUND, "Mentions \"$it\"") }
        val topUp = has(ownTransferPhrases)
        if (topUp != null && incoming == null) return Result(MoneyMovementKind.OWN_TRANSFER, "Looks like a top-up (\"$topUp\")")
        if (incoming != null) {
            // Both directions mentioned: do not guess.
            if (outgoing != null) return Result(null, "Mentions both \"$incoming\" and \"$outgoing\"")
            if (has(salaryPhrases) != null) return Result(MoneyMovementKind.INCOME, "Salary received")
            return Result(MoneyMovementKind.OTHER_IN, "Mentions \"$incoming\"")
        }
        return Result.NONE
    }
}
