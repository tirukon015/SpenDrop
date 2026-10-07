import Foundation

/// Divides an expense total between participants in integer minor units. Pure logic, no SwiftData.
/// The result always adds up exactly to the total, or the calculation fails with a validation error.
public enum SplitCalculator {
    public struct Participant: Equatable {
        public var isMe: Bool
        /// Parts method: a whole number from 1 to 99.
        public var parts: Int?
        /// Amounts method: the exact share in minor units (0 allowed).
        public var enteredMinor: Int?

        public init(isMe: Bool = false, parts: Int? = nil, enteredMinor: Int? = nil) {
            self.isMe = isMe
            self.parts = parts
            self.enteredMinor = enteredMinor
        }
    }

    public enum SplitError: Error, Equatable {
        case nonPositiveTotal
        case tooFewParticipants
        case missingMe
        case moreThanOneMe
        case invalidParts(index: Int)
        case missingAmount(index: Int)
        case negativeAmount(index: Int)
        /// Positive = shares add up to MORE than the total; negative = less. Never silently adjusted.
        case amountsDoNotMatchTotal(differenceMinor: Int)
    }

    public static let maxParts = 99

    /// - Parameter iPaid: when true, leftover sen from rounding go to Me first so friends never owe an extra sen.
    /// - Parameter requireMe: false for "paid for someone": the people I paid for share the whole total (one person
    ///   is enough) and I am not part of it.
    public static func calculate(totalMinor: Int, method: SplitMethod, participants: [Participant], iPaid: Bool = true,
                                 requireMe: Bool = true) -> Result<[Int], SplitError> {
        guard totalMinor > 0 else { return .failure(.nonPositiveTotal) }
        guard participants.count >= (requireMe ? 2 : 1) else { return .failure(.tooFewParticipants) }
        let meCount = participants.filter(\.isMe).count
        if requireMe {
            guard meCount > 0 else { return .failure(.missingMe) }
            guard meCount == 1 else { return .failure(.moreThanOneMe) }
        } else if meCount > 0 {
            return .failure(.moreThanOneMe)
        }

        switch method {
        case .equal:
            return .success(largestRemainder(totalMinor: totalMinor, weights: participants.map { _ in 1 }, participants: participants, iPaid: iPaid))

        case .parts:
            var weights: [Int] = []
            for (index, participant) in participants.enumerated() {
                guard let parts = participant.parts, (1...maxParts).contains(parts) else { return .failure(.invalidParts(index: index)) }
                weights.append(parts)
            }
            return .success(largestRemainder(totalMinor: totalMinor, weights: weights, participants: participants, iPaid: iPaid))

        case .amounts:
            var amounts: [Int] = []
            for (index, participant) in participants.enumerated() {
                guard let entered = participant.enteredMinor else { return .failure(.missingAmount(index: index)) }
                guard entered >= 0 else { return .failure(.negativeAmount(index: index)) }
                amounts.append(entered)
            }
            let difference = amounts.reduce(0, +) - totalMinor
            guard difference == 0 else { return .failure(.amountsDoNotMatchTotal(differenceMinor: difference)) }
            return .success(amounts)
        }
    }

    // MARK: Hybrid Split (Common/BusinessRules/split-hybrid.md)

    /// One group fixed amount: a TOTAL divided equally between its members (participant indices).
    public struct HybridGroup: Equatable {
        /// nil = empty, not a number, or not more than 0.
        public var amountMinor: Int?
        public var members: [Int]
        /// No amount typed and no members: the empty starter group, ignored.
        public var isBlank: Bool

        public init(amountMinor: Int?, members: [Int], isBlank: Bool = false) {
            self.amountMinor = amountMinor
            self.members = members
            self.isBlank = isBlank
        }
    }

    /// One individual fixed amount: for one person only, never divided.
    public struct HybridIndividual: Equatable {
        public var participant: Int?
        /// nil = empty, not a number, or not more than 0.
        public var amountMinor: Int?
        /// No person and no amount typed: ignored.
        public var isBlank: Bool

        public init(participant: Int?, amountMinor: Int?, isBlank: Bool = false) {
            self.participant = participant
            self.amountMinor = amountMinor
            self.isBlank = isBlank
        }
    }

    /// The result, one entry per participant (input order) in every array.
    public struct HybridSplit: Equatable {
        /// Final amount = Σ group parts + individual part + remaining part. Always adds up exactly to the total.
        public var shares: [Int]
        /// Per group (same order as the input, ignored groups all 0), per participant.
        public var groupParts: [[Int]]
        public var individualParts: [Int]
        public var remainingParts: [Int]
        public var groupAllocationMinor: Int
        public var individualAllocationMinor: Int
        public var remainingMinor: Int

        public func groupTotal(for participant: Int) -> Int { groupParts.reduce(0) { $0 + $1[participant] } }
    }

    /// Problems in the order they are checked (the shared wording lives in `SplitDraft.problem`).
    public enum HybridError: Error, Equatable {
        case nonPositiveTotal
        case tooFewParticipants
        /// Group number, counted from 1 in the order shown.
        case groupAmountMissing(group: Int)
        case groupWithoutMembers(group: Int)
        case individualWithoutPerson
        case individualAmountMissing(participant: Int)
        case duplicateIndividual(participant: Int)
        case nothingFixed
        case fixedExceedTotal(overMinor: Int)
        case remainderUnassigned(remainingMinor: Int)
        case notInAnyLayer(participant: Int)
    }

