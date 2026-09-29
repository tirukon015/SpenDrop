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

