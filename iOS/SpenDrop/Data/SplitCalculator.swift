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
