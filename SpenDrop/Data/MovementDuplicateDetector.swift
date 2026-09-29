import Foundation
import SwiftData

/// Finds an existing Money In / Money Out / Transfer that looks like the same real-world transaction.
/// Only used to WARN ("Possible duplicate"); the user decides. Nothing is ever deleted or merged automatically.
public enum MovementDuplicateDetector {
    public static func findMatch(amountMinor: Int, date: Date, reference: String?, kind: MoneyMovementKind,
                                 excluding id: UUID? = nil, in context: ModelContext) -> MoneyMovement? {
        let movements = ((try? context.fetch(FetchDescriptor<MoneyMovement>())) ?? []).filter { $0.id != id }
        if let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty,
           let byReference = movements.first(where: { $0.transactionReference == reference }) {
            return byReference
        }
        return movements.first { movement in
            movement.amountMinor == amountMinor &&
            movement.kind.direction == kind.direction &&
            abs(movement.date.timeIntervalSince(date)) < 24 * 3600
        }
    }
}
