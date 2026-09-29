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

