import Foundation
import SwiftData

/// Finds an existing Money In / Money Out / Transfer that looks like the same real-world transaction.
/// Only used to WARN ("Possible duplicate") for imports; the user decides. Nothing is ever deleted or merged
/// automatically, and manually entered records are never checked.
public enum MovementDuplicateDetector {
    public static func findMatch(amountMinor: Int, date: Date, reference: String?, kind: MoneyMovementKind,
                                 excluding id: UUID? = nil, in context: ModelContext) -> MoneyMovement? {
        let movements = ((try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []).filter { $0.id != id }
        return findMatch(amountMinor: amountMinor, date: date, reference: reference, kind: kind, among: movements)
    }

    /// The same rules applied to a given list of (possibly unsaved) movements, e.g. earlier Bulk Import drafts.
    public static func findMatch(amountMinor: Int, date: Date, reference: String?, kind: MoneyMovementKind,
                                 among movements: [MoneyMovement]) -> MoneyMovement? {
        if let reference = TransactionReconciliationEngine.normalizedReference(reference),
           let byReference = movements.first(where: { TransactionReconciliationEngine.normalizedReference($0.transactionReference) == reference }) {
            return byReference
        }
        // Same amount alone is never enough: only the same direction within a few minutes is worth a warning.
        return movements.first { movement in
            movement.amountMinor == amountMinor &&
            movement.kind.direction == kind.direction &&
            abs(movement.date.timeIntervalSince(date)) <= TransactionReconciliationEngine.weakMatchWindow
        }
    }
}
