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

