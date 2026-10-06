import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers

public struct RecognizedTextLine {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect = .zero) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct OCRResult {
    public let fullText: String
    public let lines: [RecognizedTextLine]
    public let averageConfidence: Float

    public init(fullText: String, lines: [RecognizedTextLine], averageConfidence: Float) {
        self.fullText = fullText
        self.lines = lines
        self.averageConfidence = averageConfidence
    }
}

public enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be processed."
        case .recognitionFailed(let message):
            return "Text recognition failed: \(message)"
        case .noTextFound:
            return "No readable text was found in the image."
        }
    }
}

public final class OCRService {
    public static let shared = OCRService()

    private init() {}

    /// Performs on-device text recognition on a UIImage using Apple's Vision framework
    public func recognizeText(from image: UIImage) async throws -> OCRResult {
        // Downsample working copy for OCR if excessive to protect memory in App Extensions
        let workingImage = downsampleIfNeeded(image: image, maxDimension: 1280)

        guard let cgImage = extractCGImage(from: workingImage) else {
            throw OCRError.invalidImage
        }

        let orientation = workingImage.visionOrientation

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "ms-MY", "zh-Hans"]

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            try autoreleasepool {
                do {
                    try requestHandler.perform([request])
                } catch {
                    throw OCRError.recognitionFailed(error.localizedDescription)
                }
            }

            guard let observations = request.results, !observations.isEmpty else {
                throw OCRError.noTextFound
            }

            // Quantized row-band sort ensures strict weak ordering (prevents Swift sorting runtime crash)
            let rowBandHeight: CGFloat = 0.018
            let sortedObservations = observations.sorted { obs1, obs2 in
                // In Vision coordinates, (0,0) is bottom-left, so (1.0 - midY) measures distance from top
                let topDist1 = 1.0 - obs1.boundingBox.midY
                let topDist2 = 1.0 - obs2.boundingBox.midY

                let band1 = Int(topDist1 / rowBandHeight)
                let band2 = Int(topDist2 / rowBandHeight)

                if band1 != band2 {
                    return band1 < band2 // Higher on the page (lower band number) comes first
                }
                return obs1.boundingBox.minX < obs2.boundingBox.minX // Left to right within the same band
            }

            var lines: [RecognizedTextLine] = []
            var totalConfidence: Float = 0.0

