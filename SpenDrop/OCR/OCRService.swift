import UIKit
import Vision

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
