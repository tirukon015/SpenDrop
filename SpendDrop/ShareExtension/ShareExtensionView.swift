import SwiftUI
import SwiftData

public struct ShareExtensionView: View {
    public let inputImage: UIImage
    public let onComplete: () -> Void
    public let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext

    // Parsing States
    @State private var isProcessing = true
    @State private var parsedTransaction: ParsedTransaction?
    @State private var processingError: String?

    // Editable Transaction Fields
    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedPaymentSource: PaymentSource = .unknown
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var transactionReference: String?

    // Duplicate Check State
    @State private var duplicateResult: DuplicateCheckResult = .none
    @State private var showingDuplicateConfirmation = false

    public init(
        inputImage: UIImage,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.inputImage = inputImage
        self.onComplete = onComplete
        self.onCancel = onCancel
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
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isProcessing {
                    // STATE 1: PROCESSING
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.4)
                        Text("Reading transaction...")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Extracting details on-device with Apple Vision")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                } else if let error = processingError {
                    // STATE: ERROR / NO TEXT FOUND
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Couldn't read this image")
                            .font(.headline)

                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                onCancel()
                            }
                            .buttonStyle(.bordered)

                            Button("Try Again") {
                                Task {
                                    await parseImage()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                } else if let parsed = parsedTransaction {
                    // STATE: TRANSACTION DETECTED / REVIEW
                    ScrollView {
                        VStack(spacing: 16) {
                            // STATUS BANNER
                            if parsed.isFailedTransaction {
                                bannerView(
                                    icon: "exclamationmark.octagon.fill",
                                    color: .red,
                                    title: "Payment Appears to Have Failed",
                                    subtitle: "Screenshot indicates a declined or unsuccessful transaction."
                                )
                            } else if parsed.isBalanceOrLimitOnly {
                                bannerView(
                                    icon: "info.circle.fill",
                                    color: .orange,
                                    title: "Account Balance / Credit Limit",
                                    subtitle: "This looks like an available balance rather than an expense."
                                )
                            } else if duplicateResult.isDuplicate {
                                bannerView(
                                    icon: "exclamationmark.triangle.fill",
                                    color: .yellow,
                                    title: "Possible Duplicate Detected",
                                    subtitle: duplicateResult.reason ?? "This transaction may already exist in SpendDrop."
                                )
                            } else if parsed.confidence == .high {
                                bannerView(
                                    icon: "checkmark.circle.fill",
                                    color: .green,
                                    title: "Expense Detected",
                                    subtitle: "Verified from your transaction screenshot."
                                )
                            } else {
                                bannerView(
                                    icon: "questionmark.circle.fill",
                                    color: .blue,
                                    title: "Possible Expense Detected",
                                    subtitle: "Please verify amount and details below."
                                )
                            }

                            // HERO AMOUNT
                            VStack(spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(parsed.currency)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)

                                    TextField("0.00", text: $amountText)
                                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)

                                if parsedAmount == 0 {
                                    Text("Enter amount to save")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            // TRANSACTION DETAILS CARD
                            VStack(spacing: 0) {
                                // Merchant
                                HStack(spacing: 12) {
                                    Image(systemName: "storefront.fill")
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    Text("Merchant")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    TextField("Unknown", text: $merchant)
                                        .multilineTextAlignment(.trailing)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider().padding(.leading, 52)

                                // Category
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
                                                selectedCategory = cat
                                            } label: {
                                                Label(cat.rawValue, systemImage: cat.icon)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider().padding(.leading, 52)

                                // Payment Method
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
                                                selectedPaymentSource = src
                                            } label: {
                                                Label(src.rawValue, systemImage: src.icon)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(selectedPaymentSource.rawValue)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider().padding(.leading, 52)

                                // Date & Time
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            // OPTIONAL DESCRIPTION
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("DESCRIPTION")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                        .tracking(1.0)
                                    Spacer()
                                    Text("Optional")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)

                                TextField("Add remarks (optional)", text: $notes)
                                    .padding(12)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // ACTION BUTTONS
                            VStack(spacing: 10) {
                                Button(action: handleSaveButtonTapped) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Save Expense")
                                            .fontWeight(.bold)
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(isValid ? Color.accentColor : Color.gray.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .disabled(!isValid)

                                Button("Cancel") {
                                    onCancel()
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 16)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("SpendDrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .alert("Possible Duplicate Expense", isPresented: $showingDuplicateConfirmation) {
                Button("Add Anyway") {
                    saveToSwiftData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(duplicateResult.reason ?? "This transaction appears to have been recorded already. Do you want to add it anyway?")
            }
            .task {
                await parseImage()
            }
        }
    }

    private func bannerView(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func parseImage() async {
        isProcessing = true
        processingError = nil

        do {
            let ocrResult = try await OCRService.shared.recognizeText(from: inputImage)
            let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: inputImage)

            await MainActor.run {
                self.parsedTransaction = parsed
                if let amt = parsed.amount {
                    self.amountText = String(format: "%.2f", amt)
                }
                self.merchant = parsed.merchant ?? ""
                self.selectedCategory = parsed.category ?? .other
                self.selectedPaymentSource = parsed.paymentSource ?? .unknown
                self.date = parsed.date ?? Date()
                self.transactionReference = parsed.transactionReference

                // Check for duplicates in the shared SwiftData store
                self.duplicateResult = DuplicateDetector.shared.checkDuplicate(
                    amount: parsed.amount,
                    merchant: parsed.merchant,
                    date: parsed.date,
                    reference: parsed.transactionReference,
                    in: modelContext
                )

                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.processingError = error.localizedDescription
                self.isProcessing = false
            }
        }
    }

    private func handleSaveButtonTapped() {
        if duplicateResult.isDuplicate {
            showingDuplicateConfirmation = true
        } else {
            saveToSwiftData()
        }
    }

    private func saveToSwiftData() {
        guard isValid else { return }

        // Save original image file to shared App Group container
        let savedImagePath = ImageStorageService.shared.saveImage(inputImage)

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? "Unknown" : trimmedMerchant

        let expense = Expense(
            amount: parsedAmount,
            currency: parsedTransaction?.currency ?? "RM",
            merchant: finalMerchant,
            category: selectedCategory,
            paymentSource: selectedPaymentSource,
            date: date,
            notes: notes,
            transactionReference: transactionReference,
            imageRelativePath: savedImagePath,
            sourceType: .shareExtension,
            ocrText: parsedTransaction?.rawOCRText,
            confidence: parsedTransaction?.confidence == .high ? 1.0 : (parsedTransaction?.confidence == .medium ? 0.7 : 0.4)
        )

        modelContext.insert(expense)
        try? modelContext.save()

        HapticFeedback.notification(.success)
        onComplete()
    }
}