            for observation in sortedObservations {
                if let candidate = observation.topCandidates(1).first {
                    let line = RecognizedTextLine(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                    lines.append(line)
                    totalConfidence += candidate.confidence
                }
            }

            guard !lines.isEmpty else {
                throw OCRError.noTextFound
            }

            let fullText = lines.map { $0.text }.joined(separator: "\n")
            let avgConfidence = totalConfidence / Float(lines.count)

            return OCRResult(fullText: fullText, lines: lines, averageConfidence: avgConfidence)
        }.value
    }

    // MARK: - Helpers

    private func extractCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage {
            return cg
        }
        if let ci = image.ciImage {
            let context = CIContext(options: nil)
            return context.createCGImage(ci, from: ci.extent)
        }
        // Fallback render into bitmap context
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: image.size))
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    private func downsampleIfNeeded(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else {
            return image
        }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension UIImage {
    var visionOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Shared input routing (Share Extension): PDF and text alongside the existing image path

/// What a share contained, decided before anything is decoded. Images are NOT handled here: `.image` means
/// "use the existing image path unchanged". This type does no parsing and creates no records.
public enum SharedInput {
    /// A PDF copied to a private temporary file (the caller deletes it after extraction).
    case pdf(URL)
    /// Plain text shared directly (no OCR needed).
    case text(String)
    /// Anything else: the existing image importer handles it exactly as before.
    case image
}

public enum SharedInputRouter {
    /// Looks at every attachment for a PDF (direct type, or a file URL whose content is a PDF), then for plain
    /// text. Image attachments are never touched, so the existing image flow is unchanged.
    public static func route(_ providers: [NSItemProvider]) async -> SharedInput {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               let url = await copyPDF(from: provider, typeIdentifier: UTType.pdf.identifier) {
                return .pdf(url)
            }
        }
        for provider in providers where !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await copyPDF(from: provider, typeIdentifier: UTType.fileURL.identifier) {
                return .pdf(url)
            }
        }
        let onlyText = providers.allSatisfy { !$0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        if onlyText {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadText(from: provider), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .text(text)
                }
            }
        }
        return .image
    }

    /// True when the bytes are a PDF (files are checked by content, not just by name).
    public static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF".utf8)) != nil
    }

    /// Copies the shared PDF (file, data or file URL representation) to a new temporary file. Returns nil when
    /// the item isn't a PDF, so an image behind a file URL still goes to the image path.
    static func copyPDF(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropShared-\(UUID().uuidString).pdf")
        func write(_ data: Data) -> URL? {
            guard isPDF(data), (try? data.write(to: destination, options: [.atomic, .completeFileProtection])) != nil else { return nil }
            return destination
        }
        func copy(_ source: URL) -> URL? {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            guard let handle = try? FileHandle(forReadingFrom: source) else { return nil }
            let head = (try? handle.read(upToCount: 1024)) ?? Data()
            try? handle.close()
            guard isPDF(head), (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return nil }
            return destination
        }
        // 1. File representation (most bank apps): copied while the system's temporary file still exists.
        if typeIdentifier == UTType.pdf.identifier {
            let fromFile: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                    continuation.resume(returning: url.flatMap(copy))
                }
            }
            if let fromFile { return fromFile }
            // 2. Data representation.
            let fromData: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    continuation.resume(returning: data.flatMap(write))
                }
            }
            if let fromData { return fromData }
        }
        // 3. A file URL item (or a PDF typed item delivered as a URL).
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = item as? URL, url.isFileURL { continuation.resume(returning: copy(url)) }
                else if let data = item as? Data { continuation.resume(returning: write(data)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String { continuation.resume(returning: text) }
                else if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Turns a shared PDF into text for the existing parser, on-device only:
/// 1. PDFKit's own text (no rendering, no OCR) when the PDF contains real text;
/// 2. otherwise renders the relevant pages one at a time and runs the existing Vision OCR on them.
/// Rendered images are only in memory and released after each page. Nothing is saved.
public enum PDFReceiptImporter {
    public enum ImportError: LocalizedError, Equatable {
        case unreadable
        case empty
        case noText

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "SpenDrop couldn't open this PDF."
            case .empty: return "This PDF has no pages."
            case .noText: return "No receipt details could be read from this PDF."
            }
        }
    }

    public enum Method: Equatable { case nativeText, ocr }

    public struct Result {
        /// Same shape as Vision OCR output, so the existing parser is used unchanged.
        public let ocrResult: OCRResult
        public let method: Method
        public let pageCount: Int
        /// Pages whose text was used (0-based).
        public let pagesUsed: [Int]
        /// A small first-page picture for the review screen only (never saved).
        public let preview: UIImage?
    }

    /// Receipts are short; pages past this are not inspected.
    static let maxPages = 5
    static let maxOCRPages = 3

    public static func extract(from url: URL, ocr: (UIImage) async throws -> OCRResult = { try await OCRService.shared.recognizeText(from: $0) }) async throws -> Result {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        return try await extract(from: document, ocr: ocr)
    }

    public static func extract(from document: PDFDocument, ocr: (UIImage) async throws -> OCRResult = { try await OCRService.shared.recognizeText(from: $0) }) async throws -> Result {
        guard document.pageCount > 0 else { throw ImportError.empty }
        let pages = (0..<min(document.pageCount, maxPages)).compactMap { index in document.page(at: index).map { (index, $0) } }
        let preview = pages.first.map { $0.1.thumbnail(of: CGSize(width: 600, height: 900), for: .mediaBox) }

        // 1. Native text: use the pages that look like a payment (an amount), else every page with text.
        let texts = pages.map { ($0.0, lines(in: $0.1.string ?? "")) }
        let withAmount = texts.filter { looksLikePayment($0.1) }
        let chosen = withAmount.isEmpty ? texts.filter { isUsable($0.1) } : withAmount
        let nativeLines = chosen.flatMap(\.1)
        if isUsable(nativeLines) {
            return Result(ocrResult: ocrResult(from: nativeLines, confidence: 1), method: .nativeText, pageCount: document.pageCount,
                          pagesUsed: chosen.map(\.0), preview: preview)
        }

        // 2. Image-only PDF: render and OCR one page at a time; stop at the first page that reads like a payment.
        var fallback: (Int, OCRResult)?
        for (index, page) in pages.prefix(maxOCRPages) {
            guard let image = autoreleasepool(invoking: { render(page, maxDimension: 1600) }) else { continue }
            guard let result = try? await ocr(image), !result.lines.isEmpty else { continue }
            if looksLikePayment(result.lines.map(\.text)) {
                return Result(ocrResult: result, method: .ocr, pageCount: document.pageCount, pagesUsed: [index], preview: preview)
            }
            if fallback == nil { fallback = (index, result) }
        }
        if let fallback {
            return Result(ocrResult: fallback.1, method: .ocr, pageCount: document.pageCount, pagesUsed: [fallback.0], preview: preview)
        }
        throw ImportError.noText
    }

    /// Plain text (shared text, or a PDF's own text) in the same shape as OCR output. Lines keep their order;
    /// there are no boxes, and the parser falls back to line order for positions.
    public static func ocrResult(from lines: [String], confidence: Float = 1) -> OCRResult {
        OCRResult(fullText: lines.joined(separator: "\n"),
                  lines: lines.map { RecognizedTextLine(text: $0, confidence: confidence) },
                  averageConfidence: confidence)
    }

    public static func lines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Enough real text to parse: some letters and at least one digit.
    static func isUsable(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ")
        return text.filter(\.isLetter).count >= 8 && text.contains(where: \.isNumber)
    }

    /// Contains something that looks like a money amount (e.g. "RM 15.00", "15.00").
    static func looksLikePayment(_ lines: [String]) -> Bool {
        isUsable(lines) && lines.contains { $0.range(of: #"\d+[.,]\d{2}\b"#, options: .regularExpression) != nil }
    }

    /// Renders one page at screen-like resolution (white background, no transparency); released by the caller.
    static func render(_ page: PDFPage, maxDimension: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(maxDimension / max(bounds.width, bounds.height), 4)
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
    }
}
