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
        /// Amounts method: what the user typed (kept as text so nothing is silently reformatted). For someone
        /// Auto Calculate fills in, this only mirrors the calculated value; the calculation never reads it.
        public var amountText: String
        /// Amounts + Auto Calculate: a base amount added to this person's equal part of the remainder
        /// (Vijay fixed RM50 of RM200 shared by 3 → 50 + 150/3 = RM100). nil = none. Editor-only, opt-in.
        public var fixedMinor: Int?

        public init(id: UUID = UUID(), person: PayBookProfile? = nil, isMe: Bool = false, name: String, parts: Int = 1, amountText: String = "",
                    fixedMinor: Int? = nil) {
            self.id = id
            self.person = person
            self.isMe = isMe
            self.name = name
            self.parts = parts
            self.amountText = amountText
            self.fixedMinor = fixedMinor
        }

        public static func == (lhs: Participant, rhs: Participant) -> Bool {
            lhs.id == rhs.id && lhs.person?.id == rhs.person?.id && lhs.isMe == rhs.isMe && lhs.name == rhs.name &&
            lhs.parts == rhs.parts && lhs.amountText == rhs.amountText && lhs.fixedMinor == rhs.fixedMinor
        }
    }

    /// Shared: everyone in the list (including me) shares the cost.
    /// Paid for someone: one side paid entirely for the other — I paid for the people listed (my share is 0),
    /// or the payer paid entirely for me (my share is the whole total). Nobody types a 0 share.
    public enum Purpose: String, Equatable {
        case shared, paidFor
    }

    /// Hybrid Split: one group fixed amount — a TOTAL divided equally between `memberIDs`.
    public struct HybridGroup: Identifiable, Equatable {
        public var id = UUID()
        /// "Amount (total for the group)" exactly as typed.
        public var amountText = ""
        public var memberIDs: Set<UUID> = []

        public init(id: UUID = UUID(), amountText: String = "", memberIDs: Set<UUID> = []) {
            self.id = id
            self.amountText = amountText
            self.memberIDs = memberIDs
        }

        /// No amount and no members: the empty starter group, ignored.
        public var isBlank: Bool { amountText.trimmingCharacters(in: .whitespaces).isEmpty && memberIDs.isEmpty }
    }

    /// Hybrid Split: one individual fixed amount — for one person only, never divided.
    public struct HybridIndividual: Identifiable, Equatable {
        public var id = UUID()
        public var participantID: UUID?
        public var amountText = ""

        public init(id: UUID = UUID(), participantID: UUID? = nil, amountText: String = "") {
            self.id = id
            self.participantID = participantID
            self.amountText = amountText
        }

        /// No person and no amount: ignored.
        public var isBlank: Bool { participantID == nil && amountText.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var method: SplitMethod = .equal
    /// "Paid for someone" has no Hybrid Split: choosing it turns Hybrid Split off.
    public var purpose: Purpose = .shared {
        didSet { if purpose != .shared { hybrid = false } }
    }
    /// Hybrid Split (Common/BusinessRules/split-hybrid.md): group fixed amounts + individual fixed amounts + the remaining
    /// amount split equally. While on, `method` and Auto Calculate are not used (kept so turning it off returns to them).
    public private(set) var hybrid = false
    public private(set) var hybridGroups: [HybridGroup] = []
    public private(set) var hybridIndividuals: [HybridIndividual] = []
    /// Who shares the remaining amount.
    public private(set) var remainderIDs: Set<UUID> = []
    /// Amounts method only, and only for THIS split (never a saved preference: every new split starts ON).
    /// ON: amounts the user typed are kept exactly; what's left of the total (after typed and fixed amounts) is
    /// shared equally by everyone not typed for — Me included — plus each person's fixed amount.
    /// OFF: nothing is calculated or changed; the typed amounts must add up to the total before saving.
    public var autoCalculate = true
    /// Me is always first and can never be removed.
    public private(set) var participants: [Participant] = [Participant(isMe: true, name: "Me")]
    /// nil = I paid.
    public var payer: PayBookProfile?
    /// Participants whose amount the user typed, oldest first (drives Auto Calculate).
    public private(set) var typedOrder: [UUID] = []

    public init() {}

    public static func == (lhs: SplitDraft, rhs: SplitDraft) -> Bool {
        lhs.method == rhs.method && lhs.participants == rhs.participants && lhs.payer?.id == rhs.payer?.id &&
        lhs.purpose == rhs.purpose && lhs.autoCalculate == rhs.autoCalculate && lhs.hybrid == rhs.hybrid &&
        lhs.hybridGroups == rhs.hybridGroups && lhs.hybridIndividuals == rhs.hybridIndividuals && lhs.remainderIDs == rhs.remainderIDs
    }

    /// I paid entirely for the people in the list.
    public var iPaidForOthers: Bool { purpose == .paidFor && payer == nil }
    /// Someone paid entirely for me.
    public var paidForMe: Bool { purpose == .paidFor && payer != nil }

    /// The people whose shares are calculated: everyone (shared), the people I paid for, or only me.
    public var sharingParticipants: [Participant] {
        if iPaidForOthers { return others }
        if paidForMe { return participants.filter(\.isMe) }
        return participants
    }

    /// Loads the split stored on an expense (nil when the expense is not shared).
    public init?(expense: Expense) {
        guard !expense.shares.isEmpty else { return nil }
        method = expense.splitMethod ?? .amounts
        payer = expense.paidByMe ? nil : expense.payer
        // "Paid for someone" is recognised from the data: I paid and my share is an automatic 0, or someone else
        // paid and I am the only participant.
        let mine = expense.shares.first(where: \.isMe)
        if expense.paidByMe, let mine, mine.amountMinor == 0, mine.enteredMinor == nil, mine.parts == nil, expense.shares.count > 1 {
            purpose = .paidFor
        } else if !expense.paidByMe, expense.shares.count == 1, mine != nil {
            purpose = .paidFor
        }
        // Auto Calculate is ON when a saved split is reopened too; the saved amounts are kept (see below).
        autoCalculate = true
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
        // Hybrid Split: restored from the rule when it is valid and matches the stored shares; otherwise this stays the
        // plain Custom Amount split it is also saved as.
        if purpose == .shared, let raw = expense.splitRule, let rule = HybridRule(json: raw) {
            let idBySortIndex = Dictionary(expense.shares.map { ($0.sortIndex, $0.id) }, uniquingKeysWith: { a, _ in a })
            let positions = rule.groups.flatMap(\.members) + rule.individuals.map(\.participant) + rule.remaining
            if positions.allSatisfy({ position in idBySortIndex[position].map { id in participants.contains { $0.id == id } } ?? false }) {
                hybrid = true
                hybridGroups = rule.groups.map {
                    HybridGroup(amountText: Self.text(fromMinor: $0.amountMinor), memberIDs: Set($0.members.compactMap { idBySortIndex[$0] }))
                }
                if hybridGroups.isEmpty { hybridGroups = [HybridGroup()] }
                hybridIndividuals = rule.individuals.map {
                    HybridIndividual(participantID: idBySortIndex[$0.participant], amountText: Self.text(fromMinor: $0.amountMinor))
                }
                remainderIDs = Set(rule.remaining.compactMap { idBySortIndex[$0] })
            }
        }
        // Custom Amount with Auto Calculate ON, and nothing moves: everyone keeps their saved amount as typed except Me
        // (or the last person when I'm not in it), whose amount is total − the others — the saved number.
        // (Also under a Hybrid Split, so turning it off keeps the saved amounts.)
        if method == .amounts {
            let sharing = sharingParticipants
            let calculated = sharing.first(where: \.isMe) ?? sharing.last
            typedOrder = sharing.map(\.id).filter { $0 != calculated?.id }
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
        let participant = Participant(person: person, name: person.name)
        participants.append(participant)
        // Hybrid Split: a new person joins the remaining amount only.
        if hybrid { remainderIDs.insert(participant.id) }
        return true
    }

    /// Removes a participant. Me cannot be removed. Removing the payer makes Me the payer again only if
    /// the payer was a participant — a payer who is not a participant is allowed and kept.
    public mutating func remove(id: UUID) {
        guard let index = participants.firstIndex(where: { $0.id == id }), !participants[index].isMe else { return }
        participants.remove(at: index)
        typedOrder.removeAll { $0 == id }
        // Hybrid Split: out of every group, their individual rows deleted, out of the remaining amount.
        for g in hybridGroups.indices { hybridGroups[g].memberIDs.remove(id) }
        hybridIndividuals.removeAll { $0.participantID == id }
        remainderIDs.remove(id)
    }

    public mutating func setParts(_ parts: Int, for id: UUID) {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[index].parts = min(max(parts, 1), SplitCalculator.maxParts)
    }

    /// Sets a typed amount. The amount is kept exactly as typed (and replaces any fixed amount for that person).
    /// Clearing the box hands the person back to Auto Calculate. With Auto Calculate on, when every person now has a
    /// typed amount, the one typed longest ago is handed back to Auto Calculate so the total still works out.
    public mutating func setAmountText(_ text: String, for id: UUID, totalMinor: Int? = nil) {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[index].amountText = text
        typedOrder.removeAll { $0 == id }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            if let totalMinor { refreshCalculatedText(totalMinor: totalMinor) }
            return
        }
        typedOrder.append(id)
        participants[index].fixedMinor = nil
        guard autoCalculate, method == .amounts, let totalMinor else { return }
        let group = sharingParticipants
        if group.count >= 2, group.contains(where: { $0.id == id }), group.allSatisfy({ typedOrder.contains($0.id) }),
           let oldest = typedOrder.first(where: { typed in typed != id && group.contains { $0.id == typed } }) {
            typedOrder.removeAll { $0 == oldest }
        }
        refreshCalculatedText(totalMinor: totalMinor)
    }

    /// Sets (or clears, with nil) a person's fixed amount. Negative amounts are refused (returns false). A person
    /// with a fixed amount is calculated: fixed + their equal part of the remainder.
    @discardableResult
    public mutating func setFixed(_ minor: Int?, for id: UUID, totalMinor: Int? = nil) -> Bool {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return false }
        if let minor, minor < 0 { return false }
        participants[index].fixedMinor = (minor ?? 0) > 0 ? minor : nil
        typedOrder.removeAll { $0 == id }
        if let totalMinor { refreshCalculatedText(totalMinor: totalMinor) }
        return true
    }

    /// Turns Auto Calculate on or off for this split. Turning it off keeps every amount exactly as currently shown
    /// (they become the typed amounts); turning it on again recalculates everyone the user didn't type for.
    public mutating func setAutoCalculate(_ on: Bool, totalMinor: Int) {
        guard on != autoCalculate else { return }
        if !on, method == .amounts, let shown = shares(totalMinor: totalMinor) {
            for index in participants.indices where sharingParticipants.contains(where: { $0.id == participants[index].id }) {
                participants[index].amountText = Self.text(fromMinor: shown[index])
            }
        }
        autoCalculate = on
        if on { refreshCalculatedText(totalMinor: totalMinor) }
    }

    // MARK: Hybrid Split

    /// Turning it on: one empty group, no individual amounts, everyone (Me included) shares the remaining amount.
    /// Turning it off returns to the method used before. Only for a shared expense.
    public mutating func setHybrid(_ on: Bool) {
        guard on != hybrid else { return }
        if on {
            guard purpose == .shared else { return }
            hybridGroups = [HybridGroup()]
            hybridIndividuals = []
            remainderIDs = Set(participants.map(\.id))
        }
        hybrid = on
    }

    /// Hybrid Split is in use for this split.
    public var usesHybrid: Bool { hybrid && purpose == .shared }

    @discardableResult
    public mutating func addHybridGroup() -> UUID {
        let group = HybridGroup()
        hybridGroups.append(group)
        return group.id
    }

    public mutating func removeHybridGroup(_ id: UUID) {
        hybridGroups.removeAll { $0.id == id }
    }

    public mutating func setGroupAmountText(_ text: String, for groupID: UUID) {
        guard let g = hybridGroups.firstIndex(where: { $0.id == groupID }) else { return }
        hybridGroups[g].amountText = text
    }

    public mutating func setGroupMember(_ on: Bool, participant: UUID, group groupID: UUID) {
        guard let g = hybridGroups.firstIndex(where: { $0.id == groupID }), participants.contains(where: { $0.id == participant }) else { return }
        if on { hybridGroups[g].memberIDs.insert(participant) } else { hybridGroups[g].memberIDs.remove(participant) }
    }

    @discardableResult
    public mutating func addIndividual() -> UUID {
        let row = HybridIndividual()
        hybridIndividuals.append(row)
        return row.id
    }

    public mutating func removeIndividual(_ id: UUID) {
        hybridIndividuals.removeAll { $0.id == id }
    }

    public mutating func setIndividualPerson(_ participant: UUID?, for rowID: UUID) {
        guard let r = hybridIndividuals.firstIndex(where: { $0.id == rowID }) else { return }
        hybridIndividuals[r].participantID = participant
    }

    public mutating func setIndividualAmountText(_ text: String, for rowID: UUID) {
        guard let r = hybridIndividuals.firstIndex(where: { $0.id == rowID }) else { return }
        hybridIndividuals[r].amountText = text
    }

    public mutating func setInRemainder(_ on: Bool, participant: UUID) {
        guard participants.contains(where: { $0.id == participant }) else { return }
        if on { remainderIDs.insert(participant) } else { remainderIDs.remove(participant) }
    }

    /// A typed amount, or nil when empty, not a number, or not more than 0.
    static func positiveMinor(_ text: String) -> Int? {
        guard let minor = Money.minorUnits(parsing: text), minor > 0 else { return nil }
        return minor
    }

    /// Σ group amounts that are filled in (live, even while something else is incomplete).
    public var groupAllocationMinor: Int {
        hybridGroups.filter { !$0.isBlank }.reduce(0) { $0 + (Self.positiveMinor($1.amountText) ?? 0) }
    }

    /// Σ individual amounts that are filled in.
    public var individualAllocationMinor: Int {
        hybridIndividuals.filter { !$0.isBlank }.reduce(0) { $0 + (Self.positiveMinor($1.amountText) ?? 0) }
    }

    /// total − group allocation − individual allocation (negative = the fixed amounts are too much).
    public func hybridRemainingMinor(totalMinor: Int) -> Int { totalMinor - groupAllocationMinor - individualAllocationMinor }

    /// How a group's amount divides between its members right now (participant order). Empty while it has no amount.
    public func groupPreview(_ groupID: UUID) -> [(participant: Participant, minor: Int)] {
        guard let group = hybridGroups.first(where: { $0.id == groupID }), let amount = Self.positiveMinor(group.amountText) else { return [] }
        let members = participants.filter { group.memberIDs.contains($0.id) }
        let divided = SplitCalculator.divideEqually(totalMinor: amount, isMe: members.map(\.isMe), iPaid: iPaid)
        return Array(zip(members, divided)).map { (participant: $0.0, minor: $0.1) }
    }

    /// The full Hybrid Split result (every layer per participant), or why it doesn't work.
    public func hybridSplit(totalMinor: Int) -> Result<SplitCalculator.HybridSplit, SplitCalculator.HybridError> {
        func index(_ id: UUID?) -> Int? { id.flatMap { id in participants.firstIndex { $0.id == id } } }
        return SplitCalculator.calculateHybrid(
            totalMinor: totalMinor,
            isMe: participants.map(\.isMe),
            groups: hybridGroups.map {
                .init(amountMinor: Self.positiveMinor($0.amountText), members: $0.memberIDs.compactMap(index), isBlank: $0.isBlank)
            },
            individuals: hybridIndividuals.map {
                .init(participant: index($0.participantID), amountMinor: Self.positiveMinor($0.amountText), isBlank: $0.isBlank)
            },
            remaining: remainderIDs.compactMap(index),
            iPaid: iPaid)
    }

    /// The canonical rule saved on the expense (positions = participant index = share sortIndex). Empty rows are left out.
    public var hybridRuleJSON: String? {
        guard usesHybrid else { return nil }
        func position(_ id: UUID) -> Int? { participants.firstIndex { $0.id == id } }
        let groups = hybridGroups.filter { !$0.isBlank }.map {
            HybridRule.Group(amountMinor: Self.positiveMinor($0.amountText) ?? 0, members: $0.memberIDs.compactMap(position).sorted())
        }
        let individuals = hybridIndividuals.filter { !$0.isBlank }.compactMap { row -> HybridRule.Individual? in
            guard let id = row.participantID, let p = position(id) else { return nil }
            return HybridRule.Individual(participant: p, amountMinor: Self.positiveMinor(row.amountText) ?? 0)
        }
        return HybridRule(groups: groups, individuals: individuals, remaining: remainderIDs.compactMap(position).sorted()).json
    }

    /// "Split Equally": every sharing participant gets the same amount (cents distributed so the sum is exact).
    public mutating func useEqualSplit() {
        method = .equal
    }

    /// "Custom Amount": switches to amounts. With Auto Calculate on, everyone not typed for is calculated (so the
    /// boxes start at the equal shares); with it off, empty boxes start from the current shares so they already
    /// add up and the user only adjusts.
    public mutating func useCustomAmounts(totalMinor: Int) {
        guard method != .amounts else { return }
        let current = shares(totalMinor: totalMinor)
        method = .amounts
        let sharing = Set(sharingParticipants.map(\.id))
        let nothingTyped = participants.filter { sharing.contains($0.id) }.allSatisfy { (Money.minorUnits(parsing: $0.amountText) ?? 0) == 0 }
        if let current, nothingTyped {
            for index in participants.indices where sharing.contains(participants[index].id) {
                participants[index].amountText = Self.text(fromMinor: current[index])
            }
            typedOrder = []
        }
        refreshCalculatedText(totalMinor: totalMinor)
    }

    /// True when Auto Calculate works out this person's amount (nothing typed for them).
    public func isCalculated(_ id: UUID) -> Bool {
        autoCalculate && method == .amounts && !paidForMe && !typedOrder.contains(id)
    }

    /// The amount to show in a person's box: what they typed, or the calculated amount.
    public func displayAmountText(for id: UUID, totalMinor: Int) -> String {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return "" }
        guard isCalculated(id) else { return participants[index].amountText }
        return autoAmounts(totalMinor: totalMinor).successValue.map { Self.text(fromMinor: $0[index]) } ?? ""
    }

    /// Fixed amounts of the people Auto Calculate works out (the "Fixed" line of the summary).
    public var fixedTotalMinor: Int {
        guard autoCalculate, method == .amounts else { return 0 }
        return sharingParticipants.filter { isCalculated($0.id) }.reduce(0) { $0 + ($1.fixedMinor ?? 0) }
    }

    /// Keeps the boxes of calculated people showing the calculated value.
    private mutating func refreshCalculatedText(totalMinor: Int) {
        guard autoCalculate, method == .amounts, case .success(let amounts) = autoAmounts(totalMinor: totalMinor) else { return }
        for index in participants.indices where isCalculated(participants[index].id) {
            participants[index].amountText = Self.text(fromMinor: amounts[index])
        }
    }

    /// Amounts method: what the typed shares add up to, and what's left (negative = too much).
    public func assignedMinor() -> Int {
        sharingParticipants.reduce(0) { $0 + (Money.minorUnits(parsing: $1.amountText) ?? 0) }
    }

    /// What the shares add up to for this total: typed amounts, fixed amounts and the calculated remainder.
    public func assignedMinor(totalMinor: Int) -> Int {
        guard autoCalculate, method == .amounts, !paidForMe else { return assignedMinor() }
        let group = sharingParticipants
        let typed = group.filter { !isCalculated($0.id) }.reduce(0) { $0 + (Money.minorUnits(parsing: $1.amountText) ?? 0) }
        let floating = group.filter { isCalculated($0.id) }
        let fixed = floating.reduce(0) { $0 + ($1.fixedMinor ?? 0) }
        return floating.isEmpty ? typed : max(typed + fixed, totalMinor)
    }

    public func remainingMinor(totalMinor: Int) -> Int { totalMinor - assignedMinor(totalMinor: totalMinor) }

    // MARK: Calculation

    public var iPaid: Bool { payer == nil }

    /// Why a split can't be saved yet.
    public enum Problem: Error, Equatable {
        case calculator(SplitCalculator.SplitError)
        /// Fixed amounts alone are more than the total (by this many sen).
        case fixedExceedTotal(overMinor: Int)
        /// Money is left over and Auto Calculate has nobody to give it to (everyone has a typed amount).
        case noOneForRemainder(remainingMinor: Int)
        /// Hybrid Split problems 3–11 (1 and 2 use the calculator's).
        case hybrid(SplitCalculator.HybridError)
    }

    /// One amount per entry in `participants` (people outside the sharing group get 0).
    public func calculate(totalMinor: Int) -> Result<[Int], Problem> {
        if usesHybrid {
            switch hybridSplit(totalMinor: totalMinor) {
            case .success(let split): return .success(split.shares)
            case .failure(.nonPositiveTotal): return .failure(.calculator(.nonPositiveTotal))
            case .failure(.tooFewParticipants): return .failure(.calculator(.tooFewParticipants))
            case .failure(let error): return .failure(.hybrid(error))
            }
        }
        if method == .amounts && autoCalculate && !paidForMe {
            return autoAmounts(totalMinor: totalMinor)
        }
        return plainCalculate(totalMinor: totalMinor).mapError { .calculator($0) }
    }

    /// Auto Calculate: typed amounts as typed; total − typed − fixed shared equally (exact sen, same rule as
    /// Split Equally) by everyone not typed for; each of them also gets their fixed amount.
    func autoAmounts(totalMinor: Int) -> Result<[Int], Problem> {
        guard totalMinor > 0 else { return .failure(.calculator(.nonPositiveTotal)) }
        let group = sharingParticipants
        let requireMe = !iPaidForOthers
        guard group.count >= (requireMe ? 2 : 1) else { return .failure(.calculator(.tooFewParticipants)) }
        var result = participants.map { _ in 0 }
        var typedSum = 0
        var floating: [Int] = []          // indices into `participants`
        for (groupIndex, p) in group.enumerated() {
            let index = participants.firstIndex { $0.id == p.id }!
            if isCalculated(p.id) {
                floating.append(index)
            } else {
                guard let minor = Money.minorUnits(parsing: p.amountText) else { return .failure(.calculator(.missingAmount(index: groupIndex))) }
                guard minor >= 0 else { return .failure(.calculator(.negativeAmount(index: groupIndex))) }
                result[index] = minor
                typedSum += minor
            }
        }
        let fixedSum = floating.reduce(0) { $0 + (participants[$1].fixedMinor ?? 0) }
        if fixedSum > totalMinor { return .failure(.fixedExceedTotal(overMinor: fixedSum - totalMinor)) }
        let remainder = totalMinor - typedSum - fixedSum
        if remainder < 0 { return .failure(.calculator(.amountsDoNotMatchTotal(differenceMinor: -remainder))) }
        if floating.isEmpty {
            return remainder == 0 ? .success(result) : .failure(.noOneForRemainder(remainingMinor: remainder))
        }
        var parts = floating.map { _ in 0 }
        if remainder > 0 {
            let inputs = floating.map { SplitCalculator.Participant(isMe: participants[$0].isMe) }
            let hasMe = inputs.contains(where: \.isMe)
            if inputs.count == 1 {
                parts = [remainder]
            } else if case .success(let equal) = SplitCalculator.calculate(totalMinor: remainder, method: .equal, participants: inputs,
                                                                           iPaid: iPaid, requireMe: hasMe) {
                parts = equal
            }
        }
        for (position, index) in floating.enumerated() {
            result[index] = parts[position] + (participants[index].fixedMinor ?? 0)
        }
        return .success(result)
    }

    private func plainCalculate(totalMinor: Int) -> Result<[Int], SplitCalculator.SplitError> {
        if paidForMe {
            guard totalMinor > 0 else { return .failure(.nonPositiveTotal) }
            return .success(participants.map { $0.isMe ? totalMinor : 0 })
        }
        let group = sharingParticipants
        let inputs = group.map { p in
            SplitCalculator.Participant(isMe: p.isMe, parts: p.parts, enteredMinor: Self.enteredMinor(p.amountText))
        }
        let result = SplitCalculator.calculate(totalMinor: totalMinor, method: method, participants: inputs, iPaid: iPaid,
                                               requireMe: !iPaidForOthers)
        return result.map { amounts in
            participants.map { p in group.firstIndex(where: { $0.id == p.id }).map { amounts[$0] } ?? 0 }
        }
    }

    /// Custom amounts: an empty box is RM 0.00 (what the box shows), never "missing" — e.g. You (empty) + Riyad 100
    /// of RM100 is a complete split. Text that isn't a number is reported instead of being guessed.
    static func enteredMinor(_ text: String) -> Int? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Money.minorUnits(parsing: text)
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
        func money(_ minor: Int) -> String { CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: abs(minor))) }
        switch calculate(totalMinor: totalMinor) {
        case .success:
            return nil
        case .failure(.fixedExceedTotal(let over)):
            return "Fixed amounts exceed the expense total by \(money(over))."
        case .failure(.hybrid(let error)):
            func name(_ index: Int) -> String { participants[index].isMe ? "You" : participants[index].name }
            switch error {
            case .nonPositiveTotal: return "Enter the expense amount first."
            case .tooFewParticipants: return "Add at least one other person."
            case .groupAmountMissing(let n): return "Enter the amount for group fixed amount \(n)."
            case .groupWithoutMembers(let n): return "Choose who shares group fixed amount \(n)."
            case .individualWithoutPerson: return "Choose a person for each individual fixed amount."
            case .individualAmountMissing(let i): return "Enter the individual fixed amount for \(name(i))."
            case .duplicateIndividual(let i): return "\(name(i)) already has an individual fixed amount."
            case .nothingFixed: return "Add a group fixed amount or an individual fixed amount."
            case .fixedExceedTotal(let over): return "Fixed allocations exceed the transaction total by \(money(over))."
            case .remainderUnassigned(let remaining):
                return "\(money(remaining)) is left after the fixed allocations. Choose who shares the remaining amount."
            case .notInAnyLayer(let i): return "\(name(i)) isn't in any part of the split. Add them to an allocation or remove them."
            }
        case .failure(.noOneForRemainder(let remaining)):
            return "\(money(remaining)) remains unassigned. Select at least one participant for the remaining amount (clear someone's amount)."
        case .failure(.calculator(let error)):
            switch error {
            case .nonPositiveTotal: return "Enter the expense amount first."
            case .tooFewParticipants: return iPaidForOthers ? "Choose who you paid for." : "Add at least one other person."
            case .missingMe, .moreThanOneMe: return "A split must include you exactly once."
            case .invalidParts: return "Parts must be whole numbers from 1 to \(SplitCalculator.maxParts)."
            case .missingAmount(let index): return "Enter a valid amount for \(sharingParticipants[index].isMe ? "You" : sharingParticipants[index].name)."
            case .negativeAmount(let index): return "\(sharingParticipants[index].name)'s amount can't be negative."
            case .amountsDoNotMatchTotal(let difference):
                return difference > 0 ? "Shares exceed the total by \(money(difference))." : "\(money(difference)) remains unassigned."
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
        let sharing = Set(sharingParticipants.map(\.id))
        for (index, participant) in participants.enumerated() {
            // Someone paid entirely for me: only my share is stored. I paid for others: my share is an automatic 0.
            if paidForMe && !participant.isMe { continue }
            let inGroup = sharing.contains(participant.id)
            let share = ExpenseShare(
                person: participant.isMe ? nil : participant.person,
                isMe: participant.isMe,
                nameSnapshot: participant.isMe ? "Me" : (participant.person?.name ?? participant.name),
                amountMinor: amounts[index],
                parts: method == .parts && inGroup && !paidForMe && !usesHybrid ? participant.parts : nil,
                // Hybrid Split is stored as Custom Amount: older versions and every report see the right numbers.
                enteredMinor: (method == .amounts || usesHybrid) && inGroup && !paidForMe ? amounts[index] : nil,
                sortIndex: index
            )
            context.insert(share)
            share.expense = expense
        }
        expense.splitMethod = usesHybrid ? .amounts : method
        expense.splitRule = hybridRuleJSON
        expense.setPayer(payer)
        expense.updatedAt = Date()
        return true
    }

    /// Makes the expense a normal (unshared) expense again: shares removed, I paid.
    public static func removeSplit(from expense: Expense, in context: ModelContext) {
        for share in expense.shares {
            context.delete(share)
        }
        expense.shares = []
        expense.splitMethod = nil
        expense.splitRule = nil
        expense.setPayer(nil)
        expense.updatedAt = Date()
    }

    /// After the amount of a shared expense changed: Equal, Parts and Hybrid Split are recalculated (a Hybrid Split
    /// that no longer works is left as it was); Amounts are left untouched and reported as needing attention.
    /// Returns true when the stored shares now match the amount.
    @discardableResult
    public static func recalculateAfterAmountChange(_ expense: Expense, in context: ModelContext) -> Bool {
        guard expense.isShared else { return true }
        guard let draft = SplitDraft(expense: expense) else { return true }
        if draft.usesHybrid {
            return draft.apply(to: expense, in: context) || expense.sharesMatchAmount
        }
        if draft.method == .amounts {
            return expense.sharesMatchAmount
        }
        return draft.apply(to: expense, in: context)
    }

    // MARK: Same as last time

    /// The people (and method) of the most recent shared expense — preferring one at the same merchant.
    /// Only people that still exist and are not archived are suggested. nil when there is no useful history.
    public static func lastTimeSuggestion(merchant: String?, excluding expenseID: UUID? = nil, in context: ModelContext) -> SplitDraft? {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 200
        let recent = ((try? context.fetch(descriptor)) ?? []).filter { $0.isShared && $0.id != expenseID }
        let merchantKey = merchant.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let source = recent.first { merchantKey != nil && !merchantKey!.isEmpty && $0.merchant.lowercased() == merchantKey } ?? recent.first
        guard let source else { return nil }

        var draft = SplitDraft()
        draft.method = source.splitMethod == .parts ? .parts : .equal
        let people = source.shares
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { $0.isMe ? nil : $0.person }
            .filter { !$0.isArchived }
        for person in people {
            draft.add(person)
            if draft.method == .parts, let parts = source.shares.first(where: { $0.person?.id == person.id })?.parts {
                draft.setParts(parts, for: draft.participants.last!.id)
            }
        }
        if draft.method == .parts, let myParts = source.shares.first(where: \.isMe)?.parts {
            draft.setParts(myParts, for: draft.participants[0].id)
        }
        return draft.others.isEmpty ? nil : draft
    }

    static func text(fromMinor minor: Int) -> String {
        String(format: "%.2f", Money.majorAmount(fromMinor: minor))
    }
}

