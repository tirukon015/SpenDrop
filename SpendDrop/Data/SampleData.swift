import Foundation
import SwiftData

public struct SampleData {
    public static func seed(into context: ModelContext) {
        // Idempotency: Check if sample records already exist to prevent duplicate dummy records
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { expense in
                expense.isSampleData == true
            }
        )
        descriptor.fetchLimit = 1
        if let existingCount = try? context.fetchCount(descriptor), existingCount > 0 {
            print("[SpendDrop][SampleData] Sample data already exists, skipping idempotent seed.")
            return
        }

        let calendar = Calendar.current
        let now = Date()

        // 18 realistic Malaysian test expenses spanning Today, This Week, and This Month
        let samples: [(
            merchant: String,
            amount: Double,
            category: ExpenseCategory,
            paymentSource: PaymentSource,
            daysAgo: Int,
            hoursAgo: Int,
            notes: String?,
            reference: String?,
            sourceType: ExpenseSourceType
        )] = [
            // TODAY (daysAgo: 0) - tests Today totals & Dashboard top card
            ("McDonald's", 18.50, .food, .touchNGo, 0, 1, "Quick dinner [Sample]", "DEMO-TNG-104928", .shareExtension),
            ("Grab", 14.80, .transport, .rhb, 0, 3, "Ride to meeting [Sample]", "DEMO-RHB-551029", .screenshot),
            ("Mamak", 11.50, .food, .cash, 0, 5, "Roti canai & teh tarik [Sample]", nil, .manual),
            ("7-Eleven", 12.50, .groceries, .cash, 0, 7, "Snacks and bottled water [Sample]", nil, .manual),

            // THIS WEEK (daysAgo: 1-4) - tests This Week totals & History grouping (Yesterday, day names)
            ("Starbucks", 25.90, .food, .applePay, 1, 2, "Iced caramel macchiato [Sample]", "DEMO-APL-771829", .screenshot),
            ("GrabFood", 22.40, .food, .touchNGo, 1, 6, "Nasi lemak delivery [Sample]", "DEMO-TNG-330192", .shareExtension),
            ("Shell", 50.00, .transport, .cimb, 2, 4, "Fuel refill RON95 [Sample]", "DEMO-CIMB-481902", .screenshot),
            ("University supplies", 35.00, .education, .cash, 2, 8, "Notebooks and stationery [Sample]", nil, .manual),
            ("MYDIN", 42.90, .groceries, .maybank, 3, 5, "Weekly pantry items [Sample]", "DEMO-MBB-983102", .screenshot),
            ("Cinema", 32.00, .entertainment, .applePay, 4, 3, "Movie tickets weekend [Sample]", "DEMO-APL-441029", .screenshot),

            // THIS MONTH (daysAgo: 6-23) - tests This Month totals & Analytics charts
            ("Pharmacy", 28.60, .health, .rhb, 6, 2, "Vitamin C & essentials [Sample]", "DEMO-RHB-991820", .screenshot),
            ("Shopee", 89.90, .shopping, .maybank, 8, 4, "USB hub & desk organizer [Sample]", "DEMO-MBB-662910", .screenshot),
            ("Petrol", 60.00, .transport, .touchNGo, 11, 6, "Highway petrol refill [Sample]", "DEMO-TNG-552910", .screenshot),
            ("Groceries", 68.40, .groceries, .maybank, 14, 3, "Fresh vegetables and fruits [Sample]", "DEMO-MBB-119283", .receipt),
            ("Netflix", 17.00, .subscription, .cimb, 16, 5, "Monthly subscription [Sample]", "DEMO-CIMB-129034", .screenshot),
            ("Personal item", 24.90, .personal, .cash, 18, 4, "Barber haircut [Sample]", nil, .manual),
            ("Electricity", 75.30, .bills, .bankTransfer, 20, 7, "TNB electricity bill [Sample]", "DEMO-FPX-881920", .screenshot),
            ("Clothing", 120.00, .shopping, .physicalCard, 23, 2, "Uniqlo work shirts [Sample]", "DEMO-CRD-772910", .receipt)
        ]

        for item in samples {
            let targetDate = calendar.date(byAdding: .hour, value: -(item.daysAgo * 24 + item.hoursAgo), to: now) ?? now
            let expense = Expense(
                amount: item.amount,
                currency: "RM",
                merchant: item.merchant,
                category: item.category,
                paymentSource: item.paymentSource,
                date: targetDate,
                notes: item.notes,
                transactionReference: item.reference,
                sourceType: item.sourceType,
                isSampleData: true
            )
            context.insert(expense)
        }

        try? context.save()
    }
}
