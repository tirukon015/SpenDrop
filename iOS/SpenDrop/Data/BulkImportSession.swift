import UIKit
import ImageIO
import SwiftData
import Combine

/// Bulk Screenshot Import (Common/BusinessRules/bulk-import.md). Only automates the first step of adding transactions:
/// every screenshot is read on the device (existing `OCRService`), split into one or more drafts
/// (`ScreenshotSplitter` → existing `TransactionParser` for single receipts), and each draft is a NORMAL
/// `ShareExtensionViewModel` — the same editor state, rules and save path as a shared screenshot. Nothing is merged
/// across screenshots; each draft keeps its own screenshot. Nothing financial is logged.
@MainActor
public final class BulkImportSession: ObservableObject {
    public static let maxScreenshots = 30
    /// Screenshots read at the same time (keeps memory and the UI smooth).
    public static let concurrency = 2

    public enum ScreenshotState: Equatable { case waiting, processing, done, failed }

    public final class Screenshot: Identifiable {
        public let id = UUID()
        /// 1-based, in the order the screenshots were picked.
        public let number: Int
        /// Kept in memory only until the session ends (never written anywhere until a draft is saved).
        public fileprivate(set) var image: UIImage?
        public let thumbnail: UIImage?
        public fileprivate(set) var state: ScreenshotState = .waiting
        public fileprivate(set) var draftCount = 0
        /// "Remove" on an "Unable to detect" card.
        public fileprivate(set) var removed = false

        init(number: Int, image: UIImage?, thumbnail: UIImage?) {
            self.number = number
            self.image = image
            self.thumbnail = thumbnail
        }

        /// No transaction was found (failed OCR / no text / nothing recognisable) and no draft was entered manually.
        public var isUnreadable: Bool { (state == .failed || (state == .done && draftCount == 0)) && !removed }
    }

    /// The existing duplicate actions. A possible duplicate starts as `.skip`.
    public enum DuplicateAction: Equatable { case skip, addAnyway, merge }

    public enum Match {
        /// An already saved expense (existing `DuplicateDetector` result).
        case saved(DuplicateCheckResult)
        /// An already saved Money In / Money Out (existing `MovementDuplicateDetector`).
        case savedMovement(MoneyMovement)
        /// A draft before this one in the same import.
        case batch(screenshotNumber: Int, reason: String)

        /// Merge is offered only for a strong (same reference) match with a saved expense.
        public var mergeTarget: Expense? {
            if case .saved(let r) = self, r.isStrong { return r.matchedExpense }
            return nil
        }

        public var reason: String {
            switch self {
            case .saved(let r): return r.reason ?? "This may already be recorded."
            case .savedMovement(let m):
                return "A \(m.kind.displayName.lowercased()) of the same amount on \(m.date.formatted(date: .abbreviated, time: .omitted)) is already recorded."
            case .batch(_, let reason): return reason
            }
        }

        public var isBatch: Bool { if case .batch = self { return true }; return false }
    }

    public enum Status: Equatable { case ready, needsReview, possibleDuplicate }

    /// One normal transaction draft. `editor` is the existing transaction editor state.
    public final class Draft: Identifiable {
        public let id = UUID()
        public let screenshotID: UUID
        public let screenshotNumber: Int
        /// Position in a list screenshot (1-based); nil for a single receipt.
        public let rowNumber: Int?
        /// What the parser found (flags only; no image, no OCR text kept).
        public let parsed: ParsedTransaction
        public let editor: ShareExtensionViewModel
        /// Entered by hand ("Enter Manually"): never duplicate-checked, like other manual entries.
        public let isManual: Bool
        public fileprivate(set) var match: Match?
        public fileprivate(set) var action: DuplicateAction = .skip
        public fileprivate(set) var removed = false
        /// Opened by the user: parser warnings (low confidence, no merchant…) no longer hold it in "Needs Review".
        public fileprivate(set) var reviewed = false

        init(screenshot: Screenshot, rowNumber: Int?, parsed: ParsedTransaction, editor: ShareExtensionViewModel, isManual: Bool) {
            self.screenshotID = screenshot.id
            self.screenshotNumber = screenshot.number
            self.rowNumber = rowNumber
            self.parsed = parsed
            self.editor = editor
            self.isManual = isManual
        }
    }

    public struct SaveOutcome: Equatable {
        public var expenses = 0
        public var merged = 0
        public var movements = 0
        public var failed = 0
        public var total: Int { expenses + merged + movements }
    }

    @Published public private(set) var screenshots: [Screenshot] = []
    @Published public private(set) var drafts: [Draft] = []
    @Published public private(set) var isProcessing = false
    public let importDate: Date
    private let calendar: Calendar
    private var observers: [UUID: AnyCancellable] = [:]
    private var pending: [Screenshot] = []

