import Foundation
import UIKit
import Vision

public struct DiagnosticStepResult {
    public let name: String
    public let passed: Bool
    public let detail: String
}

public struct ImageFormatTestReport {
    public let formatName: String
    public var dataLoad: DiagnosticStepResult
    public var uiImageDecode: DiagnosticStepResult
    public var cgImageDecode: DiagnosticStepResult
    public var downsampling: DiagnosticStepResult
    public var tempStorage: DiagnosticStepResult
    public var appGroupStorage: DiagnosticStepResult
    public var visionOCR: DiagnosticStepResult
    public var parser: DiagnosticStepResult
}

public final class ImagePipelineDiagnostics {

    public static func runAllTests() async -> [ImageFormatTestReport] {
        var reports: [ImageFormatTestReport] = []

        let samples: [(format: String, filename: String, ext: String)] = [
            ("Test A — PNG Screenshot", "sample_screenshot", "png"),
            ("Test B — JPEG Photo", "sample_photo", "jpg"),
            ("Test C — HEIC Camera Photo", "sample_camera", "heic")
        ]

        for sample in samples {
            print("\n==========================================")
            print("[SpenDrop][DIAGNOSTIC] Starting: \(sample.format)")
            print("==========================================")
            let report = await testSingleImage(name: sample.format, filename: sample.filename, ext: sample.ext)
            reports.append(report)
        }

        return reports
    }

    private static func testSingleImage(name: String, filename: String, ext: String) async -> ImageFormatTestReport {
        // 1. Data loading
        var dataResult = DiagnosticStepResult(name: "Data loading", passed: false, detail: "File not found in bundle")
        var dataOptional: Data? = nil

        if let url = Bundle.main.url(forResource: filename, withExtension: ext, subdirectory: "DiagnosticSamples") ??
                     Bundle.main.url(forResource: filename, withExtension: ext) {
            if let data = try? Data(contentsOf: url) {
                dataOptional = data
                dataResult = DiagnosticStepResult(name: "Data loading", passed: true, detail: "Loaded \(data.count) bytes from \(url.lastPathComponent)")
                print("[SpenDrop][IMAGE] [\(name)] Data loaded: \(data.count) bytes")
            } else {
                dataResult = DiagnosticStepResult(name: "Data loading", passed: false, detail: "Data(contentsOf:) failed to read file bytes")
                print("[SpenDrop][IMAGE] [\(name)] Data loading: FAIL (failed to read bytes)")
            }
        } else {
            // Direct filesystem check for local testing
            let fallbackPaths = [
                "/Users/apple/SpenDrop/SpenDrop/Resources/DiagnosticSamples/\(filename).\(ext)",
                "SpenDrop/Resources/DiagnosticSamples/\(filename).\(ext)"
            ]
            for p in fallbackPaths {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                    dataOptional = d
                    dataResult = DiagnosticStepResult(name: "Data loading", passed: true, detail: "Loaded \(d.count) bytes from path: \(p)")
                    print("[SpenDrop][IMAGE] [\(name)] Data loaded: \(d.count) bytes (fallback path)")
                    break
                }
            }
        }

        guard let data = dataOptional else {
            let fail = DiagnosticStepResult(name: "Skipped", passed: false, detail: "Prerequisite data failed")
            return ImageFormatTestReport(
                formatName: name,
                dataLoad: dataResult,
                uiImageDecode: fail,
                cgImageDecode: fail,
                downsampling: fail,
                tempStorage: fail,
                appGroupStorage: fail,
                visionOCR: fail,
                parser: fail
            )
        }

        // 2. UIImage decode
        var uiImageResult: DiagnosticStepResult
        var uiImageOptional: UIImage? = nil
        if let uiImg = UIImage(data: data) {
            uiImageOptional = uiImg
            uiImageResult = DiagnosticStepResult(name: "UIImage decode", passed: true, detail: "size: \(uiImg.size), scale: \(uiImg.scale), orientation: \(uiImg.imageOrientation.rawValue)")
            print("[SpenDrop][IMAGE] [\(name)] UIImage decode: SUCCESS (\(uiImageResult.detail))")
        } else {
            uiImageResult = DiagnosticStepResult(name: "UIImage decode", passed: false, detail: "UIImage(data:) returned nil for \(data.count) bytes")
            print("[SpenDrop][IMAGE] [\(name)] UIImage decode: FAIL (\(uiImageResult.detail))")
        }

        guard let uiImage = uiImageOptional else {
            let fail = DiagnosticStepResult(name: "Skipped", passed: false, detail: "UIImage decode failed")
            return ImageFormatTestReport(
                formatName: name,
                dataLoad: dataResult,
                uiImageDecode: uiImageResult,
                cgImageDecode: fail,
                downsampling: fail,
                tempStorage: fail,
                appGroupStorage: fail,
                visionOCR: fail,
                parser: fail
            )
        }

        // 3. CGImage decode
        var cgImageResult: DiagnosticStepResult
        if let cg = uiImage.cgImage {
            cgImageResult = DiagnosticStepResult(name: "CGImage decode", passed: true, detail: "width: \(cg.width), height: \(cg.height)")
            print("[SpenDrop][IMAGE] [\(name)] CGImage decode: SUCCESS (\(cgImageResult.detail))")
        } else if let ci = uiImage.ciImage, let cg = CIContext(options: nil).createCGImage(ci, from: ci.extent) {
            cgImageResult = DiagnosticStepResult(name: "CGImage decode", passed: true, detail: "rendered from CIImage: \(cg.width)x\(cg.height)")
            print("[SpenDrop][IMAGE] [\(name)] CGImage decode: SUCCESS via CIContext (\(cgImageResult.detail))")
        } else {
            cgImageResult = DiagnosticStepResult(name: "CGImage decode", passed: false, detail: "cgImage was nil and CIContext fallback failed")
            print("[SpenDrop][IMAGE] [\(name)] CGImage decode: FAIL")
        }

