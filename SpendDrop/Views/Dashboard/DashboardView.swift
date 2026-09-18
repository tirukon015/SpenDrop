import SwiftUI
import SwiftData
import PhotosUI

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

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
        todayExpenses.reduce(0) { $0 + $1.amount }
    }

    // This week's spend
    private var thisWeekExpenses: [Expense] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return allExpenses.filter { weekInterval.contains($0.date) }
    }

    private var thisWeekTotal: Double {
        thisWeekExpenses.reduce(0) { $0 + $1.amount }
    }

    // This month's spend
    private var thisMonthExpenses: [Expense] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }
        return allExpenses.filter { monthInterval.contains($0.date) }
    }

    private var thisMonthTotal: Double {
        thisMonthExpenses.reduce(0) { $0 + $1.amount }
    }

    private var currentMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: now)
    }

    public init() {}

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
                                    print("[SpendDrop][PICKER_DIAG] Header PhotosPicker tapped")
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
                                            print("[SpendDrop][PICKER_DIAG] Empty State PhotosPicker tapped")
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
                print("[SpendDrop][PICKER_DIAG] selectedPhotoItem changed from \(oldItem != nil ? "non-nil" : "nil") to \(newItem != nil ? "non-nil" : "nil")")
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
            print("[SpendDrop][IMAGE] Picker selection: nil (cancelled or reset)")
            return
        }

        print("[SpendDrop][IMAGE] Picker selection received")
        print("[SpendDrop][IMAGE] supportedContentTypes = \(item.supportedContentTypes)")
        print("[SpendDrop][IMAGE] itemIdentifier = \(item.itemIdentifier ?? "nil")")

        isProcessingOCR = true
        HapticFeedback.impact(.light)

        // Stage 1: Load Data
        print("[SpendDrop][IMAGE] Loading Data...")
        let data: Data
        do {
            guard let loadedData = try await item.loadTransferable(type: Data.self) else {
                let err = "Data loaded from PhotosPickerItem was nil"
                print("[SpendDrop][IMAGE] Data loaded: FAIL (\(err))")
                handleImportFailure(stage: "Loading Data", error: NSError(domain: "SpendDrop.ImageImport", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                return
            }
            data = loadedData
            print("[SpendDrop][IMAGE] Data loaded: \(data.count) bytes")
        } catch {
            print("[SpendDrop][IMAGE] Loading Data FAILED: \(error)")
            handleImportFailure(stage: "Loading Data", error: error)
            return
        }

        // Stage 2: UIImage decode
        guard let uiImage = UIImage(data: data) else {
            let err = "Data (\(data.count) bytes) could not be decoded by UIImage(data:)"
            print("[SpendDrop][IMAGE] UIImage decode: FAIL (\(err))")
            handleImportFailure(stage: "UIImage decode", error: NSError(domain: "SpendDrop.ImageImport", code: -2, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpendDrop][IMAGE] UIImage decode: SUCCESS (size: \(uiImage.size), scale: \(uiImage.scale), orientation: \(uiImage.imageOrientation.rawValue))")

        // Stage 3: CGImage decode
        guard let cgImage = uiImage.cgImage ?? extractCGImage(from: uiImage) else {
            let err = "Failed to obtain CGImage from UIImage"
            print("[SpendDrop][IMAGE] CGImage decode: FAIL (\(err))")
            handleImportFailure(stage: "CGImage decode", error: NSError(domain: "SpendDrop.ImageImport", code: -3, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpendDrop][IMAGE] CGImage decode: SUCCESS (width: \(cgImage.width), height: \(cgImage.height))")

        // Stage 4: Downsampling check
        let maxSide = max(uiImage.size.width, uiImage.size.height)
        if maxSide > 2048 {
            print("[SpendDrop][IMAGE] Downsampling: NEEDED (original maxSide: \(maxSide))")
        } else {
            print("[SpendDrop][IMAGE] Downsampling: NOT NEEDED (original maxSide: \(maxSide) <= 2048)")
        }

        // Stage 5: Temporary storage diagnostic test (Bypass test)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).jpg")
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: tempURL)
                print("[SpendDrop][IMAGE] Temp save: SUCCESS (\(jpegData.count) bytes written to \(tempURL.lastPathComponent))")
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                print("[SpendDrop][IMAGE] Temp save: FAIL (\(error))")
            }
        } else {
            print("[SpendDrop][IMAGE] Temp save: FAIL (jpegData conversion failed)")
        }

        // Stage 6: App Group ImageStorageService diagnostic test
        if let savedRelPath = ImageStorageService.shared.saveImage(uiImage) {
            print("[SpendDrop][IMAGE] Image storage started & completed: SUCCESS (relativePath: \(savedRelPath))")
            ImageStorageService.shared.deleteImage(relativePath: savedRelPath)
        } else {
            print("[SpendDrop][IMAGE] Image storage: FAIL (App Group write failed)")
        }

        // Stage 7: OCR
        print("[SpendDrop][IMAGE] OCR started")
        let ocrResult: OCRResult
        do {
            ocrResult = try await OCRService.shared.recognizeText(from: uiImage)
            print("[SpendDrop][IMAGE] OCR completed: SUCCESS (lines: \(ocrResult.lines.count), avgConfidence: \(ocrResult.averageConfidence), textLength: \(ocrResult.fullText.count))")
            for (idx, line) in ocrResult.lines.prefix(5).enumerated() {
                print("[SpendDrop][IMAGE] Line \(idx + 1): \"\(line.text)\" (conf: \(line.confidence))")
            }
        } catch {
            print("[SpendDrop][IMAGE] OCR FAILED: \(error)")
            handleImportFailure(stage: "Vision OCR", error: error)
            return
        }

        // Stage 8: Parser
        print("[SpendDrop][IMAGE] Parser started")
        let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: uiImage)
        print("[SpendDrop][IMAGE] Parser completed: amount: \(parsed.amount != nil ? "RM\(parsed.amount!)" : "nil"), merchant: \(parsed.merchant ?? "nil"), source: \(parsed.paymentSource?.rawValue ?? "nil"), category: \(parsed.category?.rawValue ?? "nil"), confidence: \(parsed.confidence.rawValue), isBalance: \(parsed.isBalanceOrLimitOnly), isFailed: \(parsed.isFailedTransaction)")

        isProcessingOCR = false
        selectedPhotoItem = nil
        HapticFeedback.notification(.success)
        print("[SpendDrop][IMAGE] Review screen opened")
        self.parsedTransaction = parsed
    }

    @MainActor
    private func handleImportFailure(stage: String, error: Error) {
        isProcessingOCR = false
        selectedPhotoItem = nil
        ocrErrorMessage = "Failed at [\(stage)]:\n\(error.localizedDescription)"
        showingOCRError = true
        HapticFeedback.notification(.error)
        print("[SpendDrop][IMAGE] PIPELINE FAILURE at [\(stage)]: \(error)")
    }

    private func extractCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        if let ci = image.ciImage {
            return CIContext(options: nil).createCGImage(ci, from: ci.extent)
        }
        return nil
    }
}


