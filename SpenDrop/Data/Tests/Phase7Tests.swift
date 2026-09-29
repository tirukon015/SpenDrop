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

        // MARK: ClassificationRule
        do {
            let ctx = TestKit.context()
            let key = TransactionClassifier.merchantKey("  McDonald’s  ")
            let ignored = TransactionClassifier.merchantKey("Unknown")
            TransactionClassifier.learn(merchant: "McDonald's", category: .shopping, in: ctx)
            let once = TransactionClassifier.suggestCategory(merchant: "mcdonald's", deterministic: .food, in: ctx)
            TransactionClassifier.learn(merchant: "MCDONALD'S", category: .shopping, in: ctx)
            let twice = TransactionClassifier.suggestCategory(merchant: "McDonald's", deterministic: .food, in: ctx)
            TransactionClassifier.learn(merchant: "McDonald's", category: .food, in: ctx)      // correction
            let rule = TransactionClassifier.rule(for: "mcdonald's", in: ctx)
            try? ctx.save()
            t.check("Rules: key normalised; 1 confirmation not trusted; 2 trusted and beats parser; correction resets",
                    key == "mcdonald's" && ignored == nil && once.source == .deterministic && once.category == .food &&
                    twice.source == .learned && twice.category == .shopping && rule?.category == .food && rule?.hitCount == 1 &&
                    TestKit.count(ClassificationRule.self, in: ctx) == 1,
                    expected: "deterministic, then learned shopping, then food x1, one rule",
                    actual: "once=\(once.source)/\(once.category) twice=\(twice.source)/\(twice.category) rule=\(rule?.categoryRaw ?? "nil")x\(rule?.hitCount ?? 0)")
            let generic = TransactionClassifier.suggestCategory(merchant: "Shell Petrol", deterministic: nil, in: ctx)
            let unknown = TransactionClassifier.suggestCategory(merchant: "Zyx Qwv", deterministic: .other, in: ctx)
            t.check("Priority falls back to generic suggestion, then Unknown (Other)",
                    generic.source == .generic && generic.category == .transport && unknown.source == .unknown && unknown.category == .other,
                    expected: "generic transport, unknown other", actual: "\(generic.source)/\(generic.category), \(unknown.source)/\(unknown.category)")
        }

