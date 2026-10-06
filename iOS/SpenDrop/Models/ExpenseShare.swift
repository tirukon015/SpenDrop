import Foundation
import SwiftData

/// How a shared expense was divided. Stored on `Expense.splitMethodRaw` (nil = not shared).
public enum SplitMethod: String, CaseIterable, Codable, Identifiable {
    case equal = "equal"
    case parts = "parts"
    case amounts = "amounts"

    public var id: String { rawValue }
}

/// One participant's share of a shared Expense, in integer minor units (sen).
/// A split always contains exactly one `isMe` share, and all shares add up exactly to the expense amount.
@Model
public final class ExpenseShare {
    @Attribute(.unique) public var id: UUID
    public var expense: Expense?
    /// nil for "Me", or when the person was later deleted (the name snapshot keeps history readable).
    public var person: PayBookProfile?
    public var isMe: Bool
    public var nameSnapshot: String
    public var amountMinor: Int
    /// Input for the Parts method.
    public var parts: Int?
    /// Input for the Amounts method.
    public var enteredMinor: Int?
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        expense: Expense? = nil,
        person: PayBookProfile? = nil,
        isMe: Bool = false,
        nameSnapshot: String,
        amountMinor: Int,
        parts: Int? = nil,
        enteredMinor: Int? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.expense = expense
        self.person = person
        self.isMe = isMe
        self.nameSnapshot = nameSnapshot
        self.amountMinor = amountMinor
        self.parts = parts
        self.enteredMinor = enteredMinor
        self.sortIndex = sortIndex
    }
}