    public init(importDate: Date = Date(), calendar: Calendar = .current) {
        self.importDate = importDate
        self.calendar = calendar
    }

    // MARK: - Screenshots

    /// Adds picked screenshots (in order), up to `maxScreenshots`. A nil image (couldn't be loaded) is kept and shown
    /// as "Unable to detect". Returns how many were left out.
    @discardableResult
    public func add(images: [UIImage?]) -> Int {
        let room = max(0, Self.maxScreenshots - screenshots.count)
        let accepted = images.prefix(room)
        let start = screenshots.count
        screenshots += accepted.enumerated().map { i, image in
            Screenshot(number: start + i + 1, image: image, thumbnail: image.flatMap { Self.thumbnail(of: $0) })
        }
        return images.count - accepted.count
    }

    public func screenshot(_ id: UUID) -> Screenshot? { screenshots.first { $0.id == id } }

    public var doneCount: Int { screenshots.filter { $0.state == .done || $0.state == .failed }.count }

    // MARK: - Processing

    public typealias Recognizer = (UIImage) async throws -> OCRResult

    /// Reads every waiting screenshot, `concurrency` at a time, then checks duplicates. Never blocks the UI: OCR runs
    /// off the main thread inside `OCRService`, parsing is the same quick step as a single screenshot.
    public func process(in context: ModelContext, recognizer: Recognizer? = nil) async {
        guard !isProcessing else { return }
        isProcessing = true
        let recognize: Recognizer = recognizer ?? { try await OCRService.shared.recognizeText(from: $0) }
        pending = screenshots.filter { $0.state == .waiting }

        let workers = (0..<Self.concurrency).map { _ in
            Task { @MainActor [weak self] in
                while let self, !Task.isCancelled, let shot = self.nextPending() {
                    self.setState(shot, .processing)
                    guard let image = shot.image else { self.setState(shot, .failed); continue }
                    do {
                        let ocr = try await recognize(image)
                        self.ingest(shot, ocr: ocr, in: context)
                    } catch {
                        self.setState(shot, .failed)
                    }
                }
            }
        }
        for worker in workers { await worker.value }
        refreshDuplicates(in: context)
        isProcessing = false
    }

    private func nextPending() -> Screenshot? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    private func setState(_ shot: Screenshot, _ state: ScreenshotState) {
        objectWillChange.send()
        shot.state = state
    }

