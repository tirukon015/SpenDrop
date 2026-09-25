import Foundation

public enum ExpenseSourceType: String, CaseIterable, Codable, Identifiable {
    case manual = "manual"
    case screenshot = "screenshot"
    case photo = "photo"
    case receipt = "receipt"
    case shareExtension = "shareExtension"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual: return "Manual Entry"
        case .screenshot: return "Screenshot"
        case .photo: return "Photo"
        case .receipt: return "Receipt"
        case .shareExtension: return "Share Extension"
        }
    }

    public var icon: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .screenshot: return "iphone"
        case .photo: return "camera.fill"
        case .receipt: return "doc.text.fill"
        case .shareExtension: return "square.and.arrow.up"
        }
    }
}
