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

// MARK: - Totals

/// Deterministic financial totals in integer minor units. Pure functions over the records passed in;
/// callers choose the date range. Amounts in different currencies are never added together.
public enum FinancialCalculator {
    public struct Summary: Equatable {
        public var spendingMinor = 0
        public var refundsMinor = 0
        public var moneyInMinor = 0
        public var moneyOutMinor = 0

        /// Gross spending minus refunds received in the same records.
        public var netSpendingMinor: Int { spendingMinor - refundsMinor }
        public var netCashFlowMinor: Int { moneyInMinor - moneyOutMinor }
    }

    /// - Spending: Σ expense spending (full amount if I paid, my share otherwise).
    /// - Money In: Σ inbound movements (income, loans received, repayments received, refunds, other in).
    /// - Money Out: Σ cash out on expenses I paid + outbound movements (loans given, repayments made, other out).
    /// - Own transfers are excluded from everything.
    public static func summary(expenses: [Expense], movements: [MoneyMovement], currency: String = "RM") -> Summary {
        var result = Summary()
        for expense in expenses where expense.currency == currency {
            result.spendingMinor += expense.spendingMinor
            result.moneyOutMinor += expense.cashOutMinor
        }
        for movement in movements where movement.currency == currency {
            switch movement.kind.direction {
            case .moneyIn:
                result.moneyInMinor += movement.amountMinor
                if movement.kind == .refund { result.refundsMinor += movement.amountMinor }
            case .moneyOut:
                result.moneyOutMinor += movement.amountMinor
            case .internal:
                break
            }
        }
        return result
    }

    /// Recorded money through one account. NOT a bank balance: SpenDrop only knows what was recorded.
    public struct AccountActivity: Equatable {
        public var inMinor = 0
        public var outMinor = 0
        public var netMinor: Int { inMinor - outMinor }
    }

    /// - Out: expenses I paid from this account, money out from it, own transfers leaving it.
    /// - In: money in to it, own transfers arriving in it.
    /// - Expenses someone else paid are not counted (no money left the account). Other currencies are skipped.
    public static func accountActivity(for account: Account) -> AccountActivity {
        var result = AccountActivity()
        for expense in account.expenses where expense.currency == account.currency {
            result.outMinor += expense.cashOutMinor
        }
        for movement in account.movements where movement.currency == account.currency {
            switch movement.kind.direction {
            case .moneyIn: result.inMinor += movement.amountMinor
            case .moneyOut, .internal: result.outMinor += movement.amountMinor
            }
        }
        for transfer in account.incomingTransfers where transfer.currency == account.currency && transfer.kind == .ownTransfer {
            result.inMinor += transfer.amountMinor
        }
        return result
    }

    /// What each person owes me, keyed by `PayBookProfile.id`. Positive = they owe me; negative = I owe them.
    /// - Expense I paid: every other participant's share adds to what they owe me.
    /// - Expense a person paid: my share adds to what I owe them. (Other people's shares are between them and the payer.)
    /// - Loan given / repayment made: they owe me more (or I owe them less).
    /// - Loan received / repayment received: they owe me less (or I owe them more).
    /// Records whose person was deleted are skipped; they cannot be attributed.
    public static func personBalances(expenses: [Expense], movements: [MoneyMovement], currency: String = "RM") -> [UUID: Int] {
        var balances: [UUID: Int] = [:]
        for expense in expenses where expense.currency == currency {
            if expense.paidByMe {
                for share in expense.shares where !share.isMe {
                    if let personID = share.person?.id {
                        balances[personID, default: 0] += share.amountMinor
                    }
                }
            } else if let payerID = expense.payer?.id {
                balances[payerID, default: 0] -= expense.myShareMinor
            }
        }
        for movement in movements where movement.currency == currency {
            let sign = movement.kind.personBalanceSign
            guard sign != 0, let personID = movement.person?.id else { continue }
            balances[personID, default: 0] += sign * movement.amountMinor
        }
        return balances
    }
}
