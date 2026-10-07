package com.spendrop.core.parser

import com.spendrop.core.model.ExpenseCategory

/**
 * A suggested category with how sure SpenDrop is and why. Below [CategoryDetector.REVIEW_THRESHOLD] the category is
 * only a suggestion and the review screen asks the user to check it.
 */
data class CategorySuggestion(
    val category: ExpenseCategory,
    /** 0…1. 0 means "no evidence" (shown as Other, needs review). */
    val confidence: Double,
    val reason: String,
) {
    val needsReview: Boolean get() = confidence < CategoryDetector.REVIEW_THRESHOLD

    companion object {
        val NONE = CategorySuggestion(ExpenseCategory.OTHER, 0.0, "No category evidence in this receipt")
    }
}

/**
 * Deterministic, explainable category detection. Evidence, strongest first:
 * 1. a known merchant (whole-word match), unless that merchant sells several kinds of things (e.g. plain "Grab");
 * 2. category words in the merchant name ("restaurant", "warung", "pharmacy");
 * 3. category words elsewhere on the receipt (weak: only a suggestion).
 * The funding account / payment provider and the payment channel are never category evidence. All matching is on
 * whole words, so "smart" is not "mart" and "business" is not "bus". Learned choices are applied on top by
 * `TransactionClassifier`.
 */
object CategoryDetector {
    const val REVIEW_THRESHOLD = 0.7

    /** Category words, matched as whole words or phrases. Order matters only for ties. */
    val keywords: List<Pair<ExpenseCategory, List<String>>> = listOf(
        ExpenseCategory.FOOD to listOf(
            "restaurant", "restoran", "cafe", "café", "coffee", "kopi", "bistro", "bakery", "kopitiam", "dining", "lunch", "dinner",
            "breakfast", "burger", "pizza", "nasi", "mee", "roti", "ayam", "food", "foods", "makan", "kedai makan", "warung", "selera",
            "mamak", "kitchen", "noodle", "noodles", "bakeri", "dim sum", "satay", "sushi", "tealive", "boba", "bubble tea", "catering",
        ),
        ExpenseCategory.GROCERIES to listOf(
            "supermarket", "hypermarket", "grocery", "grocer", "groceries", "pasar", "pasar malam", "pasar raya", "mart", "minimart",
            "mini market", "supermart", "fresh market", "fruit", "fruits", "vegetable", "vegetables", "runcit", "kedai runcit",
        ),
        ExpenseCategory.TRANSPORT to listOf(
            "petrol", "fuel", "diesel", "ron95", "ron97", "parking", "toll", "rfid", "lrt", "mrt", "monorail", "ktm", "rapid kl",
            "bus", "taxi", "e-hailing", "grabcar", "airasia", "flight", "airline", "airport",
        ),
        ExpenseCategory.BILLS to listOf(
            "electricity", "tenaga", "water", "air selangor", "utility", "utilities", "bill payment", "telekom", "postpaid",
            "broadband", "internet", "unifi", "reload", "topup", "top up",
        ),
        ExpenseCategory.HEALTH to listOf("pharmacy", "farmasi", "clinic", "klinik", "hospital", "doctor", "dental", "gigi", "optometry", "optical", "medicine", "ubat"),
        ExpenseCategory.ENTERTAINMENT to listOf("cinema", "cinemas", "movie", "theatre", "wayang", "bowling", "karaoke", "steam", "concert"),
        ExpenseCategory.EDUCATION to listOf("tuition", "university", "college", "school", "sekolah", "exam", "bookstore", "stationery", "popular bookstore", "mph"),
        ExpenseCategory.TRAVEL to listOf("hotel", "resort", "homestay", "airbnb", "hostel", "tour", "travel", "vacation"),
        ExpenseCategory.SUBSCRIPTION to listOf("subscription", "recurring", "monthly fee", "annual fee", "membership"),
        ExpenseCategory.PERSONAL to listOf("salon", "barber", "haircut", "spa", "massage", "facial", "nail", "nails"),
        ExpenseCategory.SHOPPING to listOf(
            "mall", "fashion", "boutique", "apparel", "shoes", "clothing", "accessories", "hardware", "gadget", "electronics", "store", "shop", "retail",
        ),
    )

    /** Kept for existing callers: the suggested category only. */
    fun detect(text: String, detectedMerchant: String?, merchantCategory: ExpenseCategory?): ExpenseCategory =
        merchantCategory ?: suggest(detectedMerchant, text).category

    /** The best category for a merchant and receipt, with confidence and reason. */
    fun suggest(merchant: String?, receiptText: String): CategorySuggestion {
        // 1. Known merchant
        MerchantDetector.knownMerchant(merchant)?.let { known ->
            if (known.ambiguous) {
                // Only receipt wording can say which kind (e.g. "food delivery"); otherwise a weak suggestion.
                val context = match(receiptText, excluding = merchant)
                if (context != null && context.category != known.defaultCategory) {
                    return CategorySuggestion(context.category, 0.6, "${known.name} sells several things; the receipt mentions '${context.word}'")
                }
                return CategorySuggestion(known.defaultCategory, 0.5, "${known.name} can be rides, food or deliveries; please check")
            }
            return CategorySuggestion(known.defaultCategory, 0.95, "Known merchant: ${known.name}")
        }
        // 2. Words in the merchant name
        if (merchant != null) {
            match(merchant)?.let { hit ->
                return CategorySuggestion(
                    hit.category, if (hit.ambiguous) 0.6 else 0.8,
                    if (hit.ambiguous) "Merchant name suggests more than one category ('${hit.word}')" else "Merchant name contains '${hit.word}'",
                )
            }
        }
        // 3. Words elsewhere on the receipt (weak)
        match(receiptText, excluding = merchant)?.let { hit ->
            return CategorySuggestion(hit.category, 0.55, "Receipt mentions '${hit.word}'")
        }
        return CategorySuggestion.NONE
    }

    data class Match(val category: ExpenseCategory, val word: String, val ambiguous: Boolean)

    /** First category whose words appear as whole words. [Match.ambiguous] when words of several categories appear. */
    fun match(text: String, excluding: String? = null): Match? {
        var haystack = " " + MerchantDetector.normalizedWords(text) + " "
        if (!excluding.isNullOrEmpty()) {
            haystack = haystack.replace(" " + MerchantDetector.normalizedWords(excluding) + " ", " ")
        }
        val hits = keywords.mapNotNull { (category, words) ->
            words.firstOrNull { haystack.contains(" " + MerchantDetector.normalizedWords(it) + " ") }?.let { category to it }
        }
        val first = hits.firstOrNull() ?: return null
        return Match(first.first, first.second, hits.size > 1)
    }
}
