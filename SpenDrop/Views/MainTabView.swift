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
    /// UI tests only: the Share Extension's review screen for an OCR-parsed RM 100 DuitNow QR receipt.
    @State private var shareReviewFixture: ShareExtensionViewModel? = MainTabView.makeShareReviewFixture()
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
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            ExpensesView()
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(1)

            PayBookView()
                .tabItem {
                    Label("PayBook", systemImage: "person.crop.rectangle.stack.fill")
                }
                .tag(2)

            AnalyticsView()
                .tabItem {
                    Label("Breakdown", systemImage: "chart.bar.xaxis")
                }
                .tag(3)

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(4)
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(.blue)
        .fullScreenCover(isPresented: Binding(get: { shareReviewFixture != nil }, set: { if !$0 { shareReviewFixture = nil } })) {
            if let fixture = shareReviewFixture {
                ShareExtensionView(viewModel: fixture, onComplete: { shareReviewFixture = nil }, onCancel: { shareReviewFixture = nil })
            }
        }
    }

    /// `--ui-testing --ui-testing-share-review`: the same review screen a shared screenshot opens after OCR,
    /// fed by the real parser. Never available outside UI tests (which use an isolated in-memory store).
    @MainActor
    private static func makeShareReviewFixture() -> ShareExtensionViewModel? {
        let args = ProcessInfo.processInfo.arguments
        guard ExpenseDataContainer.isUITesting, let flag = args.firstIndex(of: "--ui-testing-share-review") else { return nil }
        let amount = flag + 1 < args.count && Double(args[flag + 1]) != nil ? args[flag + 1] : "100.00"
        let lines = ["Transaction Details", "Successful", "- RM \(amount)", "Transaction Type", "DuitNow QR", "Merchant", "RESTORAN SELERA KAMPUNG",
                     "Payment Method", "eWallet Balance", "Date/Time", "06/10/2026 13:22", "Transaction No.", "2026100699990001"]
        let parsed = TransactionParser.shared.parse(ocrResult: PDFReceiptImporter.ocrResult(from: lines))
        let model = ShareExtensionViewModel()
        model.applyParsedTransaction(parsed)
        model.applySuggestions(parsed, in: ExpenseDataContainer.shared.mainContext)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        model.inputImage = image
        model.phase = .reviewing(image: image, parsed: parsed)
        return model
    }
}
