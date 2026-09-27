import SwiftUI
import SwiftData

public struct ExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @Bindable private var engine = TransactionFilterEngine.shared

    @State private var searchText = ""
    @State private var selectedExpense: Expense?
    @State private var showingAddExpense = false

    public init() {}

    // Group filtered expenses by day
    private var groupedExpenses: [(dateString: String, expenses: [Expense])] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let grouped = Dictionary(grouping: engine.filteredExpenses) { (expense: Expense) -> String in
            if calendar.isDateInToday(expense.date) {
                return "Today"
            } else if calendar.isDateInYesterday(expense.date) {
                return "Yesterday"
            } else {
                return dateFormatter.string(from: expense.date)
            }
        }

        return grouped.map { (dateString: $0.key, expenses: $0.value.sorted(by: { $0.date > $1.date })) }
            .sorted { (group1, group2) -> Bool in
                guard let d1 = group1.expenses.first?.date, let d2 = group2.expenses.first?.date else { return false }
                return d1 > d2
            }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar with 10 Quick Date Filters and active tags
                FilterBarView(engine: engine)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemBackground))

                // Summary KPI Ribbon
                if !engine.filteredExpenses.isEmpty {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TOTAL SPENT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(CurrencyFormatter.format(amount: engine.totalSpending))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        Divider()
                            .frame(height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("COUNT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text("\(engine.transactionCount) txns")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("AVG / DAY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text("\(CurrencyFormatter.format(amount: engine.averagePerDay)) / day")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                }

                Divider()

                if allExpenses.isEmpty {
                    emptyState(
                        icon: "tray",
                        title: "No expenses recorded",
                        message: "Add your first cash expense or drop a transaction screenshot."
                    )
                } else if engine.filteredExpenses.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No matching expenses",
                        message: "No transactions match '\(engine.selectedDateFilter.displayName)' with the current filters."
                    )
                } else {
                    List {
                        ForEach(groupedExpenses, id: \.dateString) { group in
                            Section(header: Text(group.dateString).font(.subheadline).fontWeight(.semibold)) {
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

    private func delete(expense: Expense) {
        HapticFeedback.notification(.warning)
        modelContext.delete(expense)
        try? modelContext.save()
        modelContext.processPendingChanges()
        engine.update(expenses: allExpenses)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if engine.hasActiveFilters {
                Button("Reset Filters") {
                    HapticFeedback.selection()
                    engine.clearAllFilters()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
