import SwiftUI

public enum PaymentSource: String, CaseIterable, Codable, Identifiable {
    case touchNGo = "Touch 'n Go"
    case maybank = "Maybank"
    case cimb = "CIMB"
    case rhb = "RHB"
    case applePay = "Apple Pay"
    case physicalCard = "Physical Card"
    case qrPayment = "QR Payment"
    case cash = "Cash"
    case bankTransfer = "Bank Transfer"
    case other = "Other"
    case unknown = "Unknown"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .touchNGo: return "TNG"
        default: return rawValue
        }
    }

    public var icon: String {
        switch self {
        case .touchNGo: return "wallet.pass.fill"
        case .maybank: return "building.columns.fill"
        case .cimb: return "building.columns"
        case .rhb: return "building.2.fill"
        case .applePay: return "apple.logo"
        case .physicalCard: return "creditcard.fill"
        case .qrPayment: return "qrcode"
        case .cash: return "banknote.fill"
        case .bankTransfer: return "arrow.left.arrow.right"
        case .other: return "creditcard"
        case .unknown: return "questionmark.circle"
        }
    }

    public var brandColor: Color {
        switch self {
        case .touchNGo: return Color.blue
        case .maybank: return Color.yellow
        case .cimb: return Color.red
        case .rhb: return Color.cyan
        case .applePay: return Color.primary
        case .physicalCard: return Color.purple
        case .qrPayment: return Color.indigo
        case .cash: return Color.green
        case .bankTransfer: return Color.teal
        case .other: return Color.secondary
        case .unknown: return Color.gray
        }
    }
}
