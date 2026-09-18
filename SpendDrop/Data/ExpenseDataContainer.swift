import Foundation
import SwiftData

@MainActor
public final class ExpenseDataContainer {
    public static let shared: ModelContainer = {
        let schema = Schema([Expense.self])
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
        let schema = Schema([Expense.self])
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
}
