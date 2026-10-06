import SwiftUI

public enum PaymentSource: String, CaseIterable, Codable, Identifiable {
    case touchNGo = "Touch 'n Go"
    case maybank = "Maybank"
    case cimb = "CIMB"
    case rhb = "RHB"
    case publicBank = "Public Bank"
    case bankIslam = "Bank Islam"
    case grabPay = "GrabPay"
    case boost = "Boost"
    case duitNow = "DuitNow"
    case wise = "Wise"
    case applePay = "Apple Pay"
    case physicalCard = "Physical Card"
    case qrPayment = "QR Payment"
    case cash = "Cash"
    case bankTransfer = "Bank Transfer"
    case other = "Other"
    case unknown = "Unknown"

    public var id: String { rawValue }

    public var logoAssetName: String? {
        switch self {
        case .touchNGo: return "provider_tng"
        case .maybank: return "provider_maybank"
        case .cimb: return "provider_cimb"
        case .rhb: return "provider_rhb"
        case .applePay: return "provider_apple_pay"
        default: return nil
        }
    }

    public var hasCustomLogo: Bool {
        logoAssetName != nil
    }

    public var defaultPaymentMethod: String {
        switch self {
        case .touchNGo, .grabPay, .boost: return "ewallet"
        case .applePay, .wise: return "digital_wallet"
        case .maybank, .cimb, .rhb, .publicBank, .bankIslam, .duitNow, .bankTransfer: return "bank_transfer"
        case .physicalCard: return "card"
        case .qrPayment: return "qr_code"
        case .cash: return "cash"
        case .other, .unknown: return "unknown"
        }
    }

    public var normalizedIdentifier: String {
        switch self {
        case .touchNGo: return "touch_n_go"
        case .maybank: return "maybank"
        case .cimb: return "cimb"
        case .rhb: return "rhb"
        case .publicBank: return "public_bank"
        case .bankIslam: return "bank_islam"
        case .grabPay: return "grabpay"
        case .boost: return "boost"
        case .duitNow: return "duitnow"
        case .wise: return "wise"
        case .applePay: return "apple_pay"
        case .physicalCard: return "physical_card"
        case .qrPayment: return "duitnow"
        case .cash: return "cash"
        case .bankTransfer: return "bank_transfer"
        case .other: return "other"
        case .unknown: return "unknown"
        }
    }

    public static func from(normalizedIdentifier: String) -> PaymentSource {
        if normalizedIdentifier == "maybank_mae" || normalizedIdentifier == "mae" {
            return .maybank
        }
        for source in PaymentSource.allCases {
            if source.normalizedIdentifier == normalizedIdentifier {
                return source
            }
        }
        return .unknown
    }

    public static func from(string: String) -> PaymentSource {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = PaymentSource(rawValue: trimmed) {
            return exact
        }
        for source in PaymentSource.allCases {
            if source.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame ||
               source.shortName.caseInsensitiveCompare(trimmed) == .orderedSame {
                return source
            }
        }
        return from(normalizedIdentifier: trimmed.lowercased())
    }

    public var shortName: String {
        switch self {
        case .touchNGo: return "TNG"
        case .publicBank: return "PBB"
        case .bankIslam: return "BIMB"
        default: return rawValue
        }
    }

    public var icon: String {
        switch self {
        case .touchNGo: return "wallet.pass.fill"
        case .maybank: return "building.columns.fill"
        case .cimb: return "building.columns"
        case .rhb: return "building.2.fill"
        case .publicBank: return "building.columns.fill"
        case .bankIslam: return "building.columns"
        case .grabPay: return "creditcard.and.123"
        case .boost: return "bolt.fill"
        case .duitNow: return "arrow.triangle.2.circlepath"
        case .wise: return "globe.asia.australia.fill"
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
        case .publicBank: return Color.red
        case .bankIslam: return Color.red.opacity(0.8)
        case .grabPay: return Color.green
        case .boost: return Color.red
        case .duitNow: return Color.pink
        case .wise: return Color.mint
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