        // 4. Downsampling
        let maxSide = max(uiImage.size.width, uiImage.size.height)
        let downsampleResult: DiagnosticStepResult
        if maxSide > 2048 {
            let scale = 2048.0 / maxSide
            let targetSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let downsampled = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            downsampleResult = DiagnosticStepResult(name: "Downsampling", passed: downsampled.size.width > 0, detail: "Reduced from \(uiImage.size) to \(downsampled.size)")
            print("[SpenDrop][IMAGE] [\(name)] Downsampling: SUCCESS (\(downsampleResult.detail))")
        } else {
            downsampleResult = DiagnosticStepResult(name: "Downsampling", passed: true, detail: "Not needed (\(maxSide) <= 2048)")
            print("[SpenDrop][IMAGE] [\(name)] Downsampling: NOT NEEDED (\(downsampleResult.detail))")
        }

        // 5. Temporary storage test
        var tempStorageResult: DiagnosticStepResult
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("diag_\(UUID().uuidString).jpg")
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: tempFile)
                tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: true, detail: "Wrote \(jpegData.count) bytes to temporaryDirectory")
                print("[SpenDrop][IMAGE] [\(name)] Temp storage: SUCCESS (\(tempStorageResult.detail))")
                try? FileManager.default.removeItem(at: tempFile)
            } catch {
                tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: false, detail: "write(to:) failed: \(error)")
                print("[SpenDrop][IMAGE] [\(name)] Temp storage: FAIL (\(error))")
            }
        } else {
            tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: false, detail: "jpegData(compressionQuality:) returned nil")
            print("[SpenDrop][IMAGE] [\(name)] Temp storage: FAIL (jpegData nil)")
        }

        // 6. App Group storage test
        var appGroupStorageResult: DiagnosticStepResult
        if let relPath = ImageStorageService.shared.saveImage(uiImage) {
            if let loadedBack = ImageStorageService.shared.loadImage(relativePath: relPath) {
                appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: true, detail: "Saved and verified read (\(relPath), loaded size: \(loadedBack.size))")
                print("[SpenDrop][IMAGE] [\(name)] App Group storage: SUCCESS (\(appGroupStorageResult.detail))")
            } else {
                appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: false, detail: "Saved to \(relPath) but loadImage returned nil")
                print("[SpenDrop][IMAGE] [\(name)] App Group storage: FAIL (loadImage returned nil)")
            }
            ImageStorageService.shared.deleteImage(relativePath: relPath)
        } else {
            appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: false, detail: "saveImage returned nil (App Group container unavailable or unwriteable)")
            print("[SpenDrop][IMAGE] [\(name)] App Group storage: FAIL (saveImage returned nil)")
        }

        // 7. Vision OCR
        print("[SpenDrop][IMAGE] [\(name)] OCR started")
        var ocrResultStep: DiagnosticStepResult
        var recognizedOCRResult: OCRResult? = nil
        do {
            let ocr = try await OCRService.shared.recognizeText(from: uiImage)
            recognizedOCRResult = ocr
            ocrResultStep = DiagnosticStepResult(name: "Vision OCR", passed: true, detail: "\(ocr.lines.count) lines, avgConf: \(ocr.averageConfidence), textLen: \(ocr.fullText.count)")
            print("[SpenDrop][IMAGE] [\(name)] OCR completed: SUCCESS (\(ocrResultStep.detail))")
        } catch {
            ocrResultStep = DiagnosticStepResult(name: "Vision OCR", passed: false, detail: "recognizeText threw: \(error)")
            print("[SpenDrop][IMAGE] [\(name)] OCR FAILED: \(error)")
        }

        // 8. Transaction Parser
        print("[SpenDrop][IMAGE] [\(name)] Parser started")
        let parserResultStep: DiagnosticStepResult
        if let ocr = recognizedOCRResult {
            let parsed = TransactionParser.shared.parse(ocrResult: ocr, image: uiImage)
            let detail = "amount: \(parsed.amount != nil ? "RM\(parsed.amount!)" : "nil"), merchant: \(parsed.merchant ?? "nil"), cat: \(parsed.category?.rawValue ?? "nil"), conf: \(parsed.confidence.rawValue), isBalance: \(parsed.isBalanceOrLimitOnly), isFailed: \(parsed.isFailedTransaction)"
            parserResultStep = DiagnosticStepResult(name: "Transaction Parser", passed: true, detail: detail)
            print("[SpenDrop][IMAGE] [\(name)] Parser completed: \(detail)")
        } else {
            parserResultStep = DiagnosticStepResult(name: "Transaction Parser", passed: false, detail: "Skipped due to OCR failure")
            print("[SpenDrop][IMAGE] [\(name)] Parser: SKIPPED")
        }

        return ImageFormatTestReport(
            formatName: name,
            dataLoad: dataResult,
            uiImageDecode: uiImageResult,
            cgImageDecode: cgImageResult,
            downsampling: downsampleResult,
            tempStorage: tempStorageResult,
            appGroupStorage: appGroupStorageResult,
            visionOCR: ocrResultStep,
            parser: parserResultStep
        )
    }
}

// MARK: - Screenshot storage tests (temporary folders and in-memory stores only)

