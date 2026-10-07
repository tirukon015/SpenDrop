import SwiftUI
import SwiftData

// Diagnostic logger that writes to stdout, system console, and shared App Group container
public func shareLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let formatted: String
    if message.hasPrefix("[SpenDropShare]") {
        formatted = "[\(timestamp)] \(message)"
    } else {
        formatted = "[\(timestamp)] [SpenDropShare] \(message)"
    }
    print(formatted)
    NSLog("%@", formatted)

    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ExpenseDataContainer.appGroupIdentifier) {
        let logURL = containerURL.appendingPathComponent("share_extension_diagnostics.log")
        let entry = formatted + "\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}

public enum ShareExtensionPhase {
    case receiving
    case processing(image: UIImage)
    case reviewing(image: UIImage, parsed: ParsedTransaction)
    case noTextFound(image: UIImage)
    case error(String)
}

@MainActor
public final class ShareExtensionViewModel: ObservableObject {
    @Published public var phase: ShareExtensionPhase = .receiving
    @Published public var inputImage: UIImage?
    @Published public var utiIdentifier: String = ""

    // Editable Transaction Fields
    @Published public var amountText: String = ""
    @Published public var merchant: String = ""
    @Published public var selectedCategory: ExpenseCategory = .other
    @Published public var fundingAccount: String = "Maybank"
    @Published public var selectedPaymentChannel: PaymentChannel = .unknown
    @Published public var fundingInstrument: String? = nil
    @Published public var selectedPaymentSource: PaymentSource = .unknown
    @Published public var date: Date = Date()
    @Published public var notes: String = ""
    @Published public var transactionReference: String?
    /// Why the category / channel was suggested; shown when SpenDrop isn't sure. Cleared once the user picks.
    @Published public var categoryHint: CategorySuggestion?
    @Published public var channelHint: ChannelSuggestion?
    /// "Split Money" set up before the first save (nil = not split). Saved with the expense in one go.
    @Published public var splitDraft: SplitDraft?

    // Duplicate Check State
    @Published public var duplicateResult: DuplicateCheckResult = .none
    @Published public var showingDuplicateConfirmation: Bool = false

    // Save as Expense / Money In / Money Out (suggested only from clear wording; the user confirms)
    public enum SaveType: String, CaseIterable, Identifiable {
        case expense = "Expense", moneyIn = "Money In", moneyOut = "Money Out"
        public var id: String { rawValue }
    }
    @Published public var saveAs: SaveType = .expense
    @Published public var suggestedMovementKind: MoneyMovementKind?
    @Published public var directionReason: String?
    @Published public var movementDuplicateMessage: String?

    // Asynchronous OCR Task reference
    private var ocrTask: Task<Void, Never>?
    private var isProcessingOCR: Bool = false

    public init() {}

    public func cancelTask() {
        ocrTask?.cancel()
        ocrTask = nil
        isProcessingOCR = false
    }

    /// Automatically initiates Vision OCR and Transaction Parsing immediately upon image receipt
    public func startAutomaticOCR(image: UIImage) {
        guard !isProcessingOCR else {
            shareLog("[SpenDropShare][OCR] OCR already in progress, ignoring duplicate call")
            return
        }
        isProcessingOCR = true
        cancelTask()
        isProcessingOCR = true

        phase = .processing(image: image)
        shareLog("[SpenDropShare][OCR] automatic OCR started")

        ocrTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isProcessingOCR = false
                }
            }
            guard let self = self else { return }

            shareLog("[SpenDropShare][OCR] Vision request started")

            let ocrResult: OCRResult
            do {
                ocrResult = try await OCRService.shared.recognizeText(from: image)
                shareLog("[SpenDropShare][OCR] Vision request completed")
            } catch {
                shareLog("[SpenDropShare][OCR][ERROR] OCR failed: \(error.localizedDescription)")
                if !Task.isCancelled {
                    self.phase = .noTextFound(image: image)
                }
                return
            }

            guard !Task.isCancelled else { return }
            self.finishParsing(ocrResult: ocrResult, image: image, parserImage: image)
        }
    }

    /// Shared PDF / text path: the extracted text goes through exactly the same parser, duplicate check and
    /// review as a screenshot. `preview` is only shown on screen; nothing from a PDF is stored as a receipt image.
    public func startParsing(ocrResult: OCRResult, preview: UIImage) {
        cancelTask()
        phase = .processing(image: preview)
        ocrTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.finishParsing(ocrResult: ocrResult, image: preview, parserImage: nil)
        }
    }

    /// Everything after text recognition (unchanged from the original image flow): parse → category →
    /// duplicate check → review.
    private func finishParsing(ocrResult: OCRResult, image: UIImage, parserImage: UIImage?) {
        do {
            let observationCount = ocrResult.lines.count
            let textLength = ocrResult.fullText.count
            shareLog("[SpenDropShare][OCR] observation count = \(observationCount)")
            shareLog("[SpenDropShare][OCR] text length = \(textLength)")

            let trimmedText = ocrResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            if ocrResult.lines.isEmpty || trimmedText.isEmpty {
                shareLog("[SpenDropShare][OCR] no readable text found")
                self.phase = .noTextFound(image: image)
                return
            }

            shareLog("[SpenDropShare][OCR] parser started")
            let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: parserImage)
            shareLog("[SpenDropShare][OCR] parser completed")

            guard !Task.isCancelled else { return }

            // Populate detected fields
            self.applyParsedTransaction(parsed)
            // Learned rule > parser rule > generic suggestion (local only).
            self.applySuggestions(parsed, in: ExpenseDataContainer.shared.mainContext)

            // Duplicate detection executed safely
            do {
                self.duplicateResult = DuplicateDetector.shared.checkDuplicate(
                    amount: parsed.amount,
                    merchant: parsed.merchant,
                    date: parsed.date,
                    reference: parsed.transactionReference,
                    paymentChannel: parsed.paymentChannel,
                    fundingAccount: parsed.displayFundingAccount,
                    in: ExpenseDataContainer.shared.mainContext
                )
            } catch {
                shareLog("[SpenDropShare][OCR] duplicate detector warning: \(error.localizedDescription)")
                self.duplicateResult = .none
            }

            shareLog("[SpenDropShare][OCR] review/result UI presented")
            self.phase = .reviewing(image: image, parsed: parsed)
        }
    }

    /// Directly applies parsed transaction fields into the view model
    public func applyParsedTransaction(_ parsed: ParsedTransaction) {
        if let amt = parsed.amount {
            self.amountText = String(format: "%.2f", amt)
        } else {
            self.amountText = ""
        }

        self.merchant = parsed.merchant ?? ""
        self.splitDraft = nil
        self.selectedCategory = parsed.category ?? .other
        self.suggestedMovementKind = parsed.suggestedMovementKind
        self.directionReason = parsed.directionReason
        switch parsed.suggestedMovementKind?.direction {
        case .moneyIn?: self.saveAs = .moneyIn
        case .moneyOut?: self.saveAs = .moneyOut
        default: self.saveAs = .expense   // own transfers are recorded in the app (they need two accounts)
        }
        self.fundingAccount = parsed.displayFundingAccount
        self.selectedPaymentChannel = parsed.paymentChannel
        self.fundingInstrument = parsed.fundingInstrument
        self.selectedPaymentSource = parsed.paymentSource ?? .unknown
        self.date = parsed.date ?? Date()
        self.transactionReference = parsed.transactionReference
        if let suggested = parsed.suggestedRemark, !suggested.isEmpty {
            self.notes = suggested
        }
    }

    /// Learned rule > receipt evidence > Other for the category; a learned channel only when the receipt states none.
    public func applySuggestions(_ parsed: ParsedTransaction, in context: ModelContext) {
        let evidence = CategorySuggestion(category: parsed.category ?? .other,
                                          confidence: parsed.category == nil ? 0 : parsed.categoryConfidence,
                                          reason: parsed.categoryReason ?? "No category evidence in this receipt")
        let suggestion = TransactionClassifier.suggestion(merchant: parsed.merchant, parsed: evidence, in: context).0
        self.selectedCategory = suggestion.category
        self.categoryHint = suggestion
        if let learned = ChannelLearning.suggestion(merchant: parsed.merchant, funding: fundingAccount,
                                                    detected: selectedPaymentChannel, in: context) {
            self.selectedPaymentChannel = learned.channel
            self.channelHint = learned
        } else {
            self.channelHint = ChannelSuggestion(channel: parsed.paymentChannel, confidence: parsed.channelConfidence,
                                                 reason: parsed.channelReason ?? "")
        }
    }

    /// Prepares manual entry review screen when OCR finds no text or user chooses manual input
    public func enterManualDetails(image: UIImage) {
        cancelTask()
        let manualParsed = ParsedTransaction(
            confidence: .low,
            originalImage: image,
            isCompletedTransaction: false,
            isFailedTransaction: false,
            isBalanceOrLimitOnly: false
        )
        self.amountText = ""
        self.merchant = ""
        self.splitDraft = nil
        self.selectedCategory = .other
        self.fundingAccount = "Maybank"
        self.selectedPaymentChannel = .unknown
        self.fundingInstrument = nil
        self.selectedPaymentSource = .unknown
        self.date = Date()
        self.transactionReference = nil
        self.notes = ""
        self.duplicateResult = .none
        shareLog("[SpenDropShare][OCR] review/result UI presented (manual entry)")
        self.phase = .reviewing(image: image, parsed: manualParsed)
    }

    // MARK: - Draft rules and save path (shared by the Share Extension and Bulk Import)

    public var parsedAmount: Double {
        CurrencyFormatter.parse(string: amountText) ?? 0.0
    }

    /// A split must add up to the amount exactly before the expense can be saved.
    public var isValid: Bool {
        guard parsedAmount > 0 else { return false }
        guard saveAs == .expense, let split = splitDraft else { return true }
        return split.isValid(totalMinor: Money.minorUnits(from: parsedAmount))
    }

    /// The movement kind for Money In / Money Out: the parser's suggestion when it matches, else Other In / Other Out.
    public var movementKind: MoneyMovementKind {
        let wanted: MoneyDirection = saveAs == .moneyIn ? .moneyIn : .moneyOut
        if let suggested = suggestedMovementKind, suggested.direction == wanted { return suggested }
        return wanted == .moneyIn ? .otherIn : .otherOut
    }

    /// Money In / Money Out. The account is resolved from the funding account text (Unknown stays unlinked, no
    /// duplicate accounts are created). Inserts and saves; the caller reports the result.
    @discardableResult
    public func saveMovementRecord(sourceType: ExpenseSourceType = .shareExtension, in modelContext: ModelContext) throws -> MoneyMovement {
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteParts = [trimmedMerchant, notes.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        let movement = MoneyMovement(
            kind: movementKind,
            amountMinor: Money.minorUnits(from: parsedAmount),
            date: date,
            account: AccountLinker.resolveAccount(named: fundingAccount, in: modelContext),
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: " · "),
            transactionReference: transactionReference,
            sourceType: sourceType,
            paymentChannel: selectedPaymentChannel
        )
        modelContext.insert(movement)
        try modelContext.save()
        return movement
    }

    /// Saves the draft as a new expense (screenshot attached as its receipt), or — only when the user chose
    /// "Merge with Existing" for a same-reference match — adds its details to that existing expense.
    @discardableResult
    public func saveExpenseRecord(mergeInto mergeTarget: Expense?, sourceType: ExpenseSourceType = .shareExtension,
                                  imageStore: ImageStorageService = .shared, in modelContext: ModelContext) throws -> Expense {
        let savedImagePath = inputImage.flatMap { imageStore.saveImage($0) }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? "Unknown" : trimmedMerchant

        var resolvedSource = selectedPaymentSource
        if resolvedSource == .unknown {
            resolvedSource = PaymentSource.from(string: fundingAccount)
        }

        let saved: Expense
        if let existing = mergeTarget {
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
                rawOCRText: nil,
                fundingInstrument: fundingInstrument
            )
            _ = TransactionReconciliationEngine.shared.reconcile(existing: existing, with: candidate, in: modelContext)
            // Applied only when it matches the merged expense's amount; otherwise nothing changes.
            splitDraft?.apply(to: existing, in: modelContext)
            saved = existing
        } else {
            let expense = Expense(
                amount: parsedAmount,
                currency: "RM",
                merchant: finalMerchant,
                category: selectedCategory,
                paymentSource: resolvedSource,
                underlyingBank: resolvedSource == .applePay ? PaymentSource.from(string: fundingAccount) : nil,
                paymentMethod: resolvedSource.defaultPaymentMethod,
                date: date,
                notes: notes,
                transactionReference: transactionReference,
                imageRelativePath: savedImagePath,
                sourceType: sourceType,
                ocrText: nil,
                confidence: 1.0,
                paymentChannel: selectedPaymentChannel,
                fundingAccount: fundingAccount,
                fundingInstrument: fundingInstrument
            )
            modelContext.insert(expense)
            AccountLinker.relink(expense, in: modelContext)
            // Split Money: shares (and who paid) are saved with the expense; PayBook balances follow from them.
            splitDraft?.apply(to: expense, in: modelContext)
            TransactionClassifier.learn(merchant: finalMerchant, category: selectedCategory, accountId: expense.account?.id, in: modelContext)
            ChannelLearning.learn(merchant: finalMerchant, funding: fundingAccount, channel: selectedPaymentChannel, in: modelContext)
            saved = expense
        }

        try modelContext.save()
        modelContext.processPendingChanges()
        return saved
    }
}

