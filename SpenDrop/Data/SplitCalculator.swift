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
    public static func calculate(totalMinor: Int, method: SplitMethod, participants: [Participant], iPaid: Bool = true) -> Result<[Int], SplitError> {
        guard totalMinor > 0 else { return .failure(.nonPositiveTotal) }
        guard participants.count >= 2 else { return .failure(.tooFewParticipants) }
        let meCount = participants.filter(\.isMe).count
        guard meCount > 0 else { return .failure(.missingMe) }
        guard meCount == 1 else { return .failure(.moreThanOneMe) }

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