/// Screenshot optimization and the safe migration of existing screenshots. `--run-screenshot-tests`
@MainActor
public struct ScreenshotStorageTests {
    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Screenshot storage") { results.append($0) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ScreenshotStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let storage = ImageStorageService(directory: root)
        func size(_ name: String) -> Int64 { ScreenshotOptimizer.fileSize(root.appendingPathComponent(name)) }
        func kb(_ bytes: Int64) -> String { "\(bytes / 1024) KB" }

        // A full-resolution iPhone 17 Pro Max payment screenshot (1320 × 2868) with small and large text.
        let screenshot = makePaymentScreenshot(size: CGSize(width: 1320, height: 2868))
        let legacyJPEG = screenshot.jpegData(compressionQuality: 0.8)!  // what SpenDrop used to store

        // New saves
        let saved = storage.saveImage(screenshot)
        let savedURL = saved.map { root.appendingPathComponent($0) }
        let savedPixels = savedURL.flatMap { ScreenshotOptimizer.decodedPixelSize(at: $0) }
        let savedSize = saved.map(size) ?? 0
        t.check("Large screenshot is reduced and saved as \(ScreenshotOptimizer.canEncodeHEIC ? "HEIC" : "JPEG")",
                saved != nil && savedSize > 0 && savedSize * 3 < Int64(legacyJPEG.count),
                expected: "< 1/3 of the old \(kb(Int64(legacyJPEG.count))) JPEG", actual: "\(saved ?? "nil") \(kb(savedSize))")
        t.check("Optimized file decodes; long edge between 1440 and 1800 px",
                savedPixels.map { max($0.width, $0.height) >= 1440 && max($0.width, $0.height) <= 1800 } ?? false,
                expected: "1440…1800", actual: "\(savedPixels.map { "\(Int($0.width))×\(Int($0.height))" } ?? "not decodable")")
        t.check("Target size (≈80–150 KB) is reached for a typical screenshot",
                savedSize <= 160 * 1024, expected: "≤ ~150 KB", actual: kb(savedSize))

        // Readability: on-device OCR still reads the payment details from the stored file.
        var ocrText = ""
        if let saved, let stored = storage.loadImage(relativePath: saved) {
            ocrText = (try? await OCRService.shared.recognizeText(from: stored).fullText) ?? ""
        }
        let compact = ocrText.replacingOccurrences(of: " ", with: "").uppercased()
        t.check("Payment details stay readable (OCR on the stored file finds amount, receiver and small reference text)",
                compact.contains("RM22.00") && compact.contains("RANASOHEL") && compact.contains("2026091512345678"),
                expected: "RM 22.00, RANA SOHEL, reference", actual: ocrText.replacingOccurrences(of: "\n", with: " | ").prefix(160).description)

        // Small screenshots are not enlarged
        let small = makePaymentScreenshot(size: CGSize(width: 600, height: 1000))
        let smallOut = ScreenshotOptimizer.optimize(small)
        t.check("Small screenshot is not upscaled",
                smallOut.map { $0.pixelSize.width <= 600 && $0.pixelSize.height <= 1000 } ?? false,
                expected: "≤ 600×1000", actual: "\(smallOut.map { "\(Int($0.pixelSize.width))×\(Int($0.pixelSize.height))" } ?? "nil")")

        // Existing screenshots: migration
        let ctx = TestKit.context()
        func legacyFile(_ data: Data = legacyJPEG) -> String {
            let name = "\(UUID().uuidString).jpg"
            try? data.write(to: root.appendingPathComponent(name))
            return name
        }
        let oldA = legacyFile(), oldB = legacyFile()
        let shared = legacyFile()  // referenced by two expenses (duplicate/reconciled)
        let corrupt = legacyFile(Data((0..<300_000).map { _ in UInt8.random(in: 0...255) }))
        let tiny = saved!
        let expenses = [oldA, oldB, shared, shared, corrupt, tiny, "missing.jpg"].map { path -> Expense in
            let e = Expense(amount: 22, merchant: "RANA SOHEL")
            e.imageRelativePath = path
            ctx.insert(e)
            return e
        }
        try? ctx.save()
        let corruptBytes = try? Data(contentsOf: root.appendingPathComponent(corrupt))

        let report = ScreenshotStorageMigrator.optimizeExisting(in: ctx, storage: storage)
        let refs = expenses.map { $0.imageRelativePath ?? "" }
        let allOptimizedOpen = refs[0..<4].allSatisfy {
            storage.loadImage(relativePath: $0) != nil && ($0.hasSuffix(".heic") || $0.hasSuffix("-opt.jpg"))
        }
        t.check("Existing large screenshots are optimized; references updated; each still opens",
                report.optimized == 3 && allOptimizedOpen && refs[2] == refs[3],
                expected: "3 files optimized (shared file once), all open",
                actual: "optimized=\(report.optimized) refs=\(refs[0..<4].map { ($0 as NSString).pathExtension })")
        t.check("Old large files are deleted only after the replacement is saved",
                [oldA, oldB, shared].allSatisfy { !fm.fileExists(atPath: root.appendingPathComponent($0).path) } &&
                refs[0..<4].allSatisfy { fm.fileExists(atPath: root.appendingPathComponent($0).path) },
                expected: "old gone, new present", actual: "before=\(kb(report.bytesBefore)) after=\(kb(report.bytesAfter))")
        t.check("Failed optimization keeps the original file and reference",
                refs[4] == corrupt && (try? Data(contentsOf: root.appendingPathComponent(corrupt))) == corruptBytes && report.keptOriginal == 1,
                expected: "corrupt file untouched", actual: "ref=\(refs[4] == corrupt) kept=\(report.keptOriginal)")
        t.check("Already-small screenshots and missing files are left alone",
                refs[5] == tiny && refs[6] == "missing.jpg" && report.alreadySmall == 1 && report.missing == 1,
                expected: "1 small, 1 missing", actual: "small=\(report.alreadySmall) missing=\(report.missing)")
        t.check("Old backups that still say '<id>.jpg' open the optimized file",
                storage.loadImage(relativePath: oldA) != nil, expected: "loads", actual: "\(storage.loadImage(relativePath: oldA) != nil)")

