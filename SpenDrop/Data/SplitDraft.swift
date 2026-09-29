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

    /// Removes a participant. Me cannot be removed. Removing the payer makes Me the payer again only if
    /// the payer was a participant — a payer who is not a participant is allowed and kept.
    public mutating func remove(id: UUID) {
        guard let index = participants.firstIndex(where: { $0.id == id }), !participants[index].isMe else { return }
        participants.remove(at: index)
    }

    public mutating func setParts(_ parts: Int, for id: UUID) {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[index].parts = min(max(parts, 1), SplitCalculator.maxParts)
    }

    public mutating func setAmountText(_ text: String, for id: UUID) {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[index].amountText = text
    }

    // MARK: Calculation

    public var iPaid: Bool { payer == nil }

    public func calculate(totalMinor: Int) -> Result<[Int], SplitCalculator.SplitError> {
        let inputs = participants.map { p in
            SplitCalculator.Participant(isMe: p.isMe, parts: p.parts, enteredMinor: Money.minorUnits(parsing: p.amountText))
        }
        return SplitCalculator.calculate(totalMinor: totalMinor, method: method, participants: inputs, iPaid: iPaid)
    }

    public func shares(totalMinor: Int) -> [Int]? {
        try? calculate(totalMinor: totalMinor).get()
    }

    public func myShareMinor(totalMinor: Int) -> Int? {
        guard let shares = shares(totalMinor: totalMinor), let meIndex = participants.firstIndex(where: \.isMe) else { return nil }
        return shares[meIndex]
    }

    /// A readable problem, or nil when the split is valid for this total.
    public func problem(totalMinor: Int) -> String? {
        switch calculate(totalMinor: totalMinor) {
        case .success:
            return nil
        case .failure(let error):
            switch error {
            case .nonPositiveTotal: return "Enter the expense amount first."
            case .tooFewParticipants: return "Add at least one other person."
            case .missingMe, .moreThanOneMe: return "A split must include you exactly once."
            case .invalidParts: return "Parts must be whole numbers from 1 to \(SplitCalculator.maxParts)."
            case .missingAmount(let index): return "Enter an amount for \(participants[index].name)."
            case .negativeAmount(let index): return "\(participants[index].name)'s amount can't be negative."
            case .amountsDoNotMatchTotal(let difference):
                let formatted = CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: abs(difference)))
                return difference > 0 ? "Amounts are \(formatted) more than the total." : "\(formatted) left to assign."
            }
        }
    }

    public func isValid(totalMinor: Int) -> Bool { problem(totalMinor: totalMinor) == nil }

    // MARK: Saving

    /// Replaces the expense's shares with this split. Returns false (and changes nothing) when invalid.
    @discardableResult
    public func apply(to expense: Expense, in context: ModelContext) -> Bool {
        guard let amounts = shares(totalMinor: expense.amountMinor) else { return false }
        for old in expense.shares {
            context.delete(old)
        }
        expense.shares = []
        for (index, participant) in participants.enumerated() {
            let share = ExpenseShare(
                person: participant.isMe ? nil : participant.person,
                isMe: participant.isMe,
                nameSnapshot: participant.isMe ? "Me" : (participant.person?.name ?? participant.name),
                amountMinor: amounts[index],
                parts: method == .parts ? participant.parts : nil,
                enteredMinor: method == .amounts ? Money.minorUnits(parsing: participant.amountText) : nil,
                sortIndex: index
            )
            context.insert(share)
            share.expense = expense
        }
        expense.splitMethod = method
        expense.setPayer(payer)
        expense.updatedAt = Date()
        return true
    }

