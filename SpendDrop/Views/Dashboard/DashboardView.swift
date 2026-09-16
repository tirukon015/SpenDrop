import SwiftUI
import SwiftData

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @State private var showingAddExpense = false
    @State private var initialAddPaymentSource: PaymentSource = .cash
    @State private var selectedExpenseForDetail: Expense?

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

                        // Quick Cash Button
                        QuickCashButton {
                            initialAddPaymentSource = .cash
                            showingAddExpense = true
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

                                Button(action: {
                                    initialAddPaymentSource = .cash
                                    showingAddExpense = true
                                }) {
                                    Label("Add Expense", systemImage: "plus.circle.fill")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
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

                    // RECENT EXPENSES (if no today or just general activity)
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
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(initialPaymentSource: initialAddPaymentSource)
            }
            .sheet(item: $selectedExpenseForDetail) { expense in
                ExpenseDetailView(expense: expense)
            }
        }
    }
}
