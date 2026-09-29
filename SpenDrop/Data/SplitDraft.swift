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

    /// Loads the split stored on an expense (nil when the expense is not shared).
    public init?(expense: Expense) {
        guard !expense.shares.isEmpty else { return nil }
        method = expense.splitMethod ?? .amounts
        payer = expense.paidByMe ? nil : expense.payer
        let ordered = expense.shares.sorted { a, b in
            if a.isMe != b.isMe { return a.isMe }
            return a.sortIndex < b.sortIndex
        }
        participants = ordered.map { share in
            Participant(
                id: share.id,
                person: share.person,
                isMe: share.isMe,
                name: share.isMe ? "Me" : (share.person?.name ?? share.nameSnapshot),
                parts: share.parts ?? 1,
                amountText: Self.text(fromMinor: share.enteredMinor ?? share.amountMinor)
            )
        }
        if !participants.contains(where: \.isMe) {
            participants.insert(Participant(isMe: true, name: "Me"), at: 0)
        }
    }

    // MARK: Editing

    public var others: [Participant] { participants.filter { !$0.isMe } }

    public func contains(_ person: PayBookProfile) -> Bool {
        participants.contains { $0.person?.id == person.id }
    }

    /// Adds a person once. Returns false if they were already in the split.
    @discardableResult
    public mutating func add(_ person: PayBookProfile) -> Bool {
        guard !contains(person) else { return false }
        participants.append(Participant(person: person, name: person.name))
        return true
    }

