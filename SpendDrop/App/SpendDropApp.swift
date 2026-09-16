import SwiftUI
import SwiftData

@main
struct SpendDropApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(ExpenseDataContainer.shared)
    }
}
