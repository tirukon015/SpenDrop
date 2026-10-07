package com.spendrop.core.classify

import com.spendrop.core.Ids
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.parser.CategoryDetector
import com.spendrop.core.parser.CategorySuggestion
import com.spendrop.core.parser.MerchantDetector

/**
 * Local, deterministic category classification (iOS `TransactionClassifier`). Priority:
 * 1. explicit user choice (callers never override it)
 * 2. trusted learned rule (confirmed at least [TRUSTED_HIT_COUNT] times in a row)
 * 3. existing deterministic rule (parser / CategoryDetector result)
 * 4. generic suggestion from the merchant text
 * 5. unknown (Other)
 *
 * Pure: rules are passed in (deleted ones are ignored) and [learn] RETURNS the new or updated rule for the caller to
 * store; nothing is mutated.
 */
object TransactionClassifier {
    const val TRUSTED_HIT_COUNT = 2

    enum class Source { LEARNED, DETERMINISTIC, GENERIC, UNKNOWN }

    data class Suggestion(val suggestion: CategorySuggestion, val source: Source)
    data class Choice(val category: ExpenseCategory, val source: Source)

    private val ignoredMerchants = setOf("", "unknown", "unknown merchant", "food / dining")

    /** "  McDonald’s  " → "mcdonald's". null for empty / placeholder names. */
    fun merchantKey(merchant: String?): String? {
        if (merchant == null) return null
        val key = merchant.replace('’', '\'').lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        return if (key in ignoredMerchants) null else key
    }

    /**
     * The key a rule is stored under: the known merchant's name when recognised (so "MCD BANGSAR" and "McDonald's"
     * share one rule), otherwise the merchant text itself.
     */
    fun ruleKey(merchant: String?): String? {
        MerchantDetector.knownMerchant(merchant)?.let { return merchantKey(it.name) }
        return merchantKey(merchant)
    }

    /** Looks up by the recognised merchant first, then by the exact text (rules saved before recognition existed). */
    fun rule(merchant: String?, rules: List<ClassificationRule>): ClassificationRule? {
        val live = rules.filter { it.deletedAt == null }
        for (key in listOfNotNull(ruleKey(merchant), merchantKey(merchant))) {
            live.firstOrNull { it.merchantKey == key }?.let { return it }
        }
        return null
    }

    private val ClassificationRule.category: ExpenseCategory? get() = ExpenseCategory.fromRawOrNull(categoryRaw)

    /**
     * The category to pre-select, with confidence and reason (never used when the user already picked one):
     * - the user's choice for this merchant, confirmed twice → used;
     * - the user's choice once → used when the receipt has no strong evidence of its own (or agrees);
     * - otherwise the parser's evidence-based suggestion;
     * - otherwise Other, marked for review.
     */
    fun suggestion(merchant: String?, parsed: CategorySuggestion?, rules: List<ClassificationRule>): Suggestion {
        val evidence = parsed ?: CategoryDetector.suggest(merchant, merchant ?: "")
        val rule = rule(merchant, rules)
        val learned = rule?.category
        if (rule != null && learned != null) {
            if (rule.hitCount >= TRUSTED_HIT_COUNT) {
                return Suggestion(CategorySuggestion(learned, 0.97, "You chose ${learned.raw} for this merchant before"), Source.LEARNED)
            }
            if (evidence.needsReview || evidence.category == learned) {
                return Suggestion(CategorySuggestion(learned, 0.85, "You chose ${learned.raw} for this merchant last time"), Source.LEARNED)
            }
        }
        if (evidence.category != ExpenseCategory.OTHER) {
            return Suggestion(evidence, if (parsed != null) Source.DETERMINISTIC else Source.GENERIC)
        }
        return Suggestion(CategorySuggestion.NONE, Source.UNKNOWN)
    }

    /** The category to pre-select (never used when the user already picked one). */
    fun suggestCategory(merchant: String?, deterministic: ExpenseCategory?, rules: List<ClassificationRule>): Choice {
        val rule = rule(merchant, rules)
        val learned = rule?.category
        if (rule != null && learned != null && rule.hitCount >= TRUSTED_HIT_COUNT) return Choice(learned, Source.LEARNED)
        // A single earlier choice counts when the merchant itself gives no strong evidence.
        if (learned != null && CategoryDetector.suggest(merchant, merchant ?: "").needsReview &&
            (deterministic == null || deterministic == ExpenseCategory.OTHER)
        ) return Choice(learned, Source.LEARNED)
        if (deterministic != null && deterministic != ExpenseCategory.OTHER) return Choice(deterministic, Source.DETERMINISTIC)
        if (merchant != null && merchantKey(merchant) != null) {
            val generic = CategoryDetector.detect(merchant, merchant, null)
            if (generic != ExpenseCategory.OTHER) return Choice(generic, Source.GENERIC)
        }
        return Choice(ExpenseCategory.OTHER, Source.UNKNOWN)
    }

    /**
     * What the user confirmed when saving. Agreement (same category AND type) strengthens the existing rule; a
     * different choice (a correction) replaces it and restarts its count at 1. Returns the rule to upsert (same id
     * when updated), or null when the merchant can't be keyed.
     */
    fun learn(
        merchant: String?,
        category: ExpenseCategory?,
        rules: List<ClassificationRule>,
        type: String = "expense",
        accountId: String? = null,
        now: Long = System.currentTimeMillis(),
        newId: () -> String = Ids::new,
    ): ClassificationRule? {
        val key = ruleKey(merchant) ?: return null
        rule(merchant, rules)?.let { existing ->
            val same = existing.categoryRaw == category?.raw && existing.suggestedTypeRaw == type
            return existing.copy(
                hitCount = if (same) existing.hitCount + 1 else 1,
                categoryRaw = category?.raw,
                suggestedTypeRaw = type,
                accountId = accountId ?: existing.accountId,
                updatedAt = now,
            )
        }
        return ClassificationRule(
            id = newId(), merchantKey = key, categoryRaw = category?.raw, suggestedTypeRaw = type, accountId = accountId,
            hitCount = 1, createdAt = now, updatedAt = now,
        )
    }
}

/** Replaces the rule with the same id, or appends it (helper for callers keeping rules in memory). */
@JvmName("upsertClassificationRule")
fun List<ClassificationRule>.upsert(rule: ClassificationRule?): List<ClassificationRule> =
    if (rule == null) this else if (any { it.id == rule.id }) map { if (it.id == rule.id) rule else it } else this + rule