    /// The Split Equally rule on its own: `totalMinor` divided equally (largest remainder; ties → Me first when I paid,
    /// then list order). One amount per entry of `isMe`; always adds up exactly.
    public static func divideEqually(totalMinor: Int, isMe: [Bool], iPaid: Bool) -> [Int] {
        guard !isMe.isEmpty else { return [] }
        let group = isMe.map { Participant(isMe: $0) }
        return largestRemainder(totalMinor: totalMinor, weights: group.map { _ in 1 }, participants: group, iPaid: iPaid)
    }

    /// Hybrid Split: group fixed amounts (each divided equally between its members), individual fixed amounts (never
    /// divided) and the remaining amount divided equally between `remaining`. `isMe` has one entry per participant.
    public static func calculateHybrid(totalMinor: Int, isMe: [Bool], groups: [HybridGroup], individuals: [HybridIndividual],
                                       remaining: [Int], iPaid: Bool = true) -> Result<HybridSplit, HybridError> {
        let count = isMe.count
        guard totalMinor > 0 else { return .failure(.nonPositiveTotal) }
        guard isMe.contains(false) else { return .failure(.tooFewParticipants) }
        // Group by group (amount, then members), so the first broken group is the one named.
        for (n, group) in groups.enumerated() where !group.isBlank {
            if (group.amountMinor ?? 0) <= 0 { return .failure(.groupAmountMissing(group: n + 1)) }
            if !group.members.contains(where: { (0..<count).contains($0) }) { return .failure(.groupWithoutMembers(group: n + 1)) }
        }
        // Row by row (person, amount, duplicate), so the first broken row is the one named.
        let liveIndividuals = individuals.filter { !$0.isBlank }
        var seen = Set<Int>()
        for individual in liveIndividuals {
            guard let who = individual.participant, (0..<count).contains(who) else { return .failure(.individualWithoutPerson) }
            if (individual.amountMinor ?? 0) <= 0 { return .failure(.individualAmountMissing(participant: who)) }
            if !seen.insert(who).inserted { return .failure(.duplicateIndividual(participant: who)) }
        }
        let liveGroups = groups.filter { !$0.isBlank }
        guard !liveGroups.isEmpty || !liveIndividuals.isEmpty else { return .failure(.nothingFixed) }

        let groupAllocation = liveGroups.reduce(0) { $0 + ($1.amountMinor ?? 0) }
        let individualAllocation = liveIndividuals.reduce(0) { $0 + ($1.amountMinor ?? 0) }
        let fixedAllocation = groupAllocation + individualAllocation
        guard fixedAllocation <= totalMinor else { return .failure(.fixedExceedTotal(overMinor: fixedAllocation - totalMinor)) }
        let remainingMinor = totalMinor - fixedAllocation
        let sharing = (0..<count).filter { remaining.contains($0) }
        if remainingMinor > 0 && sharing.isEmpty { return .failure(.remainderUnassigned(remainingMinor: remainingMinor)) }

        let inGroup = Set(liveGroups.flatMap(\.members))
        let individualFor = Set(liveIndividuals.compactMap(\.participant))
        if let lost = (0..<count).first(where: { !isMe[$0] && !inGroup.contains($0) && !individualFor.contains($0) && !remaining.contains($0) }) {
            return .failure(.notInAnyLayer(participant: lost))
        }

        let groupParts: [[Int]] = groups.map { group in
            var parts = Array(repeating: 0, count: count)
            guard !group.isBlank, let amount = group.amountMinor else { return parts }
            let members = (0..<count).filter { group.members.contains($0) }
            let divided = divideEqually(totalMinor: amount, isMe: members.map { isMe[$0] }, iPaid: iPaid)
            for (position, index) in members.enumerated() { parts[index] = divided[position] }
            return parts
        }
        var individualParts = Array(repeating: 0, count: count)
        for individual in liveIndividuals {
            if let who = individual.participant { individualParts[who] = individual.amountMinor ?? 0 }
        }
        var remainingParts = Array(repeating: 0, count: count)
        if remainingMinor > 0 {
            let divided = divideEqually(totalMinor: remainingMinor, isMe: sharing.map { isMe[$0] }, iPaid: iPaid)
            for (position, index) in sharing.enumerated() { remainingParts[index] = divided[position] }
        }
        let shares = (0..<count).map { i in groupParts.reduce(0) { $0 + $1[i] } + individualParts[i] + remainingParts[i] }
        return .success(HybridSplit(shares: shares, groupParts: groupParts, individualParts: individualParts, remainingParts: remainingParts,
                                    groupAllocationMinor: groupAllocation, individualAllocationMinor: individualAllocation,
                                    remainingMinor: remainingMinor))
    }

    /// Floor of each proportional share, then the leftover sen one by one to the largest fractional remainders.
    /// Ties: Me first (when I paid), then list order. Deterministic for the same input.
    private static func largestRemainder(totalMinor: Int, weights: [Int], participants: [Participant], iPaid: Bool) -> [Int] {
        let weightSum = weights.reduce(0, +)
        var shares = weights.map { totalMinor * $0 / weightSum }
        let remainders = weights.map { (totalMinor * $0) % weightSum }
        var leftover = totalMinor - shares.reduce(0, +)

        let order = participants.indices.sorted { a, b in
            if remainders[a] != remainders[b] { return remainders[a] > remainders[b] }
            if iPaid && participants[a].isMe != participants[b].isMe { return participants[a].isMe }
            return a < b
        }
        var position = 0
        while leftover > 0 {
            shares[order[position % order.count]] += 1
            leftover -= 1
            position += 1
        }
        return shares
    }
}