    /// Turns one screenshot's text into drafts: a list → one draft per row; otherwise the existing receipt parser.
    /// Screenshots are never merged; dates come from the screenshot (the parser's own fallback when it has none).
    public func ingest(_ shot: Screenshot, ocr: OCRResult, in context: ModelContext) {
        objectWillChange.send()
        let lines = ocr.lines.map(\.text)
        guard !lines.isEmpty, !ocr.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            shot.state = .failed
            return
        }
        var made: [Draft] = []
        switch ScreenshotSplitter.classify(lines: lines, importDate: importDate, calendar: calendar) {
        case .single:
            var parsed = TransactionParser.shared.parse(ocrResult: ocr, image: shot.image)
            // No amount at all → listed as "Unable to detect a transaction" (the user can still enter it manually).
            if parsed.amount != nil {
                parsed.originalImage = nil
                made.append(makeDraft(shot, row: nil, parsed: parsed, manual: false, in: context))
            }
        case .multiple(let rows):
            for (i, row) in rows.enumerated() {
                made.append(makeDraft(shot, row: i + 1, parsed: parsedTransaction(for: row), manual: false, in: context))
            }
        }
        shot.draftCount = made.count
        shot.state = .done
        drafts = (drafts + made).sorted { ($0.screenshotNumber, $0.rowNumber ?? 0) < ($1.screenshotNumber, $1.rowNumber ?? 0) }
    }

    /// A list row as a normal parsed transaction: amount, merchant, date/time and direction only (plus the normal
    /// merchant → category suggestion). No funding account or channel is guessed.
    func parsedTransaction(for row: ScreenshotSplitter.Row) -> ParsedTransaction {
        let category = CategoryDetector.suggest(merchant: row.merchant, receiptText: row.merchant)
        var parsed = ParsedTransaction(
            amount: Money.majorAmount(fromMinor: row.amountMinor),
            amountConfidence: 1,
            merchant: row.merchant,
            date: row.date(calendar: calendar),
            dateString: row.day.description,
            timeString: row.time,
            category: category.category == .other ? nil : category.category,
            confidence: .medium,
            isCompletedTransaction: true
        )
        parsed.categoryConfidence = category.confidence
        parsed.categoryReason = category.reason
        parsed.channelConfidence = 0
        parsed.channelReason = "Not shown in this list"
        if row.isMoneyIn {
            parsed.suggestedMovementKind = .otherIn
            parsed.directionReason = "shown with + in the list"
        }
        return parsed
    }

    private func makeDraft(_ shot: Screenshot, row: Int?, parsed: ParsedTransaction, manual: Bool, in context: ModelContext) -> Draft {
        let editor = ShareExtensionViewModel()
        editor.applyParsedTransaction(parsed)
        if !manual { editor.applySuggestions(parsed, in: context) }
        editor.inputImage = shot.image
        var stored = parsed
        stored.rawOCRText = ""
        stored.detectedLines = []
        let draft = Draft(screenshot: shot, rowNumber: row, parsed: stored, editor: editor, isManual: manual)
        // Edits inside a card update the summary and the "Add N" button.
        observers[draft.id] = editor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return draft
    }

    /// "Enter Manually" on a screenshot that produced no transaction: an empty normal draft with that screenshot.
    @discardableResult
    public func enterManually(_ shot: Screenshot, in context: ModelContext) -> Draft {
        objectWillChange.send()
        let draft = makeDraft(shot, row: nil, parsed: ParsedTransaction(confidence: .low), manual: true, in: context)
        draft.reviewed = true
        shot.draftCount += 1
        shot.state = .done
        drafts = (drafts + [draft]).sorted { ($0.screenshotNumber, $0.rowNumber ?? 0) < ($1.screenshotNumber, $1.rowNumber ?? 0) }
        return draft
    }

    // MARK: - Duplicates (bulk-import.md §2)

    /// Checks every draft with the existing detectors against saved transactions, then against the drafts before it
    /// in this import. A newly found duplicate starts as Skip; a choice the user already made is kept.
    public func refreshDuplicates(in context: ModelContext) {
        objectWillChange.send()
        var earlierExpenses: [(record: Expense, draft: Draft)] = []
        var earlierMovements: [(record: MoneyMovement, draft: Draft)] = []
        for draft in drafts where !draft.removed {
            let e = draft.editor
            var found: Match?
            if !draft.isManual {
                if e.saveAs == .expense {
                    let saved = DuplicateDetector.shared.checkDuplicate(
                        amount: e.parsedAmount, merchant: e.merchant, date: e.date, reference: e.transactionReference,
                        paymentChannel: e.selectedPaymentChannel, fundingAccount: e.fundingAccount, in: context)
                    if saved.isDuplicate {
                        found = .saved(saved)
                    } else {
                        let batch = DuplicateDetector.shared.checkDuplicate(
                            amount: e.parsedAmount, merchant: e.merchant, date: e.date, reference: e.transactionReference,
                            paymentChannel: e.selectedPaymentChannel, fundingAccount: e.fundingAccount,
                            among: earlierExpenses.map(\.record))
                        if batch.isDuplicate, let matched = batch.matchedExpense,
                           let other = earlierExpenses.first(where: { $0.record === matched })?.draft {
                            found = .batch(screenshotNumber: other.screenshotNumber, reason: Self.batchReason(other, strong: batch.isStrong))
                        }
                    }
                } else {
                    let minor = Money.minorUnits(from: e.parsedAmount)
                    if minor > 0 {
                        if let saved = MovementDuplicateDetector.findMatch(amountMinor: minor, date: e.date, reference: e.transactionReference,
                                                                           kind: e.movementKind, in: context) {
                            found = .savedMovement(saved)
                        } else if let matched = MovementDuplicateDetector.findMatch(amountMinor: minor, date: e.date, reference: e.transactionReference,
                                                                                    kind: e.movementKind, among: earlierMovements.map(\.record)),
                                  let other = earlierMovements.first(where: { $0.record === matched })?.draft {
                            found = .batch(screenshotNumber: other.screenshotNumber, reason: Self.batchReason(other, strong: false))
                        }
                    }
                }
            }
            let hadMatch = draft.match != nil
            draft.match = found
            if found == nil || !hadMatch { draft.action = .skip }
            if draft.action == .merge && found?.mergeTarget == nil { draft.action = .skip }

            if !draft.isManual {
                // Unsaved stand-ins for the drafts so far: compared with the same rules, never inserted anywhere.
                if e.saveAs == .expense {
                    earlierExpenses.append((Expense(amount: e.parsedAmount, merchant: e.merchant, date: e.date,
                                                    transactionReference: e.transactionReference,
                                                    paymentChannel: e.selectedPaymentChannel, fundingAccount: e.fundingAccount), draft))
                } else {
                    earlierMovements.append((MoneyMovement(kind: e.movementKind, amountMinor: Money.minorUnits(from: e.parsedAmount),
                                                           date: e.date, transactionReference: e.transactionReference), draft))
                }
            }
        }
    }

    private static func batchReason(_ other: Draft, strong: Bool) -> String {
        let row = other.rowNumber.map { ", row \($0)" } ?? ""
        return strong
            ? "Same reference as Screenshot \(other.screenshotNumber)\(row) in this import — probably the same payment screenshotted twice."
            : "Same amount and merchant as Screenshot \(other.screenshotNumber)\(row) in this import, a few minutes apart. If it's a separate payment, add it anyway."
    }

    // MARK: - User actions

    public func setAction(_ action: DuplicateAction, for draft: Draft) {
        guard draft.match != nil else { return }
        if action == .merge && draft.match?.mergeTarget == nil { return }
        objectWillChange.send()
        draft.action = action
    }

    public func remove(_ draft: Draft, in context: ModelContext) {
        objectWillChange.send()
        draft.removed = true
        observers[draft.id] = nil
        refreshDuplicates(in: context)
    }

    public func remove(_ shot: Screenshot) {
        objectWillChange.send()
        shot.removed = true
        shot.image = nil
    }

    public func markReviewed(_ draft: Draft) {
        guard !draft.reviewed else { return }
        objectWillChange.send()
        draft.reviewed = true
    }

    // MARK: - Status and counts (bulk-import.md §3)

    public func status(of draft: Draft) -> Status {
        if draft.match != nil && draft.action == .skip { return .possibleDuplicate }
        return needsReview(draft) ? .needsReview : .ready
    }

    public func needsReview(_ draft: Draft) -> Bool {
        let e = draft.editor
        if !e.isValid { return true }
        if e.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let p = draft.parsed
        return !draft.reviewed && (p.merchant == nil || p.confidence == .low || p.isFailedTransaction || p.isBalanceOrLimitOnly)
    }

    /// Not removed, not skipped, and valid.
    public func willSave(_ draft: Draft) -> Bool {
        !draft.removed && draft.editor.isValid && !(draft.match != nil && draft.action == .skip)
    }

    public var activeDrafts: [Draft] { drafts.filter { !$0.removed } }
    public var unreadableScreenshots: [Screenshot] { screenshots.filter(\.isUnreadable) }
    public var activeScreenshotCount: Int { screenshots.filter { !$0.removed }.count }
    public var saveCount: Int { drafts.filter(willSave).count }
    public var readyCount: Int { activeDrafts.filter { status(of: $0) == .ready }.count }
    public var needsReviewCount: Int { activeDrafts.filter { status(of: $0) == .needsReview }.count }
    public var duplicateCount: Int { activeDrafts.filter { status(of: $0) == .possibleDuplicate }.count }
    /// Total of the drafts that will be added.
    public var totalMinor: Int { drafts.filter(willSave).reduce(0) { $0 + Money.minorUnits(from: $1.editor.parsedAmount) } }

    // MARK: - Save (existing save path, one record per draft)

    /// Saves every draft that will be added, in order, through the existing Share Extension save path (AccountLinker,
    /// Split Money, classifier/channel learning, receipt image, Merge via reconcile when chosen).
    public func saveAll(in context: ModelContext, imageStore: ImageStorageService = .shared, updateFilterEngine: Bool = true) -> SaveOutcome {
        var outcome = SaveOutcome()
        for draft in drafts where willSave(draft) {
            do {
                if draft.editor.saveAs == .expense {
                    let target = draft.action == .merge ? draft.match?.mergeTarget : nil
                    try draft.editor.saveExpenseRecord(mergeInto: target, sourceType: .screenshot, imageStore: imageStore, in: context)
                    if target == nil { outcome.expenses += 1 } else { outcome.merged += 1 }
                } else {
                    try draft.editor.saveMovementRecord(sourceType: .screenshot, in: context)
                    outcome.movements += 1
                }
            } catch {
                outcome.failed += 1
            }
        }
        if updateFilterEngine, let all = try? context.fetch(FetchDescriptor<Expense>()) {
            TransactionFilterEngine.shared.update(expenses: all)
        }
        return outcome
    }

    /// Ends the session: screenshots and drafts are dropped from memory (nothing temporary was written to disk).
    public func end() {
        pending = []
        observers.removeAll()
        for draft in drafts { draft.editor.inputImage = nil }
        for shot in screenshots { shot.image = nil }
        drafts = []
        screenshots = []
    }

    // MARK: - Images

    /// A downsampled copy for OCR and the receipt (screenshots are large; the saved receipt is optimized anyway).
    public static func loadImage(data: Data, maxPixelSize: Int = 2400) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return UIImage(data: data) }
        let thumbOptions = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }

    static func thumbnail(of image: UIImage, side: CGFloat = 120) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = side / max(size.width, size.height)
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}
