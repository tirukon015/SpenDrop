import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showingAddExpenseSheet = false
    @AppStorage("user_appearance") private var selectedAppearance = "system"

    public init() {}

    private var preferredColorScheme: ColorScheme? {
        switch selectedAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(0)

            ExpensesView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(1)

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(.blue)
    }
}
