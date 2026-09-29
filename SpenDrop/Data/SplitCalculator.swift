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

