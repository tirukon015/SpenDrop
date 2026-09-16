import SwiftUI
import SwiftData
import PhotosUI

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
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
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                        .frame(width: 36, height: 36)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(Circle())
                                }

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

                                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                            Label("Drop Screenshot", systemImage: "viewfinder.rectangular")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color.blue)
                                                .clipShape(Capsule())
                                        }
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

                        // RECENT EXPENSES (if no today or general activity)
                        if todayExpenses.isEmpty && !allExpenses.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Recent Activity")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                VStack(spacing: 0) {
                                    ForEach(Array(allExpenses.prefix(5))) { expense in
                                        Button(action: {
                                            selectedExpenseForDetail = expense
                                        }) {
                                            ExpenseRowView(expense: expense)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                        }
                                        .buttonStyle(.plain)

                                        if expense != Array(allExpenses.prefix(5)).last {
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
                .id(scenePhase)

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
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await processSelectedImage(item: newItem)
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(initialPaymentSource: initialAddPaymentSource)
            }
            .sheet(item: $selectedExpenseForDetail) { expense in
                ExpenseDetailView(expense: expense)
            }
            .sheet(item: $parsedTransaction) { parsed in
                ExpenseReviewView(parsed: parsed)
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

    private func processSelectedImage(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isProcessingOCR = true
        HapticFeedback.impact(.light)

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                throw OCRError.invalidImage
            }

            let ocrResult = try await OCRService.shared.recognizeText(from: uiImage)
            let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: uiImage)

            await MainActor.run {
                isProcessingOCR = false
                HapticFeedback.notification(.success)
                self.parsedTransaction = parsed
            }
        } catch {
            await MainActor.run {
                isProcessingOCR = false
                ocrErrorMessage = error.localizedDescription
                showingOCRError = true
                HapticFeedback.notification(.error)
            }
        }
    }
}
