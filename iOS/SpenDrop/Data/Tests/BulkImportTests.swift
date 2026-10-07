import UIKit
import SwiftData

/// Bulk Screenshot Import (Common/BusinessRules/bulk-import.md). `--run-bulk-import-tests`
/// In-memory store and a temporary receipt folder only; OCR is replaced by fixed text (the real splitter and parser run).
@MainActor
public struct BulkImportTests {
    // MARK: Shared vectors — keep identical to Common/BusinessRules/bulk-import-vectors.json

    struct VectorItem { let merchant: String; let amountMinor: Int; let direction: String; let date: String; let time: String }
    struct Vector { let name: String; let importDate: String; let lines: [String]; let kind: String; let items: [VectorItem] }

    static let vectors: [Vector] = [
        Vector(name: "Single TNG payment receipt", importDate: "2026-10-07",
               lines: ["Touch 'n Go eWallet", "Payment Successful", "RM18.50", "Paid to: McDonald's", "16 Sep 2026 9:42 PM", "Ref No: TNG992837194"],
               kind: "single", items: []),
        Vector(name: "Single receipt with total and subtotal (amounts but no dated rows)", importDate: "2026-10-07",
               lines: ["KOPITIAM RESTORAN", "Tax Invoice", "Subtotal RM20.00", "SST 6% RM1.20", "Total RM21.20", "Cash"],
               kind: "single", items: []),
        Vector(name: "History list, one line per transaction", importDate: "2026-10-07",
               lines: ["Transaction History", "7 Oct — Grab — RM10.50", "7 Oct — McDonald's — RM12.90", "7 Oct — Starbucks — RM15.00"],
               kind: "list", items: [
                VectorItem(merchant: "Grab", amountMinor: 1050, direction: "out", date: "2026-10-07", time: "12:00"),
                VectorItem(merchant: "McDonald's", amountMinor: 1290, direction: "out", date: "2026-10-07", time: "12:00"),
                VectorItem(merchant: "Starbucks", amountMinor: 1500, direction: "out", date: "2026-10-07", time: "12:00")]),
        Vector(name: "Bank history with signs, years and times", importDate: "2026-10-07",
               lines: ["Maybank2u", "Account History", "06/10/2026 21:32 SHOPEE MALAYSIA -RM35.00", "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", "05/10/2026 08:10 PETRONAS -RM60.00"],
               kind: "list", items: [
                VectorItem(merchant: "SHOPEE MALAYSIA", amountMinor: 3500, direction: "out", date: "2026-10-06", time: "21:32"),
                VectorItem(merchant: "DUITNOW FROM ALI", amountMinor: 5000, direction: "in", date: "2026-10-06", time: "14:05"),
                VectorItem(merchant: "PETRONAS", amountMinor: 6000, direction: "out", date: "2026-10-05", time: "08:10")]),
        Vector(name: "Two dated rows on a payment receipt stay one receipt", importDate: "2026-10-07",
               lines: ["Payment Successful", "7 Oct 2026 Grab RM10.50", "Ref No: GRB12345678", "7 Oct 2026 Service fee RM0.50"],
               kind: "single", items: []),
        Vector(name: "Date without year that would be in the future belongs to last year", importDate: "2026-01-03",
               lines: ["Recent", "30 Dec Parking RM5.00", "2 Jan 7-Eleven RM8.40"],
               kind: "list", items: [
                VectorItem(merchant: "Parking", amountMinor: 500, direction: "out", date: "2025-12-30", time: "12:00"),
                VectorItem(merchant: "7-Eleven", amountMinor: 840, direction: "out", date: "2026-01-02", time: "12:00")]),
        Vector(name: "Only one dated row is a single receipt", importDate: "2026-10-07",
               lines: ["Grab", "7 Oct 2026 8:42 PM", "RM10.50", "Apple Pay", "7 Oct 2026 Grab RM10.50"],
               kind: "single", items: []),
        Vector(name: "Thousands separators and ISO dates", importDate: "2026-10-07",
               lines: ["2026-10-01 RENT PAYMENT RM1,250.00", "2026-10-02 TNB BILL RM120.40"],
               kind: "list", items: [
                VectorItem(merchant: "RENT PAYMENT", amountMinor: 125000, direction: "out", date: "2026-10-01", time: "12:00"),
                VectorItem(merchant: "TNB BILL", amountMinor: 12040, direction: "out", date: "2026-10-02", time: "12:00")])
    ]

