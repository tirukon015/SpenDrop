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

