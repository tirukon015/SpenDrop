import Foundation
import SwiftData

public struct SampleData {
    public static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()

        let samples: [(merchant: String, amount: Double, cat: ExpenseCategory, source: PaymentSource, daysAgo: Int, hoursAgo: Int, notes: String?)] = [
            ("McDonald's", 18.50, .food, .applePay, 0, 1, "Quick dinner"),
            ("MYDIN", 42.90, .groceries, .maybank, 0, 4, "Weekly essentials"),
            ("Grab", 6.00, .transport, .touchNGo, 0, 7, "Ride to office"),
            ("Mamak Mee Goreng", 12.00, .food, .cash, 0, 8, "Lunch"),
            ("Starbucks", 25.90, .food, .rhb, 1, 14, "Iced latte with team"),
            ("Shell Petrol", 50.00, .transport, .cimb, 1, 20, "Fuel refill"),
            ("Shopee", 79.90, .shopping, .touchNGo, 2, 30, "Desk cable organizer"),
            ("TNB Electricity", 145.20, .bills, .maybank, 3, 50, "Monthly utility bill"),
            ("Netflix", 44.90, .subscription, .physicalCard, 4, 75, "Monthly plan"),
            ("Watson's", 31.40, .health, .touchNGo, 5, 100, "Vitamins and medicine"),
            ("GSC Cinemas", 38.00, .entertainment, .applePay, 6, 120, "Movie weekend")
        ]

        for item in samples {
            let date = calendar.date(byAdding: .hour, value: -(item.daysAgo * 24 + item.hoursAgo), to: now) ?? now
            let expense = Expense(
                amount: item.amount,
                currency: "RM",
                merchant: item.merchant,
                category: item.cat,
                paymentSource: item.source,
                date: date,
                notes: item.notes,
                sourceType: item.source == .cash ? .manual : .screenshot
            )
            context.insert(expense)
        }

        try? context.save()
    }
}
