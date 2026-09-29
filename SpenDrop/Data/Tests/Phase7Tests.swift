import Foundation
import SwiftData

/// Phase 7: payment channels, ClassificationRule, direction detection, scan→movement, Apple Pay automation,
/// trend/breakdown calculations, backup V3 and the V2 → V3 migration. `--run-phase7-tests`
@MainActor
public struct Phase7Tests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 7") { results.append($0) }

        // MARK: Payment channels
        do {
            let oldValues = [PaymentChannel.applePay, .qrPayment, .bankTransfer, .card, .cash, .other, .unknown].map(\.rawValue)
            let newValues = [PaymentChannel.duitNowQR, .onlineBanking, .eWallet].map(\.rawValue)
            let expense = Expense(amount: 1, merchant: "X")
            expense.paymentChannelRaw = "SOMETHING_NEW"
            t.check("Payment channels: old stored values unchanged, 3 new values, unknown raw falls back to Unknown",
                    oldValues == ["APPLE_PAY", "QR_PAYMENT", "BANK_TRANSFER", "CARD", "CASH", "OTHER", "UNKNOWN"] &&
                    newValues == ["DUITNOW_QR", "ONLINE_BANKING", "E_WALLET"] && expense.paymentChannel == .unknown,
                    expected: "unchanged + 3 new + Unknown", actual: "\(newValues) fallback=\(expense.paymentChannel)")
            t.check("Channel detection never guesses (no text → Unknown; DuitNow QR text keeps its historical QR mapping)",
                    PaymentChannel.detect(from: "Thank you") == .unknown && PaymentChannel.detect(from: "DuitNow QR payment") == .qrPayment,
                    expected: "unknown, qrPayment", actual: "\(PaymentChannel.detect(from: "Thank you")), \(PaymentChannel.detect(from: "DuitNow QR payment"))")
        }

