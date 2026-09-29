import Foundation
import SwiftData

public enum MoneyDirection: String, Codable {
    case moneyIn = "in"
    case moneyOut = "out"
    /// Between the user's own accounts. Never counted as spending, money in or money out.
    case `internal` = "internal"
}