/// The Hybrid Split rule stored on `Expense.splitRule`. Canonical JSON, keys in this order, no spaces:
/// {"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}
/// Numbers are participant positions (= the shares' sortIndex).
public struct HybridRule: Equatable {
    public struct Group: Equatable { public var amountMinor: Int; public var members: [Int] }
    public struct Individual: Equatable { public var participant: Int; public var amountMinor: Int }

    public var groups: [Group]
    public var individuals: [Individual]
    public var remaining: [Int]

    public init(groups: [Group], individuals: [Individual], remaining: [Int]) {
        self.groups = groups
        self.individuals = individuals
        self.remaining = remaining
    }

    /// nil for anything that isn't a version-1 hybrid rule (unknown type, bad JSON, wrong shapes).
    public init?(json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              object["type"] as? String == "hybrid", (object["version"] as? Int) == 1,
              let groupList = object["groups"] as? [[String: Any]], let individualList = object["individuals"] as? [[String: Any]],
              let remaining = object["remaining"] as? [Int] else { return nil }
        var groups: [Group] = []
        for g in groupList {
            guard let amount = g["amountMinor"] as? Int, let members = g["members"] as? [Int] else { return nil }
            groups.append(Group(amountMinor: amount, members: members))
        }
        var individuals: [Individual] = []
        for i in individualList {
            guard let participant = i["participant"] as? Int, let amount = i["amountMinor"] as? Int else { return nil }
            individuals.append(Individual(participant: participant, amountMinor: amount))
        }
        self.init(groups: groups, individuals: individuals, remaining: remaining)
    }

    public var json: String {
        func list(_ numbers: [Int]) -> String { "[" + numbers.map(String.init).joined(separator: ",") + "]" }
        let g = groups.map { "{\"amountMinor\":\($0.amountMinor),\"members\":\(list($0.members))}" }.joined(separator: ",")
        let i = individuals.map { "{\"participant\":\($0.participant),\"amountMinor\":\($0.amountMinor)}" }.joined(separator: ",")
        return "{\"type\":\"hybrid\",\"version\":1,\"groups\":[\(g)],\"individuals\":[\(i)],\"remaining\":\(list(remaining))}"
    }
}

private extension Result {
    var successValue: Success? { if case .success(let value) = self { return value }; return nil }
}
