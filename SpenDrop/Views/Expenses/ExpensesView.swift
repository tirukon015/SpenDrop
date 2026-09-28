import SwiftUI
import SwiftData

public struct ExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @Bindable private var engine = TransactionFilterEngine.shared

    @State private var searchText = ""
    @State private var selectedExpense: Expense?
    @State private var showingAddExpense = false

    // Secondary controls state (moved inside ⋯)
    @State private var showingCustomDatePicker = false
    @State private var showingAccountsSheet = false
    @State private var showingCategoriesSheet = false
    @State private var showingPaymentChannelsSheet = false

    public enum ExpenseSortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
    }
    @State private var sortOrder: ExpenseSortOrder = .newestFirst

    public init() {}

    // Group filtered expenses by calendar day
    private var groupedExpenses: [(dateHeader: String, dateSubtitle: String?, date: Date, expenses: [Expense])] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        let sortedList = engine.filteredExpenses.sorted { exp1, exp2 in
            sortOrder == .newestFirst ? exp1.date > exp2.date : exp1.date < exp2.date
        }

        let grouped = Dictionary(grouping: sortedList) { (expense: Expense) -> String in
            dateFormatter.string(from: expense.date)
        }

        return grouped.compactMap { (dateKey: String, expenses: [Expense]) in
            guard let firstDate = expenses.first?.date else { return nil }
            let dayStart = calendar.startOfDay(for: firstDate)

            let header: String
            let subtitle: String?

            if calendar.isDateInToday(firstDate) {
                header = "Today"
                subtitle = dateKey
            } else if calendar.isDateInYesterday(firstDate) {
                header = "Yesterday"
                subtitle = dateKey
            } else {
                header = dateKey
                subtitle = nil
            }

            return (dateHeader: header, dateSubtitle: subtitle, date: dayStart, expenses: expenses)
        }
        .sorted { g1, g2 in
            sortOrder == .newestFirst ? g1.date > g2.date : g1.date < g2.date
        }
    }

    private var activeDimensionSummary: String? {
        var parts: [String] = []
        if !engine.selectedFundingAccounts.isEmpty {
            parts.append(engine.accountsSummaryLabel)
        }
        if !engine.selectedCategories.isEmpty {
            parts.append(engine.categoriesSummaryLabel)
        }
        if !engine.selectedPaymentChannels.isEmpty {
            parts.append(engine.paymentChannelsSummaryLabel)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - COMPACT CONTROL BAR: [ Last 7 Days ▾ ] ... [ ⋯ ]
                HStack(spacing: 8) {
                    // Date range compact dropdown (Default: Last 7 Days)
                    Menu {
                        Section("Date Range") {
                            compactDateButton(.last7Days)
                            compactDateButton(.last30Days)
                            compactDateButton(.thisMonth)
                            compactDateButton(.today)
                            compactDateButton(.yesterday)
                            compactDateButton(.thisWeek)
                            compactDateButton(.lastWeek)
                            compactDateButton(.lastMonth)

                            Button {
                                showingCustomDatePicker = true
                            } label: {
                                HStack {
                                    Text("Custom Range...")
                                    if engine.selectedDateFilter == .custom {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(engine.selectedDateFilter.displayName)
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .opacity(0.7)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .foregroundStyle(Color.primary)
                        .clipShape(Capsule())
                    }

                    // Active dimension filters badge (if any active)
                    if let summary = activeDimensionSummary {
                        HStack(spacing: 4) {
                            Text(summary)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)

                            Button {
                                HapticFeedback.selection()
                                engine.clearDimensionFilters()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // THREE-DOT ⋯ MENU: Filter, Sort, Reset
                    Menu {
                        // Multi-select Filters Section
                        Section("Filter") {
                            Button {
                                showingAccountsSheet = true
                            } label: {
                                Label(
                                    engine.selectedFundingAccounts.isEmpty ? "Accounts" : "Accounts (\(engine.selectedFundingAccounts.count))",
                                    systemImage: "building.columns"
                                )
                            }

                            Button {
                                showingCategoriesSheet = true
                            } label: {
                                Label(
                                    engine.selectedCategories.isEmpty ? "Categories" : "Categories (\(engine.selectedCategories.count))",
                                    systemImage: "tag"
                                )
                            }

                            Button {
                                showingPaymentChannelsSheet = true
                            } label: {
                                Label(
                                    engine.selectedPaymentChannels.isEmpty ? "Payment Channels" : "Payment (\(engine.selectedPaymentChannels.count))",
                                    systemImage: "creditcard"
                                )
                            }

                            if engine.hasActiveDimensionFilters {
                                Button(role: .destructive) {
                                    HapticFeedback.notification(.warning)
                                    engine.clearDimensionFilters()
                                } label: {
                                    Label("Reset Dimension Filters", systemImage: "xmark.circle")
                                }
                            }
                        }

                        // Sorting Section
                        Section("Sort") {
                            Button {
                                HapticFeedback.selection()
                                sortOrder = .newestFirst
                            } label: {
                                HStack {
                                    Text("Newest First")
                                    if sortOrder == .newestFirst {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                HapticFeedback.selection()
                                sortOrder = .oldestFirst
                            } label: {
                                HStack {
                                    Text("Oldest First")
                                    if sortOrder == .oldestFirst {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        // Reset All Section
                        if engine.hasActiveFilters {
                            Section {
                                Button(role: .destructive) {
                                    HapticFeedback.notification(.warning)
                                    engine.clearAllFilters()
                                } label: {
                                    Label("Reset All Filters", systemImage: "arrow.counterclockwise")
                                }
                            }
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(engine.hasActiveDimensionFilters ? Color.accentColor.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(engine.hasActiveDimensionFilters ? Color.accentColor : Color.primary)
                                .clipShape(Capsule())

                            if engine.hasActiveDimensionFilters {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                // MARK: - EXPENSE LIST (Starts high on screen)
                if allExpenses.isEmpty {
                    emptyState(
                        title: "No expenses recorded",
                        message: "Add your first cash expense or drop a transaction screenshot."
                    )
                } else if engine.filteredExpenses.isEmpty {
                    emptyState(
                        title: "No expenses yet",
                        message: "Your expenses from \(engine.selectedDateFilter.displayName) will appear here."
                    )
                } else {
                    List {
                        ForEach(groupedExpenses, id: \.dateHeader) { group in
                            Section {
                                ForEach(group.expenses) { expense in
                                    Button(action: {
                                        selectedExpense = expense
                                    }) {
                                        ExpenseRowView(expense: expense)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            delete(expense: expense)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(group.dateHeader.uppercased())
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    if let sub = group.dateSubtitle {
                                        Text("• \(sub)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search merchant, amount, category...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddExpense = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(item: $selectedExpense) { expense in
                ExpenseDetailView(expense: expense)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView()
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showingAccountsSheet) {
                AccountsMultiSelectSheet(engine: engine)
            }
            .sheet(isPresented: $showingCategoriesSheet) {
                CategoriesMultiSelectSheet(engine: engine)
            }
            .sheet(isPresented: $showingPaymentChannelsSheet) {
                PaymentChannelsMultiSelectSheet(engine: engine)
            }
            .sheet(isPresented: $showingCustomDatePicker) {
                CustomDateRangeSheet(engine: engine, isPresented: $showingCustomDatePicker)
            }
            .onAppear {
                engine.update(expenses: allExpenses)
            }
            .onChange(of: allExpenses) { _, newExpenses in
                engine.update(expenses: newExpenses)
            }
            .onChange(of: searchText) { _, newText in
                engine.searchText = newText
            }
        }
    }

    @ViewBuilder
    private func compactDateButton(_ filter: QuickDateFilter) -> some View {
        Button {
            HapticFeedback.selection()
            engine.selectedDateFilter = filter
        } label: {
            HStack {
                Text(filter.displayName)
                if engine.selectedDateFilter == filter {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func delete(expense: Expense) {
        HapticFeedback.notification(.warning)
        modelContext.delete(expense)
        try? modelContext.save()
        modelContext.processPendingChanges()
        if let all = try? modelContext.fetch(FetchDescriptor<Expense>()) {
            engine.update(expenses: all)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingAddExpense = true
            } label: {
                Label("Add Expense", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)

            if engine.hasActiveFilters {
                Button("Reset Filters") {
                    HapticFeedback.selection()
                    engine.clearAllFilters()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
