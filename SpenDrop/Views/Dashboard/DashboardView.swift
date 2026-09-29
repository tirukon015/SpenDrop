import SwiftUI
import SwiftData
import PhotosUI

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query(sort: \MoneyMovement.date, order: .reverse) private var allMovements: [MoneyMovement]
    @Query private var people: [PayBookProfile]

    @State private var showingAddExpense = false
    @State private var initialAddPaymentSource: PaymentSource = .cash
    @State private var selectedExpenseForDetail: Expense?

    // Direct Dashboard Screenshot Drop / Scan
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var parsedTransaction: ParsedTransaction?
    @State private var showingOCRError = false
    @State private var ocrErrorMessage = ""

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    // Today's spend
    private var todayExpenses: [Expense] {
        allExpenses.filter { calendar.isDateInToday($0.date) }
    }

    private var todayTotal: Double {
        todayExpenses.reduce(0) { $0 + $1.spendingAmount }
    }

    // This week's spend
    private var thisWeekExpenses: [Expense] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return allExpenses.filter { weekInterval.contains($0.date) }
    }

    private var thisWeekTotal: Double {
        thisWeekExpenses.reduce(0) { $0 + $1.spendingAmount }
    }

    // This month's spend
    private var thisMonthExpenses: [Expense] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }
        return allExpenses.filter { monthInterval.contains($0.date) }
    }

    private var thisMonthTotal: Double {
        thisMonthExpenses.reduce(0) { $0 + $1.spendingAmount }
    }

    // Cash flow this month (own transfers excluded). Only shown once money in/out has been recorded.
    private var thisMonthMovements: [MoneyMovement] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }
        return allMovements.filter { monthInterval.contains($0.date) }
    }

    private var monthCashFlow: FinancialCalculator.Summary {
        FinancialCalculator.summary(expenses: thisMonthExpenses, movements: thisMonthMovements)
    }

    private var sharedThisMonth: [Expense] { thisMonthExpenses.filter(\.isShared) }

    private func formatMinor(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor))
    }

    private var currentMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: now)
    }

    public init() {}

    @ViewBuilder
    private var secondaryCards: some View {
        let balances = PersonLedger.summary(of: people)
        let owed = balances.owedToMe["RM"] ?? 0
        let owe = balances.iOwe["RM"] ?? 0
        VStack(spacing: 12) {
            if !sharedThisMonth.isEmpty {
                HStack {
                    Image(systemName: "person.2.fill").foregroundStyle(.blue)
                    Text("My share of \(sharedThisMonth.count) shared expense\(sharedThisMonth.count == 1 ? "" : "s") this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMinor(sharedThisMonth.reduce(0) { $0 + $1.myShareMinor }))
                        .font(.caption.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }

            if !thisMonthMovements.isEmpty {
                let flow = monthCashFlow
                homeCard(title: "CASH FLOW · THIS MONTH", icon: "arrow.left.arrow.right", tint: .teal) {
                    HStack {
                        metric("Money In", formatMinor(flow.moneyInMinor), .green)
                        metric("Money Out", formatMinor(flow.moneyOutMinor), .primary)
                        metric("Net", (flow.netCashFlowMinor >= 0 ? "+" : "") + formatMinor(flow.netCashFlowMinor),
                               flow.netCashFlowMinor >= 0 ? .green : .orange)
                    }
                }
                .accessibilityIdentifier("home.cashFlow")
            }

            if owed != 0 || owe != 0 {
                homeCard(title: "BALANCES", icon: "person.2", tint: .purple) {
                    HStack {
                        if owed != 0 { metric("Owed to you", formatMinor(owed), .green) }
                        if owe != 0 { metric("You owe", formatMinor(owe), .orange) }
                        Spacer()
                    }
                }
                .accessibilityIdentifier("home.balances")
            }
        }
    }

    private func homeCard<Content: View>(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Image(systemName: icon).foregroundStyle(tint)
            }
            content()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // DATE BANNER & QUICK ACTIONS
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentMonthYearString)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                Text("Dashboard")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                // Scan / Drop Screenshot shortcut
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .current) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                        .frame(width: 36, height: 36)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    print("[SpenDrop][PICKER_DIAG] Header PhotosPicker tapped")
                                })

                                // Quick Cash Button
                                QuickCashButton {
                                    initialAddPaymentSource = .cash
                                    showingAddExpense = true
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)

                        // SUMMARY TOTALS CARDS
                        VStack(spacing: 12) {
                            // TODAY HERO CARD
                            SpendingSummaryCard(
                                title: "Today",
                                amount: todayTotal,
                                currency: "RM",
                                icon: "sun.max.fill",
                                tintColor: .orange
                            )

                            // THIS WEEK & THIS MONTH ROW
                            HStack(spacing: 12) {
                                SpendingSummaryCard(
                                    title: "This Week",
                                    amount: thisWeekTotal,
                                    currency: "RM",
                                    icon: "calendar.badge.clock",
                                    tintColor: .blue
                                )

                                SpendingSummaryCard(
                                    title: "This Month",
                                    amount: thisMonthTotal,
                                    currency: "RM",
                                    icon: "chart.bar.fill",
                                    tintColor: .green
                                )
                            }
                        }
                        .padding(.horizontal)

                        // TODAY'S EXPENSES LIST
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Today's Expenses")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Spacer()

                                if !todayExpenses.isEmpty {
                                    Text("\(todayExpenses.count) transactions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)

                            if todayExpenses.isEmpty {
                                // Empty state
                                VStack(spacing: 12) {
                                    Image(systemName: "wallet.pass")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 16)

                                    Text("No expenses recorded today")
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text("Add a cash expense or drop a payment screenshot.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)

                                    HStack(spacing: 12) {
                                        Button(action: {
                                            initialAddPaymentSource = .cash
                                            showingAddExpense = true
                                        }) {
                                            Label("Quick Cash", systemImage: "banknote.fill")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color.green)
                                                .clipShape(Capsule())
                                        }

                                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .current) {
                                            Label("Drop Screenshot", systemImage: "viewfinder.rectangular")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color.blue)
                                                .clipShape(Capsule())
                                        }
                                        .simultaneousGesture(TapGesture().onEnded {
                                            print("[SpenDrop][PICKER_DIAG] Empty State PhotosPicker tapped")
                                        })
                                    }
                                    .padding(.vertical, 8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal)
                            } else {
                                // List of today's expenses
                                VStack(spacing: 0) {
                                    ForEach(todayExpenses) { expense in
                                        Button(action: {
                                            selectedExpenseForDetail = expense
                                        }) {
                                            ExpenseRowView(expense: expense)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                        }
                                        .buttonStyle(.plain)

                                        if expense != todayExpenses.last {
                                            Divider()
                                                .padding(.leading, 74)
                                        }
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal)
                            }
                        }

                        // RECENT EXPENSES (shows recent transactions even when today has expenses)
                        let recentNonTodayExpenses = allExpenses.filter { !calendar.isDateInToday($0.date) }
                        if !recentNonTodayExpenses.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Recent Activity")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding(.horizontal)

                                VStack(spacing: 0) {
                                    ForEach(Array(recentNonTodayExpenses.prefix(5))) { expense in
                                        Button(action: {
                                            selectedExpenseForDetail = expense
                                        }) {
                                            ExpenseRowView(expense: expense)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                        }
                                        .buttonStyle(.plain)

                                        if expense != Array(recentNonTodayExpenses.prefix(5)).last {
                                            Divider()
                                                .padding(.leading, 74)
                                        }
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }

                // PROCESSING OCR OVERLAY
                if isProcessingOCR {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Reading transaction...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        initialAddPaymentSource = .cash
                        showingAddExpense = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { oldItem, newItem in
                print("[SpenDrop][PICKER_DIAG] selectedPhotoItem changed from \(oldItem != nil ? "non-nil" : "nil") to \(newItem != nil ? "non-nil" : "nil")")
                Task {
                    await processSelectedImage(item: newItem)
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(initialPaymentSource: initialAddPaymentSource)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(item: $selectedExpenseForDetail) { expense in
                ExpenseDetailView(expense: expense)
            }
            .sheet(item: $parsedTransaction) { parsed in
                ExpenseReviewView(parsed: parsed)
                    .environment(\.modelContext, modelContext)
            }
            .alert("Couldn't read this image", isPresented: $showingOCRError) {
                Button("Try Again") {
                    selectedPhotoItem = nil
                }
                Button("Add Manually", role: .cancel) {
                    selectedPhotoItem = nil
                    showingAddExpense = true
                }
            } message: {
                Text(ocrErrorMessage.isEmpty ? "No clear transaction information could be extracted from this image." : ocrErrorMessage)
            }
        }
    }

    @MainActor
    private func processSelectedImage(item: PhotosPickerItem?) async {
        guard let item = item else {
            print("[SpenDrop][IMAGE] Picker selection: nil (cancelled or reset)")
            return
        }

        print("[SpenDrop][IMAGE] Picker selection received")
        print("[SpenDrop][IMAGE] supportedContentTypes = \(item.supportedContentTypes)")
        print("[SpenDrop][IMAGE] itemIdentifier = \(item.itemIdentifier ?? "nil")")

        isProcessingOCR = true
        HapticFeedback.impact(.light)

        // Stage 1: Load Data
        print("[SpenDrop][IMAGE] Loading Data...")
        let data: Data
        do {
            guard let loadedData = try await item.loadTransferable(type: Data.self) else {
                let err = "Data loaded from PhotosPickerItem was nil"
                print("[SpenDrop][IMAGE] Data loaded: FAIL (\(err))")
                handleImportFailure(stage: "Loading Data", error: NSError(domain: "SpenDrop.ImageImport", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                return
            }
            data = loadedData
            print("[SpenDrop][IMAGE] Data loaded: \(data.count) bytes")
        } catch {
            print("[SpenDrop][IMAGE] Loading Data FAILED: \(error)")
            handleImportFailure(stage: "Loading Data", error: error)
            return
        }

        // Stage 2: UIImage decode
        guard let uiImage = UIImage(data: data) else {
            let err = "Data (\(data.count) bytes) could not be decoded by UIImage(data:)"
            print("[SpenDrop][IMAGE] UIImage decode: FAIL (\(err))")
            handleImportFailure(stage: "UIImage decode", error: NSError(domain: "SpenDrop.ImageImport", code: -2, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpenDrop][IMAGE] UIImage decode: SUCCESS (size: \(uiImage.size), scale: \(uiImage.scale), orientation: \(uiImage.imageOrientation.rawValue))")

        // Stage 3: CGImage decode
        guard let cgImage = uiImage.cgImage ?? extractCGImage(from: uiImage) else {
            let err = "Failed to obtain CGImage from UIImage"
            print("[SpenDrop][IMAGE] CGImage decode: FAIL (\(err))")
            handleImportFailure(stage: "CGImage decode", error: NSError(domain: "SpenDrop.ImageImport", code: -3, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpenDrop][IMAGE] CGImage decode: SUCCESS (width: \(cgImage.width), height: \(cgImage.height))")

        // Stage 4: Downsampling check
        let maxSide = max(uiImage.size.width, uiImage.size.height)
        if maxSide > 2048 {
            print("[SpenDrop][IMAGE] Downsampling: NEEDED (original maxSide: \(maxSide))")
        } else {
            print("[SpenDrop][IMAGE] Downsampling: NOT NEEDED (original maxSide: \(maxSide) <= 2048)")
        }

        // Stage 5: Temporary storage diagnostic test (Bypass test)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).jpg")
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: tempURL)
                print("[SpenDrop][IMAGE] Temp save: SUCCESS (\(jpegData.count) bytes written to \(tempURL.lastPathComponent))")
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                print("[SpenDrop][IMAGE] Temp save: FAIL (\(error))")
            }
        } else {
            print("[SpenDrop][IMAGE] Temp save: FAIL (jpegData conversion failed)")
        }

        // Stage 6: App Group ImageStorageService diagnostic test
        if let savedRelPath = ImageStorageService.shared.saveImage(uiImage) {
            print("[SpenDrop][IMAGE] Image storage started & completed: SUCCESS (relativePath: \(savedRelPath))")
            ImageStorageService.shared.deleteImage(relativePath: savedRelPath)
        } else {
            print("[SpenDrop][IMAGE] Image storage: FAIL (App Group write failed)")
        }

        // Stage 7: OCR
        print("[SpenDrop][IMAGE] OCR started")
        let ocrResult: OCRResult
        do {
            ocrResult = try await OCRService.shared.recognizeText(from: uiImage)
            print("[SpenDrop][IMAGE] OCR completed: SUCCESS (lines: \(ocrResult.lines.count), avgConfidence: \(ocrResult.averageConfidence), textLength: \(ocrResult.fullText.count))")
            for (idx, line) in ocrResult.lines.prefix(5).enumerated() {
                print("[SpenDrop][IMAGE] Line \(idx + 1): \"\(line.text)\" (conf: \(line.confidence))")
            }
        } catch {
            print("[SpenDrop][IMAGE] OCR FAILED: \(error)")
            handleImportFailure(stage: "Vision OCR", error: error)
            return
        }

        // Stage 8: Parser
        print("[SpenDrop][IMAGE] Parser started")
        let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: uiImage)
        print("[SpenDrop][IMAGE] Parser completed: amount: \(parsed.amount != nil ? "RM\(parsed.amount!)" : "nil"), merchant: \(parsed.merchant ?? "nil"), source: \(parsed.paymentSource?.rawValue ?? "nil"), category: \(parsed.category?.rawValue ?? "nil"), confidence: \(parsed.confidence.rawValue), isBalance: \(parsed.isBalanceOrLimitOnly), isFailed: \(parsed.isFailedTransaction)")

        isProcessingOCR = false
        selectedPhotoItem = nil
        HapticFeedback.notification(.success)
        print("[SpenDrop][IMAGE] Review screen opened")
        self.parsedTransaction = parsed
    }

    @MainActor
    private func handleImportFailure(stage: String, error: Error) {
        isProcessingOCR = false
        selectedPhotoItem = nil
        ocrErrorMessage = "Failed at [\(stage)]:\n\(error.localizedDescription)"
        showingOCRError = true
        HapticFeedback.notification(.error)
        print("[SpenDrop][IMAGE] PIPELINE FAILURE at [\(stage)]: \(error)")
    }

    private func extractCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        if let ci = image.ciImage {
            return CIContext(options: nil).createCGImage(ci, from: ci.extent)
        }
        return nil
    }
}


