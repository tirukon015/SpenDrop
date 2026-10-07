import SwiftUI
import SwiftData
import PhotosUI

/// Bulk Screenshot Import: pick up to 30 screenshots → each is read on the device → a review queue of normal
/// transaction drafts (collapsed cards that open into the existing editor) → "Add N Transactions" saves each draft as
/// its own record through the existing save path. See Common/BusinessRules/bulk-import.md.
public struct BulkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @StateObject private var session = BulkImportSession()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var phase: Phase = .pick
    @State private var leftOut = 0
    @State private var expandedID: UUID?
    @State private var previewShot: BulkImportSession.Screenshot?
    @State private var outcome: BulkImportSession.SaveOutcome?
    @State private var confirmingDiscard = false
    @State private var processingTask: Task<Void, Never>?

    private enum Phase { case pick, processing, review, done }
    private let commonFundingAccounts = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"]

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick: pickView
                case .processing: processingView
                case .review: reviewView
                case .done: doneView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if phase == .review && !session.activeDrafts.isEmpty { confirmingDiscard = true } else { close() }
                        }
                    }
                }
            }
            .confirmationDialog("Discard this import?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard \(session.activeDrafts.count) Drafts", role: .destructive) { close() }
                Button("Keep Reviewing", role: .cancel) {}
            } message: {
                Text("Nothing has been saved yet.")
            }
            .sheet(item: $previewShot) { shot in
                ScreenshotPreview(shot: shot)
            }
        }
        .interactiveDismissDisabled(phase == .processing || phase == .review)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            start(with: items)
        }
        .onAppear(perform: loadUITestFixtureIfNeeded)
        .onDisappear {
            processingTask?.cancel()
            session.end()
        }
    }

    private func close() {
        processingTask?.cancel()
        session.end()
        dismiss()
    }

    // MARK: - 1. Pick

    private var pickView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .padding(.top, 32)
                VStack(spacing: 8) {
                    Text("Import Several Screenshots")
                        .font(.title2.weight(.bold))
                    Text("Pick up to \(BulkImportSession.maxScreenshots) payment screenshots. Each one is read on this iPhone and becomes its own transaction — nothing is saved until you review them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)

                PhotosPicker(selection: $pickerItems, maxSelectionCount: BulkImportSession.maxScreenshots,
                             selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current) {
                    Label("Choose Screenshots", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("bulk.choose")

                VStack(alignment: .leading, spacing: 10) {
                    hintRow("list.bullet.rectangle", "A history screenshot with several payments becomes one transaction per row.")
                    hintRow("doc.on.doc", "Possible duplicates are skipped unless you choose to add them.")
                    hintRow("lock.shield", "Screenshots stay on this iPhone; each saved transaction keeps its own screenshot.")
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
    }

    private func hintRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func start(with items: [PhotosPickerItem]) {
        phase = .processing
        processingTask = Task { @MainActor in
            var images: [UIImage?] = []
            for item in items.prefix(BulkImportSession.maxScreenshots) {
                let data = try? await item.loadTransferable(type: Data.self)
                images.append(data.flatMap { BulkImportSession.loadImage(data: $0) })
            }
            leftOut = max(0, items.count - BulkImportSession.maxScreenshots) + session.add(images: images)
            pickerItems = []
            await session.process(in: modelContext)
            guard !Task.isCancelled else { return }
            withAnimation { phase = .review }
        }
    }

    // MARK: - 2. Processing

    private var processingView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.screenshots.isEmpty ? "Loading screenshots…" : "Reading \(min(session.doneCount + 1, session.screenshots.count)) of \(session.screenshots.count)…")
                        .font(.headline)
                    ProgressView(value: Double(session.doneCount), total: Double(max(session.screenshots.count, 1)))
                    Text("Read on this iPhone, \(BulkImportSession.concurrency) at a time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if leftOut > 0 {
                Section {
                    Label("Only the first \(BulkImportSession.maxScreenshots) screenshots are imported. \(leftOut) left out.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(session.screenshots) { shot in
                    HStack(spacing: 12) {
                        thumbnail(shot, size: 40)
                        Text("Screenshot \(shot.number)").font(.subheadline)
                        Spacer()
                        processingState(shot)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("bulk.progress.\(shot.number)")
                }
            }
        }
    }

    @ViewBuilder
    private func processingState(_ shot: BulkImportSession.Screenshot) -> some View {
        switch shot.state {
        case .waiting:
            Label("Waiting", systemImage: "circle").font(.caption).foregroundStyle(.secondary)
        case .processing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading…").font(.caption).foregroundStyle(.secondary) }
        case .done where shot.draftCount > 0:
            Label(shot.draftCount == 1 ? "1 transaction" : "\(shot.draftCount) transactions", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .done, .failed:
            Label("No transaction", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: - 3. Review queue

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                ForEach(session.activeDrafts) { draft in
                    draftCard(draft)
                }
                ForEach(session.unreadableScreenshots) { shot in
                    unreadableCard(shot)
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(session.activeScreenshotCount) screenshot\(session.activeScreenshotCount == 1 ? "" : "s") · \(session.activeDrafts.count) transaction\(session.activeDrafts.count == 1 ? "" : "s") detected")
                .font(.headline)
                .accessibilityIdentifier("bulk.summary")
            HStack(spacing: 8) {
                summaryChip("checkmark.circle.fill", "\(session.readyCount) ready", .green)
                summaryChip("exclamationmark.triangle.fill", "\(session.needsReviewCount) need review", .orange)
                summaryChip("doc.on.doc.fill", "\(session.duplicateCount) possible duplicate\(session.duplicateCount == 1 ? "" : "s")", .yellow)
            }
            Text("Total \(CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: session.totalMinor)))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("bulk.total")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryChip(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .foregroundStyle(color == .yellow ? Color.orange : color)
            .clipShape(Capsule())
    }

    private func statusBadge(_ status: BulkImportSession.Status) -> some View {
        let (text, icon, color): (String, String, Color) = {
            switch status {
            case .ready: return ("Ready", "checkmark.circle.fill", .green)
            case .needsReview: return ("Needs Review", "exclamationmark.triangle.fill", .orange)
            case .possibleDuplicate: return ("Possible Duplicate", "doc.on.doc.fill", .yellow)
            }
        }()
        return Label(text, systemImage: icon)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color == .yellow ? Color.orange : color)
            .clipShape(Capsule())
    }

    private func paymentInfo(_ e: ShareExtensionViewModel) -> String? {
        var parts: [String] = []
        let funding = e.fundingAccount.trimmingCharacters(in: .whitespaces)
        if !funding.isEmpty && funding != "Unknown" { parts.append(funding) }
        if e.selectedPaymentChannel != .unknown { parts.append(e.selectedPaymentChannel.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func draftCard(_ draft: BulkImportSession.Draft) -> some View {
        let e = draft.editor
        let expanded = expandedID == draft.id
        let status = session.status(of: draft)
        let willSave = session.willSave(draft)
        let merchant = e.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = "Screenshot \(draft.screenshotNumber)" + (draft.rowNumber.map { " · row \($0)" } ?? "")
        let line = [e.date.formatted(.dateTime.day().month(.abbreviated).year()),
                    e.date.formatted(date: .omitted, time: .shortened),
                    paymentInfo(e)].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { toggle(draft) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    if let shot = session.screenshot(draft.screenshotID) { thumbnail(shot, size: 44) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(merchant.isEmpty ? "Unknown merchant" : merchant)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(e.parsedAmount > 0 ? (e.saveAs == .moneyIn ? "+" : "") + CurrencyFormatter.format(amount: e.parsedAmount, currency: draft.parsed.currency) : "No amount")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(e.parsedAmount > 0 ? (e.saveAs == .moneyIn ? Color.green : Color.primary) : Color.red)
                                .strikethrough(!willSave && e.parsedAmount > 0, color: .secondary)
                        }
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 6) {
                            statusBadge(status)
                            if e.saveAs != .expense {
                                Text(e.saveAs.rawValue).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(source).font(.caption2).foregroundStyle(.tertiary)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bulk.card.\(draft.screenshotNumber).\(draft.rowNumber ?? 0)")

            if expanded {
                Divider()
                expandedEditor(draft)
                    .padding(14)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(status == .possibleDuplicate ? Color.yellow.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    private func toggle(_ draft: BulkImportSession.Draft) {
        if expandedID == draft.id {
            expandedID = nil
            session.refreshDuplicates(in: modelContext)
        } else {
            if expandedID != nil { session.refreshDuplicates(in: modelContext) }
            expandedID = draft.id
            session.markReviewed(draft)
        }
    }

    /// The complete existing editor (same pieces as the Share Extension review), plus this draft's duplicate actions,
    /// its screenshot and Remove.
    @ViewBuilder
    private func expandedEditor(_ draft: BulkImportSession.Draft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let match = draft.match {
                duplicateSection(draft, match: match)
            }
            if draft.parsed.isFailedTransaction {
                Label("This screenshot looks like a failed or declined payment.", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption).foregroundStyle(.red)
            } else if draft.parsed.isBalanceOrLimitOnly {
                Label("This looks like an account balance rather than a payment.", systemImage: "info.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            ShareSaveAsSection(viewModel: draft.editor)

            if let shot = session.screenshot(draft.screenshotID) {
                Button { previewShot = shot } label: {
                    HStack(spacing: 12) {
                        thumbnail(shot, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshot \(shot.number)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(draft.editor.saveAs == .expense ? "Saved as this transaction's receipt · tap to view" : "Tap to view")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ShareDraftEditor(viewModel: draft.editor, currency: draft.parsed.currency,
                             fundingOptions: AccountLinker.fundingOptions(base: commonFundingAccounts, accounts: accounts),
                             showsPaidForSomeone: true)

            HStack {
                Button(role: .destructive) {
                    withAnimation {
                        expandedID = nil
                        session.remove(draft, in: modelContext)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .accessibilityIdentifier("bulk.remove")
                Spacer()
                Button("Done") { withAnimation(.easeInOut(duration: 0.2)) { toggle(draft) } }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("bulk.collapse")
            }
            .padding(.top, 4)
        }
    }

    private func duplicateSection(_ draft: BulkImportSession.Draft, match: BulkImportSession.Match) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(match.mergeTarget != nil ? "Already Recorded?" : "Possible Duplicate", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
            Text(match.reason).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                actionButton("Add Anyway", selected: draft.action == .addAnyway) { session.setAction(.addAnyway, for: draft) }
                if match.mergeTarget != nil && draft.editor.saveAs == .expense {
                    actionButton("Merge with Existing", selected: draft.action == .merge) { session.setAction(.merge, for: draft) }
                }
                actionButton("Skip", selected: draft.action == .skip) { session.setAction(.skip, for: draft) }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { HapticFeedback.selection(); action() }) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func unreadableCard(_ shot: BulkImportSession.Screenshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                thumbnail(shot, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Unable to detect transaction", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Screenshot \(shot.number)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if shot.image != nil {
                    actionButton("View Screenshot", selected: false) { previewShot = shot }
                }
                actionButton("Enter Manually", selected: false) {
                    let draft = session.enterManually(shot, in: modelContext)
                    withAnimation { expandedID = draft.id }
                }
                actionButton("Remove", selected: false) { withAnimation { session.remove(shot) } }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("bulk.unreadable.\(shot.number)")
    }

    private var footer: some View {
        let n = session.saveCount
        return VStack(spacing: 6) {
            Button(action: saveAll) {
                Text(n == 1 ? "Add 1 Transaction" : "Add \(n) Transactions")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(n > 0 ? Color.accentColor : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(n == 0)
            .accessibilityIdentifier("bulk.add")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func saveAll() {
        session.refreshDuplicates(in: modelContext)
        expandedID = nil
        let result = session.saveAll(in: modelContext)
        HapticFeedback.notification(result.failed == 0 ? .success : .warning)
        outcome = result
        session.end()
        withAnimation { phase = .done }
    }

    // MARK: - 4. Result

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            let o = outcome ?? .init()
            Text(o.total == 1 ? "Added 1 transaction" : "Added \(o.total) transactions")
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("bulk.result")
            VStack(spacing: 4) {
                if o.merged > 0 { Text("\(o.merged) merged with an existing expense").foregroundStyle(.secondary) }
                if o.movements > 0 { Text("\(o.movements) recorded as Money In / Money Out").foregroundStyle(.secondary) }
                if o.failed > 0 { Text("\(o.failed) couldn't be saved").foregroundStyle(.red) }
            }
            .font(.subheadline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityIdentifier("bulk.done")
        }
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func thumbnail(_ shot: BulkImportSession.Screenshot, size: CGFloat) -> some View {
        Group {
            if let thumb = shot.thumbnail {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size * 1.25)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 0.5))
    }

    /// `--ui-testing --ui-testing-bulk-import`: four fixture screenshots (a receipt, a two-row history, the same receipt
    /// again, and one with no text) read by the real splitter and parser. Only in UI tests (isolated store).
    private func loadUITestFixtureIfNeeded() {
        guard phase == .pick, ExpenseDataContainer.isUITesting,
              ProcessInfo.processInfo.arguments.contains("--ui-testing-bulk-import") else { return }
        let receipt = ["Touch 'n Go eWallet", "Payment Successful", "RM18.50", "Paid to: McDonald's", "16 Sep 2026 9:42 PM", "Ref No: TNG992837194"]
        let fixtures: [[String]] = [receipt, ["Transaction History", "7 Oct — Grab — RM10.50", "7 Oct — Starbucks — RM15.00"], receipt, []]
        let images = fixtures.indices.map { i in
            UIGraphicsImageRenderer(size: CGSize(width: 30, height: 60)).image { ctx in
                UIColor.systemGray4.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 60))
                UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 4, y: 6 + i * 10, width: 22, height: 6))
            }
        }
        var linesByImage: [ObjectIdentifier: [String]] = [:]
        for (image, lines) in zip(images, fixtures) { linesByImage[ObjectIdentifier(image)] = lines }
        phase = .processing
        session.add(images: images)
        let recognizer: BulkImportSession.Recognizer = { image in
            PDFReceiptImporter.ocrResult(from: linesByImage[ObjectIdentifier(image)] ?? [])
        }
        processingTask = Task { @MainActor in
            await session.process(in: modelContext, recognizer: recognizer)
            withAnimation { phase = .review }
        }
    }
}

/// Full-size view of one picked screenshot.
private struct ScreenshotPreview: View {
    let shot: BulkImportSession.Screenshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = shot.image ?? shot.thumbnail {
                    Image(uiImage: image).resizable().scaledToFit().padding()
                } else {
                    Text("This screenshot couldn't be loaded.").foregroundStyle(.secondary).padding()
                }
            }
            .navigationTitle("Screenshot \(shot.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
