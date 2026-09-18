import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--tab"), idx + 1 < args.count, let t = Int(args[idx + 1]) {
            return t
        }
        return 0
    }()
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

            PayBookView()
                .tabItem {
                    Label("PayBook", systemImage: "person.crop.rectangle.stack.fill")
                }
                .tag(2)

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(.blue)
    }
}
