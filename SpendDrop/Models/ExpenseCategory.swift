import SwiftUI

public enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case food = "Food"
    case groceries = "Groceries"
    case transport = "Transport"
    case shopping = "Shopping"
    case bills = "Bills"
    case entertainment = "Entertainment"
    case education = "Education"
    case health = "Health"
    case travel = "Travel"
    case personal = "Personal"
    case subscription = "Subscription"
    case other = "Other"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .groceries: return "cart.fill"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .bills: return "bolt.fill"
        case .entertainment: return "tv.fill"
        case .education: return "book.fill"
        case .health: return "heart.fill"
        case .travel: return "airplane"
        case .personal: return "person.fill"
        case .subscription: return "repeat.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .food: return .orange
        case .groceries: return .green
        case .transport: return .blue
        case .shopping: return .pink
        case .bills: return .red
        case .entertainment: return .purple
        case .education: return .indigo
        case .health: return .mint
        case .travel: return .teal
        case .personal: return .cyan
        case .subscription: return .yellow
        case .other: return .gray
        }
    }
}
