import SwiftUI
import SwiftData

public struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var expense: Expense

    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var fundingAccount: String = "Maybank"
    @State private var selectedPaymentChannel: PaymentChannel = .unknown
    @State private var selectedPaymentSource: PaymentSource = .maybank
    @State private var date: Date = Date()
    @State private var notes: String = ""

    private let commonFundingAccounts = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"]

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
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // FUNDING ACCOUNT EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FUNDING ACCOUNT (WHERE MONEY CAME FROM)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        Picker("Funding Account", selection: $fundingAccount) {
                            ForEach(commonFundingAccounts, id: \.self) { acc in
                                Text(acc).tag(acc)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // PAYMENT CHANNEL EDIT
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PAYMENT CHANNEL (HOW PAYMENT WAS MADE)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        Picker("Payment Channel", selection: $selectedPaymentChannel) {
                            ForEach(PaymentChannel.allCases) { channel in
                                Label(channel.displayName, systemImage: channel.iconName)
                                    .tag(channel)
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
                fundingAccount = expense.effectiveFundingAccount
                selectedPaymentChannel = expense.paymentChannel
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
        expense.fundingAccount = fundingAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : fundingAccount
        expense.paymentChannel = selectedPaymentChannel
        expense.date = date
        expense.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        expense.updatedAt = Date()

        try? modelContext.save()
        modelContext.processPendingChanges()

        // Invalidate engine cache so new data appears immediately
        if let all = try? modelContext.fetch(FetchDescriptor<Expense>()) {
            TransactionFilterEngine.shared.update(expenses: all)
        }

        HapticFeedback.notification(.success)
        dismiss()
    }
}
