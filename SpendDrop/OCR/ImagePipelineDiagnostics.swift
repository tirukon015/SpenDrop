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
            print("[SpendDrop][DIAGNOSTIC] Starting: \(sample.format)")
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
                print("[SpendDrop][IMAGE] [\(name)] Data loaded: \(data.count) bytes")
            } else {
                dataResult = DiagnosticStepResult(name: "Data loading", passed: false, detail: "Data(contentsOf:) failed to read file bytes")
                print("[SpendDrop][IMAGE] [\(name)] Data loading: FAIL (failed to read bytes)")
            }
        } else {
            // Direct filesystem check for local testing
            let fallbackPaths = [
                "/Users/apple/SpendDrop/SpendDrop/Resources/DiagnosticSamples/\(filename).\(ext)",
                "SpendDrop/Resources/DiagnosticSamples/\(filename).\(ext)"
            ]
            for p in fallbackPaths {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                    dataOptional = d
                    dataResult = DiagnosticStepResult(name: "Data loading", passed: true, detail: "Loaded \(d.count) bytes from path: \(p)")
                    print("[SpendDrop][IMAGE] [\(name)] Data loaded: \(d.count) bytes (fallback path)")
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
            print("[SpendDrop][IMAGE] [\(name)] UIImage decode: SUCCESS (\(uiImageResult.detail))")
        } else {
            uiImageResult = DiagnosticStepResult(name: "UIImage decode", passed: false, detail: "UIImage(data:) returned nil for \(data.count) bytes")
            print("[SpendDrop][IMAGE] [\(name)] UIImage decode: FAIL (\(uiImageResult.detail))")
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
            print("[SpendDrop][IMAGE] [\(name)] CGImage decode: SUCCESS (\(cgImageResult.detail))")
        } else if let ci = uiImage.ciImage, let cg = CIContext(options: nil).createCGImage(ci, from: ci.extent) {
            cgImageResult = DiagnosticStepResult(name: "CGImage decode", passed: true, detail: "rendered from CIImage: \(cg.width)x\(cg.height)")
            print("[SpendDrop][IMAGE] [\(name)] CGImage decode: SUCCESS via CIContext (\(cgImageResult.detail))")
        } else {
            cgImageResult = DiagnosticStepResult(name: "CGImage decode", passed: false, detail: "cgImage was nil and CIContext fallback failed")
            print("[SpendDrop][IMAGE] [\(name)] CGImage decode: FAIL")
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
            print("[SpendDrop][IMAGE] [\(name)] Downsampling: SUCCESS (\(downsampleResult.detail))")
        } else {
            downsampleResult = DiagnosticStepResult(name: "Downsampling", passed: true, detail: "Not needed (\(maxSide) <= 2048)")
            print("[SpendDrop][IMAGE] [\(name)] Downsampling: NOT NEEDED (\(downsampleResult.detail))")
        }

        // 5. Temporary storage test
        var tempStorageResult: DiagnosticStepResult
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("diag_\(UUID().uuidString).jpg")
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: tempFile)
                tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: true, detail: "Wrote \(jpegData.count) bytes to temporaryDirectory")
                print("[SpendDrop][IMAGE] [\(name)] Temp storage: SUCCESS (\(tempStorageResult.detail))")
                try? FileManager.default.removeItem(at: tempFile)
            } catch {
                tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: false, detail: "write(to:) failed: \(error)")
                print("[SpendDrop][IMAGE] [\(name)] Temp storage: FAIL (\(error))")
            }
        } else {
            tempStorageResult = DiagnosticStepResult(name: "Temp storage", passed: false, detail: "jpegData(compressionQuality:) returned nil")
            print("[SpendDrop][IMAGE] [\(name)] Temp storage: FAIL (jpegData nil)")
        }

        // 6. App Group storage test
        var appGroupStorageResult: DiagnosticStepResult
        if let relPath = ImageStorageService.shared.saveImage(uiImage) {
            if let loadedBack = ImageStorageService.shared.loadImage(relativePath: relPath) {
                appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: true, detail: "Saved and verified read (\(relPath), loaded size: \(loadedBack.size))")
                print("[SpendDrop][IMAGE] [\(name)] App Group storage: SUCCESS (\(appGroupStorageResult.detail))")
            } else {
                appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: false, detail: "Saved to \(relPath) but loadImage returned nil")
                print("[SpendDrop][IMAGE] [\(name)] App Group storage: FAIL (loadImage returned nil)")
            }
            ImageStorageService.shared.deleteImage(relativePath: relPath)
        } else {
            appGroupStorageResult = DiagnosticStepResult(name: "App Group storage", passed: false, detail: "saveImage returned nil (App Group container unavailable or unwriteable)")
            print("[SpendDrop][IMAGE] [\(name)] App Group storage: FAIL (saveImage returned nil)")
        }

        // 7. Vision OCR
        print("[SpendDrop][IMAGE] [\(name)] OCR started")
        var ocrResultStep: DiagnosticStepResult
        var recognizedOCRResult: OCRResult? = nil
        do {
            let ocr = try await OCRService.shared.recognizeText(from: uiImage)
            recognizedOCRResult = ocr
            ocrResultStep = DiagnosticStepResult(name: "Vision OCR", passed: true, detail: "\(ocr.lines.count) lines, avgConf: \(ocr.averageConfidence), textLen: \(ocr.fullText.count)")
            print("[SpendDrop][IMAGE] [\(name)] OCR completed: SUCCESS (\(ocrResultStep.detail))")
        } catch {
            ocrResultStep = DiagnosticStepResult(name: "Vision OCR", passed: false, detail: "recognizeText threw: \(error)")
            print("[SpendDrop][IMAGE] [\(name)] OCR FAILED: \(error)")
        }

        // 8. Transaction Parser
        print("[SpendDrop][IMAGE] [\(name)] Parser started")
        let parserResultStep: DiagnosticStepResult
        if let ocr = recognizedOCRResult {
            let parsed = TransactionParser.shared.parse(ocrResult: ocr, image: uiImage)
            let detail = "amount: \(parsed.amount != nil ? "RM\(parsed.amount!)" : "nil"), merchant: \(parsed.merchant ?? "nil"), cat: \(parsed.category?.rawValue ?? "nil"), conf: \(parsed.confidence.rawValue), isBalance: \(parsed.isBalanceOrLimitOnly), isFailed: \(parsed.isFailedTransaction)"
            parserResultStep = DiagnosticStepResult(name: "Transaction Parser", passed: true, detail: detail)
            print("[SpendDrop][IMAGE] [\(name)] Parser completed: \(detail)")
        } else {
            parserResultStep = DiagnosticStepResult(name: "Transaction Parser", passed: false, detail: "Skipped due to OCR failure")
            print("[SpendDrop][IMAGE] [\(name)] Parser: SKIPPED")
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
