import Foundation

/// Suggests whether a screenshot is money coming IN, an own-account top-up/transfer, or a refund —
/// only from clear wording. Anything unclear returns no suggestion and stays a normal expense for review.
/// It never decides on its own; the user confirms on the review screen.
public enum DirectionDetector {
    public struct Result: Equatable {
        /// nil = no confident suggestion (treat as the usual expense review).
        public let kind: MoneyMovementKind?
        public let reason: String?

        public static let none = Result(kind: nil, reason: nil)
    }

    private static let refundPhrases = ["refund", "refunded", "reversal", "reversed transaction"]
    private static let ownTransferPhrases = ["reload", "top up", "top-up", "topup", "transfer to wallet", "add money to", "cash in to wallet"]
    private static let incomingPhrases = [
        "you have received", "you received", "received from", "money received", "incoming transfer", "credited to your",
        "has been credited", "fund received", "funds received", "payment received from", "transfer received", "duitnow received"
    ]
    private static let salaryPhrases = ["salary", "gaji", "payroll"]
    private static let outgoingPhrases = [
        "paid to", "payment to", "pay to", "transfer to", "transferred to", "sent to", "you paid", "you sent", "purchase at"
    ]

    public static func detect(text: String) -> Result {
        let lower = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        func has(_ phrases: [String]) -> String? { phrases.first { lower.contains($0) } }

        let incoming = has(incomingPhrases)
        let outgoing = has(outgoingPhrases)

        if let phrase = has(refundPhrases) {
            return Result(kind: .refund, reason: "Mentions \"\(phrase)\"")
        }
        if let phrase = has(ownTransferPhrases), incoming == nil {
            return Result(kind: .ownTransfer, reason: "Looks like a top-up (\"\(phrase)\")")
        }
        if let phrase = incoming {
            if let conflicting = outgoing {
                // Both directions mentioned: do not guess.
                return Result(kind: nil, reason: "Mentions both \"\(phrase)\" and \"\(conflicting)\"")
            }
            if has(salaryPhrases) != nil {
                return Result(kind: .income, reason: "Salary received")
            }
            return Result(kind: .otherIn, reason: "Mentions \"\(phrase)\"")
        }
        return .none
    }
}
