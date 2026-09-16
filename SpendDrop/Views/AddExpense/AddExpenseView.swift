import SwiftUI
import SwiftData
import PhotosUI

public struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedPaymentSource: PaymentSource
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var currency: String = "RM"

    // Image Import & OCR States
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var parsedTransaction: ParsedTransaction?
    @State private var showingReviewSheet = false
    @State private var showingOCRError = false
    @State private var ocrErrorMessage = ""

    // Quick suggestions for fast Malaysian daily spending
    private let quickMerchants = ["McDonald's", "Grab", "MYDIN", "Mamak", "Starbucks", "7-Eleven", "Shell"]
    private let quickAmounts: [Double] = [5, 10, 20, 50]

    public init(initialPaymentSource: PaymentSource = .cash) {
        _selectedPaymentSource = State(initialValue: initialPaymentSource)
    }

    private var parsedAmount: Double {
        CurrencyFormatter.parse(string: amountText) ?? 0.0
    }

    private var isValid: Bool {
        parsedAmount > 0
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // SCAN / IMPORT SCREENSHOT BUTTON (Milestone 2 core feature)
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            HStack(spacing: 10) {
                                Image(systemName: "viewfinder.rectangular")
                                    .font(.title3)
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan Screenshot or Receipt")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)

                                    Text("Auto-detect amount, merchant & category with Vision OCR")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                await processSelectedImage(item: newItem)
                            }
                        }

                        // HERO AMOUNT CARD
                        VStack(spacing: 12) {
                            Text("ENTER AMOUNT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.2)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(currency)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                TextField("0.00", text: $amountText)
                                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)

                            // Quick Amount Adders
                            HStack(spacing: 10) {
                                ForEach(quickAmounts, id: \.self) { increment in
                                    Button(action: {
                                        HapticFeedback.impact(.light)
                                        let current = parsedAmount
                                        let newTotal = current + increment
                                        amountText = String(format: "%.2f", newTotal)
                                    }) {
                                        Text("+\(currency)\(Int(increment))")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(uiColor: .tertiarySystemFill))
                                            .clipShape(Capsule())
                                    }
                                }

                                if parsedAmount > 0 {
                                    Button(action: {
                                        HapticFeedback.selection()
                                        amountText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // PAYMENT METHOD PICKER
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PAYMENT METHOD")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(PaymentSource.allCases) { source in
                                        Button(action: {
                                            HapticFeedback.selection()
                                            selectedPaymentSource = source
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: source.icon)
                                                Text(source.shortName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                selectedPaymentSource == source
                                                    ? source.brandColor
                                                    : Color(uiColor: .secondarySystemGroupedBackground)
                                            )
                                            .foregroundStyle(
                                                selectedPaymentSource == source
                                                    ? Color.white
                                                    : Color.primary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }

                        // CATEGORY PICKER GRID
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CATEGORY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 10) {
                                ForEach(ExpenseCategory.allCases) { category in
                                    Button(action: {
                                        HapticFeedback.selection()
                                        selectedCategory = category
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.title3)
                                            Text(category.rawValue)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            selectedCategory == category
                                                ? category.color
                                                : Color(uiColor: .secondarySystemGroupedBackground)
                                        )
                                        .foregroundStyle(
                                            selectedCategory == category
                                                ? Color.white
                                                : Color.primary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }
                        }

                        // MERCHANT INPUT & QUICK SUGGESTIONS
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MERCHANT / STORE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            TextField("e.g. McDonald's, Mamak, Grab (optional)", text: $merchant)
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(quickMerchants, id: \.self) { item in
                                        Button(action: {
                                            HapticFeedback.selection()
                                            merchant = item
                                            // Auto suggest category
                                            if ["McDonald's", "Mamak", "Starbucks"].contains(item) {
                                                selectedCategory = .food
                                            } else if item == "Grab" {
                                                selectedCategory = .transport
                                            } else if ["MYDIN", "7-Eleven"].contains(item) {
                                                selectedCategory = .groceries
                                            } else if item == "Shell" {
                                                selectedCategory = .transport
                                            }
                                        }) {
                                            Text(item)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color(uiColor: .tertiarySystemFill))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        // DATE & TIME
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DATE & TIME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            DatePicker("Transaction Time", selection: $date)
                                .datePickerStyle(.compact)
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // OPTIONAL DESCRIPTION / NOTES
                        VStack(alignment: .leading, spacing: 12) {
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

                            TextField("e.g. Lunch with team, monthly groceries", text: $notes)
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // SAVE BUTTON
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
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .padding()
                }

                // PROCESSING OVERLAY (Vision OCR)
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
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $parsedTransaction) { parsed in
                ExpenseReviewView(parsed: parsed) { savedExpense in
                    dismiss()
                }
            }
            .alert("Couldn't read this image", isPresented: $showingOCRError) {
                Button("Try Again") {
                    selectedPhotoItem = nil
                }
                Button("Add Manually", role: .cancel) {
                    selectedPhotoItem = nil
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

    private func saveExpense() {
        guard isValid else { return }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? (selectedCategory == .food ? "Food / Dining" : "Unknown") : trimmedMerchant

        let expense = Expense(
            amount: parsedAmount,
            currency: currency,
            merchant: finalMerchant,
            category: selectedCategory,
            paymentSource: selectedPaymentSource,
            date: date,
            notes: notes,
            sourceType: selectedPaymentSource == .cash ? .manual : .manual
        )

        modelContext.insert(expense)
        try? modelContext.save()

        HapticFeedback.notification(.success)
        dismiss()
    }
}

// Extension to allow ParsedTransaction to be used with .sheet(item:)
extension ParsedTransaction: Identifiable {
    public var id: String {
        rawOCRText.isEmpty ? UUID().uuidString : String(rawOCRText.hashValue)
    }
}
