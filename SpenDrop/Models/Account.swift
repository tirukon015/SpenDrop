import Foundation
import SwiftData

public enum AccountType: String, CaseIterable, Codable, Identifiable {
    case bank = "bank"
    case eWallet = "eWallet"
    case cash = "cash"
    case other = "other"

    public var id: String { rawValue }
}

/// Where a transaction came from or went to (e.g. Maybank, Touch 'n Go, Cash).
/// Deliberately has NO balance: SpenDrop does not know real bank balances. Accounts only group recorded transactions.
@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var typeRaw: String
    public var currency: String
    public var icon: String?
    public var isArchived: Bool = false
    public var createdAt: Date
    public var sortIndex: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Expense.account)
    public var expenses: [Expense] = []

    @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.account)
    public var movements: [MoneyMovement] = []

    /// Own transfers that moved money INTO this account.
    @Relationship(deleteRule: .nullify, inverse: \MoneyMovement.counterAccount)
    public var incomingTransfers: [MoneyMovement] = []

