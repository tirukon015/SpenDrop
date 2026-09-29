import Foundation

// MARK: - Per-expense values (minor units)

public extension Expense {
    var amountMinor: Int { Money.minorUnits(from: amount) }

    var isShared: Bool { !shares.isEmpty }

    /// My share: the full amount when the expense is not shared, otherwise the "Me" share (0 if missing).
    var myShareMinor: Int {
        guard isShared else { return amountMinor }
        return shares.first(where: \.isMe)?.amountMinor ?? 0
    }

    /// Spending: the full amount if I paid, my share if someone else paid.
    var spendingMinor: Int { paidByMe ? amountMinor : myShareMinor }

    /// Spending as a Double for existing charts and cards (converted from exact minor units).
    var spendingAmount: Double { Money.majorAmount(fromMinor: spendingMinor) }

    /// Cash out: the full amount if I paid, nothing if someone else paid.
    var cashOutMinor: Int { paidByMe ? amountMinor : 0 }

    /// True when the stored shares add up exactly to the amount (or the expense is not shared).
    var sharesMatchAmount: Bool {
        !isShared || shares.reduce(0) { $0 + $1.amountMinor } == amountMinor
    }
}

