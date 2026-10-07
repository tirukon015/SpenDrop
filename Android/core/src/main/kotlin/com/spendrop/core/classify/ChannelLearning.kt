package com.spendrop.core.classify

import com.spendrop.core.Ids
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.parser.ChannelSuggestion

/**
 * Learned payment channel per merchant AND funding account (never a global "Touch 'n Go = DuitNow QR" rule), applied
 * only when a receipt doesn't state its channel, and only after the same choice twice (iOS `ChannelLearning`).
 * Pure: rules are passed in; [learn] returns the rule to store.
 */
object ChannelLearning {
    const val TRUSTED_HIT_COUNT = 2

    /** Funding account key: trimmed, lower case; "", "unknown" and "other" all mean "no account" (""). */
    fun fundingKey(funding: String?): String {
        val value = (funding ?: "").trim { it == ' ' || it == '\t' || Character.isSpaceChar(it) }.lowercase()
        return if (value in setOf("", "unknown", "other")) "" else value
    }

    fun rule(merchant: String?, funding: String?, rules: List<ChannelRule>): ChannelRule? {
        val merchantKey = TransactionClassifier.ruleKey(merchant) ?: return null
        val key = fundingKey(funding)
        return rules.firstOrNull { it.deletedAt == null && it.merchantKey == merchantKey && it.fundingKey == key }
    }

    /** A channel to pre-select when the receipt gave none (null otherwise). */
    fun suggestion(merchant: String?, funding: String?, detected: PaymentChannel, rules: List<ChannelRule>): ChannelSuggestion? {
        if (detected != PaymentChannel.UNKNOWN) return null
        val rule = rule(merchant, funding, rules) ?: return null
        val channel = PaymentChannel.fromRawOrNull(rule.channelRaw)
        if (rule.hitCount < TRUSTED_HIT_COUNT || channel == null || channel == PaymentChannel.UNKNOWN) return null
        val from = if (fundingKey(funding).isEmpty()) "" else " from ${funding ?: ""}"
        return ChannelSuggestion(channel, 0.85, "You chose ${channel.displayName} for this merchant$from before")
    }

    /**
     * Records the channel the user saved (Unknown is never learned). The same channel strengthens the rule; a
     * different one replaces it and restarts the count at 1. Returns the rule to upsert, or null.
     */
    fun learn(
        merchant: String?,
        funding: String?,
        channel: PaymentChannel,
        rules: List<ChannelRule>,
        now: Long = System.currentTimeMillis(),
        newId: () -> String = Ids::new,
    ): ChannelRule? {
        if (channel == PaymentChannel.UNKNOWN) return null
        val merchantKey = TransactionClassifier.ruleKey(merchant) ?: return null
        rule(merchant, funding, rules)?.let { existing ->
            return existing.copy(
                hitCount = if (existing.channelRaw == channel.raw) existing.hitCount + 1 else 1,
                channelRaw = channel.raw,
                updatedAt = now,
            )
        }
        return ChannelRule(id = newId(), merchantKey = merchantKey, fundingKey = fundingKey(funding), channelRaw = channel.raw,
            hitCount = 1, createdAt = now, updatedAt = now)
    }
}

/** Replaces the rule with the same id, or appends it. */
@JvmName("upsertChannelRule")
fun List<ChannelRule>.upsert(rule: ChannelRule?): List<ChannelRule> =
    if (rule == null) this else if (any { it.id == rule.id }) map { if (it.id == rule.id) rule else it } else this + rule