public struct ShareExtensionView: View {
    @ObservedObject public var viewModel: ShareExtensionViewModel
    public let onComplete: () -> Void
    public let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    private let commonFundingAccounts = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"]

    public init(
        viewModel: ShareExtensionViewModel,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private var parsedAmount: Double { viewModel.parsedAmount }

    /// A split must add up to the amount exactly before the expense can be saved.
    private var isValid: Bool { viewModel.isValid }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive system background: respects Light and Dark mode automatically
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                switch viewModel.phase {
                case .receiving:
                    receivingView()

                case .processing(let image):
                    processingView(image: image)

                case .reviewing(let image, let parsed):
                    reviewingView(image: image, parsed: parsed)

                case .noTextFound(let image):
                    noTextFoundView(image: image)

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("SpenDrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelTask()
                        shareLog("[SpenDropShare][OCR] user cancelled extension")
                        onCancel()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }

    // MARK: - State 1: Receiving Screenshot
    private func receivingView() -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.3)

            Text("SpenDrop")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Receiving screenshot…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    // MARK: - State 2: Automatic Processing (Scanning OCR)
    private func processingView(image: UIImage) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            // Image Preview Thumbnail
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.3)

                Text("Reading payment details…")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Extracting merchant, amount & category on-device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)
        }
        .padding()
    }

    // MARK: - State 3: No Text Found (Fallback View)
    private func noTextFoundView(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    Text("Couldn't read payment details")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("We couldn't detect transaction details in this screenshot. You can enter the expense manually or try scanning again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 12) {
                    Button {
                        viewModel.enterManualDetails(image: image)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.pencil")
                            Text("Enter Details Manually")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        viewModel.startAutomaticOCR(image: image)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    // MARK: - State 4: Review & Edit Form
    private func reviewingView(image: UIImage, parsed: ParsedTransaction) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status Banner
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
                } else if viewModel.duplicateResult.isDuplicate {
                    bannerView(
                        icon: "exclamationmark.triangle.fill",
                        color: .yellow,
                        title: "Possible Duplicate Detected",
                        subtitle: viewModel.duplicateResult.reason ?? "This transaction may already exist in SpenDrop."
                    )
                } else if parsed.confidence == .high {
                    bannerView(
                        icon: "checkmark.circle.fill",
                        color: .green,
                        title: "Payment Detected",
                        subtitle: "Verified from your transaction screenshot."
                    )
                } else {
                    bannerView(
                        icon: "checkmark.circle",
                        color: .blue,
                        title: "Payment Details",
                        subtitle: "Review and confirm details below."
                    )
                }

                // Save as
                ShareSaveAsSection(viewModel: viewModel)

                // Screenshot Preview Thumbnail (Allows verifying while editing)
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(uiColor: .separator), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Transaction Screenshot")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if let ref = viewModel.transactionReference, !ref.isEmpty {
                            Text("Ref: \(ref)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Attached to this expense")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Amount, details, Split Money and remarks (the same editor fields Bulk Import uses)
                ShareDraftEditor(viewModel: viewModel, currency: parsed.currency, fundingOptions: commonFundingAccounts)

                // Save Expense Button
                Button(action: handleSaveButtonTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(viewModel.saveAs == .expense ? "Save Expense" : "Save \(viewModel.saveAs.rawValue)")
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
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .padding()
        }
        .alert("Possible Duplicate", isPresented: Binding(get: { viewModel.movementDuplicateMessage != nil },
                                                         set: { if !$0 { viewModel.movementDuplicateMessage = nil } })) {
            Button("Add Anyway") { saveMovement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.movementDuplicateMessage ?? "")
        }
        .alert(viewModel.duplicateResult.isStrong ? "Already Recorded?" : "Possible Duplicate", isPresented: $viewModel.showingDuplicateConfirmation) {
            // "Add Anyway" always saves a NEW expense; it never merges into the matched one.
            Button("Add Anyway") {
                saveToSwiftData(mergeInto: nil)
            }
            if viewModel.duplicateResult.isStrong, let existing = viewModel.duplicateResult.matchedExpense {
                Button("Merge with Existing") {
                    saveToSwiftData(mergeInto: existing)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.duplicateResult.reason ?? "This may already be recorded. If it's a separate payment, add it anyway.")
        }
    }

    // MARK: - State 5: Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("SpenDrop Share Extension")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - Helper Views & Actions
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

    private var movementKind: MoneyMovementKind { viewModel.movementKind }

    private func handleSaveButtonTapped() {
        if viewModel.saveAs != .expense {
            let amountMinor = Money.minorUnits(from: parsedAmount)
            if let match = MovementDuplicateDetector.findMatch(amountMinor: amountMinor, date: viewModel.date,
                                                               reference: viewModel.transactionReference, kind: movementKind, in: modelContext) {
                viewModel.movementDuplicateMessage = "A \(match.kind.displayName.lowercased()) of the same amount on \(match.date.formatted(date: .abbreviated, time: .omitted)) is already recorded."
            } else {
                saveMovement()
            }
            return
        }
        if viewModel.duplicateResult.isDuplicate {
            viewModel.showingDuplicateConfirmation = true
        } else {
            saveToSwiftData(mergeInto: nil)
        }
    }

    /// Money In / Money Out from a shared screenshot. The account is resolved from the funding account text
    /// (Unknown stays unlinked, no duplicate accounts are created).
    private func saveMovement() {
        guard isValid else { return }
        do {
            let movement = try viewModel.saveMovementRecord(in: modelContext)
            shareLog("[SpenDropShare] money movement saved (\(movement.kind.rawValue))")
        } catch {
            shareLog("[SpenDropShare][ERROR] failed to save money movement: \(error.localizedDescription)")
        }
        HapticFeedback.notification(.success)
        onComplete()
    }

    /// Saves the shared payment as a new expense, or — only when the user chose "Merge with Existing" for a
    /// same-reference match — adds its details to that existing expense.
    private func saveToSwiftData(mergeInto mergeTarget: Expense?) {
        guard isValid else { return }
        do {
            try viewModel.saveExpenseRecord(mergeInto: mergeTarget, in: modelContext)
            shareLog("[SpenDropShare][OCR] expense saved successfully")
        } catch {
            shareLog("[SpenDropShare][OCR][ERROR] failed to save expense: \(error.localizedDescription)")
        }

        HapticFeedback.notification(.success)
        onComplete()
    }
}

// MARK: - Reusable draft editor pieces
// The Share Extension review form, split into pieces so Bulk Import can show exactly the same fields for each of its
// drafts. They only read and write a `ShareExtensionViewModel`; saving stays with the screen that shows them.

/// "Save as" Expense / Money In / Money Out, with the reason it was suggested.
public struct ShareSaveAsSection: View {
    @ObservedObject public var viewModel: ShareExtensionViewModel

    public init(viewModel: ShareExtensionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Save as", selection: $viewModel.saveAs) {
                ForEach(ShareExtensionViewModel.SaveType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            if viewModel.suggestedMovementKind == .ownTransfer {
                Text("Looks like a top-up between your own accounts. Open SpenDrop to record it as a Transfer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let reason = viewModel.directionReason {
                Text("Suggested from the screenshot: \(reason). Please confirm.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Amount, Paid To, Category, Funding Method, Payment Channel, Funding Instrument, Date & Time, Split Money and
/// Remarks for one draft. `showsPaidForSomeone` adds the "Paid for Someone" shortcut of Add Expense.
public struct ShareDraftEditor: View {
    @ObservedObject public var viewModel: ShareExtensionViewModel
    public let currency: String
    public let fundingOptions: [String]
    public let showsPaidForSomeone: Bool

    public init(viewModel: ShareExtensionViewModel, currency: String, fundingOptions: [String], showsPaidForSomeone: Bool = false) {
        self.viewModel = viewModel
        self.currency = currency
        self.fundingOptions = fundingOptions
        self.showsPaidForSomeone = showsPaidForSomeone
    }

    private var parsedAmount: Double { viewModel.parsedAmount }

    /// A small explanation under a field: why SpenDrop suggested it, or that it needs checking.
    private func shareCaption(_ text: String, warning: Bool = true) -> some View {
        Label(text, systemImage: warning ? "exclamationmark.circle" : "info.circle")
            .font(.caption)
            .foregroundStyle(warning ? Color.orange : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 52)
            .padding(.trailing, 16)
            .padding(.bottom, 8)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Amount Card
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currency)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $viewModel.amountText)
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

            // Details Card
            VStack(spacing: 0) {
                // Paid To (Merchant / Payee)
                HStack(spacing: 12) {
                    Image(systemName: "storefront.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Paid To")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Optional", text: $viewModel.merchant)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 52)

                // Category
                HStack(spacing: 12) {
                    Image(systemName: viewModel.selectedCategory.icon)
                        .foregroundStyle(viewModel.selectedCategory.color)
                        .frame(width: 24)
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(ExpenseCategory.allCases) { cat in
                            Button {
                                viewModel.selectedCategory = cat
                                viewModel.categoryHint = nil
                            } label: {
                                Label(cat.rawValue, systemImage: cat.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedCategory.rawValue)
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

                // Funding Method (Where money came from)
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Funding Method")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(fundingOptions, id: \.self) { acc in
                            Button {
                                viewModel.fundingAccount = acc
                            } label: {
                                Text(acc)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.fundingAccount.isEmpty ? "Unknown" : viewModel.fundingAccount)
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
                if let hint = viewModel.categoryHint, hint.needsReview {
                    shareCaption("Suggested · please check. \(hint.reason)")
                }

                Divider().padding(.leading, 52)

                // Payment Channel (How payment was made - ALWAYS VISIBLE)
                HStack(spacing: 12) {
                    Image(systemName: viewModel.selectedPaymentChannel.iconName)
                        .foregroundStyle(viewModel.selectedPaymentChannel.tintColor)
                        .frame(width: 24)
                    Text("Payment Channel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(PaymentChannel.allCases) { ch in
                            Button {
                                viewModel.selectedPaymentChannel = ch
                                viewModel.channelHint = nil
                            } label: {
                                Label(ch.displayName, systemImage: ch.iconName)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedPaymentChannel.displayName)
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
                if let hint = viewModel.channelHint {
                    if hint.channel == .unknown {
                        shareCaption("Unknown — needs review. \(hint.reason)")
                    } else if !hint.reason.isEmpty {
                        shareCaption(hint.reason, warning: false)
                    }
                }

                // Funding Instrument (if available)
                if let instrument = viewModel.fundingInstrument, !instrument.isEmpty {
                    Divider().padding(.leading, 52)

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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

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
                    DatePicker("", selection: $viewModel.date)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Split Money: share the amount with people in PayBook before saving (expenses only)
            if viewModel.saveAs == .expense {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { viewModel.splitDraft != nil }, set: { on in
                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.splitDraft = on ? SplitDraft() : nil }
                    })) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.2.fill").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Split Money").font(.subheadline.weight(.semibold))
                                Text("Share this amount with people in PayBook").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("share.splitToggle")
                    if viewModel.splitDraft != nil {
                        Divider()
                        InlineSplitSection(draft: Binding(get: { viewModel.splitDraft ?? SplitDraft() }, set: { viewModel.splitDraft = $0 }),
                                           totalMinor: Money.minorUnits(from: parsedAmount))
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Notes
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("REMARKS")
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

                TextField("Add remarks (optional)", text: $viewModel.notes)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if showsPaidForSomeone && viewModel.saveAs == .expense && viewModel.splitDraft == nil {
                // "I paid RM100 for Bijoy" / "Bijoy paid for me" without typing anyone's share (as in Add Expense).
                Button {
                    var draft = SplitDraft()
                    draft.purpose = .paidFor
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.splitDraft = draft }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paid for Someone").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("You paid for them, or they paid for you").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("draft.paidFor")
            }
        }
    }
}
