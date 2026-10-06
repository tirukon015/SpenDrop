import SwiftUI

/// Distinguishes how a payment was executed (Payment Channel) from where the funds came from (Funding Account).
/// Requirement: Never guess the payment channel. If it cannot be reliably identified, use `.unknown`.
public enum PaymentChannel: String, CaseIterable, Codable, Identifiable {
    case applePay = "APPLE_PAY"
    case qrPayment = "QR_PAYMENT"
    case bankTransfer = "BANK_TRANSFER"
    case card = "CARD"
    case cash = "CASH"
    // Added later; stored values of the cases above never change.
    case duitNowQR = "DUITNOW_QR"
    case onlineBanking = "ONLINE_BANKING"
    case eWallet = "E_WALLET"
    case other = "OTHER"
    case unknown = "UNKNOWN"
    // Added for Touch 'n Go's own QR (different from DuitNow QR). Existing stored values are unchanged.
    case tngQR = "TNG_QR"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .qrPayment: return "QR Payment"
        case .bankTransfer: return "Bank Transfer"
        case .card: return "Card"
        case .cash: return "Cash"
        case .duitNowQR: return "DuitNow QR"
        case .tngQR: return "Touch 'n Go QR"
        case .onlineBanking: return "Online Banking"
        case .eWallet: return "E-Wallet"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }

    public var iconName: String {
        switch self {
        case .applePay: return "apple.logo"
        case .qrPayment: return "qrcode"
        case .bankTransfer: return "arrow.left.arrow.right"
        case .card: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .duitNowQR: return "qrcode.viewfinder"
        case .tngQR: return "qrcode"
        case .onlineBanking: return "globe"
        case .eWallet: return "iphone"
        case .other: return "ellipsis.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    public var tintColor: Color {
        switch self {
        case .applePay: return .primary
        case .qrPayment: return .indigo
        case .bankTransfer: return .teal
        case .card: return .purple
        case .cash: return .green
        case .duitNowQR: return .pink
        case .tngQR: return .blue
        case .onlineBanking: return .cyan
        case .eWallet: return .blue
        case .other: return .orange
        case .unknown: return .gray
        }
    }

    /// Evidence-first detection from receipt text (kept for existing callers): the channel when the receipt says
    /// so, otherwise Unknown. A bank or wallet name alone (Maybank, Touch 'n Go) is never channel evidence, and a
    /// parser's default payment method is not evidence either.
    public static func detect(from text: String, paymentSource: PaymentSource? = nil, paymentMethod: String? = nil, detectedSource: DetectedTransactionSource = .unknown) -> PaymentChannel {
        suggest(evidenceText: text, paymentSource: paymentSource, detectedSource: detectedSource).channel
    }

    /// Phrases that are explicit evidence for each channel (whole words; most specific first).
    static let evidence: [(PaymentChannel, Double, [String])] = [
        (.applePay, 0.98, ["apple pay", "pay with apple", "apple cash"]),
        (.duitNowQR, 0.97, ["duitnow qr", "duitnow-qr", "duit now qr", "d-qr", "paynet qr"]),
        (.tngQR, 0.95, ["touch 'n go qr", "touch n go qr", "tng qr", "tng ewallet qr", "touchngo qr"]),
        (.card, 0.92, ["card purchase", "pos purchase", "pos card", "card present", "contactless", "chip & pin", "chip and pin",
                      "card payment", "debit card purchase", "credit card purchase", "card transaction"]),
        (.bankTransfer, 0.9, ["duitnow transfer", "fund transfer", "funds transfer", "interbank", "ibg", "instant transfer",
                              "transfer to account", "transferred to", "giro", "fpx", "fpx payment", "bank transfer", "transfer successful",
                              "online transfer", "jompay"]),
        (.qrPayment, 0.8, ["scan & pay", "scan and pay", "qr pay", "qr payment", "scan qr", "via qr", "qr code payment", "pay by qr"]),
        (.other, 0.75, ["online payment", "online purchase", "pay online", "online transaction"]),
        (.cash, 0.85, ["cash", "cash payment", "paid in cash", "tunai", "wang tunai"])
    ]

    /// The channel with confidence and the reason. Unknown (confidence 1) when the receipt has no channel wording.
    public static func suggest(evidenceText text: String, paymentSource: PaymentSource? = nil,
                               detectedSource: DetectedTransactionSource = .unknown) -> ChannelSuggestion {
        if detectedSource == .appleWallet {
            return ChannelSuggestion(channel: .applePay, confidence: 0.98, reason: "Apple Wallet receipt")
        }
        let haystack = " " + MerchantDetector.normalizedWords(text) + " "
        for (channel, confidence, phrases) in evidence {
            if let phrase = phrases.first(where: { haystack.contains(" " + MerchantDetector.normalizedWords($0) + " ") }) {
                return ChannelSuggestion(channel: channel, confidence: confidence, reason: "Receipt says '\(phrase)'")
            }
        }
        // Older records: an explicit channel stored as the payment source.
        switch paymentSource {
        case .applePay?: return ChannelSuggestion(channel: .applePay, confidence: 0.9, reason: "Paid with Apple Pay")
        case .physicalCard?: return ChannelSuggestion(channel: .card, confidence: 0.85, reason: "Paid by card")
        default: break
        }
        return ChannelSuggestion(channel: .unknown, confidence: 1, reason: "The receipt doesn't say how it was paid")
    }
}


/// A payment channel with how sure SpenDrop is and why.
public struct ChannelSuggestion: Equatable {
    public let channel: PaymentChannel
    public let confidence: Double
    public let reason: String
    /// Unknown is a confident answer ("not enough evidence"); anything below 0.75 is not used.
    public var needsReview: Bool { channel == .unknown }
}
