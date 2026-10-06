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

    /// The key a rule is stored under: the known merchant's name when the merchant is recognised (so "MCD BANGSAR"
    /// and "McDonald's" share one rule), otherwise the merchant text itself.
    public static func ruleKey(_ merchant: String?) -> String? {
        if let known = MerchantDetector.knownMerchant(for: merchant) { return merchantKey(known.name) }
        return merchantKey(merchant)
    }

    /// Looks up by the recognised merchant first, then by the exact text (rules saved before recognition existed).
    public static func rule(for merchant: String?, in context: ModelContext) -> ClassificationRule? {
        for key in [ruleKey(merchant), merchantKey(merchant)].compactMap({ $0 }) {
            var descriptor = FetchDescriptor<ClassificationRule>(predicate: #Predicate { $0.merchantKey == key })
            descriptor.fetchLimit = 1
            if let found = try? context.fetch(descriptor).first { return found }
        }
        return nil
    }

    /// The category to pre-select, with confidence and reason (never used when the user already picked one):
    /// - the user's choice for this merchant, confirmed twice → used;
    /// - the user's choice once → used when the receipt has no strong evidence of its own (an unclear merchant);
    /// - otherwise the parser's evidence-based suggestion (merchant first, receipt wording weakly);
    /// - otherwise Other, marked for review.
    public static func suggestion(merchant: String?, parsed: CategorySuggestion?, in context: ModelContext) -> (CategorySuggestion, Source) {
        let evidence = parsed ?? CategoryDetector.suggest(merchant: merchant, receiptText: merchant ?? "")
        if let rule = rule(for: merchant, in: context), let learned = rule.category {
            if rule.hitCount >= trustedHitCount {
                return (CategorySuggestion(category: learned, confidence: 0.97, reason: "You chose \(learned.rawValue) for this merchant before"), .learned)
            }
            if evidence.needsReview || evidence.category == learned {
                return (CategorySuggestion(category: learned, confidence: 0.85, reason: "You chose \(learned.rawValue) for this merchant last time"), .learned)
            }
        }
        if evidence.category != .other {
            return (evidence, parsed != nil ? .deterministic : .generic)
        }
        return (.none, .unknown)
    }

    /// The category to pre-select (never used when the user already picked one).
    public static func suggestCategory(merchant: String?, deterministic: ExpenseCategory?, in context: ModelContext) -> (category: ExpenseCategory, source: Source) {
        if let rule = rule(for: merchant, in: context), rule.hitCount >= trustedHitCount, let learned = rule.category {
            return (learned, .learned)
        }
        // A single earlier choice counts when the merchant itself gives no strong evidence.
        if let rule = rule(for: merchant, in: context), let learned = rule.category,
           CategoryDetector.suggest(merchant: merchant, receiptText: merchant ?? "").needsReview,
           deterministic == nil || deterministic == .other {
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
        guard let key = ruleKey(merchant) else { return nil }
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


/// Learned payment channel per merchant AND funding account (never a global "Touch 'n Go = DuitNow QR" rule).
/// Applied only when a receipt doesn't state its channel, and only after the same choice twice.
public enum ChannelLearning {
    public static let trustedHitCount = 2

    static func key(_ funding: String?) -> String {
        let value = (funding ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return ["", "unknown", "other"].contains(value) ? "" : value
    }

    public static func rule(merchant: String?, funding: String?, in context: ModelContext) -> ChannelRule? {
        guard let merchantKey = TransactionClassifier.ruleKey(merchant) else { return nil }
        let fundingKey = key(funding)
        var descriptor = FetchDescriptor<ChannelRule>(predicate: #Predicate { $0.merchantKey == merchantKey && $0.fundingKey == fundingKey })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A channel to pre-select when the receipt gave none (nil otherwise).
    public static func suggestion(merchant: String?, funding: String?, detected: PaymentChannel, in context: ModelContext) -> ChannelSuggestion? {
        guard detected == .unknown, let rule = rule(merchant: merchant, funding: funding, in: context),
              rule.hitCount >= trustedHitCount, let channel = rule.channel, channel != .unknown else { return nil }
        let from = key(funding).isEmpty ? "" : " from \(funding ?? "")"
        return ChannelSuggestion(channel: channel, confidence: 0.85, reason: "You chose \(channel.displayName) for this merchant\(from) before")
    }

    /// Records the channel the user saved (Unknown is not learned). Same channel strengthens; a different one restarts.
    @discardableResult
    public static func learn(merchant: String?, funding: String?, channel: PaymentChannel, in context: ModelContext, now: Date = Date()) -> ChannelRule? {
        guard channel != .unknown, let merchantKey = TransactionClassifier.ruleKey(merchant) else { return nil }
        if let rule = rule(merchant: merchant, funding: funding, in: context) {
            rule.hitCount = rule.channelRaw == channel.rawValue ? rule.hitCount + 1 : 1
            rule.channelRaw = channel.rawValue
            rule.updatedAt = now
            return rule
        }
        let rule = ChannelRule(merchantKey: merchantKey, fundingKey: key(funding), channelRaw: channel.rawValue, createdAt: now, updatedAt: now)
        context.insert(rule)
        return rule
    }
}