        // Repeating the migration changes nothing (no endless re-compression)
        let bytesAfterFirst = refs[0..<4].map(size)
        let second = ScreenshotStorageMigrator.optimizeExisting(in: ctx, storage: storage)
        t.check("Running the optimization again does not re-compress anything",
                second.optimized == 0 && refs[0..<4].map(size) == bytesAfterFirst && expenses.map { $0.imageRelativePath ?? "" } == refs,
                expected: "0 optimized, files identical", actual: "optimized=\(second.optimized)")

        // Restart safety: interrupted after writing the copy, and after saving the reference
        let interruptedCopy = legacyFile()
        let stem = (interruptedCopy as NSString).deletingPathExtension
        let preWritten = ScreenshotOptimizer.optimize(fileAt: root.appendingPathComponent(interruptedCopy))!
        let preName = preWritten.fileExtension == "heic" ? "\(stem).heic" : "\(stem)-opt.jpg"
        try? preWritten.data.write(to: root.appendingPathComponent(preName))
        let e1 = Expense(amount: 1, merchant: "A"); e1.imageRelativePath = interruptedCopy; ctx.insert(e1)
        let leftover = legacyFile()
        let leftoverStem = (leftover as NSString).deletingPathExtension
        let leftoverOut = ScreenshotOptimizer.optimize(fileAt: root.appendingPathComponent(leftover))!
        let leftoverNew = leftoverOut.fileExtension == "heic" ? "\(leftoverStem).heic" : "\(leftoverStem)-opt.jpg"
        try? leftoverOut.data.write(to: root.appendingPathComponent(leftoverNew))
        let e2 = Expense(amount: 1, merchant: "B"); e2.imageRelativePath = leftoverNew; ctx.insert(e2)
        try? ctx.save()
        let filesBefore = (try? fm.contentsOfDirectory(atPath: root.path).count) ?? 0
        _ = ScreenshotStorageMigrator.optimizeExisting(in: ctx, storage: storage)
        let filesAfter = (try? fm.contentsOfDirectory(atPath: root.path).count) ?? 0
        t.check("Restart-safe: a finished copy is reused (no duplicate) and a leftover old file is removed",
                e1.imageRelativePath == preName && !fm.fileExists(atPath: root.appendingPathComponent(interruptedCopy).path) &&
                e2.imageRelativePath == leftoverNew && !fm.fileExists(atPath: root.appendingPathComponent(leftover).path) &&
                filesAfter == filesBefore - 2,
                expected: "reused copy; 2 old files removed; no new files", actual: "files \(filesBefore) → \(filesAfter), e1=\(e1.imageRelativePath ?? "nil")")

        let stats = storage.storageStats(relativePaths: expenses.compactMap(\.imageRelativePath))
        t.check("Storage stats count each referenced file once",
                stats.count == 5 && stats.totalBytes > 0, expected: "5 files (shared once, missing skipped)", actual: "\(stats.count) files, \(kb(stats.totalBytes))")
        return results
    }

    /// Draws a payment confirmation like a real eWallet screenshot: header, big amount, small details, photo-like noise.
    static func makePaymentScreenshot(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let k = size.width / 1320
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.96, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.05, green: 0.33, blue: 0.75, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 520 * k))
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<400 {  // photo-like banner area (ads/avatars) that compresses poorly
                UIColor(hue: .random(in: 0...1, using: &rng), saturation: 0.5, brightness: 0.8, alpha: 1).setFill()
                ctx.fill(CGRect(x: .random(in: 0...size.width, using: &rng), y: (2200 * k) + .random(in: 0...(600 * k), using: &rng),
                                width: 40 * k, height: 40 * k))
            }
            func text(_ s: String, _ y: CGFloat, _ pt: CGFloat, _ color: UIColor = .black, bold: Bool = false) {
                let font = bold ? UIFont.boldSystemFont(ofSize: pt * k) : UIFont.systemFont(ofSize: pt * k)
                (s as NSString).draw(at: CGPoint(x: 80 * k, y: y * k), withAttributes: [.font: font, .foregroundColor: color])
            }
            text("Touch 'n Go eWallet", 200, 64, .white, bold: true)
            text("Transferred", 620, 56, .darkGray)
            text("RM 22.00", 720, 150, .black, bold: true)
            text("Receiver", 1000, 40, .gray); text("RANA SOHEL", 1050, 52, .black, bold: true)
            text("Date/Time", 1200, 40, .gray); text("15/09/2026 13:49:06", 1250, 46)
            text("Reference No.", 1400, 40, .gray); text("2026091512345678", 1450, 42)
            text("Wallet Ref", 1600, 40, .gray); text("TNG-20260915-RANA", 1650, 42)
            for i in 0..<6 { text("Terms and conditions apply. Line \(i + 1) of small print text.", 1820 + CGFloat(i) * 50, 34, .gray) }
        }
    }
}

import PDFKit
import UniformTypeIdentifiers

// MARK: - PDF / text share import tests (generated PDFs in temporary files only)

