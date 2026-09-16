import Foundation

public struct TestCaseResult: Identifiable {
    public let id = UUID()
    public let testName: String
    public let passed: Bool
    public let expected: String
    public let actual: String
    public let details: String
}

public struct TransactionParserTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let parser = TransactionParser.shared

        func makeOCRResult(text: String) -> OCRResult {
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            let textLines = lines.map { RecognizedTextLine(text: $0, confidence: 0.95) }
            return OCRResult(fullText: text, lines: textLines, averageConfidence: 0.95)
        }

        // Test 1: TNG Successful Payment
        let tngText = """
        Touch 'n Go eWallet
        Payment Successful
        RM18.50
        Paid to: McDonald's
        16 Sep 2026 9:42 PM
        Ref No: TNG992837194
        """
        let tngParsed = parser.parse(ocrResult: makeOCRResult(text: tngText))
        let tngPassed = tngParsed.amount == 18.50 &&
                        tngParsed.paymentSource == .touchNGo &&
                        tngParsed.merchant == "McDonald's" &&
                        tngParsed.category == .food &&
                        tngParsed.isCompletedTransaction
        results.append(TestCaseResult(
            testName: "TNG McDonald's Payment",
            passed: tngPassed,
            expected: "RM18.50, TNG, McDonald's, Food",
            actual: "RM\(tngParsed.amount ?? 0), \(tngParsed.paymentSource?.shortName ?? "nil"), \(tngParsed.merchant ?? "nil"), \(tngParsed.category?.rawValue ?? "nil")",
            details: "Tests Malaysian eWallet payment extraction"
        ))

        // Test 2: Maybank MYDIN Groceries
        let maybankText = """
        Maybank2u
        Transfer Successful
        Amount: RM42.90
        Recipient: MYDIN
        16/09/2026
        Reference: MBB20260916892
        """
        let mbbParsed = parser.parse(ocrResult: makeOCRResult(text: maybankText))
        let mbbPassed = mbbParsed.amount == 42.90 &&
                        mbbParsed.paymentSource == .maybank &&
                        mbbParsed.merchant == "MYDIN" &&
                        mbbParsed.category == .groceries
        results.append(TestCaseResult(
            testName: "Maybank MYDIN Transfer",
            passed: mbbPassed,
            expected: "RM42.90, Maybank, MYDIN, Groceries",
            actual: "RM\(mbbParsed.amount ?? 0), \(mbbParsed.paymentSource?.rawValue ?? "nil"), \(mbbParsed.merchant ?? "nil"), \(mbbParsed.category?.rawValue ?? "nil")",
            details: "Tests bank app transfer and grocery category matching"
        ))

        // Test 3: CIMB Shell Petrol
        let cimbText = """
        CIMB OCTO
        DuitNow Transfer Successful
        RM50.00
        Paid to: Shell
        """
        let cimbParsed = parser.parse(ocrResult: makeOCRResult(text: cimbText))
        let cimbPassed = cimbParsed.amount == 50.00 &&
                         cimbParsed.paymentSource == .cimb &&
                         cimbParsed.merchant == "Shell" &&
                         cimbParsed.category == .transport
        results.append(TestCaseResult(
            testName: "CIMB Shell Petrol",
            passed: cimbPassed,
            expected: "RM50.00, CIMB, Shell, Transport",
            actual: "RM\(cimbParsed.amount ?? 0), \(cimbParsed.paymentSource?.rawValue ?? "nil"), \(cimbParsed.merchant ?? "nil"), \(cimbParsed.category?.rawValue ?? "nil")",
            details: "Tests fuel merchant & transport category"
        ))

        // Test 4: Apple Pay Starbucks
        let appleText = """
        Apple Pay
        Paid RM25.90
        Starbucks
        16 Sep 2026
        """
        let appleParsed = parser.parse(ocrResult: makeOCRResult(text: appleText))
        let applePassed = appleParsed.amount == 25.90 &&
                          appleParsed.paymentSource == .applePay &&
                          appleParsed.merchant == "Starbucks"
        results.append(TestCaseResult(
            testName: "Apple Pay Starbucks",
            passed: applePassed,
            expected: "RM25.90, Apple Pay, Starbucks",
            actual: "RM\(appleParsed.amount ?? 0), \(appleParsed.paymentSource?.rawValue ?? "nil"), \(appleParsed.merchant ?? "nil")",
            details: "Tests Apple Pay notification pattern"
        ))

        // Test 5: Multiple Amounts (Receipt Total Priority)
        let receiptText = """
        KOPITIAM RESTORAN
        Tax Invoice
        Subtotal RM20.00
        SST 6% RM1.20
        Total RM21.20
        Cash
        """
        let receiptParsed = parser.parse(ocrResult: makeOCRResult(text: receiptText))
        let receiptPassed = receiptParsed.amount == 21.20
        results.append(TestCaseResult(
            testName: "Receipt Multiple Amounts (Total > Subtotal)",
            passed: receiptPassed,
            expected: "RM21.20 (Grand Total)",
            actual: "RM\(receiptParsed.amount ?? 0)",
            details: "Ensures parser selects Total RM21.20 instead of Subtotal RM20.00 or Tax RM1.20"
        ))

        // Test 6: False Positive Protection (Available Balance)
        let balanceText = """
        Maybank2u
        Welcome Back
        Available Balance
        RM1,250.00
        Account No: 114012345678
        """
        let balanceParsed = parser.parse(ocrResult: makeOCRResult(text: balanceText))
        let balancePassed = balanceParsed.isBalanceOrLimitOnly && balanceParsed.amount == nil
        results.append(TestCaseResult(
            testName: "False Positive: Account Balance",
            passed: balancePassed,
            expected: "Rejected (amount = nil, isBalanceOrLimitOnly = true)",
            actual: "isBalance=\(balanceParsed.isBalanceOrLimitOnly), amount=\(balanceParsed.amount != nil ? "RM\(balanceParsed.amount!)" : "nil")",
            details: "Prevents account balances from being recorded as expenses"
        ))

        // Test 7: False Positive Protection (Credit Limit)
        let limitText = """
        RHB Bank
        Credit Limit
        RM5,000.00
        Available Credit: RM4,500.00
        """
        let limitParsed = parser.parse(ocrResult: makeOCRResult(text: limitText))
        let limitPassed = limitParsed.isBalanceOrLimitOnly && limitParsed.amount == nil
        results.append(TestCaseResult(
            testName: "False Positive: Credit Limit",
            passed: limitPassed,
            expected: "Rejected (amount = nil, isBalanceOrLimitOnly = true)",
            actual: "isBalance=\(limitParsed.isBalanceOrLimitOnly), amount=\(limitParsed.amount != nil ? "RM\(limitParsed.amount!)" : "nil")",
            details: "Prevents card limits from becoming expenses"
        ))

        // Test 8: False Positive Protection (Reward Points)
        let pointsText = """
        Touch 'n Go eWallet
        My Rewards
        2,500 points
        Points expiring soon
        """
        let pointsParsed = parser.parse(ocrResult: makeOCRResult(text: pointsText))
        let pointsPassed = pointsParsed.isBalanceOrLimitOnly && pointsParsed.amount == nil
        results.append(TestCaseResult(
            testName: "False Positive: Reward Points",
            passed: pointsPassed,
            expected: "Rejected (amount = nil, isBalanceOrLimitOnly = true)",
            actual: "isBalance=\(pointsParsed.isBalanceOrLimitOnly), amount=\(pointsParsed.amount != nil ? "RM\(pointsParsed.amount!)" : "nil")",
            details: "Prevents reward points from becoming expenses"
        ))

        // Test 9: Failed Payment
        let failedText = """
        Touch 'n Go eWallet
        Payment Failed
        RM25.90
        Reason: Insufficient Balance
        """
        let failedParsed = parser.parse(ocrResult: makeOCRResult(text: failedText))
        let failedPassed = failedParsed.isFailedTransaction
        results.append(TestCaseResult(
            testName: "Failed Payment Detection",
            passed: failedPassed,
            expected: "isFailedTransaction = true",
            actual: "isFailedTransaction = \(failedParsed.isFailedTransaction)",
            details: "Flags failed transactions and warns user"
        ))

        // Test 10: QR Payment without explicit merchant
        let qrText = """
        DuitNow QR
        Payment Successful
        RM15.00
        Ref: 981273981
        """
        let qrParsed = parser.parse(ocrResult: makeOCRResult(text: qrText))
        let qrPassed = qrParsed.amount == 15.00 && qrParsed.paymentSource == .qrPayment && qrParsed.merchant == nil
        results.append(TestCaseResult(
            testName: "QR Payment with Unknown Merchant",
            passed: qrPassed,
            expected: "RM15.00, QR Payment, Unknown Merchant (nil)",
            actual: "RM\(qrParsed.amount ?? 0), \(qrParsed.paymentSource?.rawValue ?? "nil"), \(qrParsed.merchant ?? "nil")",
            details: "Allows user to edit merchant when not present in screenshot"
        ))

        // Test 11: Duplicate Detection (Matching existing expense)
        let schema = Schema([Expense.self])
        let memConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        if let memContainer = try? ModelContainer(for: schema, configurations: [memConfig]) {
            let testContext = memContainer.mainContext
            let existing = Expense(
                amount: 18.50,
                merchant: "McDonald's",
                category: .food,
                paymentSource: .touchNGo,
                date: Date(),
                transactionReference: "TNG12345"
            )
            testContext.insert(existing)
            try? testContext.save()

            let dupCheck = DuplicateDetector.shared.checkDuplicate(
                amount: 18.50,
                merchant: "McDonald's",
                date: Date(),
                reference: "TNG12345",
                in: testContext
            )

            results.append(TestCaseResult(
                testName: "Duplicate Detection (Identical Transaction)",
                passed: dupCheck.isDuplicate,
                expected: "isDuplicate = true",
                actual: "isDuplicate = \(dupCheck.isDuplicate)",
                details: "Warns user when sharing the exact same screenshot/transaction twice"
            ))

            // Test 12: Unique Transaction (Different amount/merchant)
            let uniqueCheck = DuplicateDetector.shared.checkDuplicate(
                amount: 99.00,
                merchant: "Uniqlo",
                date: Date(),
                reference: "UNIQLO999",
                in: testContext
            )

            results.append(TestCaseResult(
                testName: "Unique Transaction (Non-Duplicate)",
                passed: !uniqueCheck.isDuplicate,
                expected: "isDuplicate = false",
                actual: "isDuplicate = \(uniqueCheck.isDuplicate)",
                details: "Ensures legitimate different transactions are not blocked"
            ))
        }

        return results
    }
}
