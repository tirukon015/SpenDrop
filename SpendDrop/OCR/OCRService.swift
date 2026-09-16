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
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: image.visionOrientation, options: [:])

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                var lines: [RecognizedTextLine] = []
                var totalConfidence: Float = 0.0

                // Sort observations top-to-bottom, then left-to-right
                let sortedObservations = observations.sorted { obs1, obs2 in
                    let y1 = obs1.boundingBox.origin.y
                    let y2 = obs2.boundingBox.origin.y
                    if abs(y1 - y2) > 0.02 {
                        // In Vision, (0,0) is bottom-left, so higher Y is higher on the page
                        return y1 > y2
                    }
                    return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x
                }

                for observation in sortedObservations {
                    // Get candidate with highest confidence
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

                let fullText = lines.map { $0.text }.joined(separator: "\n")
                let avgConfidence = lines.isEmpty ? 0.0 : totalConfidence / Float(lines.count)

                let result = OCRResult(fullText: fullText, lines: lines, averageConfidence: avgConfidence)
                continuation.resume(returning: result)
            }

            // Accurate recognition level with language correction
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "ms-MY", "zh-Hans"]

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
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