/// Shared PDFs and text: routing (PDF vs text vs the untouched image path), native text extraction, the
/// image-only OCR fallback, multi-page, malformed/empty files, and the existing parser + duplicate rules.
/// `--run-pdf-import-tests`
@MainActor
public struct PDFImportTests {
    /// A Maybank-style receipt (fictional values, only used here).
    static let receiptLines = ["Maybank", "DuitNow QR", "Successful", "RM 15.00", "Recipient", "RANASOHEL",
                               "Reference ID", "QR80504572", "Date & Time", "06 Oct 2026, 12:31 PM", "From Account", "Savings Account-i"]

    /// A real text PDF (selectable text), one array of lines per page.
    static func textPDF(_ pages: [[String]]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { ctx in
            for lines in pages {
                ctx.beginPage()
                for (i, line) in lines.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 60, y: 80 + CGFloat(i) * 34),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
                }
            }
        }
    }

    /// A PDF whose page is only a picture of the receipt (no text layer), like a scanned receipt.
    static func imageOnlyPDF(_ lines: [String]) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1400), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 80, y: 100 + CGFloat(i) * 70), withAttributes: [.font: UIFont.systemFont(ofSize: 40)])
            }
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            picture.draw(in: CGRect(x: 0, y: 0, width: 595, height: 842))
        }
    }

    static func write(_ data: Data, name: String = "receipt.pdf") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDFImportTests-\(UUID().uuidString)-\(name)")
        try? data.write(to: url)
        return url
    }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "PDF import") { results.append($0) }
        let parser = TransactionParser.shared
        func describe(_ p: ParsedTransaction) -> String {
            "amount=\(p.amount ?? -1) merchant=\(p.merchant ?? "nil") ref=\(p.transactionReference ?? "nil") date=\(p.dateString ?? "nil") time=\(p.timeString ?? "nil") status=\(p.transactionStatus ?? "nil") channel=\(p.paymentChannel.rawValue) source=\(p.paymentSource?.rawValue ?? "nil") funding=\(p.displayFundingAccount)"
        }

        // 1. Text-based PDF → native text (no OCR) → existing parser
        let textURL = write(textPDF([receiptLines]))
        defer { try? FileManager.default.removeItem(at: textURL) }
        var ocrCalls = 0
        let native = try? await PDFReceiptImporter.extract(from: textURL) { _ in ocrCalls += 1; return OCRResult(fullText: "", lines: [], averageConfidence: 0) }
        let nativeParsed = native.map { parser.parse(ocrResult: $0.ocrResult) }
        t.check("Text PDF: PDFKit text is used directly (no rendering, no OCR) and the existing parser reads the receipt",
                native?.method == .nativeText && ocrCalls == 0 && native?.pagesUsed == [0] && native?.preview != nil &&
                nativeParsed?.amount == 15.0 && nativeParsed?.merchant == "RANASOHEL" && nativeParsed?.transactionReference == "QR80504572" &&
                nativeParsed?.dateString == "2026-10-06" && nativeParsed?.timeString?.hasPrefix("12:31") == true,
                expected: "native text; RM15, RANASOHEL, QR80504572, 6 Oct 12:31", actual: nativeParsed.map(describe) ?? "nil")
        t.check("Funding account and payment channel stay separate: Maybank is the funding account, DuitNow QR the channel (never 'Maybank' as a channel)",
                nativeParsed?.displayFundingAccount == "Maybank" && nativeParsed?.paymentChannel == .duitNowQR && nativeParsed?.transactionStatus != nil,
                expected: "Maybank / DuitNow QR", actual: nativeParsed.map(describe) ?? "nil")

        // A receipt that names the bank but not how it was paid: the bank is the funding account, the channel is Unknown.
        let noChannel = parser.parse(ocrResult: PDFReceiptImporter.ocrResult(from: ["Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN", "Reference ID", "MB12345678"]))
        t.check("Receipt without channel wording: funding account Maybank, channel Unknown (needs review), never a guessed Bank Transfer",
                noChannel.displayFundingAccount == "Maybank" && noChannel.amount == 42.5 && noChannel.transactionReference == "MB12345678" &&
                noChannel.paymentChannel == .unknown,
                expected: "funding Maybank, RM42.50, MB12345678, UNKNOWN", actual: describe(noChannel))

        // 2. Image-only PDF → render page → existing on-device Vision OCR → parser
        let imageURL = write(imageOnlyPDF(receiptLines))
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let viaOCR = try? await PDFReceiptImporter.extract(from: imageURL)
        let ocrParsed = viaOCR.map { parser.parse(ocrResult: $0.ocrResult) }
        t.check("Image-only PDF: no text layer → page rendered → Vision OCR → amount and reference still found",
                viaOCR?.method == .ocr && ocrParsed?.amount == 15.0 && ocrParsed?.transactionReference == "QR80504572",
                expected: "OCR; RM15; QR80504572", actual: ocrParsed.map(describe) ?? "nil")

        // 3. Multi-page: cover page, receipt, terms → only the receipt page is used
        let multiURL = write(textPDF([["Maybank2u", "Transaction receipt", "Thank you for banking with us"], receiptLines,
                                      ["Terms and conditions apply", "Please keep this receipt for your records"]]))
        defer { try? FileManager.default.removeItem(at: multiURL) }
        let multi = try? await PDFReceiptImporter.extract(from: multiURL)
        t.check("Multi-page PDF: 3 pages, only the page with the payment is used (native text, nothing rendered)",
                multi?.pageCount == 3 && multi?.pagesUsed == [1] && multi?.method == .nativeText &&
                multi.map { parser.parse(ocrResult: $0.ocrResult).amount } == 15.0,
                expected: "pages 3, used [1]", actual: "\(String(describing: multi?.pageCount)) \(String(describing: multi?.pagesUsed))")

        // 4–5, 8–10. Routing: file and data PDFs, plain text, images untouched, unsupported files
        let pdfData = textPDF([receiptLines])
        func routed(_ provider: NSItemProvider) async -> String {
            switch await SharedInputRouter.route([provider]) {
            case .pdf(let url):
                let ok = (try? Data(contentsOf: url)).map(SharedInputRouter.isPDF) ?? false
                try? FileManager.default.removeItem(at: url)
                return ok && url.path.hasPrefix(FileManager.default.temporaryDirectory.path) ? "pdf" : "pdf-bad"
            case .text(let text): return "text:\(text.prefix(7))"
            case .image: return "image"
            }
        }
        let fileProvider = NSItemProvider(contentsOf: textURL)!
        let dataProvider = NSItemProvider(item: pdfData as NSData, typeIdentifier: UTType.pdf.identifier)
        let fileURLProvider = NSItemProvider(item: textURL as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let textProvider = NSItemProvider(item: "Maybank RM 15.00 Reference ID QR80504572" as NSString, typeIdentifier: UTType.plainText.identifier)
        let pngProvider = NSItemProvider(item: ScreenshotStorageTests.makePaymentScreenshot(size: CGSize(width: 300, height: 600)).pngData()! as NSData,
                                         typeIdentifier: UTType.png.identifier)
        let pngFile = write(ScreenshotStorageTests.makePaymentScreenshot(size: CGSize(width: 300, height: 600)).pngData()!, name: "shot.png")
        defer { try? FileManager.default.removeItem(at: pngFile) }
        let imageFileURLProvider = NSItemProvider(item: pngFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let zipProvider = NSItemProvider(item: Data("PK not a pdf".utf8) as NSData, typeIdentifier: "public.zip-archive")
        let r = [await routed(fileProvider), await routed(dataProvider), await routed(fileURLProvider), await routed(textProvider),
                 await routed(pngProvider), await routed(imageFileURLProvider), await routed(zipProvider)]
        t.check("Routing: PDF as file, as data and as file URL → PDF path (private temporary copy); plain text → text; a PNG and an image file URL → the existing image path; unsupported → image path's error",
                r == ["pdf", "pdf", "pdf", "text:Maybank", "image", "image", "image"],
                expected: "pdf, pdf, pdf, text, image, image, image", actual: "\(r)")

        // 6–7. Malformed and empty PDFs fail gracefully
        var garbage = Data("%PDF-1.7\n".utf8); garbage.append(Data((0..<4000).map { _ in UInt8.random(in: 0...255) }))
        let badURL = write(garbage)
        defer { try? FileManager.default.removeItem(at: badURL) }
        var badError: PDFReceiptImporter.ImportError?
        do { _ = try await PDFReceiptImporter.extract(from: badURL) } catch { badError = error as? PDFReceiptImporter.ImportError }
        var emptyError: PDFReceiptImporter.ImportError?
        do { _ = try await PDFReceiptImporter.extract(from: PDFDocument()) } catch { emptyError = error as? PDFReceiptImporter.ImportError }
        let blankURL = write(textPDF([[]]))
        defer { try? FileManager.default.removeItem(at: blankURL) }
        var blankError: PDFReceiptImporter.ImportError?
        do { _ = try await PDFReceiptImporter.extract(from: blankURL) { _ in OCRResult(fullText: "", lines: [], averageConfidence: 0) } } catch { blankError = error as? PDFReceiptImporter.ImportError }
        t.check("Malformed PDF → 'couldn't open'; no pages → 'no pages'; a blank page with nothing readable → 'no details' (no crash)",
                badError == .unreadable && emptyError == .empty && blankError == .noText,
                expected: "unreadable, empty, noText", actual: "\(String(describing: badError)) \(String(describing: emptyError)) \(String(describing: blankError))")

        // 10–11. Existing duplicate rules with the PDF's reference
        let ctx = TestKit.context()
        let existing = Expense(amount: 15, merchant: "RANASOHEL", date: nativeParsed?.date ?? Date(), transactionReference: "QR80504572",
                               paymentChannel: .qrPayment, fundingAccount: "Maybank")
        ctx.insert(existing); try? ctx.save()
        let same = DuplicateDetector.shared.checkDuplicate(amount: nativeParsed?.amount, merchant: nativeParsed?.merchant, date: nativeParsed?.date,
                                                           reference: nativeParsed?.transactionReference, paymentChannel: nativeParsed?.paymentChannel,
                                                           fundingAccount: nativeParsed?.displayFundingAccount, in: ctx)
        let otherReceipt = parser.parse(ocrResult: PDFReceiptImporter.ocrResult(from: ["Maybank", "DuitNow QR", "Successful", "RM 15.00", "Recipient", "LABIB STORE",
                                                                                        "Reference ID", "QR99990001", "Date & Time", "06 Oct 2026, 18:05 PM"]))
        let different = DuplicateDetector.shared.checkDuplicate(amount: otherReceipt.amount, merchant: otherReceipt.merchant, date: otherReceipt.date,
                                                                reference: otherReceipt.transactionReference, paymentChannel: otherReceipt.paymentChannel,
                                                                fundingAccount: otherReceipt.displayFundingAccount, in: ctx)
        t.check("Same PDF shared twice: its reference is a strong duplicate; another RM15 receipt with a different reference and recipient is not a duplicate",
                same.isDuplicate && same.isStrong && same.matchedExpense?.id == existing.id && !different.isDuplicate,
                expected: "strong, none", actual: "\(same.isStrong) \(different.isDuplicate)")
        return results
    }
}

