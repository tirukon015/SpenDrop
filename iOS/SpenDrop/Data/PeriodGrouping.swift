import Foundation

/// Groups spending and cash flow into consecutive days / weeks / months for trend charts. Pure; minor units.
public enum PeriodGrouping {
    public enum Granularity: String, CaseIterable, Identifiable {
        case daily = "Daily", weekly = "Weekly", monthly = "Monthly"
        public var id: String { rawValue }

        /// How many periods a trend shows.
        public var defaultCount: Int {
            switch self {
            case .daily: return 7
            case .weekly: return 8
            case .monthly: return 6
            }
        }

        var component: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            }
        }
    }

    public struct Bucket: Identifiable, Equatable {
        public var id: Date { start }
        public let start: Date
        public let label: String
        public var spendingMinor = 0
        public var inMinor = 0
        public var outMinor = 0
        public var netMinor: Int { inMinor - outMinor }
    }

    /// The last `count` periods ending with the one containing `now`, oldest first. Own transfers are excluded.
    public static func buckets(expenses: [Expense], movements: [MoneyMovement], granularity: Granularity,
                               count: Int? = nil, now: Date = Date(), currency: String = "RM",
                               calendar: Calendar = .current) -> [Bucket] {
        let n = max(1, count ?? granularity.defaultCount)
        guard let current = calendar.dateInterval(of: granularity.component, for: now) else { return [] }
        let formatter = DateFormatter()
        switch granularity {
        case .daily: formatter.dateFormat = "EEE d"
        case .weekly: formatter.dateFormat = "d MMM"
        case .monthly: formatter.dateFormat = "MMM"
        }

        var buckets: [Bucket] = []
        for offset in stride(from: n - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: granularity.component, value: -offset, to: current.start) else { continue }
            buckets.append(Bucket(start: start, label: formatter.string(from: start)))
        }
        guard let first = buckets.first?.start, let end = calendar.date(byAdding: granularity.component, value: 1, to: current.start) else {
            return buckets
        }

        func index(for date: Date) -> Int? {
            guard date >= first && date < end else { return nil }
            return buckets.lastIndex { $0.start <= date }
        }

        for expense in expenses where expense.currency == currency {
            guard let i = index(for: expense.date) else { continue }
            buckets[i].spendingMinor += expense.spendingMinor
            buckets[i].outMinor += expense.cashOutMinor
        }
        for movement in movements where movement.currency == currency {
            guard let i = index(for: movement.date) else { continue }
            switch movement.kind.direction {
            case .moneyIn: buckets[i].inMinor += movement.amountMinor
            case .moneyOut: buckets[i].outMinor += movement.amountMinor
            case .internal: break
            }
        }
        return buckets
    }
}
