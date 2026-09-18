import Foundation
import SwiftData

@MainActor
public final class ExpenseDataContainer {
    public static let shared: ModelContainer = {
        let schema = Schema([Expense.self, PayBookContact.self])
        let appGroupIdentifier = "group.com.spenddrop.shared"
        
        var modelConfiguration: ModelConfiguration
        
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let storeURL = containerURL.appendingPathComponent("SpendDrop.store")
            modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to initialize configured container: \(error). Falling back to default.")
            do {
                return try ModelContainer(for: schema)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    public static let previewContainer: ModelContainer = {
        let schema = Schema([Expense.self, PayBookContact.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            SampleData.seed(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

    public static func seedInitialDataIfNeeded() {
        let defaults = UserDefaults.standard
        let seededKey = "has_seeded_initial_sample_data_v1"
        guard !defaults.bool(forKey: seededKey) else { return }

        let context = ExpenseDataContainer.shared.mainContext
        var descriptor = FetchDescriptor<Expense>()
        descriptor.fetchLimit = 1
        let count = (try? context.fetchCount(descriptor)) ?? 0
        if count == 0 {
            SampleData.seed(into: context)
        }
        defaults.set(true, forKey: seededKey)
    }

    public static func handlePayBookLaunchArguments(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--clear-paybook") {
            let desc = FetchDescriptor<PayBookContact>()
            if let items = try? context.fetch(desc) {
                for item in items { context.delete(item) }
                try? context.save()
            }
        }
        if args.contains("--seed-paybook") {
            let desc = FetchDescriptor<PayBookContact>()
            let count = (try? context.fetchCount(desc)) ?? 0
            if count == 0 {
                seedSamplePayBookContacts(into: context)
            }
        }
    }

    public static func seedSamplePayBookContacts(into context: ModelContext) {
        let samples = [
            PayBookContact(
                name: "Rahim",
                bankName: "Maybank",
                accountHolderName: "Abdul Rahim Bin Osman",
                accountNumber: "1234567890",
                phoneNumber: "012-345 6789"
            ),
            PayBookContact(
                name: "Ahmad",
                bankName: "CIMB",
                accountHolderName: "Ahmad Farhan",
                accountNumber: "9876543210",
                phoneNumber: "017-890 1234"
            ),
            PayBookContact(
                name: "Siti Nurhaliza",
                bankName: "RHB Bank",
                accountHolderName: "Siti Nurhaliza Binti Tarudin",
                accountNumber: "21415600192837",
                phoneNumber: "019-988 7766"
            )
        ]
        for s in samples {
            context.insert(s)
        }
        try? context.save()
    }
}
