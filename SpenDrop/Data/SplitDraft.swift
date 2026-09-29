import Foundation
import SwiftData

/// Editable state of an expense split (participants, method, payer). Pure logic on top of `SplitCalculator`;
/// the SwiftUI editor only binds to it. A split is stored as `ExpenseShare` rows on the one `Expense`.
public struct SplitDraft: Equatable {
    public struct Participant: Identifiable, Equatable {
        public var id: UUID
        public var person: PayBookProfile?
        public var isMe: Bool
        public var name: String
        /// Parts method: 1…99.
        public var parts: Int
        /// Amounts method: what the user typed (kept as text so nothing is silently reformatted).
        public var amountText: String

        public init(id: UUID = UUID(), person: PayBookProfile? = nil, isMe: Bool = false, name: String, parts: Int = 1, amountText: String = "") {
            self.id = id
            self.person = person
            self.isMe = isMe
            self.name = name
            self.parts = parts
            self.amountText = amountText
        }

        public static func == (lhs: Participant, rhs: Participant) -> Bool {
            lhs.id == rhs.id && lhs.person?.id == rhs.person?.id && lhs.isMe == rhs.isMe && lhs.name == rhs.name &&
            lhs.parts == rhs.parts && lhs.amountText == rhs.amountText
        }
    }

    public var method: SplitMethod = .equal
    /// Me is always first and can never be removed.
    public private(set) var participants: [Participant] = [Participant(isMe: true, name: "Me")]
    /// nil = I paid.
    public var payer: PayBookProfile?

    public init() {}

    public static func == (lhs: SplitDraft, rhs: SplitDraft) -> Bool {
        lhs.method == rhs.method && lhs.participants == rhs.participants && lhs.payer?.id == rhs.payer?.id
    }

