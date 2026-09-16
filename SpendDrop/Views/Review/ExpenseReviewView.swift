import SwiftUI
import SwiftData

public struct ExpenseReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let initialParsed: ParsedTransaction
    public var onSaved: ((Expense) -> Void)?

    @State private var amountText: String
    @State private var merchant: String
    @State private var selectedCategory: ExpenseCategory
    @State private var selectedPaymentSource: PaymentSource
    @State private var date: Date
    @State private var notes: String = ""
    @State private var transactionReference: String?
    @State private var showingImagePreview = false

    public init(parsed: ParsedTransaction, onSaved: ((Expense) -> Void)? = nil) {
        self.initialParsed = parsed
        self.onSaved = onSaved

        _amountText = State(initialValue: parsed.amount != nil ? String(format: "%.2f", parsed.amount!) : "")
        _merchant = State(initialValue: parsed.merchant ?? "")
        _selectedCategory = State(initialValue: parsed.category ?? .other)
        _selectedPaymentSource = State(initialValue: parsed.paymentSource ?? .unknown)
        _date = State(initialValue: parsed.date ?? Date())
        _transactionReference = State(initialValue: parsed.transactionReference)
    }

    private var parsedAmount: Double {
        CurrencyFormatter.parse(string: amountText) ?? 0.0
    }

    private var isValid: Bool {
        parsedAmount > 0
    }

    private var isHighConfidence: Bool {
        initialParsed.confidence == .high && !initialParsed.isBalanceOrLimitOnly && !initialParsed.isFailedTransaction
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // STATUS HEADER BANNER
                    if initialParsed.isFailedTransaction {
                        statusBanner(
                            icon: "exclamationmark.octagon.fill",
                            color: .red,
                            title: "Payment Failed / Declined",
                            subtitle: "This screenshot indicates an unsuccessful transaction."
                        )
                    } else if initialParsed.isBalanceOrLimitOnly {
                        statusBanner(
                            icon: "info.circle.fill",
                            color: .orange,
                            title: "Account Balance / Credit Limit",
                            subtitle: "This looks like an account balance rather than a new expense."
                        )
                    } else if isHighConfidence {
                        statusBanner(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            title: "Expense Detected",
                            subtitle: "All key details verified from your screenshot."
                        )
                    } else {
                        statusBanner(
                            icon: "questionmark.circle.fill",
                            color: .yellow,
                            title: "Possible Expense Detected",
                            subtitle: "Please verify the highlighted fields below."
                        )
                    }

                    // AMOUNT HERO DISPLAY
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(initialParsed.currency)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $amountText)
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        if parsedAmount == 0 {
                            Text("Tap to enter amount")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // REVIEW DETAILS CARD
                    VStack(spacing: 0) {
                        // Merchant field
                        HStack(spacing: 12) {
                            Image(systemName: "storefront.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            Text("Merchant")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            TextField("Unknown (tap to add)", text: $merchant)
                                .multilineTextAlignment(.trailing)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if initialParsed.merchant != nil {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()

                        Divider().padding(.leading, 48)

                        // Category field
                        HStack(spacing: 12) {
                            Image(systemName: selectedCategory.icon)
                                .foregroundStyle(selectedCategory.color)
                                .frame(width: 24)

                            Text("Category")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Menu {
                                ForEach(ExpenseCategory.allCases) { cat in
                                    Button {
                                        HapticFeedback.selection()
                                        selectedCategory = cat
                                    } label: {
                                        Label(cat.rawValue, systemImage: cat.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCategory.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()

                        Divider().padding(.leading, 48)

                        // Payment source field
                        HStack(spacing: 12) {
                            Image(systemName: selectedPaymentSource.icon)
                                .foregroundStyle(selectedPaymentSource.brandColor)
                                .frame(width: 24)

                            Text("Payment")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Menu {
                                ForEach(PaymentSource.allCases) { src in
                                    Button {
                                        HapticFeedback.selection()
                                        selectedPaymentSource = src
                                    } label: {
                                        Label(src.rawValue, systemImage: src.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedPaymentSource.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if initialParsed.paymentSource != nil {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()

                        Divider().padding(.leading, 48)

                        // Date & Time field
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .foregroundStyle(.indigo)
                                .frame(width: 24)

                            Text("Date & Time")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            DatePicker("", selection: $date)
                                .labelsHidden()
                        }
                        .padding()
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // OPTIONAL DESCRIPTION FIELD
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DESCRIPTION")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                            Spacer()
                            Text("Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        TextField("Add optional remarks (e.g. dinner with friends)", text: $notes)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // ORIGINAL IMAGE PREVIEW
                    if let image = initialParsed.originalImage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ORIGINAL SCREENSHOT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            Button(action: {
                                showingImagePreview = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Captured Screenshot")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text("Tap to view full image")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }

                    // ACTION BUTTONS
                    VStack(spacing: 12) {
                        Button(action: saveExpense) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Save Expense")
                                    .fontWeight(.bold)
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isValid ? Color.accentColor : Color.gray.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(!isValid)

                        Button("Discard") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Review Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingImagePreview) {
                if let image = initialParsed.originalImage {
                    NavigationStack {
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                        .navigationTitle("Screenshot")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingImagePreview = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusBanner(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func saveExpense() {
        guard isValid else { return }

        // Save original image to disk if present
        var savedImagePath: String? = nil
        if let image = initialParsed.originalImage {
            savedImagePath = ImageStorageService.shared.saveImage(image)
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? "Unknown" : trimmedMerchant

        let expense = Expense(
            amount: parsedAmount,
            currency: initialParsed.currency,
            merchant: finalMerchant,
            category: selectedCategory,
            paymentSource: selectedPaymentSource,
            date: date,
            notes: notes,
            transactionReference: transactionReference,
            imageRelativePath: savedImagePath,
            sourceType: .screenshot,
            ocrText: initialParsed.rawOCRText,
            confidence: initialParsed.confidence == .high ? 1.0 : (initialParsed.confidence == .medium ? 0.7 : 0.4)
        )

        modelContext.insert(expense)
        try? modelContext.save()

        HapticFeedback.notification(.success)
        onSaved?(expense)
        dismiss()
    }
}
