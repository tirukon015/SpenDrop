import Foundation

/// The single boundary between the existing `Double` amounts (`Expense.amount`) and integer minor units (sen).
/// All new financial calculations work in `Int` minor units; convert once here, never with ad-hoc math.
public enum Money {
    public static let minorUnitsPerMajor = 100

    /// RM7.50 -> 750. Rounds to the nearest sen (half away from zero), which absorbs binary floating-point
    /// noise such as 100.99 being stored as 100.98999….
    public static func minorUnits(from amount: Double) -> Int {
        Int((amount * Double(minorUnitsPerMajor)).rounded(.toNearestOrAwayFromZero))
    }

    /// Exact conversion for user-typed text; "7.50" -> 750, "RM 1,234.5" -> 123450. Returns nil when not a number.
    public static func minorUnits(parsing text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: "RM", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "MYR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var scaled = decimal * Decimal(minorUnitsPerMajor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// 750 -> 7.5, for display only.
    public static func majorAmount(fromMinor minor: Int) -> Double {
        Double(minor) / Double(minorUnitsPerMajor)
    }
}
