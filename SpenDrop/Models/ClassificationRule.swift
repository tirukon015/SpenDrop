import Foundation
import SwiftData

/// A locally learned suggestion for a merchant (e.g. "mcdonald's" → Food), created from the user's own
/// confirmed saves and corrections. Never sent anywhere; no AI service involved.
@Model
public final class ClassificationRule {
    @Attribute(.unique) public var id: UUID
    /// Normalised merchant name (see `TransactionClassifier.merchantKey`). One rule per key.
    public var merchantKey: String
    public var categoryRaw: String?
    /// "expense", "moneyIn", "moneyOut" or "transfer".
    public var suggestedTypeRaw: String?
    /// Account the user last used for this merchant (by id; the account may since have been deleted).
    public var accountId: UUID?
    /// How many consecutive confirmations agreed with the current suggestion.
    public var hitCount: Int
    public var createdAt: Date
    public var updatedAt: Date

