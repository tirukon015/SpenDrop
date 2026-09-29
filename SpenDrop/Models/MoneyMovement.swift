import Foundation
import SwiftData

public enum MoneyDirection: String, Codable {
    case moneyIn = "in"
    case moneyOut = "out"
    /// Between the user's own accounts. Never counted as spending, money in or money out.
    case `internal` = "internal"
}

public enum MoneyMovementKind: String, CaseIterable, Codable, Identifiable {
    // Money In
    case income = "income"
    case loanReceived = "loanReceived"
    case repaymentReceived = "repaymentReceived"
    case refund = "refund"
    case otherIn = "otherIn"
    // Money Out
    case loanGiven = "loanGiven"
    case repaymentMade = "repaymentMade"
    case otherOut = "otherOut"
    // Internal
    case ownTransfer = "ownTransfer"

    public var id: String { rawValue }

    public var direction: MoneyDirection {
        switch self {
        case .income, .loanReceived, .repaymentReceived, .refund, .otherIn: return .moneyIn
        case .loanGiven, .repaymentMade, .otherOut: return .moneyOut
        case .ownTransfer: return .internal
        }
    }

    /// Effect on "what this person owes me" per unit of amount: +1 they owe me more, -1 they owe me less.
    /// Kinds that do not involve a debt between me and a person return 0.
    public var personBalanceSign: Int {
        switch self {
        case .loanGiven, .repaymentMade: return 1
        case .loanReceived, .repaymentReceived: return -1
        case .income, .refund, .otherIn, .otherOut, .ownTransfer: return 0
        }
    }

    public var requiresPerson: Bool { personBalanceSign != 0 }
}

public extension MoneyMovementKind {
    var displayName: String {
        switch self {
        case .income: return "Income"
        case .loanReceived: return "Loan received"
        case .repaymentReceived: return "Repayment received"
        case .refund: return "Refund"
        case .otherIn: return "Other money in"
        case .loanGiven: return "Loan given"
        case .repaymentMade: return "Repayment made"
        case .otherOut: return "Other money out"
        case .ownTransfer: return "Own transfer"
        }
    }
}

/// Money that moved in or out and is NOT spending: loans, repayments, refunds, income, own-account transfers.
/// Amounts are integer minor units (sen) and always positive; `kind` decides the direction.
@Model
public final class MoneyMovement {
    @Attribute(.unique) public var id: UUID
    public var directionRaw: String
    public var kindRaw: String
    public var amountMinor: Int
    public var currency: String
    public var date: Date
    public var person: PayBookProfile?
    public var personNameSnapshot: String?
    /// For refunds: the original expense (which stays unchanged).
    public var linkedExpense: Expense?
    public var linkedExpenseSnapshot: String?
    /// The account money left (out / own transfer) or arrived in (in).
    public var account: Account?
    /// Own transfers only: the account money moved to.
    public var counterAccount: Account?
    public var note: String?
    public var transactionReference: String?
    public var sourceTypeRaw: String
    public var paymentChannelRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: MoneyMovementKind,
        amountMinor: Int,
        currency: String = "RM",
        date: Date = Date(),
        person: PayBookProfile? = nil,
        linkedExpense: Expense? = nil,
        account: Account? = nil,
        counterAccount: Account? = nil,
        note: String? = nil,
        transactionReference: String? = nil,
        sourceType: ExpenseSourceType = .manual,
        paymentChannel: PaymentChannel = .unknown,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.directionRaw = kind.direction.rawValue
        self.kindRaw = kind.rawValue
        self.amountMinor = amountMinor
        self.currency = currency
        self.date = date
        self.person = person
        self.personNameSnapshot = person?.name
        self.linkedExpense = linkedExpense
        self.linkedExpenseSnapshot = linkedExpense.map(MoneyMovement.snapshot(of:))
        self.account = account
        self.counterAccount = counterAccount
        self.note = note
        self.transactionReference = transactionReference
        self.sourceTypeRaw = sourceType.rawValue
        self.paymentChannelRaw = paymentChannel.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: MoneyMovementKind {
        get { MoneyMovementKind(rawValue: kindRaw) ?? (direction == .moneyIn ? .otherIn : .otherOut) }
        set {
            kindRaw = newValue.rawValue
            directionRaw = newValue.direction.rawValue
        }
    }

    public var direction: MoneyDirection {
        MoneyDirection(rawValue: directionRaw) ?? .moneyOut
    }

    public var paymentChannel: PaymentChannel {
        PaymentChannel(rawValue: paymentChannelRaw) ?? .unknown
    }

    public var sourceType: ExpenseSourceType {
        ExpenseSourceType(rawValue: sourceTypeRaw) ?? .manual
    }

    /// Links a person and records their current name for history.
    public func setPerson(_ newPerson: PayBookProfile?) {
        person = newPerson
        personNameSnapshot = newPerson?.name
    }

    /// Links an expense (e.g. the purchase a refund belongs to) and records a readable summary for history.
    public func setLinkedExpense(_ expense: Expense?) {
        linkedExpense = expense
        linkedExpenseSnapshot = expense.map(MoneyMovement.snapshot(of:))
    }

    static func snapshot(of expense: Expense) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(expense.merchant) · \(expense.currency) \(String(format: "%.2f", expense.amount)) · \(formatter.string(from: expense.date))"
    }

    public enum ValidationIssue: Equatable {
        case nonPositiveAmount
        case missingPerson
        case missingTransferAccounts
        case sameTransferAccount
    }

    /// Problems that make this record unusable for calculations. Future UI must not save a record with issues.
    public var validationIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if amountMinor <= 0 { issues.append(.nonPositiveAmount) }
        if kind.requiresPerson && person == nil && (personNameSnapshot ?? "").isEmpty { issues.append(.missingPerson) }
        if kind == .ownTransfer {
            if account == nil || counterAccount == nil {
                issues.append(.missingTransferAccounts)
            } else if account?.id == counterAccount?.id {
                issues.append(.sameTransferAccount)
            }
        }
        return issues
    }
}