// MARK: - Classifier evaluation set (synthetic, anonymised receipts; never real user data)

/// A fixed set of Malaysian receipt texts with the expected merchant, category, payment channel and funding
/// account. `expectedCategory == nil` means "too ambiguous to decide": the correct result is Other/low confidence,
/// never a confident guess. Used to measure accuracy before/after classifier changes.
public enum ClassifierEvaluation {
    public struct Case {
        public let name: String
        public let lines: [String]
        public let merchantContains: String?
        public let expectedCategory: ExpenseCategory?
        public let expectedChannel: PaymentChannel
        public let expectedFunding: String
    }

    /// What a classifier produced for one case.
    public struct Output {
        public let merchant: String?
        public let category: ExpenseCategory
        /// false = shown as a suggestion that needs review (low confidence).
        public let categoryConfident: Bool
        public let channel: PaymentChannel
        public let funding: String
    }

    static func tng(_ type: String, _ merchant: String, _ amount: String = "12.50") -> [String] {
        ["Transaction Details", "Successful", "- RM \(amount)", "Transaction Type", type, "Merchant", merchant,
         "Payment Method", "eWallet Balance", "Date/Time", "05/10/2026 13:22", "Transaction No.", "2026100512345678"]
    }

    public static let cases: [Case] = [
        // Touch 'n Go (funding account) with different merchants and channels
        Case(name: "TNG DuitNow QR restaurant", lines: tng("DuitNow QR", "NASI KANDAR PELITA"), merchantContains: "pelita", expectedCategory: .food, expectedChannel: .duitNowQR, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG payment McDonald's", lines: tng("Payment", "MCDONALD'S BANGSAR"), merchantContains: "mcdonald", expectedCategory: .food, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG payment grocery", lines: tng("Payment", "JAYA GROCER"), merchantContains: "jaya grocer", expectedCategory: .groceries, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG payment transport", lines: tng("Payment", "PRASARANA RAPID KL"), merchantContains: "rapid", expectedCategory: .transport, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG online Shopee", lines: tng("Online Payment", "SHOPEE MALAYSIA"), merchantContains: "shopee", expectedCategory: .shopping, expectedChannel: .other, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG unknown merchant", lines: tng("Payment", "AH SENG ENTERPRISE"), merchantContains: "ah seng", expectedCategory: nil, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG QR warung", lines: tng("Touch 'n Go QR", "WARUNG MAK LONG"), merchantContains: "warung", expectedCategory: .food, expectedChannel: .tngQR, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG GrabFood", lines: tng("Payment", "GRABFOOD"), merchantContains: "grab", expectedCategory: .food, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG GrabCar", lines: tng("Payment", "GRABCAR"), merchantContains: "grab", expectedCategory: .transport, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        Case(name: "TNG Grab (no context)", lines: tng("Payment", "GRAB"), merchantContains: "grab", expectedCategory: nil, expectedChannel: .unknown, expectedFunding: "Touch 'n Go"),
        // Maybank
        Case(name: "Maybank DuitNow QR", lines: ["Maybank", "Successful", "RM 15.00", "DuitNow QR", "Recipient", "TEALIVE KLCC", "Reference ID", "QR80504572", "Date & Time", "06 Oct 2026, 12:31 PM"], merchantContains: "tealive", expectedCategory: .food, expectedChannel: .duitNowQR, expectedFunding: "Maybank"),
        Case(name: "Maybank transfer", lines: ["Maybank", "Transfer Successful", "RM 50.00", "DuitNow Transfer", "Recipient's Name", "ALI BIN ABU", "Recipient's Bank", "CIMB Bank", "Reference ID", "MB20261006001"], merchantContains: "ali bin abu", expectedCategory: nil, expectedChannel: .bankTransfer, expectedFunding: "Maybank"),
        Case(name: "Maybank card", lines: ["Maybank", "Card Purchase", "Maybank Visa Debit", "RM 32.90", "Merchant", "UNIQLO MID VALLEY", "Approval Code 123456", "06 Oct 2026"], merchantContains: "uniqlo", expectedCategory: .shopping, expectedChannel: .card, expectedFunding: "Maybank"),
        Case(name: "Maybank no channel", lines: ["Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN SELERA", "Reference ID", "MB12345678"], merchantContains: "selera", expectedCategory: .food, expectedChannel: .unknown, expectedFunding: "Maybank"),
        // CIMB
        Case(name: "CIMB DuitNow QR", lines: ["CIMB OCTO", "Payment successful", "RM 18.90", "DuitNow QR", "Paid to", "ZUS COFFEE SUNWAY", "OCTO Reference No.", "C2026100555"], merchantContains: "zus", expectedCategory: .food, expectedChannel: .duitNowQR, expectedFunding: "CIMB"),
        Case(name: "CIMB transfer", lines: ["CIMB OCTO", "Transfer successful", "RM 100.00", "Instant Transfer", "To", "AHMAD BIN ALI", "Recipient bank Maybank", "OCTO Reference No.", "C2026100777"], merchantContains: "ahmad", expectedCategory: nil, expectedChannel: .bankTransfer, expectedFunding: "CIMB"),
        Case(name: "CIMB card fuel", lines: ["CIMB", "Card Purchase", "CIMB Mastercard Debit", "RM 120.00", "Merchant", "SHELL MALAYSIA TRADING", "Approval Code 654321"], merchantContains: "shell", expectedCategory: .transport, expectedChannel: .card, expectedFunding: "CIMB"),
        Case(name: "CIMB no channel", lines: ["CIMB OCTO", "Successful", "RM 9.00", "Paid to", "KOPITIAM HAPPY", "OCTO Reference No.", "C1234567890"], merchantContains: "kopitiam", expectedCategory: .food, expectedChannel: .unknown, expectedFunding: "CIMB"),
        // RHB
        Case(name: "RHB DuitNow QR", lines: ["RHB", "Transaction Successful", "RM 25.00", "DuitNow QR", "Merchant Name", "7-ELEVEN MALAYSIA", "Reference No.", "RHB20261005777"], merchantContains: "7-eleven", expectedCategory: .groceries, expectedChannel: .duitNowQR, expectedFunding: "RHB"),
        Case(name: "RHB transfer", lines: ["RHB", "Transaction Successful", "RM 300.00", "Fund Transfer", "Beneficiary Name", "SITI AMINAH", "Reference No.", "RHB123456789"], merchantContains: "siti", expectedCategory: nil, expectedChannel: .bankTransfer, expectedFunding: "RHB"),
        Case(name: "RHB card", lines: ["RHB", "Card Purchase", "RHB Visa Debit", "RM 59.00", "Merchant", "WATSONS PERSONAL CARE", "Approval Code 111222"], merchantContains: "watsons", expectedCategory: .health, expectedChannel: .card, expectedFunding: "RHB"),
        Case(name: "RHB no channel", lines: ["RHB", "Successful", "RM 12.00", "Recipient", "ABC TRADING", "Reference No.", "RHB555666777"], merchantContains: "abc trading", expectedCategory: nil, expectedChannel: .unknown, expectedFunding: "RHB"),
        // Other channels
        Case(name: "Apple Pay", lines: ["Apple Pay", "STARBUCKS PAVILION", "RM 18.50", "Maybank Visa Debit", "Status: Approved"], merchantContains: "starbucks", expectedCategory: .food, expectedChannel: .applePay, expectedFunding: "Maybank"),
        Case(name: "Generic Scan & Pay", lines: ["Payment Successful", "RM 6.00", "Scan & Pay", "Merchant", "PASAR MALAM STALL", "Date 05/10/2026"], merchantContains: "pasar malam", expectedCategory: .groceries, expectedChannel: .qrPayment, expectedFunding: "Unknown"),
        Case(name: "Business wording trap", lines: tng("Payment", "SMART BUSINESS PROVIDER SDN BHD"), merchantContains: "smart business", expectedCategory: nil, expectedChannel: .unknown, expectedFunding: "Touch 'n Go")
    ]

    /// Merchant-name variants that should (or must not) normalize to a known merchant.
    public static let normalization: [(raw: String, expected: String?)] = [
        ("McDonald's", "McDonald's"), ("MCD", "McDonald's"), ("McD", "McDonald's"), ("MCDONALDS", "McDonald's"),
        ("MCDONALD'S MALAYSIA", "McDonald's"), ("7 ELEVEN", "7-Eleven"), ("7-ELEVEN", "7-Eleven"), ("7ELEVEN", "7-Eleven"),
        ("Lotus's", "Lotus's"), ("LOTUSS MALAYSIA", "Lotus's"), ("GRABFOOD", "GrabFood"), ("SHELL MALAYSIA TRADING", "Shell"),
        ("MCDERMOTT LAW", nil), ("SHELLY BEAUTY", nil), ("DIGITAL STORE", nil), ("ATMOS CAFE", nil), ("AMAZARA TRAVEL", nil),
        ("TMART KEDAI", nil)
    ]

    public struct Score: CustomStringConvertible {
        public var total = 0, category = 0, channel = 0, funding = 0, merchant = 0
        public var confidentWrongCategory = 0, wrongChannelNotUnknown = 0, lowConfidence = 0
        public var misses: [String] = []
        public var description: String {
            "category \(category)/\(total), channel \(channel)/\(total), funding \(funding)/\(total), merchant \(merchant)/\(total); " +
            "confident-wrong categories \(confidentWrongCategory), wrong non-Unknown channels \(wrongChannelNotUnknown), review-needed \(lowConfidence)"
        }
    }

    public static func score(_ classify: ([String]) -> Output) -> Score {
        var s = Score()
        for c in cases {
            let out = classify(c.lines)
            s.total += 1
            let categoryOK: Bool
            if let expected = c.expectedCategory {
                categoryOK = out.category == expected
                if !categoryOK && out.categoryConfident { s.confidentWrongCategory += 1 }
            } else {
                categoryOK = out.category == .other || !out.categoryConfident
                if !categoryOK { s.confidentWrongCategory += 1 }
            }
            if !out.categoryConfident { s.lowConfidence += 1 }
            if categoryOK { s.category += 1 } else { s.misses.append("\(c.name): category \(out.category.rawValue)\(out.categoryConfident ? "" : "?")") }
            if out.channel == c.expectedChannel { s.channel += 1 } else {
                s.misses.append("\(c.name): channel \(out.channel.rawValue)")
                if out.channel != .unknown { s.wrongChannelNotUnknown += 1 }
            }
            if out.funding.lowercased() == c.expectedFunding.lowercased() { s.funding += 1 } else { s.misses.append("\(c.name): funding \(out.funding)") }
            if let m = c.merchantContains, (out.merchant ?? "").lowercased().contains(m) { s.merchant += 1 }
            else if c.merchantContains != nil { s.misses.append("\(c.name): merchant \(out.merchant ?? "nil")") }
        }
        return s
    }
}