    static func day(_ iso: String) -> ScreenshotSplitter.Day {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return ScreenshotSplitter.Day(year: p[0], month: p[1], day: p[2])
    }

    static func describe(_ r: ScreenshotSplitter.Result) -> String {
        switch r {
        case .single: return "single"
        case .multiple(let rows): return "list " + rows.map { "\($0.merchant)|\($0.amountMinor)|\($0.direction)|\($0.day)|\($0.time)" }.joined(separator: "; ")
        }
    }

    // MARK: Fixtures

    static let tngReceipt = ["Touch 'n Go eWallet", "Payment Successful", "RM18.50", "Paid to: McDonald's", "16 Sep 2026 9:42 PM", "Ref No: TNG992837194"]
    static let duitNowReceipt = ["Transaction Details", "Successful", "- RM 42.00", "Transaction Type", "DuitNow QR", "Merchant", "RESTORAN SELERA KAMPUNG",
                                 "Payment Method", "eWallet Balance", "Date/Time", "06/10/2026 13:22", "Transaction No.", "2026100699990001"]
    static let bankHistory = ["Maybank2u", "Account History", "06/10/2026 21:32 SHOPEE MALAYSIA -RM35.00", "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", "05/10/2026 08:10 PETRONAS -RM60.00"]

    static func image(_ i: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40)).image { ctx in
            UIColor(hue: CGFloat(i % 10) / 10, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
    }

    /// A session whose screenshots are "read" as the given texts (in picking order), with the real worker loop.
    final class InFlight { var current = 0; var max = 0 }

    static func run(_ texts: [[String]], ctx: ModelContext, importDate: Date, counter: InFlight = InFlight()) async -> BulkImportSession {
        let session = BulkImportSession(importDate: importDate)
        let images = texts.indices.map(image)
        var byImage: [ObjectIdentifier: [String]] = [:]
        for (img, lines) in zip(images, texts) { byImage[ObjectIdentifier(img)] = lines }
        session.add(images: images)
        let lookup = byImage
        await session.process(in: ctx) { img in
            await MainActor.run { counter.current += 1; counter.max = max(counter.max, counter.current) }
            try? await Task.sleep(nanoseconds: 20_000_000)
            await MainActor.run { counter.current -= 1 }
            return PDFReceiptImporter.ocrResult(from: lookup[ObjectIdentifier(img)] ?? [])
        }
        return session
    }

    static func components(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Bulk import") { results.append($0) }

        // 1. The 8 shared vectors, exactly.
        for v in vectors {
            let got = ScreenshotSplitter.classify(lines: v.lines, importDate: day(v.importDate))
            let want = v.kind == "single" ? "single" : "list " + v.items.map { "\($0.merchant)|\($0.amountMinor)|\($0.direction)|\($0.date)|\($0.time)" }.joined(separator: "; ")
            t.check("Vector: \(v.name)", describe(got) == want, expected: want, actual: describe(got))
        }

        let importDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15, minute: 0))!

        // 2. Three screenshots → three separate drafts, each with its own screenshot; never merged.
        do {
            let ctx = TestKit.context()
            let counter = InFlight()
            let s = await run([tngReceipt, duitNowReceipt, ["Grab", "7 Oct 2026 8:42 PM", "RM10.50", "Apple Pay", "Ref: GRB778899001"]],
                              ctx: ctx, importDate: importDate, counter: counter)
            let ids = Set(s.drafts.map(\.screenshotID))
            t.check("3 screenshots → 3 drafts", s.drafts.count == 3 && ids.count == 3,
                    expected: "3 drafts from 3 screenshots", actual: "\(s.drafts.count) drafts from \(ids.count) screenshots")
            let ownImages = s.drafts.allSatisfy { d in d.editor.inputImage != nil && d.editor.inputImage === s.screenshot(d.screenshotID)?.image }
            t.check("Each draft keeps its own screenshot", ownImages, expected: "image of its screenshot", actual: "\(ownImages)")
            t.check("Drafts are in picking order", s.drafts.map(\.screenshotNumber) == [1, 2, 3], expected: "[1, 2, 3]", actual: "\(s.drafts.map(\.screenshotNumber))")
            t.check("At most \(BulkImportSession.concurrency) screenshots read at a time", counter.max >= 1 && counter.max <= BulkImportSession.concurrency,
                    expected: "1…\(BulkImportSession.concurrency)", actual: "\(counter.max)")
            t.check("Every screenshot finished", s.screenshots.allSatisfy { $0.state == .done } && !s.isProcessing,
                    expected: "all done", actual: s.screenshots.map { "\($0.state)" }.joined(separator: ","))
            // Dates come from each screenshot, never the import time.
            let dates = s.drafts.map { components($0.editor.date) }
            t.check("Dates preserved per screenshot", dates == ["2026-09-16 21:42", "2026-10-06 13:22", "2026-10-07 20:42"],
                    expected: "2026-09-16 21:42, 2026-10-06 13:22, 2026-10-07 20:42", actual: dates.joined(separator: ", "))
            t.check("Single receipts use the existing parser amounts", s.drafts.map(\.editor.amountText) == ["18.50", "42.00", "10.50"],
                    expected: "18.50, 42.00, 10.50", actual: s.drafts.map(\.editor.amountText).joined(separator: ", "))
            t.check("No duplicates among different payments", s.drafts.allSatisfy { $0.match == nil } && s.saveCount == 3,
                    expected: "no match, Add 3", actual: "matches \(s.drafts.filter { $0.match != nil }.count), Add \(s.saveCount)")

            // Saving: one record per draft, each with its own receipt file, through the normal save path.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bulk-tests-\(UUID().uuidString)", isDirectory: true)
            let store = ImageStorageService(directory: folder)
            let outcome = s.saveAll(in: ctx, imageStore: store, updateFilterEngine: false)
            let saved = TestKit.fetch(Expense.self, in: ctx).sorted { $0.date < $1.date }
            t.check("Add 3 → 3 individual expenses", outcome.expenses == 3 && saved.count == 3,
                    expected: "3 saved", actual: "outcome \(outcome.expenses), store \(saved.count)")
            let paths = Set(saved.compactMap(\.imageRelativePath))
            t.check("Each saved expense has its own receipt image", paths.count == 3 && paths.allSatisfy { store.resolveURL(relativePath: $0) != nil },
                    expected: "3 distinct files", actual: "\(paths.count)")
            t.check("Saved dates are the screenshots' dates", saved.map { components($0.date) } == ["2026-09-16 21:42", "2026-10-06 13:22", "2026-10-07 20:42"],
                    expected: "screenshot dates", actual: saved.map { components($0.date) }.joined(separator: ", "))
            t.check("Saved as screenshot imports", saved.allSatisfy { $0.sourceType == .screenshot }, expected: "screenshot", actual: saved.map(\.sourceTypeRaw).joined(separator: ","))
            try? FileManager.default.removeItem(at: folder)
        }

        // 3. A list screenshot → one draft per row (same screenshot), Money In for "+", row dates and times.
        do {
            let ctx = TestKit.context()
            let s = await run([bankHistory], ctx: ctx, importDate: importDate)
            t.check("List → one draft per row", s.drafts.count == 3 && Set(s.drafts.map(\.screenshotID)).count == 1 && s.drafts.map { $0.rowNumber ?? 0 } == [1, 2, 3],
                    expected: "3 rows of screenshot 1", actual: "\(s.drafts.count) drafts, rows \(s.drafts.map { $0.rowNumber ?? 0 })")
            t.check("Row dates and times kept", s.drafts.map { components($0.editor.date) } == ["2026-10-06 21:32", "2026-10-06 14:05", "2026-10-05 08:10"],
                    expected: "row dates", actual: s.drafts.map { components($0.editor.date) }.joined(separator: ", "))
            t.check("'+' row is a Money In draft, others expenses", s.drafts.map(\.editor.saveAs) == [.expense, .moneyIn, .expense],
                    expected: "Expense, Money In, Expense", actual: s.drafts.map(\.editor.saveAs.rawValue).joined(separator: ", "))
            t.check("List rows don't guess a funding account or channel",
                    s.drafts.allSatisfy { $0.editor.fundingAccount == "Unknown" && $0.editor.selectedPaymentChannel == .unknown },
                    expected: "Unknown / Unknown", actual: s.drafts.map { "\($0.editor.fundingAccount)/\($0.editor.selectedPaymentChannel.rawValue)" }.joined(separator: ", "))
            t.check("List rows are Ready", s.drafts.allSatisfy { s.status(of: $0) == .ready }, expected: "ready", actual: s.drafts.map { "\(s.status(of: $0))" }.joined(separator: ","))
            let outcome = s.saveAll(in: ctx, imageStore: ImageStorageService(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bulk-tests-\(UUID().uuidString)")), updateFilterEngine: false)
            t.check("List saves 2 expenses + 1 Money In", outcome.expenses == 2 && outcome.movements == 1 &&
                    TestKit.count(Expense.self, in: ctx) == 2 && TestKit.count(MoneyMovement.self, in: ctx) == 1,
                    expected: "2 + 1", actual: "\(outcome.expenses) + \(outcome.movements)")
        }

        // 4. The same payment screenshotted twice in one batch → the second is a possible duplicate, Skip by default.
        do {
            let ctx = TestKit.context()
            let s = await run([tngReceipt, duitNowReceipt, tngReceipt], ctx: ctx, importDate: importDate)
            let third = s.drafts.last!
            var batchOf = 0
            if case .batch(let n, _)? = third.match { batchOf = n }
            t.check("Batch-internal duplicate found (same reference)", batchOf == 1 && s.drafts[0].match == nil,
                    expected: "screenshot 3 matches screenshot 1", actual: "matches screenshot \(batchOf)")
            t.check("Possible duplicate defaults to Skip", third.action == .skip && s.status(of: third) == .possibleDuplicate,
                    expected: "skip / possibleDuplicate", actual: "\(third.action) / \(s.status(of: third))")
            t.check("Merge isn't offered for a batch duplicate", third.match?.mergeTarget == nil, expected: "no merge", actual: "\(third.match?.mergeTarget != nil)")
            t.check("Add N excludes the skipped duplicate", s.saveCount == 2, expected: "2", actual: "\(s.saveCount)")
            s.setAction(.addAnyway, for: third)
            t.check("Add Anyway counts it", s.saveCount == 3 && s.status(of: third) != .possibleDuplicate,
                    expected: "3", actual: "\(s.saveCount), \(s.status(of: third))")
            s.setAction(.skip, for: third)
            s.remove(s.drafts[0], in: ctx)
            t.check("Removing the first copy clears the batch match", third.match == nil && s.saveCount == 2,
                    expected: "no match, Add 2", actual: "match \(third.match != nil), Add \(s.saveCount)")
        }

        // 5. Duplicate of a saved expense: strong → Merge offered, Skip by default; Merge reconciles, no new expense.
        do {
            let ctx = TestKit.context()
            let existing = Expense(amount: 18.50, merchant: "McDonald's",
                                   date: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 21, minute: 40))!,
                                   transactionReference: "TNG992837194", sourceType: .manual)
            ctx.insert(existing); try? ctx.save()
            let s = await run([tngReceipt], ctx: ctx, importDate: importDate)
            let d = s.drafts.first!
            t.check("Strong match with a saved expense", d.match?.mergeTarget === existing && d.action == .skip,
                    expected: "merge target = saved, Skip", actual: "target \(d.match?.mergeTarget != nil), \(d.action)")
            t.check("Skipped duplicate → Add 0", s.saveCount == 0, expected: "0", actual: "\(s.saveCount)")
            s.setAction(.merge, for: d)
            let outcome = s.saveAll(in: ctx, imageStore: ImageStorageService(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bulk-tests-\(UUID().uuidString)")), updateFilterEngine: false)
            t.check("Merge with Existing reconciles instead of adding", outcome.merged == 1 && TestKit.count(Expense.self, in: ctx) == 1,
                    expected: "1 merged, 1 expense", actual: "\(outcome.merged) merged, \(TestKit.count(Expense.self, in: ctx)) expenses")
        }

        // 6. "Add N" rules: removed, skipped and invalid drafts are not counted; Needs Review for no amount.
        do {
            let ctx = TestKit.context()
            let s = await run([tngReceipt, duitNowReceipt, bankHistory], ctx: ctx, importDate: importDate)
            t.check("5 drafts → Add 5", s.drafts.count == 5 && s.saveCount == 5, expected: "5", actual: "\(s.drafts.count) / \(s.saveCount)")
            s.remove(s.drafts[0], in: ctx)
            t.check("Removed draft not counted", s.saveCount == 4, expected: "4", actual: "\(s.saveCount)")
            s.drafts[1].editor.amountText = ""
            t.check("Invalid draft (no amount) not counted and Needs Review", s.saveCount == 3 && s.status(of: s.drafts[1]) == .needsReview,
                    expected: "3, needsReview", actual: "\(s.saveCount), \(s.status(of: s.drafts[1]))")
            t.check("Summary total follows the drafts to add", s.totalMinor == 3500 + 5000 + 6000,
                    expected: "14500", actual: "\(s.totalMinor)")
        }

        // 7. A screenshot without a transaction is listed, never dropped; Enter Manually makes a normal draft.
        do {
            let ctx = TestKit.context()
            let s = await run([[], ["Settings", "Wi-Fi", "Bluetooth"]], ctx: ctx, importDate: importDate)
            t.check("Unreadable screenshots are listed", s.drafts.isEmpty && s.unreadableScreenshots.map(\.number) == [1, 2],
                    expected: "[1, 2]", actual: "\(s.unreadableScreenshots.map(\.number)), drafts \(s.drafts.count)")
            let manual = s.enterManually(s.screenshots[0], in: ctx)
            manual.editor.amountText = "12.00"
            manual.editor.merchant = "Kedai"
            s.refreshDuplicates(in: ctx)
            t.check("Enter Manually → normal draft with that screenshot", s.drafts.count == 1 && manual.editor.inputImage === s.screenshots[0].image &&
                    s.unreadableScreenshots.map(\.number) == [2] && s.saveCount == 1 && manual.match == nil,
                    expected: "1 draft, screenshot 2 still listed", actual: "\(s.drafts.count) drafts, unreadable \(s.unreadableScreenshots.map(\.number))")
            s.remove(s.screenshots[1])
            t.check("Remove hides the unreadable screenshot", s.unreadableScreenshots.isEmpty, expected: "none", actual: "\(s.unreadableScreenshots.count)")
            s.end()
            t.check("Session end releases screenshots and drafts", s.screenshots.isEmpty && s.drafts.isEmpty && manual.editor.inputImage == nil,
                    expected: "empty", actual: "\(s.screenshots.count) / \(s.drafts.count)")
        }

        // 8. At most 30 screenshots per import.
        do {
            let s = BulkImportSession(importDate: importDate)
            let left = s.add(images: (0..<31).map { _ in UIImage?.none })
            t.check("Cap of \(BulkImportSession.maxScreenshots) screenshots", s.screenshots.count == 30 && left == 1,
                    expected: "30 kept, 1 left out", actual: "\(s.screenshots.count) kept, \(left) left out")
        }

        return results
    }
}
