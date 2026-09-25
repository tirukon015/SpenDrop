import SwiftUI
import SwiftData

public struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var expense: Expense

    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedPaymentSource: PaymentSource = .cash
    @State private var date: Date = Date()
    @State private var notes: String = ""

    public init(expense: Expense) {
        self.expense = expense
    }

    private var parsedAmount: Double {
        CurrencyFormatter.parse(string: amountText) ?? 0.0
    }

    private var isValid: Bool {
        parsedAmount > 0
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // AMOUNT EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AMOUNT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        HStack {
                            Text(expense.currency)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            TextField("Amount", text: $amountText)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .keyboardType(.decimalPad)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // MERCHANT EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MERCHANT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        TextField("Merchant name", text: $merchant)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // CATEGORY EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CATEGORY")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        Picker("Category", selection: $selectedCategory) {
                            ForEach(ExpenseCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.icon)
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // PAYMENT METHOD EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PAYMENT METHOD")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        Picker("Payment Method", selection: $selectedPaymentSource) {
                            ForEach(PaymentSource.allCases) { source in
                                Label(source.rawValue, systemImage: source.icon)
                                    .tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // DATE & TIME EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DATE & TIME")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        DatePicker("Date & Time", selection: $date)
                            .datePickerStyle(.compact)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // NOTES EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION (OPTIONAL)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 4)

                        TextField("Optional description", text: $notes)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.bold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                amountText = String(format: "%.2f", expense.amount)
                merchant = expense.merchant
                selectedCategory = expense.category
                selectedPaymentSource = expense.paymentSource
                date = expense.date
                notes = expense.notes ?? ""
            }
        }
    }

    private func saveChanges() {
        guard isValid else { return }

        expense.amount = parsedAmount
        expense.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : merchant
        expense.category = selectedCategory
        expense.paymentSource = selectedPaymentSource
        expense.date = date
        expense.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        expense.updatedAt = Date()

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
