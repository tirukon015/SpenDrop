import Foundation

/// A suggested category with how sure SpenDrop is and why. Below `CategoryDetector.reviewThreshold` the
/// category is only a suggestion and the review screen asks the user to check it.
public struct CategorySuggestion: Equatable {
    public let category: ExpenseCategory
    /// 0…1. 0 means "no evidence" (shown as Other, needs review).
    public let confidence: Double
    public let reason: String

    public var needsReview: Bool { confidence < CategoryDetector.reviewThreshold }

    public static let none = CategorySuggestion(category: .other, confidence: 0, reason: "No category evidence in this receipt")
}

/// Deterministic, explainable category detection. Evidence, strongest first:
/// 1. a known merchant (whole-word match), unless that merchant sells several kinds of things (e.g. plain "Grab");
/// 2. category words in the merchant name ("restaurant", "warung", "pharmacy");
/// 3. category words elsewhere on the receipt (weak: only a suggestion).
/// The funding account or payment provider (Touch 'n Go, Maybank…) and the payment channel (DuitNow QR…) are never
/// category evidence. All matching is on whole words, so "smart" is not "mart" and "business" is not "bus".
/// Learned user choices are applied on top of this by `TransactionClassifier`.
public struct CategoryDetector {
    public static let reviewThreshold = 0.7

    /// Category words, matched as whole words or phrases. Order matters only for ties.
    static let keywords: [(ExpenseCategory, [String])] = [
        (.food, ["restaurant", "restoran", "cafe", "café", "coffee", "kopi", "bistro", "bakery", "kopitiam", "dining", "lunch", "dinner",
                 "breakfast", "burger", "pizza", "nasi", "mee", "roti", "ayam", "food", "foods", "makan", "kedai makan", "warung", "selera",
                 "mamak", "kitchen", "noodle", "noodles", "bakeri", "dim sum", "satay", "sushi", "tealive", "boba", "bubble tea", "catering"]),
        (.groceries, ["supermarket", "hypermarket", "grocery", "grocer", "groceries", "pasar", "pasar malam", "pasar raya", "mart", "minimart",
                      "mini market", "supermart", "fresh market", "fruit", "fruits", "vegetable", "vegetables", "runcit", "kedai runcit"]),
        (.transport, ["petrol", "fuel", "diesel", "ron95", "ron97", "parking", "toll", "rfid", "lrt", "mrt", "monorail", "ktm", "rapid kl",
                      "bus", "taxi", "e-hailing", "grabcar", "airasia", "flight", "airline", "airport"]),
        (.bills, ["electricity", "tenaga", "water", "air selangor", "utility", "utilities", "bill payment", "telekom", "postpaid",
                  "broadband", "internet", "unifi", "reload", "topup", "top up"]),
        (.health, ["pharmacy", "farmasi", "clinic", "klinik", "hospital", "doctor", "dental", "gigi", "optometry", "optical", "medicine", "ubat"]),
        (.entertainment, ["cinema", "cinemas", "movie", "theatre", "wayang", "bowling", "karaoke", "steam", "concert"]),
        (.education, ["tuition", "university", "college", "school", "sekolah", "exam", "bookstore", "stationery", "popular bookstore", "mph"]),
        (.travel, ["hotel", "resort", "homestay", "airbnb", "hostel", "tour", "travel", "vacation"]),
        (.subscription, ["subscription", "recurring", "monthly fee", "annual fee", "membership"]),
        (.personal, ["salon", "barber", "haircut", "spa", "massage", "facial", "nail", "nails"]),
        (.shopping, ["mall", "fashion", "boutique", "apparel", "shoes", "clothing", "accessories", "hardware", "gadget", "electronics", "store", "shop", "retail"])
    ]

    /// Kept for existing callers: the suggested category only.
    public static func detect(text: String, detectedMerchant: String?, merchantCategory: ExpenseCategory?) -> ExpenseCategory {
        if let merchantCategory { return merchantCategory }
        return suggest(merchant: detectedMerchant, receiptText: text).category
    }

    /// The best category for a merchant and receipt, with confidence and reason.
    public static func suggest(merchant: String?, receiptText: String) -> CategorySuggestion {
        // 1. Known merchant
        if let known = MerchantDetector.knownMerchant(for: merchant) {
            if known.ambiguous {
                // Only receipt wording can say which kind (e.g. "food delivery"); otherwise a weak suggestion.
                if let context = match(in: receiptText, excluding: merchant), context.0 != known.defaultCategory {
                    return CategorySuggestion(category: context.0, confidence: 0.6,
                                              reason: "\(known.name) sells several things; the receipt mentions '\(context.1)'")
                }
                return CategorySuggestion(category: known.defaultCategory, confidence: 0.5,
                                          reason: "\(known.name) can be rides, food or deliveries; please check")
            }
            return CategorySuggestion(category: known.defaultCategory, confidence: 0.95, reason: "Known merchant: \(known.name)")
        }
        // 2. Words in the merchant name
        if let merchant, let hit = match(in: merchant) {
            return CategorySuggestion(category: hit.0, confidence: hit.2 ? 0.6 : 0.8,
                                      reason: hit.2 ? "Merchant name suggests more than one category ('\(hit.1)')" : "Merchant name contains '\(hit.1)'")
        }
        // 3. Words elsewhere on the receipt (weak)
        if let hit = match(in: receiptText, excluding: merchant) {
            return CategorySuggestion(category: hit.0, confidence: 0.55, reason: "Receipt mentions '\(hit.1)'")
        }
        return .none
    }

    /// First category whose words appear as whole words. The Bool is true when words of more than one category
    /// appear (ambiguous).
    static func match(in text: String, excluding merchant: String? = nil) -> (ExpenseCategory, String, Bool)? {
        var haystack = " " + MerchantDetector.normalizedWords(text) + " "
        if let merchant, !merchant.isEmpty {
            haystack = haystack.replacingOccurrences(of: " " + MerchantDetector.normalizedWords(merchant) + " ", with: " ")
        }
        var hits: [(ExpenseCategory, String)] = []
        for (category, words) in keywords {
            if let word = words.first(where: { haystack.contains(" " + MerchantDetector.normalizedWords($0) + " ") }) {
                hits.append((category, word))
            }
        }
        guard let first = hits.first else { return nil }
        return (first.0, first.1, hits.count > 1)
    }
}
