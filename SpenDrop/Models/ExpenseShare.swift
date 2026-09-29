import Foundation
import SwiftData

/// How a shared expense was divided. Stored on `Expense.splitMethodRaw` (nil = not shared).
public enum SplitMethod: String, CaseIterable, Codable, Identifiable {
    case equal = "equal"
    case parts = "parts"
    case amounts = "amounts"

    public var id: String { rawValue }
}

