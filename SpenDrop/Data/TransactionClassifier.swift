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

