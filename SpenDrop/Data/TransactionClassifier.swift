import Foundation
import SwiftData

/// Local, deterministic classification. Priority:
/// 1. explicit user choice (callers never override it)
/// 2. trusted learned rule (confirmed at least `trustedHitCount` times in a row)
/// 3. existing deterministic rule (parser / CategoryDetector result)
/// 4. generic suggestion from the merchant text
/// 5. unknown (`.other`)
public enum TransactionClassifier {
    public static let trustedHitCount = 2

    public enum Source: String {
        case learned, deterministic, generic, unknown
    }

    private static let ignoredMerchants: Set<String> = ["", "unknown", "unknown merchant", "food / dining"]

    /// "  McDonald’s  " → "mcdonald's". nil for empty/placeholder names.
    public static func merchantKey(_ merchant: String?) -> String? {
        guard let merchant else { return nil }
        let key = merchant
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return ignoredMerchants.contains(key) ? nil : key
    }

    public static func rule(for merchant: String?, in context: ModelContext) -> ClassificationRule? {
        guard let key = merchantKey(merchant) else { return nil }
        var descriptor = FetchDescriptor<ClassificationRule>(predicate: #Predicate { $0.merchantKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The category to pre-select (never used when the user already picked one).
    public static func suggestCategory(merchant: String?, deterministic: ExpenseCategory?, in context: ModelContext) -> (category: ExpenseCategory, source: Source) {
        if let rule = rule(for: merchant, in: context), rule.hitCount >= trustedHitCount, let learned = rule.category {
            return (learned, .learned)
        }
        if let deterministic, deterministic != .other {
            return (deterministic, .deterministic)
        }
        if let merchant, merchantKey(merchant) != nil {
            let generic = CategoryDetector.detect(text: merchant, detectedMerchant: merchant, merchantCategory: nil)
            if generic != .other { return (generic, .generic) }
        }
        return (.other, .unknown)
    }

    /// Records what the user confirmed when saving. Agreement strengthens the rule; a different choice
    /// (a correction) replaces the suggestion and restarts its count.
    @discardableResult
    public static func learn(merchant: String?, category: ExpenseCategory?, type: String = "expense", accountId: UUID? = nil,
                             in context: ModelContext, now: Date = Date()) -> ClassificationRule? {
        guard let key = merchantKey(merchant) else { return nil }
        if let rule = rule(for: merchant, in: context) {
            let sameCategory = rule.categoryRaw == category?.rawValue
            let sameType = rule.suggestedTypeRaw == type
            rule.hitCount = (sameCategory && sameType) ? rule.hitCount + 1 : 1
            rule.categoryRaw = category?.rawValue
            rule.suggestedTypeRaw = type
            if let accountId { rule.accountId = accountId }
            rule.updatedAt = now
            return rule
        }
        let rule = ClassificationRule(merchantKey: key, categoryRaw: category?.rawValue, suggestedTypeRaw: type,
                                      accountId: accountId, createdAt: now, updatedAt: now)
        context.insert(rule)
        return rule
    }
}
