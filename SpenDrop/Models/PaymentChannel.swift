import SwiftUI

/// Distinguishes how a payment was executed (Payment Channel) from where the funds came from (Funding Account).
/// Requirement: Never guess the payment channel. If it cannot be reliably identified, use `.unknown`.
public enum PaymentChannel: String, CaseIterable, Codable, Identifiable {
    case applePay = "APPLE_PAY"
    case qrPayment = "QR_PAYMENT"
    case bankTransfer = "BANK_TRANSFER"
    case card = "CARD"
    case cash = "CASH"
    case other = "OTHER"
    case unknown = "UNKNOWN"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .qrPayment: return "QR Payment"
        case .bankTransfer: return "Bank Transfer"
        case .card: return "Card"
        case .cash: return "Cash"
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
        case .other: return .orange
        case .unknown: return .gray
        }
    }

    /// Conservative detection from OCR text or metadata.
    /// Never guesses: returns .unknown if clear evidence is absent.
    /// Priority hierarchy:
    ///   1. Apple Wallet provenance (detectedSource == .appleWallet) → .applePay
    ///   2. Explicit channel text ("Apple Pay", "DuitNow QR", etc.)
    ///   3. Explicit physical card text ("Card Purchase", "POS Card")
    ///   4. Instrument alone (e.g. "Visa Debit" without source context) → .unknown
    ///   5. Fallback → .unknown
    public static func detect(from text: String, paymentSource: PaymentSource? = nil, paymentMethod: String? = nil, detectedSource: DetectedTransactionSource = .unknown) -> PaymentChannel {
        // PRIORITY 1: Apple Wallet provenance
        if detectedSource == .appleWallet {
            return .applePay
        }

        let lower = text.lowercased()

        // PRIORITY 2: Explicit channel text
        // 2a. Apple Pay evidence
        if lower.contains("apple pay") || lower.contains("pay with apple") || lower.contains("apple cash") {
            return .applePay
        }

        // 2b. QR payment evidence
        if lower.contains("duitnow qr") || lower.contains("scan & pay") || lower.contains("scan and pay") ||
           lower.contains("qr pay") || lower.contains("paynet qr") || lower.contains("scan qr") ||
           lower.contains("via qr") || lower.contains("d-qr") || paymentMethod == "duitnow_qr" {
            return .qrPayment
        }

        // 2c. Bank transfer evidence
        if lower.contains("duitnow transfer") || lower.contains("fund transfer") || lower.contains("funds transfer") ||
           lower.contains("interbank") || lower.contains("ibg") || lower.contains("fpx payment") ||
           lower.contains("fpx") || lower.contains("giro") || lower.contains("transferred to") ||
           lower.contains("transfer to account") || lower.contains("instant transfer") ||
           paymentMethod == "bank_transfer" {
            return .bankTransfer
        }

        // PRIORITY 3: Explicit physical card text (POS / card purchase context)
        if lower.contains("card purchase") || lower.contains("pos card") || lower.contains("card present") ||
           lower.contains("contactless") || lower.contains("chip & pin") || lower.contains("chip and pin") ||
           paymentMethod == "card" {
            return .card
        }

        // 5. Cash evidence
        if lower.contains("cash") || lower.contains("tunai") || lower.contains("wang tunai") || paymentMethod == "cash" || paymentSource == .cash {
            return .cash
        }

        // Conservative fallback: If paymentSource was explicitly Apple Pay or QR Payment in older data
        if paymentSource == .applePay {
            return .applePay
        }
        if paymentSource == .qrPayment {
            return .qrPayment
        }
        if paymentSource == .bankTransfer {
            return .bankTransfer
        }
        if paymentSource == .physicalCard {
            return .card
        }

        // PRIORITY 4 & 5: Instrument alone (e.g. "Visa Debit") without source context → .unknown
        return .unknown
    }
}
