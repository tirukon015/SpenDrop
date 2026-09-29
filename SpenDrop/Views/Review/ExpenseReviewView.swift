import SwiftUI
import SwiftData

public struct ExpenseReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

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

    // Funding Account & Payment Channel
    @State private var fundingAccount: String
    @State private var selectedPaymentChannel: PaymentChannel
    @State private var fundingInstrument: String?
    private let commonFundingAccounts = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"]

    // Duplicate Check State
    @State private var duplicateResult: DuplicateCheckResult = .none
    @State private var showingDuplicateConfirmation = false

    // PayBook Integration State
    @State private var showingSaveToPayBookSheet = false

    // Save as Expense / Money In / Money Out / Transfer (suggested from clear wording only; user confirms)
    @State private var saveAs: TransactionEntryType
    @State private var pendingMovement: PrefilledMovement?
    @State private var movementDuplicateMessage: String?
    @State private var categoryTouched = false

    public init(parsed: ParsedTransaction, onSaved: ((Expense) -> Void)? = nil) {
        self.initialParsed = parsed
        self.onSaved = onSaved

        _amountText = State(initialValue: parsed.amount != nil ? String(format: "%.2f", parsed.amount!) : "")
        _merchant = State(initialValue: parsed.merchant ?? "")
        _selectedCategory = State(initialValue: parsed.category ?? .other)
        _selectedPaymentSource = State(initialValue: parsed.paymentSource ?? .unknown)
        _fundingAccount = State(initialValue: parsed.displayFundingAccount)
        _selectedPaymentChannel = State(initialValue: parsed.paymentChannel)
        _fundingInstrument = State(initialValue: parsed.fundingInstrument)
        _date = State(initialValue: parsed.date ?? Date())
        _notes = State(initialValue: parsed.suggestedRemark ?? "")
        _transactionReference = State(initialValue: parsed.transactionReference)
        _saveAs = State(initialValue: parsed.suggestedMovementKind.map(TransactionEntryType.init(kind:)) ?? .expense)
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
                    } else if duplicateResult.isDuplicate {
                        statusBanner(
                            icon: "exclamationmark.triangle.fill",
                            color: .yellow,
                            title: "Possible Duplicate Detected",
                            subtitle: duplicateResult.reason ?? "This transaction may already exist in SpenDrop."
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

                    // SAVE AS (Expense stays the default unless the screenshot clearly says otherwise)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Save as", selection: $saveAs) {
                            ForEach(TransactionEntryType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("review.saveAs")
                        if let reason = initialParsed.directionReason {
                            Text(initialParsed.suggestedMovementKind == nil ? "Unclear direction (\(reason)). Please choose." : "Suggested: \(reason). Please confirm.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // AMOUNT HERO DISPLAY
                    VStack(spacing: 8) {
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

                        // Alternative amount candidates quick selector (Issue 4, 5)
                        let altCandidates = initialParsed.amountCandidates.filter {
                            !$0.semanticType.isExcludedFromTransactionAmount
                        }
                        if altCandidates.count > 1 {
                            VStack(spacing: 6) {
                                Text("POSSIBLE AMOUNTS")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .tracking(0.8)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(altCandidates) { cand in
                                            let candText = String(format: "%.2f", cand.amount)
                                            Button {
                                                HapticFeedback.selection()
                                                amountText = candText
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Text("\(cand.currency)\(candText)")
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    if cand.semanticType != .unknown {
                                                        Text("(\(cand.semanticType.displayName))")
                                                            .font(.caption2)
                                                            .opacity(0.8)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(
                                                    amountText == candText
                                                        ? Color.accentColor
                                                        : Color(uiColor: .tertiarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    amountText == candText
                                                        ? Color.white
                                                        : Color.primary
                                                )
                                                .clipShape(Capsule())
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                    .padding(.vertical, 14)
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
                                        categoryTouched = true
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

                        // Funding Method field (Where money actually came from)
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            Text("Funding Method")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Menu {
                                ForEach(AccountLinker.fundingOptions(base: commonFundingAccounts, accounts: accounts), id: \.self) { acc in
                                    Button {
                                        HapticFeedback.selection()
                                        fundingAccount = acc
                                    } label: {
                                        Text(acc)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(fundingAccount.isEmpty ? "Unknown" : fundingAccount)
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

                        // Payment Channel field (How payment was made)
                        HStack(spacing: 12) {
                            Image(systemName: selectedPaymentChannel.iconName)
                                .foregroundStyle(selectedPaymentChannel.tintColor)
                                .frame(width: 24)

                            Text("Payment Channel")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Menu {
                                ForEach(PaymentChannel.allCases) { ch in
                                    Button {
                                        HapticFeedback.selection()
                                        selectedPaymentChannel = ch
                                    } label: {
                                        Label(ch.displayName, systemImage: ch.iconName)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedPaymentChannel.displayName)
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

                        // Funding Instrument field (if present)
                        if let instrument = fundingInstrument, !instrument.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "creditcard")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)

                                Text("Funding Instrument")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(instrument)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                            .padding()

                            Divider().padding(.leading, 48)
                        }

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
                        if !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: {
                                showingSaveToPayBookSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.badge.plus")
                                    Text("Save Recipient to PayBook")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        Button(action: { saveAs == .expense ? handleSaveTapped() : continueAsMovement() }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(saveAs == .expense ? "Save Expense" : "Continue as \(saveAs.title)")
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
            .sheet(isPresented: $showingSaveToPayBookSheet) {
                PayBookPickerSheet(
                    mode: .saveRecipient(
                        name: merchant,
                        provider: selectedPaymentSource.rawValue,
                        account: transactionReference ?? ""
                    )
                )
            }
            .alert("Existing Transaction Detected", isPresented: $showingDuplicateConfirmation) {
                Button("Reconcile with Existing (Recommended)") {
                    reconcileExpense()
                }
                Button("Add as Separate Transaction") {
                    saveExpense()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(duplicateResult.reason ?? "This transaction matches an existing record. Reconciling will link them into one single expense without double-counting.")
            }
            .sheet(item: $pendingMovement) { item in
                MoneyMovementCreateSheet(draft: item.draft) {
                    dismiss()
                }
            }
            .alert("Possible duplicate", isPresented: Binding(get: { movementDuplicateMessage != nil },
                                                               set: { if !$0 { movementDuplicateMessage = nil } })) {
                Button("Continue Anyway") { presentMovementDraft() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(movementDuplicateMessage ?? "")
            }
            .onAppear {
                // Learned rule > parser rule > generic; never overrides a category the user picked.
                if !categoryTouched {
                    selectedCategory = TransactionClassifier.suggestCategory(
                        merchant: merchant, deterministic: initialParsed.category, in: modelContext).category
                }
                duplicateResult = DuplicateDetector.shared.checkDuplicate(
                    amount: parsedAmount,
                    merchant: merchant,
                    date: date,
                    reference: transactionReference,
                    in: modelContext
                )
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

    /// The kind to use for the chosen type: the parser's suggestion when it matches, else the type's default.
    private var movementKind: MoneyMovementKind {
        if let suggested = initialParsed.suggestedMovementKind, TransactionEntryType(kind: suggested) == saveAs {
            return suggested
        }
        return saveAs.kinds.first ?? .otherIn
    }

    private func makeMovementDraft() -> MoneyMovementDraft {
        MoneyMovementDraft.fromParsed(
            amount: parsedAmount, date: date, fundingAccount: fundingAccount, merchant: merchant,
            reference: transactionReference, channel: selectedPaymentChannel, walletSource: initialParsed.paymentSource,
            kind: movementKind, source: .screenshot, in: modelContext
        )
    }

    private func continueAsMovement() {
        let draft = makeMovementDraft()
        if let amountMinor = draft.amountMinor,
           let match = MovementDuplicateDetector.findMatch(amountMinor: amountMinor, date: date, reference: transactionReference,
                                                           kind: movementKind, in: modelContext) {
            movementDuplicateMessage = "A \(match.kind.displayName.lowercased()) of \(CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: match.amountMinor))) on \(match.date.formatted(date: .abbreviated, time: .omitted)) is already recorded."
        } else {
            presentMovementDraft()
        }
    }

    private func presentMovementDraft() {
        pendingMovement = PrefilledMovement(draft: makeMovementDraft())
    }

    private func handleSaveTapped() {
        if duplicateResult.isDuplicate {
            showingDuplicateConfirmation = true
        } else {
            saveExpense()
        }
    }

    private func reconcileExpense() {
        guard let existing = duplicateResult.matchedExpense else {
            saveExpense()
            return
        }

        var savedImagePath: String? = nil
        if let image = initialParsed.originalImage {
            savedImagePath = ImageStorageService.shared.saveImage(image)
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? "Unknown" : trimmedMerchant

        let candidate = ReconcileCandidate(
            amount: parsedAmount,
            merchant: finalMerchant,
            date: date,
            category: selectedCategory,
            fundingAccount: fundingAccount,
            paymentChannel: selectedPaymentChannel,
            reference: transactionReference,
            notes: notes.isEmpty ? nil : notes,
            imageRelativePath: savedImagePath,
            rawOCRText: initialParsed.rawOCRText,
            fundingInstrument: fundingInstrument
        )

        let reconciled = TransactionReconciliationEngine.shared.reconcile(existing: existing, with: candidate, in: modelContext)

        if let all = try? modelContext.fetch(FetchDescriptor<Expense>()) {
            TransactionFilterEngine.shared.update(expenses: all)
        }

        HapticFeedback.notification(.success)
        onSaved?(reconciled)
        dismiss()
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
            underlyingBank: selectedPaymentSource == .applePay ? initialParsed.underlyingBank : nil,
            paymentMethod: selectedPaymentSource.defaultPaymentMethod,
            date: date,
            notes: notes,
            transactionReference: transactionReference,
            imageRelativePath: savedImagePath,
            sourceType: .screenshot,
            ocrText: initialParsed.rawOCRText,
            confidence: initialParsed.confidence == .high ? 1.0 : (initialParsed.confidence == .medium ? 0.7 : 0.4),
            paymentChannel: selectedPaymentChannel,
            fundingAccount: fundingAccount,
            fundingInstrument: fundingInstrument
        )

        modelContext.insert(expense)
        try? modelContext.save()
        modelContext.processPendingChanges()

        // Invalidate engine cache immediately
        if let all = try? modelContext.fetch(FetchDescriptor<Expense>()) {
            TransactionFilterEngine.shared.update(expenses: all)
        }

        HapticFeedback.notification(.success)
        onSaved?(expense)
        dismiss()
    }
}
