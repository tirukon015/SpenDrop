import SwiftUI
import SwiftData

public struct ExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @State private var searchText = ""
    @State private var selectedCategory: ExpenseCategory?
    @State private var selectedPaymentSource: PaymentSource?
    @State private var selectedExpense: Expense?
    @State private var showingAddExpense = false

    public init() {}

    private var filteredExpenses: [Expense] {
        allExpenses.filter { expense in
            // Search text filter
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let term = searchText.lowercased()
                let matchesMerchant = expense.merchant.lowercased().contains(term)
                let matchesCategory = expense.category.rawValue.lowercased().contains(term)
                let matchesSource = expense.paymentSource.rawValue.lowercased().contains(term)
                let matchesNotes = expense.notes?.lowercased().contains(term) ?? false
                let matchesAmount = String(format: "%.2f", expense.amount).contains(term)
                matchesSearch = matchesMerchant || matchesCategory || matchesSource || matchesNotes || matchesAmount
            }

            // Category filter
            let matchesCategory: Bool
            if let cat = selectedCategory {
                matchesCategory = expense.category == cat
            } else {
                matchesCategory = true
            }

            // Payment source filter
            let matchesPayment: Bool
            if let src = selectedPaymentSource {
                matchesPayment = expense.paymentSource == src
            } else {
                matchesPayment = true
            }

            return matchesSearch && matchesCategory && matchesPayment
        }
    }

    // Group filtered expenses by day
    private var groupedExpenses: [(dateString: String, expenses: [Expense])] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let grouped = Dictionary(grouping: filteredExpenses) { (expense: Expense) -> String in
            if calendar.isDateInToday(expense.date) {
                return "Today"
            } else if calendar.isDateInYesterday(expense.date) {
                return "Yesterday"
            } else {
                return dateFormatter.string(from: expense.date)
            }
        }

        // Sort groups by the latest date in each group, and sort expenses inside each group newest first
        return grouped.map { (dateString: $0.key, expenses: $0.value.sorted(by: { $0.date > $1.date })) }
            .sorted { (group1, group2) -> Bool in
                guard let d1 = group1.expenses.first?.date, let d2 = group2.expenses.first?.date else { return false }
                return d1 > d2
            }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                FilterBarView(
                    selectedCategory: $selectedCategory,
                    selectedPaymentSource: $selectedPaymentSource
                )
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))

                Divider()

                if allExpenses.isEmpty {
                    emptyState(
                        icon: "tray",
                        title: "No expenses recorded",
                        message: "Add your first cash expense or drop a transaction screenshot."
                    )
                } else if filteredExpenses.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No matching expenses",
                        message: "Try searching with a different term or clear the active filters."
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
        }
    }

    private func delete(expense: Expense) {
        HapticFeedback.notification(.warning)
        modelContext.delete(expense)
        try? modelContext.save()
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
