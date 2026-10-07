import SwiftUI
import SwiftData
import PhotosUI

public struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var fundingAccount: String = "Maybank"
    @State private var selectedPaymentChannel: PaymentChannel = .unknown
    @State private var selectedPaymentSource: PaymentSource
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var currency: String = "RM"
    @State private var entryType: TransactionEntryType = .expense
    // Optional split (Phase 4). nil = normal expense.
    @State private var splitDraft: SplitDraft?
    @State private var categoryTouched = false

    private let commonFundingAccounts = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"]

    // Image Import & OCR States
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var parsedTransaction: ParsedTransaction?
    @State private var showingReviewSheet = false
    @State private var showingOCRError = false
    @State private var ocrErrorMessage = ""

    // PayBook Integration States
    @State private var showingPayBookPicker = false
    @State private var showingSaveToPayBookSheet = false

    // Quick suggestions for fast Malaysian daily spending
    private let quickMerchants = ["McDonald's", "Grab", "MYDIN", "Mamak", "Starbucks", "7-Eleven", "Shell"]
    private let quickAmounts: [Double] = [5, 10, 20, 50]

    public init(initialPaymentSource: PaymentSource = .cash) {
        _selectedPaymentSource = State(initialValue: initialPaymentSource)
    }

    /// Fixed list plus any account the user added in More → Accounts.
    private var fundingOptions: [String] {
        AccountLinker.fundingOptions(base: commonFundingAccounts, accounts: accounts)
    }

    private var parsedAmount: Double {
        CurrencyFormatter.parse(string: amountText) ?? 0.0
    }

    private var isValid: Bool {
        parsedAmount > 0 && (splitDraft?.isValid(totalMinor: Money.minorUnits(from: parsedAmount)) ?? true)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if entryType == .expense {
                ZStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            // SCAN / IMPORT SCREENSHOT BUTTON (Milestone 2 core feature)
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .current) {
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
                            .simultaneousGesture(TapGesture().onEnded {
                                print("[SpenDrop][PICKER_DIAG] AddExpenseView PhotosPicker tapped")
                            })
                            .onChange(of: selectedPhotoItem) { oldItem, newItem in
                                print("[SpenDrop][PICKER_DIAG] AddExpenseView selectedPhotoItem changed: \(oldItem != nil ? "non-nil" : "nil") -> \(newItem != nil ? "non-nil" : "nil")")
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

                            // FUNDING ACCOUNT PICKER (Where money came from)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("FUNDING ACCOUNT (WHERE MONEY CAME FROM)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .tracking(0.8)
                                    .padding(.horizontal, 4)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(fundingOptions, id: \.self) { acc in
                                            Button(action: {
                                                HapticFeedback.selection()
                                                fundingAccount = acc
                                            }) {
                                                Text(acc)
                                                    .font(.subheadline)
                                                    .fontWeight(fundingAccount == acc ? .semibold : .regular)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        fundingAccount == acc
                                                            ? Color.blue
                                                            : Color(uiColor: .secondarySystemGroupedBackground)
                                                    )
                                                    .foregroundStyle(
                                                        fundingAccount == acc
                                                            ? Color.white
                                                            : Color.primary
                                                    )
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                        }
                                    }
                                }
                            }

                            // PAYMENT CHANNEL PICKER (How payment was made)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PAYMENT CHANNEL (HOW PAYMENT WAS MADE)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .tracking(0.8)
                                    .padding(.horizontal, 4)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(PaymentChannel.allCases) { channel in
                                            Button(action: {
                                                HapticFeedback.selection()
                                                selectedPaymentChannel = channel
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: channel.iconName)
                                                    Text(channel.displayName)
                                                        .font(.subheadline)
                                                        .fontWeight(selectedPaymentChannel == channel ? .semibold : .regular)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedPaymentChannel == channel
                                                        ? channel.tintColor
                                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                                )
                                                .foregroundStyle(
                                                    selectedPaymentChannel == channel
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
                                            categoryTouched = true
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
                                HStack {
                                    Text("MERCHANT / RECIPIENT")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                        .tracking(1.0)

                                    Spacer()

                                    Button(action: {
                                        showingPayBookPicker = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.crop.rectangle.stack")
                                            Text("Select from PayBook")
                                        }
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 4)

                                TextField("e.g. McDonald's, Mamak, Rahim (optional)", text: $merchant)
                                    .onChange(of: merchant) { _, newMerchant in
                                        // A trusted learned rule may pre-select the category, never over the user's own pick.
                                        guard !categoryTouched,
                                              let rule = TransactionClassifier.rule(for: newMerchant, in: modelContext),
                                              rule.hitCount >= TransactionClassifier.trustedHitCount,
                                              let learned = rule.category else { return }
                                        selectedCategory = learned
                                    }
                                    .padding()
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                if !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button(action: {
                                        showingSaveToPayBookSheet = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.badge.plus")
                                            Text("Save Recipient to PayBook")
                                        }
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.blue)
                                    }
                                    .padding(.horizontal, 4)
                                }

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

                            // SPLIT TRANSACTION (off = normal expense; on = split right here, no extra screen).
                            // The same InlineSplitSection is used by Edit, scan review and the Share Extension.
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: Binding(get: { splitDraft != nil }, set: { on in
                                    withAnimation(.easeInOut(duration: 0.2)) { splitDraft = on ? SplitDraft() : nil }
                                })) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.2.fill").foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Split Transaction").font(.subheadline.weight(.semibold))
                                            Text("Share this amount with people in PayBook").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("addExpense.splitToggle")
                                if splitDraft != nil {
                                    Divider()
                                    InlineSplitSection(draft: Binding(get: { splitDraft ?? SplitDraft() }, set: { splitDraft = $0 }),
                                                       totalMinor: Money.minorUnits(from: parsedAmount), currency: currency)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            if splitDraft == nil {
                                // "I paid RM100 for Bijoy" / "Bijoy paid for me" without typing anyone's share.
                                Button {
                                    var draft = SplitDraft()
                                    draft.purpose = .paidFor
                                    withAnimation(.easeInOut(duration: 0.2)) { splitDraft = draft }
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
                                    .padding()
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("addExpense.paidFor")
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
                } else {
                    // Money In / Money Out / Transfer (Phase 3). Expense stays the default and is unchanged.
                    MoneyMovementFormView(entryType: entryType) { dismiss() }
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
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(TransactionEntryType.allCases) { type in
                            Button {
                                entryType = type
                            } label: {
                                Label(type.title, systemImage: type.icon)
                            }
                            .accessibilityIdentifier("addType.\(type.rawValue)")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(entryType == .expense ? "Add Expense" : "Add \(entryType.title)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Record type: \(entryType.title)")
                }
            }
            .sheet(item: $parsedTransaction) { parsed in
                ExpenseReviewView(parsed: parsed) { savedExpense in
                    dismiss()
                }
                .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showingPayBookPicker) {
                PayBookPickerSheet(mode: .selectForPayment) { profile, method in
                    merchant = profile.name
                    let provLower = method.displayProvider.lowercased()
                    if provLower.contains("maybank") {
                        selectedPaymentSource = .maybank
                    } else if provLower.contains("cimb") {
                        selectedPaymentSource = .cimb
                    } else if provLower.contains("rhb") {
                        selectedPaymentSource = .rhb
                    } else if provLower.contains("touch") || provLower.contains("tng") {
                        selectedPaymentSource = .touchNGo
                    } else if provLower.contains("grab") {
                        selectedPaymentSource = .grabPay
                    } else if provLower.contains("boost") {
                        selectedPaymentSource = .boost
                    } else if provLower.contains("duitnow") {
                        selectedPaymentSource = .duitNow
                    }
                    let accInfo = "\(method.displayProvider): \(method.accountIdentifier)"
                    if notes.isEmpty {
                        notes = accInfo
                    } else if !notes.contains(method.accountIdentifier) {
                        notes += " (\(accInfo))"
                    }
                }
            }
            .sheet(isPresented: $showingSaveToPayBookSheet) {
                PayBookPickerSheet(mode: .saveRecipient(name: merchant, provider: selectedPaymentSource.rawValue, account: ""))
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

    @MainActor
    private func processSelectedImage(item: PhotosPickerItem?) async {
        guard let item = item else {
            print("[SpenDrop][IMAGE] Picker selection: nil (cancelled or reset)")
            return
        }

        print("[SpenDrop][IMAGE] Picker selection received")
        print("[SpenDrop][IMAGE] supportedContentTypes = \(item.supportedContentTypes)")
        print("[SpenDrop][IMAGE] itemIdentifier = \(item.itemIdentifier ?? "nil")")

        isProcessingOCR = true
        HapticFeedback.impact(.light)

        // Stage 1: Load Data
        print("[SpenDrop][IMAGE] Loading Data...")
        let data: Data
        do {
            guard let loadedData = try await item.loadTransferable(type: Data.self) else {
                let err = "Data loaded from PhotosPickerItem was nil"
                print("[SpenDrop][IMAGE] Data loaded: FAIL (\(err))")
                handleImportFailure(stage: "Loading Data", error: NSError(domain: "SpenDrop.ImageImport", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                return
            }
            data = loadedData
            print("[SpenDrop][IMAGE] Data loaded: \(data.count) bytes")
        } catch {
            print("[SpenDrop][IMAGE] Loading Data FAILED: \(error)")
            handleImportFailure(stage: "Loading Data", error: error)
            return
        }

        // Stage 2: UIImage decode
        guard let uiImage = UIImage(data: data) else {
            let err = "Data (\(data.count) bytes) could not be decoded by UIImage(data:)"
            print("[SpenDrop][IMAGE] UIImage decode: FAIL (\(err))")
            handleImportFailure(stage: "UIImage decode", error: NSError(domain: "SpenDrop.ImageImport", code: -2, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpenDrop][IMAGE] UIImage decode: SUCCESS (size: \(uiImage.size), scale: \(uiImage.scale), orientation: \(uiImage.imageOrientation.rawValue))")

        // Stage 3: CGImage decode
        guard let cgImage = uiImage.cgImage ?? extractCGImage(from: uiImage) else {
            let err = "Failed to obtain CGImage from UIImage"
            print("[SpenDrop][IMAGE] CGImage decode: FAIL (\(err))")
            handleImportFailure(stage: "CGImage decode", error: NSError(domain: "SpenDrop.ImageImport", code: -3, userInfo: [NSLocalizedDescriptionKey: err]))
            return
        }
        print("[SpenDrop][IMAGE] CGImage decode: SUCCESS (width: \(cgImage.width), height: \(cgImage.height))")

        // Stage 4: Downsampling check
        let maxSide = max(uiImage.size.width, uiImage.size.height)
        if maxSide > 2048 {
            print("[SpenDrop][IMAGE] Downsampling: NEEDED (original maxSide: \(maxSide))")
        } else {
            print("[SpenDrop][IMAGE] Downsampling: NOT NEEDED (original maxSide: \(maxSide) <= 2048)")
        }

        // Stage 5: Temporary storage diagnostic test (Bypass test)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).jpg")
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: tempURL)
                print("[SpenDrop][IMAGE] Temp save: SUCCESS (\(jpegData.count) bytes written to \(tempURL.lastPathComponent))")
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                print("[SpenDrop][IMAGE] Temp save: FAIL (\(error))")
            }
        } else {
            print("[SpenDrop][IMAGE] Temp save: FAIL (jpegData conversion failed)")
        }

        // Stage 6: App Group ImageStorageService diagnostic test
        if let savedRelPath = ImageStorageService.shared.saveImage(uiImage) {
            print("[SpenDrop][IMAGE] Image storage started & completed: SUCCESS (relativePath: \(savedRelPath))")
            ImageStorageService.shared.deleteImage(relativePath: savedRelPath)
        } else {
            print("[SpenDrop][IMAGE] Image storage: FAIL (App Group write failed)")
        }

        // Stage 7: OCR
        print("[SpenDrop][IMAGE] OCR started")
        let ocrResult: OCRResult
        do {
            ocrResult = try await OCRService.shared.recognizeText(from: uiImage)
            print("[SpenDrop][IMAGE] OCR completed: SUCCESS (lines: \(ocrResult.lines.count), avgConfidence: \(ocrResult.averageConfidence), textLength: \(ocrResult.fullText.count))")
            #if DEBUG
            for (idx, line) in ocrResult.lines.prefix(5).enumerated() {
                print("[SpenDrop][IMAGE] Line \(idx + 1): \"\(line.text)\" (conf: \(line.confidence))")
            }
            #endif
        } catch {
            print("[SpenDrop][IMAGE] OCR FAILED: \(error)")
            handleImportFailure(stage: "Vision OCR", error: error)
            return
        }

        // Stage 8: Parser
        print("[SpenDrop][IMAGE] Parser started")
        let parsed = TransactionParser.shared.parse(ocrResult: ocrResult, image: uiImage)
        #if DEBUG
        print("[SpenDrop][IMAGE] Parser completed: amount: \(parsed.amount != nil ? "RM\(parsed.amount!)" : "nil"), merchant: \(parsed.merchant ?? "nil"), source: \(parsed.paymentSource?.rawValue ?? "nil"), category: \(parsed.category?.rawValue ?? "nil"), confidence: \(parsed.confidence.rawValue), isBalance: \(parsed.isBalanceOrLimitOnly), isFailed: \(parsed.isFailedTransaction)")
        #endif

        isProcessingOCR = false
        selectedPhotoItem = nil
        HapticFeedback.notification(.success)
        print("[SpenDrop][IMAGE] Review screen opened")
        self.parsedTransaction = parsed
    }

    @MainActor
    private func handleImportFailure(stage: String, error: Error) {
        isProcessingOCR = false
        selectedPhotoItem = nil
        ocrErrorMessage = "Failed at [\(stage)]:\n\(error.localizedDescription)"
        showingOCRError = true
        HapticFeedback.notification(.error)
        print("[SpenDrop][IMAGE] PIPELINE FAILURE at [\(stage)]: \(error)")
    }

    private func extractCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        if let ci = image.ciImage {
            return CIContext(options: nil).createCGImage(ci, from: ci.extent)
        }
        return nil
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
            sourceType: selectedPaymentChannel == .cash ? .manual : .manual,
            paymentChannel: selectedPaymentChannel,
            fundingAccount: fundingAccount
        )

        modelContext.insert(expense)
        AccountLinker.relink(expense, in: modelContext)
        if let splitDraft {
            splitDraft.apply(to: expense, in: modelContext)
        }
        TransactionClassifier.learn(merchant: trimmedMerchant, category: selectedCategory, accountId: expense.account?.id, in: modelContext)
        ChannelLearning.learn(merchant: trimmedMerchant, funding: fundingAccount, channel: selectedPaymentChannel, in: modelContext)
        try? modelContext.save()
        modelContext.processPendingChanges()

        if let all = try? modelContext.fetch(FetchDescriptor<Expense>()) {
            TransactionFilterEngine.shared.update(expenses: all)
        }

        HapticFeedback.notification(.success)
        dismiss()
    }
}


