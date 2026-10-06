import Foundation
import SwiftData

/// The record types offered by the Add sheet. Expense stays the default.
public enum TransactionEntryType: String, CaseIterable, Identifiable {
    case expense
    case moneyIn
    case moneyOut
    case transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: return "Expense"
        case .moneyIn: return "Money In"
        case .moneyOut: return "Money Out"
        case .transfer: return "Transfer"
        }
    }

    public var icon: String {
        switch self {
        case .expense: return "cart"
        case .moneyIn: return "arrow.down.circle"
        case .moneyOut: return "arrow.up.right.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }

    /// Kinds offered for this entry type, most common first.
    public var kinds: [MoneyMovementKind] {
        switch self {
        case .expense: return []
        case .moneyIn: return [.income, .repaymentReceived, .loanReceived, .refund, .otherIn]
        case .moneyOut: return [.loanGiven, .repaymentMade, .otherOut]
        case .transfer: return [.ownTransfer]
        }
    }

    public init(kind: MoneyMovementKind) {
        switch kind.direction {
        case .moneyIn: self = .moneyIn
        case .moneyOut: self = .moneyOut
        case .internal: self = .transfer
        }
    }
}

/// Editable, validated form state for a Money In / Money Out / Transfer record.
/// Keeps validation out of the view so it can be tested.
public struct MoneyMovementDraft {
    public enum Issue: Equatable {
        case invalidAmount
        case missingPerson
        case missingFromAccount
        case missingToAccount
        case sameAccount

        public var message: String {
            switch self {
            case .invalidAmount: return "Enter an amount above RM0.00."
            case .missingPerson: return "Choose who this money is with."
            case .missingFromAccount: return "Choose the account the money left."
            case .missingToAccount: return "Choose the account the money went to."
            case .sameAccount: return "From and To must be different accounts."
            }
        }
    }

    public var entryType: TransactionEntryType
    public var kind: MoneyMovementKind
    public var amountText: String = ""
    public var currency: String = "RM"
    public var date: Date = Date()
    public var person: PayBookProfile?
    public var account: Account?
    public var counterAccount: Account?
    public var note: String = ""
    // Carried over from scans/imports so the saved record keeps its provenance.
    public var transactionReference: String?
    public var sourceType: ExpenseSourceType = .manual
    public var paymentChannel: PaymentChannel = .unknown

    public init(entryType: TransactionEntryType) {
        self.entryType = entryType
        self.kind = entryType.kinds.first ?? .otherOut
    }

    public init(movement: MoneyMovement) {
        self.entryType = TransactionEntryType(kind: movement.kind)
        self.kind = movement.kind
        self.amountText = String(format: "%.2f", Money.majorAmount(fromMinor: movement.amountMinor))
        self.currency = movement.currency
        self.date = movement.date
        self.person = movement.person
        self.account = movement.account
        self.counterAccount = movement.counterAccount
        self.note = movement.note ?? ""
        self.transactionReference = movement.transactionReference
        self.sourceType = movement.sourceType
        self.paymentChannel = movement.paymentChannel
    }

    /// Draft for a scanned screenshot the user chose to save as Money In / Money Out / Transfer.
    /// The account is resolved from the detected funding account (never invented; Unknown stays empty).
    public static func fromParsed(amount: Double, date: Date, fundingAccount: String, merchant: String, reference: String?,
                                  channel: PaymentChannel, walletSource: PaymentSource?, kind: MoneyMovementKind,
                                  source: ExpenseSourceType, in context: ModelContext) -> MoneyMovementDraft {
        var draft = MoneyMovementDraft(entryType: TransactionEntryType(kind: kind))
        draft.kind = kind
        draft.amountText = String(format: "%.2f", amount)
        draft.date = date
        draft.account = AccountLinker.resolveAccount(named: fundingAccount, in: context)
        if kind == .ownTransfer, let wallet = walletSource, [.touchNGo, .grabPay, .boost].contains(wallet) {
            let to = AccountLinker.resolveAccount(named: wallet.rawValue, in: context)
            if to?.id != draft.account?.id { draft.counterAccount = to }
        }
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.note = trimmed == "Unknown" ? "" : trimmed
        draft.transactionReference = reference
        draft.sourceType = source
        draft.paymentChannel = channel
        return draft
    }

    /// Switches entry type, picking that type's default kind.
    public mutating func setEntryType(_ newType: TransactionEntryType) {
        guard newType != entryType else { return }
        entryType = newType
        kind = newType.kinds.first ?? .otherOut
        if newType != .transfer { counterAccount = nil }
    }

    public var amountMinor: Int? { Money.minorUnits(parsing: amountText) }

    public var issues: [Issue] {
        var issues: [Issue] = []
        if (amountMinor ?? 0) <= 0 { issues.append(.invalidAmount) }
        if kind.requiresPerson && person == nil { issues.append(.missingPerson) }
        if kind == .ownTransfer {
            if account == nil { issues.append(.missingFromAccount) }
            if counterAccount == nil { issues.append(.missingToAccount) }
            if let from = account, let to = counterAccount, from.id == to.id { issues.append(.sameAccount) }
        }
        return issues
    }

    public var isValid: Bool { issues.isEmpty }

    /// Creates and inserts a new movement. Returns nil when the draft is invalid.
    @discardableResult
    public func insertMovement(into context: ModelContext, sourceType: ExpenseSourceType? = nil) -> MoneyMovement? {
        guard isValid, let amountMinor else { return nil }
        let movement = MoneyMovement(kind: kind, amountMinor: amountMinor, currency: currency, date: date,
                                     transactionReference: transactionReference, sourceType: sourceType ?? self.sourceType,
                                     paymentChannel: paymentChannel)
        context.insert(movement)
        apply(to: movement)
        return movement
    }

    /// Writes the draft into an existing movement (edit). Returns false when the draft is invalid.
    @discardableResult
    public func apply(to movement: MoneyMovement) -> Bool {
        guard isValid, let amountMinor else { return false }
        movement.kind = kind
        movement.amountMinor = amountMinor
        movement.currency = currency
        movement.date = date
        movement.setPerson(kind.requiresPerson ? person : nil)
        movement.account = account
        movement.counterAccount = kind == .ownTransfer ? counterAccount : nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        movement.note = trimmed.isEmpty ? nil : trimmed
        movement.updatedAt = Date()
        return true
    }
}
