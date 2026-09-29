import Foundation

/// Per-person balances and history, always calculated from ExpenseShare, Expense.payer and MoneyMovement.
/// Positive = they owe me; negative = I owe them. Nothing is stored.
public enum PersonLedger {
    public struct Entry: Identifiable {
        public enum Source {
            case expense(Expense)
            case movement(MoneyMovement)
        }

        public let id: UUID
        public let date: Date
        public let title: String
        public let detail: String
        /// Change to "what they owe me" in minor units (0 = recorded but does not affect our balance).
        public let effectMinor: Int
        public let currency: String
        public let source: Source
    }

