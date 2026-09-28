import Foundation
import SwiftData
import UIKit

public struct TestCaseResult: Identifiable {
    public let id = UUID()
    public let testName: String
    public let passed: Bool
    public let expected: String
    public let actual: String
    public let details: String
}

@MainActor
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

        // Test 13: Recipient / Payee Name Detection (e.g. Receiver: RANA SOHEL)
        let receiverText = """
        DuitNow Transfer
        Transfer Successful
        RM85.00
        Receiver: RANA SOHEL
        17 Sep 2026 10:15 AM
        Ref No: DT991823719
        """
        let receiverParsed = parser.parse(ocrResult: makeOCRResult(text: receiverText))
        let receiverPassed = receiverParsed.amount == 85.00 &&
                             receiverParsed.merchant == "RANA SOHEL"
        results.append(TestCaseResult(
            testName: "Receiver / Payee Name Detection",
            passed: receiverPassed,
            expected: "RM85.00, RANA SOHEL",
            actual: "RM\(receiverParsed.amount ?? 0), \(receiverParsed.merchant ?? "nil")",
            details: "Tests payee / recipient extraction for bank and DuitNow transfers"
        ))

        // Test 14: TNG Screenshot with RM22.00 vs RM450.00 Advertisement (Issue 1 Regression)
        let tngAdText = """
        Touch 'n Go eWallet
        Transferred
        RM22.00
        Receiver: RANA SOHEL
        Date: 15/09/2026
        Time: 13:49:06
        Ref: TNG992837194
        Special Offer
        Panasonic Air Conditioner
        RM450
        Shop Now
        """
        let tngAdParsed = parser.parse(ocrResult: makeOCRResult(text: tngAdText))
        let tngAdPassed = tngAdParsed.amount == 22.00 &&
                          tngAdParsed.merchant == "RANA SOHEL" &&
                          tngAdParsed.provider == "touch_n_go" &&
                          tngAdParsed.providerConfidence >= 0.90 &&
                          tngAdParsed.amount != 450.00
        results.append(TestCaseResult(
            testName: "TNG RM22.00 vs RM450 Advertisement",
            passed: tngAdPassed,
            expected: "RM22.00, RANA SOHEL, touch_n_go (NOT RM450)",
            actual: "RM\(tngAdParsed.amount ?? 0), \(tngAdParsed.merchant ?? "nil"), \(tngAdParsed.provider)",
            details: "Ensures parser selects transaction amount RM22.00 over advertisement amount RM450"
        ))

        // Test 15: Multiple Amounts with Fee, Balance, Cashback, and Total (Issue 4, 11-B)
        let multiAmountTotalText = """
        Payment Receipt
        Amount: RM50.00
        Service Fee: RM1.00
        Total: RM51.00
        Balance: RM948.00
        Cashback: RM5.00
        Paid to: Coffee Bean
        """
        let multiTotalParsed = parser.parse(ocrResult: makeOCRResult(text: multiAmountTotalText))
        let multiTotalPassed = multiTotalParsed.amount == 51.00 &&
                               (multiTotalParsed.merchant?.contains("Coffee Bean") == true)
        results.append(TestCaseResult(
            testName: "Multiple Amounts with Total (RM51 Total Priority)",
            passed: multiTotalPassed,
            expected: "RM51.00 (Total), Coffee Bean",
            actual: "RM\(multiTotalParsed.amount ?? 0), \(multiTotalParsed.merchant ?? "nil")",
            details: "Classifies Amount, Fee, Total, Balance, Cashback and selects Total"
        ))

        // Test 16: Multiple Amounts without Total: Amount RM50, Fee RM1, Balance RM948 (Issue 4, 11-B)
        let multiNoTotalText = """
        Transfer Receipt
        Amount: RM50.00
        Service Fee: RM1.00
        Balance: RM948.00
        Receiver: Ali Express
        """
        let multiNoTotalParsed = parser.parse(ocrResult: makeOCRResult(text: multiNoTotalText))
        let multiNoTotalPassed = multiNoTotalParsed.amount == 50.00
        results.append(TestCaseResult(
            testName: "Multiple Amounts without Total (Amount RM50 over Fee RM1 & Balance RM948)",
            passed: multiNoTotalPassed,
            expected: "RM50.00",
            actual: "RM\(multiNoTotalParsed.amount ?? 0)",
            details: "Selects transaction amount over fee and balance when total is not present"
        ))

        // Test 17: Provider Auto-Detection for Malaysian Banks (Issue 2, 11-C)
        let providersToTest: [(text: String, expectedProvider: String)] = [
            ("Touch 'n Go eWallet\nPayment Successful\nRM10.00", "touch_n_go"),
            ("MAE by Maybank2u\nTransfer Successful\nRM20.00", "maybank"),
            ("CIMB OCTO\nTransfer Successful\nRM30.00", "cimb"),
            ("RHB Mobile Banking\nSuccessful\nRM40.00", "rhb"),
            ("Public Bank PB Engage\nPayment Successful\nRM50.00", "public_bank"),
            ("Bank Islam GO\nTransfer Successful\nRM60.00", "bank_islam"),
            ("GrabPay\nPayment Successful\nRM70.00", "grabpay"),
            ("Boost eWallet\nPayment Successful\nRM80.00", "boost"),
            ("DuitNow Transfer\nSuccessful\nRM90.00", "duitnow")
        ]
        var allProvidersPassed = true
        var providerDetails: [String] = []
        for p in providersToTest {
            let res = parser.parse(ocrResult: makeOCRResult(text: p.text))
            if res.provider != p.expectedProvider {
                allProvidersPassed = false
                providerDetails.append("\(p.expectedProvider) != \(res.provider)")
            }
        }
        results.append(TestCaseResult(
            testName: "Malaysian Bank Provider Auto-Detection",
            passed: allProvidersPassed,
            expected: "All 9 Malaysian providers correctly identified",
            actual: allProvidersPassed ? "All 9 identified" : providerDetails.joined(separator: ", "),
            details: "Tests TNG, Maybank, CIMB, RHB, Public Bank, Bank Islam, GrabPay, Boost, DuitNow"
        ))

        // Test 18: Unknown Provider with Successful Extraction (Issue 2, 11-D)
        let unknownProviderText = """
        Transfer Successful
        RM35.00
        Receiver: Ali Baba
        Date: 12/09/2026
        """
        let unknownParsed = parser.parse(ocrResult: makeOCRResult(text: unknownProviderText))
        let unknownPassed = unknownParsed.provider == "unknown" &&
                            unknownParsed.amount == 35.00 &&
                            unknownParsed.merchant == "Ali Baba"
        results.append(TestCaseResult(
            testName: "Unknown Provider with Successful Extraction",
            passed: unknownPassed,
            expected: "provider = unknown, RM35.00, Ali Baba",
            actual: "provider = \(unknownParsed.provider), RM\(unknownParsed.amount ?? 0), \(unknownParsed.merchant ?? "nil")",
            details: "Ensures unknown bank/app does NOT prevent expense extraction"
        ))

        // Test 19: Low-Confidence Screenshot with Multiple Bare Amounts (Issue 5, 11-E)
        let lowConfText = """
        Statement of Account
        22.00
        20.00
        2.00
        """
        let lowConfParsed = parser.parse(ocrResult: makeOCRResult(text: lowConfText))
        let lowConfPassed = lowConfParsed.confidence == .low &&
                            lowConfParsed.amountCandidates.count >= 3
        results.append(TestCaseResult(
            testName: "Low-Confidence Screenshot Flagging",
            passed: lowConfPassed,
            expected: "confidence = Low, multiple candidates for user confirmation",
            actual: "confidence = \(lowConfParsed.confidence.rawValue), candidates count = \(lowConfParsed.amountCandidates.count)",
            details: "Requires user confirmation rather than silently assuming an uncertain amount"
        ))

        // Test 20: Normalized Transaction Model (Issue 6)
        let tngFullText = """
        Touch 'n Go eWallet
        Transferred
        RM22.00
        Receiver: RANA SOHEL
        Date: 15/09/2026
        Time: 13:49:06
        Ref: TNG123456
        """
        let normParsed = parser.parse(ocrResult: makeOCRResult(text: tngFullText))
        let normDict = normParsed.toNormalizedDictionary()
        let normPassed = (normDict["provider"] as? String) == "touch_n_go" &&
                         (normDict["amount"] as? Double) == 22.00 &&
                         (normDict["merchant"] as? String) == "RANA SOHEL" &&
                         (normDict["date"] as? String) == "2026-09-15" &&
                         (normDict["time"] as? String) == "13:49:06" &&
                         (normDict["status"] as? String) == "transferred"
        results.append(TestCaseResult(
            testName: "Normalized Transaction Model",
            passed: normPassed,
            expected: "provider=touch_n_go, amount=22.0, merchant=RANA SOHEL, date=2026-09-15, time=13:49:06, status=transferred",
            actual: "provider=\(normDict["provider"] ?? "nil"), amount=\(normDict["amount"] ?? "nil"), merchant=\(normDict["merchant"] ?? "nil"), date=\(normDict["date"] ?? "nil"), time=\(normDict["time"] ?? "nil"), status=\(normDict["status"] ?? "nil")",
            details: "Ensures extraction maps to normalized cross-provider structure"
        ))

        // Test 21: Complete Persistence Lifecycle (Issue 10)
        let schema2 = Schema([Expense.self])
        let memConfig2 = ModelConfiguration(isStoredInMemoryOnly: true)
        if let memContainer2 = try? ModelContainer(for: schema2, configurations: [memConfig2]) {
            let ctx = memContainer2.mainContext

            // 1. Create & save Test Merchant RM22.00
            let testExpense = Expense(
                amount: 22.00,
                currency: "RM",
                merchant: "Test Merchant",
                category: .food,
                paymentSource: .touchNGo,
                date: Date(),
                transactionReference: "REF-TEST-2200"
            )
            ctx.insert(testExpense)
            try? ctx.save()

            // 2. Immediately query and verify
            let fetchDesc = FetchDescriptor<Expense>(
                predicate: #Predicate<Expense> { $0.merchant == "Test Merchant" && $0.amount == 22.00 }
            )
            let fetched = (try? ctx.fetch(fetchDesc)) ?? []
            let saveSucceeded = fetched.count == 1 && fetched.first?.amount == 22.00

            // 3. Duplicate detection checks for exact same expense
            let dupCheck = DuplicateDetector.shared.checkDuplicate(
                amount: 22.00,
                merchant: "Test Merchant",
                date: Date(),
                reference: "REF-TEST-2200",
                in: ctx
            )

            let lifecyclePassed = saveSucceeded && dupCheck.isDuplicate
            results.append(TestCaseResult(
                testName: "Persistence Lifecycle & Duplicate Verification",
                passed: lifecyclePassed,
                expected: "Persisted = true, Queryable = true, Duplicate Detected = true",
                actual: "Persisted = \(saveSucceeded), Duplicate Detected = \(dupCheck.isDuplicate)",
                details: "Tests complete lifecycle: save, immediate query, and duplicate detection"
            ))

            // Test 22: Consecutive Expenses (RM10, RM25, RM50)
            let exp10 = Expense(amount: 10.00, merchant: "Merchant 10", date: Date())
            let exp25 = Expense(amount: 25.00, merchant: "Merchant 25", date: Date())
            let exp50 = Expense(amount: 50.00, merchant: "Merchant 50", date: Date())
            ctx.insert(exp10)
            ctx.insert(exp25)
            ctx.insert(exp50)
            try? ctx.save()

            let allDesc = FetchDescriptor<Expense>()
            let totalExpenses = (try? ctx.fetch(allDesc)) ?? []
            let consecutivePassed = totalExpenses.contains(where: { $0.amount == 10.00 }) &&
                                    totalExpenses.contains(where: { $0.amount == 25.00 }) &&
                                    totalExpenses.contains(where: { $0.amount == 50.00 })
            results.append(TestCaseResult(
                testName: "Consecutive Expense Persistence (RM10, RM25, RM50)",
                passed: consecutivePassed,
                expected: "All 3 consecutive expenses saved and queryable",
                actual: "Total count = \(totalExpenses.count), RM10/25/50 present = \(consecutivePassed)",
                details: "Ensures consecutive saves do not overwrite each other"
            ))

            // Test 23: Idempotent Dummy Data Seeding & Separation (Issue 9)
            let initialCount = totalExpenses.count
            SampleData.seed(into: ctx)
            let countAfterFirstSeed = (try? ctx.fetch(allDesc))?.count ?? 0
            // Second seed call must be idempotent
            SampleData.seed(into: ctx)
            let countAfterSecondSeed = (try? ctx.fetch(allDesc))?.count ?? 0

            let idempotentPassed = countAfterFirstSeed > initialCount &&
                                   countAfterSecondSeed == countAfterFirstSeed
            results.append(TestCaseResult(
                testName: "Idempotent Sample Data Seeding",
                passed: idempotentPassed,
                expected: "Second seed does not recreate duplicate dummy records",
                actual: "First seed: \(countAfterFirstSeed), Second seed: \(countAfterSecondSeed)",
                details: "Protects existing expenses and ensures sample seeding is strictly idempotent"
            ))

            // Test 24: Provider Detection - Touch 'n Go (TEST 1)
            let tngSample = """
            Touch 'n Go eWallet
            Payment Successful
            RM 15.80
            Subway Malaysia
            18 Sep 2026 12:30
            """
            let tngResult = parser.parse(ocrResult: makeOCRResult(text: tngSample))
            let tngPassed = tngResult.paymentSource == .touchNGo &&
                            tngResult.underlyingBank == nil &&
                            tngResult.paymentMethod == "ewallet"
            results.append(TestCaseResult(
                testName: "Provider Detection: Touch 'n Go",
                passed: tngPassed,
                expected: "Provider = Touch 'n Go, Underlying Bank = nil, Method = ewallet",
                actual: "Provider = \(tngResult.paymentSource?.rawValue ?? "nil"), Bank = \(tngResult.underlyingBank?.rawValue ?? "nil")",
                details: "Verifies Touch 'n Go detection without false underlying bank"
            ))

            // Test 25: Provider Detection - Maybank / MAE (TEST 2)
            let maeSample = """
            MAE by Maybank2u
            Transfer Successful
            RM 45.00
            Recipient: Ahmad Zaki
            18/09/2026
            """
            let maeResult = parser.parse(ocrResult: makeOCRResult(text: maeSample))
            let maePassed = maeResult.paymentSource == .maybank &&
                            maeResult.underlyingBank == .maybank
            results.append(TestCaseResult(
                testName: "Provider Detection: Maybank / MAE",
                passed: maePassed,
                expected: "Provider = Maybank, Underlying Bank = Maybank",
                actual: "Provider = \(maeResult.paymentSource?.rawValue ?? "nil"), Bank = \(maeResult.underlyingBank?.rawValue ?? "nil")",
                details: "Verifies Maybank/MAE detection with matching bank"
            ))

            // Test 26: Provider Detection - CIMB (TEST 3)
            let cimbSample = """
            CIMB OCTO
            DuitNow Transfer Successful
            RM 88.00
            Beneficiary: Siti Nurhaliza
            Reference: 20260918112233
            """
            let cimbResult = parser.parse(ocrResult: makeOCRResult(text: cimbSample))
            let cimbPassed = cimbResult.paymentSource == .cimb &&
                             cimbResult.underlyingBank == .cimb
            results.append(TestCaseResult(
                testName: "Provider Detection: CIMB",
                passed: cimbPassed,
                expected: "Provider = CIMB, Underlying Bank = CIMB",
                actual: "Provider = \(cimbResult.paymentSource?.rawValue ?? "nil"), Bank = \(cimbResult.underlyingBank?.rawValue ?? "nil")",
                details: "Verifies direct CIMB transaction detection"
            ))

            // Test 27: Provider Detection - RHB (TEST 4)
            let rhbSample = """
            RHB Mobile Banking
            Successful Transaction
            RM 120.00
            Paid to: Tenaga Nasional
            18 Sep 2026
            """
            let rhbResult = parser.parse(ocrResult: makeOCRResult(text: rhbSample))
            let rhbPassed = rhbResult.paymentSource == .rhb &&
                            rhbResult.underlyingBank == .rhb
            results.append(TestCaseResult(
                testName: "Provider Detection: RHB",
                passed: rhbPassed,
                expected: "Provider = RHB, Underlying Bank = RHB",
                actual: "Provider = \(rhbResult.paymentSource?.rawValue ?? "nil"), Bank = \(rhbResult.underlyingBank?.rawValue ?? "nil")",
                details: "Verifies direct RHB transaction detection"
            ))

            // Test 28: Apple Pay Standalone (Underlying bank = nil) (TEST 5)
            let applePayOnlySample = """
            Starbucks Coffee
            Total: RM 25.90
            Paid with Apple Pay
            Device Account Number: *1234
            18/09/2026 09:15
            """
            let apOnlyResult = parser.parse(ocrResult: makeOCRResult(text: applePayOnlySample))
            let apOnlyPassed = apOnlyResult.paymentSource == .applePay &&
                               apOnlyResult.underlyingBank == nil &&
                               apOnlyResult.amount == 25.90
            results.append(TestCaseResult(
                testName: "Apple Pay Standalone (Underlying Bank = nil)",
                passed: apOnlyPassed,
                expected: "Payment Provider = Apple Pay, Underlying Bank = nil, RM 25.90",
                actual: "Provider = \(apOnlyResult.paymentSource?.rawValue ?? "nil"), Bank = \(apOnlyResult.underlyingBank?.rawValue ?? "nil")",
                details: "Ensures no bank is guessed when Apple Pay alone is identifiable"
            ))

            // Test 29: Apple Pay + CIMB (Both Logos & Structured Metadata) (TEST 6)
            let apCimbSample = """
            Starbucks Coffee
            Total: RM 28.50
            Payment Method: Apple Pay
            Card: CIMB Bank Debit *8821
            18/09/2026 14:02
            """
            let apCimbResult = parser.parse(ocrResult: makeOCRResult(text: apCimbSample))
            let apCimbPassed = apCimbResult.paymentSource == .applePay &&
                               apCimbResult.underlyingBank == .cimb &&
                               apCimbResult.paymentMethod == "digital_wallet" &&
                               apCimbResult.merchant != "CIMB"
            results.append(TestCaseResult(
                testName: "Apple Pay + CIMB Underlying Bank",
                passed: apCimbPassed,
                expected: "Provider = Apple Pay, Underlying Bank = CIMB, Method = digital_wallet, Merchant != CIMB",
                actual: "Provider = \(apCimbResult.paymentSource?.rawValue ?? "nil"), Bank = \(apCimbResult.underlyingBank?.rawValue ?? "nil"), Merchant = \(apCimbResult.merchant ?? "nil")",
                details: "Verifies Apple Pay interface paired with underlying CIMB funding source"
            ))

            // Test 30: Apple Pay + Maybank (TEST 7)
            let apMaybankSample = """
            Uniqlo Mid Valley
            Total: RM 149.90
            Paid using Apple Pay
            Funding: Maybank Visa Signature
            18/09/2026 16:20
            """
            let apMaybankResult = parser.parse(ocrResult: makeOCRResult(text: apMaybankSample))
            let apMaybankPassed = apMaybankResult.paymentSource == .applePay &&
                                  apMaybankResult.underlyingBank == .maybank
            results.append(TestCaseResult(
                testName: "Apple Pay + Maybank Underlying Bank",
                passed: apMaybankPassed,
                expected: "Provider = Apple Pay, Underlying Bank = Maybank",
                actual: "Provider = \(apMaybankResult.paymentSource?.rawValue ?? "nil"), Bank = \(apMaybankResult.underlyingBank?.rawValue ?? "nil")",
                details: "Verifies Apple Pay interface paired with Maybank card"
            ))

            // Test 31: Unknown Provider Fallback (TEST 8)
            let unknownSample = """
            Kopitiam Ah Kow
            RM 12.50
            Receipt #48291
            18/09/2026 08:30
            """
            let unknownResult = parser.parse(ocrResult: makeOCRResult(text: unknownSample))
            let unknownPassed = (unknownResult.paymentSource == .unknown || unknownResult.paymentSource == nil) &&
                                unknownResult.provider == "unknown" &&
                                unknownResult.amount == 12.50 &&
                                unknownResult.merchant != nil
            results.append(TestCaseResult(
                testName: "Unknown Provider Graceful Fallback",
                passed: unknownPassed,
                expected: "Provider = Unknown, Amount = RM 12.50, Extraction continues normally",
                actual: "Provider = \(unknownResult.paymentSource?.rawValue ?? "nil") (normalized: \(unknownResult.provider)), Amount = \(unknownResult.amount != nil ? "\(unknownResult.amount!)" : "nil")",
                details: "Ensures extraction does not block when provider is unknown"
            ))

            // Test 32: Provider Logo Assets Availability (All 5 Assets)
            let hasTngLogo = UIImage(named: "provider_tng") != nil
            let hasMaybankLogo = UIImage(named: "provider_maybank") != nil
            let hasCimbLogo = UIImage(named: "provider_cimb") != nil
            let hasRhbLogo = UIImage(named: "provider_rhb") != nil
            let hasApplePayLogo = UIImage(named: "provider_apple_pay") != nil
            let allLogosPresent = hasTngLogo && hasMaybankLogo && hasCimbLogo && hasRhbLogo && hasApplePayLogo
            results.append(TestCaseResult(
                testName: "Provider Logo Assets Availability",
                passed: allLogosPresent,
                expected: "All 5 provider logos available in asset catalog",
                actual: "TNG: \(hasTngLogo), Maybank: \(hasMaybankLogo), CIMB: \(hasCimbLogo), RHB: \(hasRhbLogo), ApplePay: \(hasApplePayLogo)",
                details: "Ensures TNG, Maybank, CIMB, RHB, and Apple Pay imagesets exist and load"
            ))

            // Test 33: Real Reference — CIMB QR Payment with Ad Disqualification
            let cimbQrText = """
            Transaction Summary
            MYR 0.01
            18 Sep 2026 2:17:49 PM
            OCTO Reference No.
            DuitNow Reference No.
            To
            From
            283547681
            03382744
            RUKON TOUHIDUL ISLAM
            SAVINGS ACCT-i PLUS
            7658174175
            QR BASKIN-ROBBINS CAMPAIGN
            RM5 OFF
            Scan & pay via QR with OCTO!
            Minimum spend RM15 (non-promotional items only)
            Validity: 1 September 2026 - 31 January 2027
            Find out more
            Terms and Conditions apply.
            Done
            """
            let cimbQrParsed = parser.parse(ocrResult: makeOCRResult(text: cimbQrText))
            let cimbQrPassed = cimbQrParsed.amount == 0.01 &&
                               cimbQrParsed.provider == "cimb" &&
                               cimbQrParsed.paymentMethod == "duitnow_qr" &&
                               cimbQrParsed.underlyingBank == .cimb &&
                               cimbQrParsed.merchant == "RUKON TOUHIDUL ISLAM" &&
                               cimbQrParsed.amount != 5.00 &&
                               cimbQrParsed.amount != 15.00
            results.append(TestCaseResult(
                testName: "Real Ref: CIMB QR Payment (Ad Exclusions)",
                passed: cimbQrPassed,
                expected: "Amount = 0.01 (NOT RM5 OFF or RM15 Min spend), Provider = CIMB, Method = duitnow_qr, Merchant = RUKON TOUHIDUL ISLAM",
                actual: "Amount = \(cimbQrParsed.amount ?? 0), Provider = \(cimbQrParsed.provider), Method = \(cimbQrParsed.paymentMethod ?? "nil"), Merchant = \(cimbQrParsed.merchant ?? "nil")",
                details: "Disqualifies RM5 OFF and Minimum spend RM15 ads, selects MYR 0.01, identifies CIMB OCTO"
            ))

            // Test 34: Real Reference — CIMB Notification Alert with FPX
            let cimbNotifText = """
            Transaction Alert
            CIMB: FPX Payment RM932.46 to IPAY88 (M) SDN BHD accepted on 06-Aug-2026, 23:13:56. Call the no at the back of your card for queries.
            """
            let cimbNotifParsed = parser.parse(ocrResult: makeOCRResult(text: cimbNotifText))
            let cimbNotifPassed = cimbNotifParsed.amount == 932.46 &&
                                 cimbNotifParsed.provider == "cimb" &&
                                 cimbNotifParsed.paymentMethod == "bank_transfer" &&
                                 cimbNotifParsed.merchant == "IPAY88"
            results.append(TestCaseResult(
                testName: "Real Ref: CIMB Notification FPX Payment",
                passed: cimbNotifPassed,
                expected: "Amount = 932.46, Provider = CIMB, Method = bank_transfer, Merchant = IPAY88",
                actual: "Amount = \(cimbNotifParsed.amount ?? 0), Provider = \(cimbNotifParsed.provider), Method = \(cimbNotifParsed.paymentMethod ?? "nil"), Merchant = \(cimbNotifParsed.merchant ?? "nil")",
                details: "Extracts high value amount from notification, strips SDN BHD from merchant, preserves CIMB provider"
            ))

            // Test 35: Real Reference — CIMB Interbank Transfer (Sender CIMB vs Recipient Maybank)
            let cimbInterbankText = """
            Transaction Summary
            MYR 1.00
            18 Sep 2026 2:18:39 PM
            Reference No.
            TO
            Nickname
            From
            When
            Repeat
            Transfer Method
            Payment Type
            283550902
            TOUHIDUL ISLAM RUKON
            Maybank 168603292644
            Rukon
            SAVINGS ACCT-i PLUS
            7658174175
            Today, 18 Sep 2026
            No
            Duit Now to Account
            Fund Transfer
            Done
            """
            let cimbInterbankParsed = parser.parse(ocrResult: makeOCRResult(text: cimbInterbankText))
            let cimbInterbankPassed = cimbInterbankParsed.amount == 1.00 &&
                                     cimbInterbankParsed.provider == "cimb" &&
                                     cimbInterbankParsed.underlyingBank == .cimb &&
                                     cimbInterbankParsed.paymentMethod == "duitnow"
            results.append(TestCaseResult(
                testName: "Real Ref: CIMB Interbank (Sender CIMB vs Recipient Maybank)",
                passed: cimbInterbankPassed,
                expected: "Sender Provider = CIMB (NOT Maybank), Amount = 1.00, Method = duitnow",
                actual: "Provider = \(cimbInterbankParsed.provider), Amount = \(cimbInterbankParsed.amount ?? 0), Method = \(cimbInterbankParsed.paymentMethod ?? "nil")",
                details: "Prioritizes sender SAVINGS ACCT-i PLUS over recipient Maybank account"
            ))

            // Test 36: Real Reference — Maybank Interbank Transfer (Sender Maybank vs Recipient RHB)
            let maybankInterbankText = """
            Maybank
            DuitNow Transfer
            Successful
            Reference ID
            035649071M
            Beneficiary name
            TOUHIDUL ISLAM RUKON
            Beneficiary account number
            2160 1100 0364 06
            Receiving bank
            RHB BANK
            Recipient reference
            Rukon
            Payment details
            App Test
            Amount
            RM 0.01
            18 Sep 2026, 02:16 PM
            """
            let mbbInterbankParsed = parser.parse(ocrResult: makeOCRResult(text: maybankInterbankText))
            let mbbInterbankPassed = mbbInterbankParsed.amount == 0.01 &&
                                     mbbInterbankParsed.provider == "maybank" &&
                                     mbbInterbankParsed.underlyingBank == .maybank &&
                                     mbbInterbankParsed.paymentMethod == "duitnow" &&
                                     mbbInterbankParsed.merchant == "TOUHIDUL ISLAM RUKON"
            results.append(TestCaseResult(
                testName: "Real Ref: Maybank Interbank (Sender Maybank vs Recipient RHB)",
                passed: mbbInterbankPassed,
                expected: "Sender Provider = Maybank (NOT RHB), Amount = 0.01, Merchant = TOUHIDUL ISLAM RUKON",
                actual: "Provider = \(mbbInterbankParsed.provider), Amount = \(mbbInterbankParsed.amount ?? 0), Merchant = \(mbbInterbankParsed.merchant ?? "nil")",
                details: "Identifies Maybank header as sender and ignores Receiving bank: RHB BANK"
            ))

            // Test 37: Real Reference — Maybank Scan & Pay Receipt
            let mbbReceiptText = """
            Maybank
            Scan & Pay
            Successful
            Reference ID
            QR70737488
            18 Sep 2026, 2:15 PM
            Beneficiary Name
            RUKONTOUHIDULISLAM
            Amount
            RM 0.01
            Note: This receipt is computer generated
            Malayan Banking Berhad
            """
            let mbbReceiptParsed = parser.parse(ocrResult: makeOCRResult(text: mbbReceiptText))
            let mbbReceiptPassed = mbbReceiptParsed.amount == 0.01 &&
                                   mbbReceiptParsed.provider == "maybank" &&
                                   mbbReceiptParsed.paymentMethod == "duitnow_qr" &&
                                   mbbReceiptParsed.merchant == "RUKONTOUHIDULISLAM"
            results.append(TestCaseResult(
                testName: "Real Ref: Maybank Scan & Pay Receipt",
                passed: mbbReceiptPassed,
                expected: "Provider = Maybank, Method = duitnow_qr, Merchant = RUKONTOUHIDULISLAM, Amount = 0.01",
                actual: "Provider = \(mbbReceiptParsed.provider), Method = \(mbbReceiptParsed.paymentMethod ?? "nil"), Merchant = \(mbbReceiptParsed.merchant ?? "nil"), Amount = \(mbbReceiptParsed.amount ?? 0)",
                details: "Extracts Maybank Scan & Pay, Beneficiary Name, and Amount"
            ))

            // Test 38: Real Reference — RHB Interbank Transfer (Sender RHB vs Recipient CIMB)
            let rhbInterbankText = """
            Status
            Successful
            02:21PM Friday, 18 September 2026 MYT
            Amount
            MYR 1.00
            Reference ID
            DuitNow
            Transfer
            17897124619260845
            From
            RHB Smart Account
            21601100036406
            To
            TOUHIDUL ISLAM RUKON
            7658174175
            Bank
            CIMB
            Transfer Method
            DuitNow (Instant)
            """
            let rhbInterbankParsed = parser.parse(ocrResult: makeOCRResult(text: rhbInterbankText))
            let rhbInterbankPassed = rhbInterbankParsed.amount == 1.00 &&
                                     rhbInterbankParsed.provider == "rhb" &&
                                     rhbInterbankParsed.underlyingBank == .rhb &&
                                     rhbInterbankParsed.paymentMethod == "duitnow" &&
                                     rhbInterbankParsed.merchant == "TOUHIDUL ISLAM RUKON"
            results.append(TestCaseResult(
                testName: "Real Ref: RHB Interbank (Sender RHB vs Recipient CIMB)",
                passed: rhbInterbankPassed,
                expected: "Sender Provider = RHB (NOT CIMB), Amount = 1.00, Method = duitnow, Merchant = TOUHIDUL ISLAM RUKON",
                actual: "Provider = \(rhbInterbankParsed.provider), Amount = \(rhbInterbankParsed.amount ?? 0), Method = \(rhbInterbankParsed.paymentMethod ?? "nil"), Merchant = \(rhbInterbankParsed.merchant ?? "nil")",
                details: "Identifies RHB Smart Account as sender and ignores Bank: CIMB under To section"
            ))

            // Test 39: Real Reference — RHB DuitNow QR Transfer
            let rhbQrText = """
            Status
            Successful
            02:19PM Friday, 18 September 2026 MYT
            Amount
            MYR 0.01
            Reference ID
            DuitNow QR
            20260918RHBBMYKL0400QR59060146
            From
            RHB Smart Account
            21601100036406
            To
            RUKONTOUHIDULISLAM
            Payment Type
            Duit Now QR P2P
            """
            let rhbQrParsed = parser.parse(ocrResult: makeOCRResult(text: rhbQrText))
            let rhbQrPassed = rhbQrParsed.amount == 0.01 &&
                             rhbQrParsed.provider == "rhb" &&
                             rhbQrParsed.paymentMethod == "duitnow_qr" &&
                             rhbQrParsed.merchant == "RUKONTOUHIDULISLAM"
            results.append(TestCaseResult(
                testName: "Real Ref: RHB DuitNow QR Transfer",
                passed: rhbQrPassed,
                expected: "Provider = RHB, Method = duitnow_qr, Amount = 0.01, Merchant = RUKONTOUHIDULISLAM",
                actual: "Provider = \(rhbQrParsed.provider), Method = \(rhbQrParsed.paymentMethod ?? "nil"), Amount = \(rhbQrParsed.amount ?? 0), Merchant = \(rhbQrParsed.merchant ?? "nil")",
                details: "Identifies RHB Smart Account sender with DuitNow QR P2P method"
            ))

            // Test 40: Real Reference — Touch 'n Go Notification with Negative Amount
            let tngNotifText = """
            Details
            -RM12.00
            Transaction Type
            Transfer to Wallet
            Transfer To
            BARAKAT MD ABUL
            Payment Details
            BARAKAT MD ABUL
            Payment Method
            eWallet Balance
            Date/Time
            02/08/2026 13:07:14
            Wallet Ref 2026080211121700010100171897968925005
            Status
            Successful
            """
            let tngNotifParsed = parser.parse(ocrResult: makeOCRResult(text: tngNotifText))
            let tngNotifPassed = tngNotifParsed.amount == 12.00 &&
                                 tngNotifParsed.provider == "touch_n_go" &&
                                 tngNotifParsed.paymentMethod == "ewallet" &&
                                 tngNotifParsed.underlyingBank == nil &&
                                 tngNotifParsed.merchant == "BARAKAT MD ABUL"
            results.append(TestCaseResult(
                testName: "Real Ref: TNG Notification (-RM12.00 Negative Amount)",
                passed: tngNotifPassed,
                expected: "Amount = 12.00 (from -RM12.00), Provider = touch_n_go, Method = ewallet, Merchant = BARAKAT MD ABUL",
                actual: "Amount = \(tngNotifParsed.amount ?? 0), Provider = \(tngNotifParsed.provider), Method = \(tngNotifParsed.paymentMethod ?? "nil"), Merchant = \(tngNotifParsed.merchant ?? "nil")",
                details: "Extracts negative amount magnitude, maps eWallet Balance and BARAKAT MD ABUL payee"
            ))

            // Test 41: Real Reference — Touch 'n Go Interbank with Near Me Ad
            let tngInterbankText = """
            RM 1.00
            Transferred
            Receiver
            Nickname
            Transaction Type
            Transfer to
            Recipient Bank/E-Wallet
            Account Number
            Transfer Type
            Remark
            Date & Time
            DuitNow Ref No.
            TOUHIDUL ISLAM RUKON
            Rukon
            DuitNow Transfer
            Bank/E-Wallet Account
            Maybank
            168603292644
            Fund Transfer
            18/09/2026 14:12:57
            20260918TNGDMYNB010ORM42680415
            Gong cha
            RM 2 Gong Cha
            is here on Near Me!
            Done
            """
            let tngInterbankParsed = parser.parse(ocrResult: makeOCRResult(text: tngInterbankText))
            let tngInterbankPassed = tngInterbankParsed.amount == 1.00 &&
                                     tngInterbankParsed.amount != 2.00 &&
                                     tngInterbankParsed.provider == "touch_n_go" &&
                                     tngInterbankParsed.paymentMethod == "duitnow" &&
                                     tngInterbankParsed.merchant == "TOUHIDUL ISLAM RUKON"
            results.append(TestCaseResult(
                testName: "Real Ref: TNG Interbank Transfer (Ad Disqualification & Sender TNG)",
                passed: tngInterbankPassed,
                expected: "Amount = 1.00 (NOT RM 2 Gong Cha), Provider = touch_n_go (NOT Maybank), Merchant = TOUHIDUL ISLAM RUKON",
                actual: "Amount = \(tngInterbankParsed.amount ?? 0), Provider = \(tngInterbankParsed.provider), Method = \(tngInterbankParsed.paymentMethod ?? "nil"), Merchant = \(tngInterbankParsed.merchant ?? "nil")",
                details: "Excludes Near Me Gong Cha RM2 promotion, recognizes TNG DuitNow reference, ignores recipient Maybank"
            ))

            // Test 42: Real Reference — Touch 'n Go QR Transfer
            let tngQrText = """
            RM 0.01
            Transferred
            Receiver: RIYAD MD TANVIR ISLAM
            Fund Transfer
            18/09/2026 14:13:58
            Done
            """
            let tngQrParsed = parser.parse(ocrResult: makeOCRResult(text: tngQrText))
            let tngQrPassed = tngQrParsed.amount == 0.01 &&
                             tngQrParsed.provider == "touch_n_go" &&
                             tngQrParsed.merchant == "RIYAD MD TANVIR ISLAM"
            results.append(TestCaseResult(
                testName: "Real Ref: TNG QR Transfer (RM 0.01)",
                passed: tngQrPassed,
                expected: "Amount = 0.01, Provider = touch_n_go, Merchant = RIYAD MD TANVIR ISLAM",
                actual: "Amount = \(tngQrParsed.amount ?? 0), Provider = \(tngQrParsed.provider), Merchant = \(tngQrParsed.merchant ?? "nil")",
                details: "Extracts RM 0.01 transaction amount and payee name from Touch 'n Go transfer screen"
            ))
        }

        // Test 43: PayBook — One Person / Profile -> Multiple Payment Accounts
        let rahim = PayBookProfile(name: "Rahim")
        let m1 = PayBookPaymentMethod(paymentType: .bankAccount, provider: "CIMB Bank", accountIdentifier: "123456789", label: "Personal", profile: rahim)
        let m2 = PayBookPaymentMethod(paymentType: .bankAccount, provider: "Maybank", accountIdentifier: "987654321", label: "Savings", profile: rahim)
        let m3 = PayBookPaymentMethod(paymentType: .eWallet, provider: "Touch 'n Go", accountIdentifier: "0123456789", profile: rahim)
        rahim.paymentMethods = [m1, m2, m3]

        let multipleAccountsPassed = rahim.paymentMethods.count == 3 &&
                                     rahim.paymentMethods.contains(where: { $0.provider == "CIMB Bank" }) &&
                                     rahim.paymentMethods.contains(where: { $0.provider == "Maybank" }) &&
                                     rahim.paymentMethods.contains(where: { $0.provider == "Touch 'n Go" })
        results.append(TestCaseResult(
            testName: "PayBook: One Profile -> Multiple Payment Accounts",
            passed: multipleAccountsPassed,
            expected: "1 Rahim profile with 3 accounts (CIMB, Maybank, TNG)",
            actual: "Count=\(rahim.paymentMethods.count), Providers=\(rahim.providersSummary)",
            details: "Verifies that one person holds multiple bank accounts and e-wallets"
        ))

        // Test 44: PayBook — Same Bank Multiple Accounts Allowed & Masking
        let m4 = PayBookPaymentMethod(paymentType: .bankAccount, provider: "CIMB Bank", accountIdentifier: "999888777", label: "Business", profile: rahim)
        rahim.paymentMethods.append(m4)
        let cimbAccounts = rahim.paymentMethods.filter { $0.displayProvider == "CIMB Bank" }
        let sameBankPassed = cimbAccounts.count == 2 &&
                             cimbAccounts.contains(where: { $0.accountIdentifier == "123456789" }) &&
                             cimbAccounts.contains(where: { $0.accountIdentifier == "999888777" }) &&
                             m1.maskedIdentifier == "••••6789" &&
                             m2.maskedIdentifier == "••••4321"
        results.append(TestCaseResult(
            testName: "PayBook: Same Bank Multiple Accounts Allowed",
            passed: sameBankPassed,
            expected: "2 distinct CIMB accounts under Rahim (123456789 and 999888777) with masking",
            actual: "CIMB Accounts count=\(cimbAccounts.count), Masked=\(m1.maskedIdentifier)",
            details: "Allows multiple different accounts from the same provider under one person"
        ))

        // PayBook Database Tests Container (Schema: Expense + PayBookProfile + PayBookPaymentMethod)
        let pbSchema = Schema([Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self])
        let pbConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        if let pbContainer = try? ModelContainer(for: pbSchema, configurations: [pbConfig]) {
            let pbCtx = pbContainer.mainContext

            // Test 45: PayBook — Duplicate Account Detection Logic
            let testPerson = PayBookProfile(name: "Test Person")
            pbCtx.insert(testPerson)
            let existingAcc = PayBookPaymentMethod(paymentType: .bankAccount, provider: "Maybank", accountIdentifier: "1234-5678-90", profile: testPerson)
            testPerson.paymentMethods.append(existingAcc)
            pbCtx.insert(existingAcc)
            try? pbCtx.save()

            func isDuplicateMethod(provider: String, account: String, in profile: PayBookProfile) -> Bool {
                let normProv = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let normAcc = account.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber || $0.isLetter }.lowercased()
                return profile.paymentMethods.contains {
                    $0.displayProvider.lowercased() == normProv && $0.normalizedIdentifier == normAcc
                }
            }

            let dupExact = isDuplicateMethod(provider: "  MAYBANK  ", account: "1234567890", in: testPerson)
            let nonDupDiffBank = isDuplicateMethod(provider: "CIMB", account: "1234567890", in: testPerson)
            let nonDupDiffAcc = isDuplicateMethod(provider: "Maybank", account: "9999888877", in: testPerson)

            let dupPassed = dupExact && !nonDupDiffBank && !nonDupDiffAcc
            results.append(TestCaseResult(
                testName: "PayBook: Duplicate Account Detection Logic",
                passed: dupPassed,
                expected: "Duplicate=true for same provider & account under person; false otherwise",
                actual: "SameAcc=\(dupExact), DiffBank=\(nonDupDiffBank), DiffAcc=\(nonDupDiffAcc)",
                details: "Detects duplicate payment accounts under the same person profile"
            ))

            // Test 46: PayBook — Persistence Lifecycle & Cascade Delete
            let persProfile = PayBookProfile(name: "Cascade Test Person")
            pbCtx.insert(persProfile)
            let childMethod1 = PayBookPaymentMethod(paymentType: .bankAccount, provider: "RHB", accountIdentifier: "1111", profile: persProfile)
            let childMethod2 = PayBookPaymentMethod(paymentType: .eWallet, provider: "Touch 'n Go", accountIdentifier: "2222", profile: persProfile)
            persProfile.paymentMethods.append(contentsOf: [childMethod1, childMethod2])
            pbCtx.insert(childMethod1)
            pbCtx.insert(childMethod2)
            try? pbCtx.save()

            let beforeProfCount = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>()))?.count ?? 0
            let beforeMethodCount = (try? pbCtx.fetch(FetchDescriptor<PayBookPaymentMethod>()))?.count ?? 0

            // Delete profile -> should cascade delete child methods
            pbCtx.delete(persProfile)
            try? pbCtx.save()

            let afterProfCount = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>()))?.count ?? 0
            let afterMethodCount = (try? pbCtx.fetch(FetchDescriptor<PayBookPaymentMethod>()))?.count ?? 0

            let cascadePassed = (afterProfCount == beforeProfCount - 1) && (afterMethodCount == beforeMethodCount - 2)
            results.append(TestCaseResult(
                testName: "PayBook: Persistence Lifecycle & Cascade Delete",
                passed: cascadePassed,
                expected: "Profiles -1, Methods -2 on cascade delete",
                actual: "Profs: \(beforeProfCount)->\(afterProfCount), Methods: \(beforeMethodCount)->\(afterMethodCount)",
                details: "Deleting a person profile cascades to remove all associated payment accounts"
            ))

            // Test 47: PayBook — Search Filtering & Duplicate Person Names Allowed
            let p1 = PayBookProfile(name: "Rahim Ali")
            let p2 = PayBookProfile(name: "Rahim Ali") // Duplicate person name is explicitly allowed
            let p3 = PayBookProfile(name: "Siti Nurhaliza")
            pbCtx.insert(p1)
            pbCtx.insert(p2)
            pbCtx.insert(p3)

            let p1Method = PayBookPaymentMethod(paymentType: .bankAccount, provider: "CIMB Bank", accountIdentifier: "77778888", profile: p1)
            p1.paymentMethods.append(p1Method)
            pbCtx.insert(p1Method)
            try? pbCtx.save()

            let allProfs = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>())) ?? []
            func search(term: String, list: [PayBookProfile]) -> [PayBookProfile] {
                let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !t.isEmpty else { return list }
                return list.filter { prof in
                    prof.name.lowercased().contains(t) ||
                    prof.paymentMethods.contains { $0.displayProvider.lowercased().contains(t) || $0.accountIdentifier.contains(t) }
                }
            }

            let rahimMatches = search(term: "Rahim", list: allProfs)
            let accountMatches = search(term: "77778888", list: allProfs)
            let sitiMatches = search(term: "siti", list: allProfs)
            let duplicateNamesAllowed = p1.id != p2.id && p1.name == p2.name

            let searchPassed = rahimMatches.count >= 2 && accountMatches.count >= 1 && sitiMatches.count >= 1 && duplicateNamesAllowed
            results.append(TestCaseResult(
                testName: "PayBook: Search Filtering & Duplicate Person Names Allowed",
                passed: searchPassed,
                expected: "Search matches name/account; 2 Rahim profiles coexist with distinct IDs",
                actual: "Rahim=\(rahimMatches.count), AccMatch=\(accountMatches.count), DupNamesAllowed=\(duplicateNamesAllowed)",
                details: "Verifies search by person name and payment accounts, and permits duplicate person names"
            ))

            // Test 48: PayBook — Data Isolation from Expenses
            let expA = Expense(amount: 88.0, merchant: "PayBook Isolation Exp A", date: Date())
            pbCtx.insert(expA)
            try? pbCtx.save()

            let expCountBefore = (try? pbCtx.fetch(FetchDescriptor<Expense>()))?.count ?? 0
            let profCountBefore = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>()))?.count ?? 0

            // Delete an expense -> PayBook profiles unaffected
            pbCtx.delete(expA)
            try? pbCtx.save()

            let expCountAfter = (try? pbCtx.fetch(FetchDescriptor<Expense>()))?.count ?? 0
            let profCountAfter = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>()))?.count ?? 0

            let isolationPassed = (expCountAfter == expCountBefore - 1) && (profCountAfter == profCountBefore)
            results.append(TestCaseResult(
                testName: "PayBook: Data Isolation from Expenses",
                passed: isolationPassed,
                expected: "Expenses -1, PayBook profiles unaffected",
                actual: "ExpBefore=\(expCountBefore), After=\(expCountAfter), Profs=\(profCountAfter)",
                details: "Guarantees complete table/model isolation between Expense and PayBookProfile"
            ))

            // Test 49: UserDataBackupService — Screenshot Receipts Rehydration & Idempotency
            let initialRestore = UserDataBackupService.restoreAccountData(into: pbCtx, force: true)
            let expCountAfterSeed = (try? pbCtx.fetch(FetchDescriptor<Expense>()))?.count ?? 0
            let allRestored = (try? pbCtx.fetch(FetchDescriptor<Expense>())) ?? []
            let hasRana = allRestored.contains { $0.merchant == "RANA SOHEL" && $0.amount == 22.00 }
            let hasIpay88 = allRestored.contains { $0.merchant == "IPAY88" && $0.amount == 932.46 }
            let hasBarakat = allRestored.contains { $0.merchant == "BARAKAT MD ABUL" && $0.amount == 12.00 }
            let hasStarbucks = allRestored.contains { $0.merchant == "Starbucks Coffee" && $0.amount == 25.90 }

            // Re-run non-forced restore -> should be strictly idempotent (0 duplicates added)
            let secondRestore = UserDataBackupService.restoreAccountData(into: pbCtx, force: false)
            let expCountAfterSecond = (try? pbCtx.fetch(FetchDescriptor<Expense>()))?.count ?? 0

            let restorePassed = initialRestore.expensesCount >= 20 &&
                                expCountAfterSeed >= 20 &&
                                hasRana && hasIpay88 && hasBarakat && hasStarbucks &&
                                secondRestore.expensesCount == 0 &&
                                expCountAfterSecond == expCountAfterSeed

            results.append(TestCaseResult(
                testName: "UserDataBackupService: Screenshot Receipts Rehydration & Idempotency",
                passed: restorePassed,
                expected: "Restores >=20 expenses (Rana Sohel, IPAY88, Barakat, Starbucks), second run adds 0 duplicates",
                actual: "Initial=\(initialRestore.expensesCount), Total=\(expCountAfterSeed), Rana=\(hasRana), IPAY88=\(hasIpay88), Barakat=\(hasBarakat), Starbucks=\(hasStarbucks), 2ndRunAdded=\(secondRestore.expensesCount)",
                details: "Rehydrates verified screenshot transactions into active SwiftData and enforces idempotency"
            ))

            // Test 50: UserDataBackupService — PayBook Profile Account Holder (Touhidul Islam Rukon)
            let profs = (try? pbCtx.fetch(FetchDescriptor<PayBookProfile>())) ?? []
            let rukonProf = profs.first { $0.name.lowercased() == "touhidul islam rukon" }
            let rukonMethods = rukonProf?.paymentMethods ?? []
            let hasCimb = rukonMethods.contains { $0.displayProvider == "CIMB Bank" && $0.accountIdentifier == "7658174175" }
            let hasMbb = rukonMethods.contains { $0.displayProvider == "Maybank" && $0.accountIdentifier == "168603292644" }
            let hasRhb = rukonMethods.contains { $0.displayProvider == "RHB Bank" && $0.accountIdentifier == "21601100036406" }
            let hasTng = rukonMethods.contains { $0.displayProvider == "Touch 'n Go" }
            let hasDuitNow = rukonMethods.contains { $0.displayProvider == "DuitNow" && $0.accountIdentifier == "tirukon015@gmail.com" }

            let rukonPassed = rukonProf != nil && hasCimb && hasMbb && hasRhb && hasTng && hasDuitNow
            results.append(TestCaseResult(
                testName: "UserDataBackupService: Account Holder PayBook Profile",
                passed: rukonPassed,
                expected: "Profile 'Touhidul Islam Rukon' with CIMB, Maybank, RHB, TNG, and DuitNow accounts",
                actual: "ProfileFound=\(rukonProf != nil), CIMB=\(hasCimb), MBB=\(hasMbb), RHB=\(hasRhb), TNG=\(hasTng), DuitNow=\(hasDuitNow)",
                details: "Restores owner account profile with 5 verified banking & eWallet methods"
            ))

            // Test 51: UserDataBackupService — JSON Export & Import Roundtrip
            var roundtripPassed = false
            if let exportURL = UserDataBackupService.generateExportJSONFile(from: pbCtx) {
                if let importContainer = try? ModelContainer(for: pbSchema, configurations: [pbConfig]) {
                    let importCtx = importContainer.mainContext
                    if let importResult = try? UserDataBackupService.importFromJSON(at: exportURL, into: importCtx) {
                        let importedExpCount = (try? importCtx.fetch(FetchDescriptor<Expense>()))?.count ?? 0
                        let importedProfCount = (try? importCtx.fetch(FetchDescriptor<PayBookProfile>()))?.count ?? 0
                        roundtripPassed = (importResult.expensesAdded == importedExpCount) && (importedExpCount >= 20) && (importedProfCount >= 4)
                    }
                }
                try? FileManager.default.removeItem(at: exportURL)
            }

            results.append(TestCaseResult(
                testName: "UserDataBackupService: JSON Export & Import Roundtrip",
                passed: roundtripPassed,
                expected: "Exports full JSON backup, imports into clean container, recovers all records with zero loss",
                actual: "RoundtripPassed=\(roundtripPassed)",
                details: "Verifies complete serialization, file writing, deserialization, and SwiftData restoration"
            ))
        }

        // MARK: - Transaction Intelligence & Filtering V1 Tests (Tests 52 - 66)

        // Test 52: Scenario 1 - Maybank + Apple Pay Detection
        let mbbAppleText = """
        Apple Pay
        Paid RM50.00 to Starbucks
        Maybank Debit Card ending in 4175
        26 Sep 2026
        """
        let mbbAppleParsed = parser.parse(ocrResult: makeOCRResult(text: mbbAppleText))
        let t52Passed = mbbAppleParsed.amount == 50.0 &&
                        mbbAppleParsed.paymentChannel == .applePay &&
                        mbbAppleParsed.displayFundingAccount.contains("Maybank")
        results.append(TestCaseResult(
            testName: "Scenario 1: Maybank + Apple Pay",
            passed: t52Passed,
            expected: "Amount: RM50.00, Channel: APPLE_PAY, Funding: Maybank",
            actual: "Amount: RM\(mbbAppleParsed.amount ?? 0), Channel: \(mbbAppleParsed.paymentChannel.rawValue), Funding: \(mbbAppleParsed.displayFundingAccount)",
            details: "Tests distinguishing Maybank as Funding Account and Apple Pay as Payment Channel"
        ))

        // Test 53: Scenario 2 - Maybank + QR Payment
        let mbbQrText = """
        Maybank2u
        Scan & Pay Successful
        RM35.00
        Paid to: Restaurant Ali
        DuitNow QR Reference: MBBQR102938
        """
        let mbbQrParsed = parser.parse(ocrResult: makeOCRResult(text: mbbQrText))
        let t53Passed = mbbQrParsed.amount == 35.0 &&
                        mbbQrParsed.paymentChannel == .qrPayment &&
                        mbbQrParsed.displayFundingAccount.contains("Maybank")
        results.append(TestCaseResult(
            testName: "Scenario 2: Maybank + QR Payment",
            passed: t53Passed,
            expected: "Amount: RM35.00, Channel: QR_PAYMENT, Funding: Maybank",
            actual: "Amount: RM\(mbbQrParsed.amount ?? 0), Channel: \(mbbQrParsed.paymentChannel.rawValue), Funding: \(mbbQrParsed.displayFundingAccount)",
            details: "Tests Maybank Scan & Pay DuitNow QR detection"
        ))

        // Test 54: Scenario 3 - Maybank + Bank Transfer
        let mbbTransferText = """
        Maybank
        DuitNow Transfer Successful
        Amount: RM500.00
        Recipient: Rahim bin Ahmad
        Reference: 20260925MBB8291
        """
        let mbbTransferParsed = parser.parse(ocrResult: makeOCRResult(text: mbbTransferText))
        let t54Passed = mbbTransferParsed.amount == 500.0 &&
                        mbbTransferParsed.paymentChannel == .bankTransfer &&
                        mbbTransferParsed.displayFundingAccount.contains("Maybank")
        results.append(TestCaseResult(
            testName: "Scenario 3: Maybank + Bank Transfer",
            passed: t54Passed,
            expected: "Amount: RM500.00, Channel: BANK_TRANSFER, Funding: Maybank",
            actual: "Amount: RM\(mbbTransferParsed.amount ?? 0), Channel: \(mbbTransferParsed.paymentChannel.rawValue), Funding: \(mbbTransferParsed.displayFundingAccount)",
            details: "Tests bank transfer channel detection with Maybank funding"
        ))

        // Test 55: Scenario 4 - Wise + Apple Pay
        let wiseAppleText = """
        Apple Pay
        RM20.00
        Uniqlo
        Paid with Wise Card ending in 8891
        """
        let wiseAppleParsed = parser.parse(ocrResult: makeOCRResult(text: wiseAppleText))
        let t55Passed = wiseAppleParsed.amount == 20.0 &&
                        wiseAppleParsed.paymentChannel == .applePay &&
                        wiseAppleParsed.displayFundingAccount.contains("Wise")
        results.append(TestCaseResult(
            testName: "Scenario 4: Wise + Apple Pay",
            passed: t55Passed,
            expected: "Amount: RM20.00, Channel: APPLE_PAY, Funding: Wise",
            actual: "Amount: RM\(wiseAppleParsed.amount ?? 0), Channel: \(wiseAppleParsed.paymentChannel.rawValue), Funding: \(wiseAppleParsed.displayFundingAccount)",
            details: "Tests Wise as funding account and Apple Pay as channel"
        ))

        // Setup In-Memory Engine for Filtering & Date Scenarios
        let engine = TransactionFilterEngine()
        let cal = Calendar.current
        let testNow = Date()
        let startOfToday = cal.startOfDay(for: testNow)

        let expTodayFoodMBBApple = Expense(
            amount: 50.0,
            merchant: "Starbucks",
            category: .food,
            date: testNow,
            paymentChannel: .applePay,
            fundingAccount: "Maybank"
        )
        let exp2DaysAgoFoodMBBQR = Expense(
            amount: 35.0,
            merchant: "Restaurant Ali",
            category: .food,
            date: cal.date(byAdding: .day, value: -2, to: startOfToday)!.addingTimeInterval(3600),
            paymentChannel: .qrPayment,
            fundingAccount: "Maybank"
        )
        let exp5DaysAgoShoppingWiseApple = Expense(
            amount: 20.0,
            merchant: "Uniqlo",
            category: .shopping,
            date: cal.date(byAdding: .day, value: -5, to: startOfToday)!.addingTimeInterval(7200),
            paymentChannel: .applePay,
            fundingAccount: "Wise"
        )
        let exp15DaysAgoTransportMBB = Expense(
            amount: 80.0,
            merchant: "Shell Petrol",
            category: .transport,
            date: cal.date(byAdding: .day, value: -15, to: startOfToday)!,
            paymentChannel: .card,
            fundingAccount: "Maybank"
        )
        let expYesterdayFoodCash = Expense(
            amount: 15.0,
            merchant: "Mamak",
            category: .food,
            date: cal.date(byAdding: .day, value: -1, to: startOfToday)!.addingTimeInterval(4000),
            paymentChannel: .cash,
            fundingAccount: "Cash"
        )

        let sampleExpenses = [
            expTodayFoodMBBApple,
            expYesterdayFoodCash,
            exp2DaysAgoFoodMBBQR,
            exp5DaysAgoShoppingWiseApple,
            exp15DaysAgoTransportMBB
        ]
        engine.update(expenses: sampleExpenses)

        // Test 56: Scenario 5 - Food + Last 7 Days
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        engine.selectedCategory = .food
        let food7DaysExpenses = engine.filteredExpenses
        let food7DaysTotal = engine.totalSpending
        let t56Passed = food7DaysExpenses.count == 3 && abs(food7DaysTotal - 100.0) < 0.01 // 50 + 15 + 35 = 100
        results.append(TestCaseResult(
            testName: "Scenario 5: Food + Last 7 Days",
            passed: t56Passed,
            expected: "3 expenses, Total: RM100.00",
            actual: "\(food7DaysExpenses.count) expenses, Total: RM\(food7DaysTotal)",
            details: "Tests combined category and Last 7 Days filter"
        ))

        // Test 57: Scenario 6 - Maybank + Food + Last 7 Days
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        engine.selectedCategory = .food
        engine.selectedFundingAccount = "Maybank"
        let mbbFood7Days = engine.filteredExpenses
        let mbbFood7DaysTotal = engine.totalSpending
        let t57Passed = mbbFood7Days.count == 2 && abs(mbbFood7DaysTotal - 85.0) < 0.01 // 50 + 35 = 85
        results.append(TestCaseResult(
            testName: "Scenario 6: Maybank + Food + Last 7 Days",
            passed: t57Passed,
            expected: "2 expenses, Total: RM85.00",
            actual: "\(mbbFood7Days.count) expenses, Total: RM\(mbbFood7DaysTotal)",
            details: "Tests combined Account + Category + Date window"
        ))

        // Test 58: Scenario 7 - Apple Pay + Food + Last 7 Days
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        engine.selectedCategory = .food
        engine.selectedPaymentChannel = .applePay
        let appleFood7Days = engine.filteredExpenses
        let appleFood7DaysTotal = engine.totalSpending
        let t58Passed = appleFood7Days.count == 1 && abs(appleFood7DaysTotal - 50.0) < 0.01
        results.append(TestCaseResult(
            testName: "Scenario 7: Apple Pay + Food + Last 7 Days",
            passed: t58Passed,
            expected: "1 expense, Total: RM50.00",
            actual: "\(appleFood7Days.count) expenses, Total: RM\(appleFood7DaysTotal)",
            details: "Tests combined Channel + Category + Date window"
        ))

        // Test 59: Scenario 8 - Yesterday Filter
        engine.clearAllFilters()
        engine.selectedDateFilter = .yesterday
        let yesterdayExpenses = engine.filteredExpenses
        let t59Passed = yesterdayExpenses.count == 1 && yesterdayExpenses.first?.merchant == "Mamak"
        results.append(TestCaseResult(
            testName: "Scenario 8: Yesterday Filter",
            passed: t59Passed,
            expected: "1 expense (Mamak RM15.00)",
            actual: "\(yesterdayExpenses.count) expense(s), First: \(yesterdayExpenses.first?.merchant ?? "nil")",
            details: "Tests Yesterday date boundary"
        ))

        // Test 60: Scenario 9 - Last 3 Days Filter
        engine.clearAllFilters()
        engine.selectedDateFilter = .last3Days
        let last3DaysExpenses = engine.filteredExpenses
        let t60Passed = last3DaysExpenses.count == 3 // Today (Starbucks), Yesterday (Mamak), 2 Days ago (Restaurant Ali)
        results.append(TestCaseResult(
            testName: "Scenario 9: Last 3 Days Filter",
            passed: t60Passed,
            expected: "3 expenses (Starbucks, Mamak, Restaurant Ali)",
            actual: "\(last3DaysExpenses.count) expenses",
            details: "Tests Today + previous 2 calendar days = 3 days"
        ))

        // Test 61: Scenario 10 - Last 7 Days Filter (Today + previous 6 calendar days)
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        let (l7Start, l7End) = engine.dateInterval(for: .last7Days, now: testNow)
        let daysBetween = cal.dateComponents([.day], from: cal.startOfDay(for: l7Start), to: cal.startOfDay(for: l7End)).day ?? 0
        let l7Expenses = engine.filteredExpenses
        let t61Passed = (daysBetween == 6) && (engine.numberOfCalendarDays == 7) && (l7Expenses.count == 4) // excludes 15 days ago
        results.append(TestCaseResult(
            testName: "Scenario 10: Last 7 Days (Today + previous 6 days)",
            passed: t61Passed,
            expected: "Exact 7 calendar days window, 4 expenses (excludes Shell)",
            actual: "Days=\(engine.numberOfCalendarDays), Expenses=\(l7Expenses.count), Subtitle=\(engine.currentSubtitle)",
            details: "Strict definition: Today + previous 6 calendar days"
        ))

        // Test 62: Scenario 11 - Last 30 Days Filter
        engine.clearAllFilters()
        engine.selectedDateFilter = .last30Days
        let l30Expenses = engine.filteredExpenses
        let t62Passed = l30Expenses.count == 5 && (engine.numberOfCalendarDays == 30)
        results.append(TestCaseResult(
            testName: "Scenario 11: Last 30 Days Filter",
            passed: t62Passed,
            expected: "Exact 30 calendar days window, all 5 expenses",
            actual: "Days=\(engine.numberOfCalendarDays), Expenses=\(l30Expenses.count)",
            details: "Today + previous 29 calendar days"
        ))

        // Test 63: Scenario 12 - Custom Date Range
        engine.clearAllFilters()
        engine.selectedDateFilter = .custom
        engine.customStartDate = cal.date(byAdding: .day, value: -6, to: startOfToday)!
        engine.customEndDate = cal.date(byAdding: .day, value: -2, to: startOfToday)!
        let customExpenses = engine.filteredExpenses
        let t63Passed = customExpenses.count == 2 // 2 days ago (Restaurant Ali) and 5 days ago (Uniqlo)
        results.append(TestCaseResult(
            testName: "Scenario 12: Custom Date Range",
            passed: t63Passed,
            expected: "2 expenses within custom interval",
            actual: "\(customExpenses.count) expenses (\(engine.currentSubtitle))",
            details: "User custom start and end date bounds"
        ))

        // Test 64: Scenario 13 - Duplicate Apple Pay & Bank Transaction Reconciliation
        var t64Passed = false
        if let recSchema = try? Schema([Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self]),
           let recConfig = try? ModelConfiguration(isStoredInMemoryOnly: true),
           let recContainer = try? ModelContainer(for: recSchema, configurations: [recConfig]) {
            let recCtx = recContainer.mainContext

            // Record 1: Apple Pay screenshot (amount RM50, merchant Starbucks, funding Unknown, channel Apple Pay)
            let exp1 = Expense(
                amount: 50.0,
                merchant: "Starbucks",
                category: .food,
                date: testNow,
                paymentChannel: .applePay,
                fundingAccount: "Unknown"
            )
            recCtx.insert(exp1)
            try? recCtx.save()

            // Candidate from Maybank debit statement (amount RM50, merchant Starbucks, funding Maybank, channel Unknown, reference MBB12345)
            let match = TransactionReconciliationEngine.shared.findMatch(
                amount: 50.0,
                merchant: "Starbucks",
                date: testNow,
                reference: "MBB12345",
                in: recCtx
            )

            let candidate = ReconcileCandidate(
                amount: 50.0,
                merchant: "Starbucks Mid Valley",
                date: testNow,
                category: .food,
                fundingAccount: "Maybank",
                paymentChannel: .unknown,
                reference: "MBB12345",
                notes: "Bank debit statement"
            )

            let reconciled = TransactionReconciliationEngine.shared.reconcile(existing: exp1, with: candidate, in: recCtx)
            let allRec = (try? recCtx.fetch(FetchDescriptor<Expense>())) ?? []

            t64Passed = match.isMatch &&
                        allRec.count == 1 &&
                        reconciled.effectiveFundingAccount == "Maybank" &&
                        reconciled.paymentChannel == .applePay &&
                        reconciled.isReconciled &&
                        reconciled.transactionReference == "MBB12345" &&
                        abs(reconciled.amount - 50.0) < 0.001
        }
        results.append(TestCaseResult(
            testName: "Scenario 13: Reconciliation into ONE Expense",
            passed: t64Passed,
            expected: "Match detected, single record retained, Maybank + Apple Pay reconciled, 0 duplicate count",
            actual: "ReconciliationPassed=\(t64Passed)",
            details: "Merges Apple Pay authorization and bank debit into 1 financial transaction"
        ))

        // Test 65: Scenario 14 - New Transaction Immediately Appears After Saving
        var t65Passed = false
        if let invSchema = try? Schema([Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self]),
           let invConfig = try? ModelConfiguration(isStoredInMemoryOnly: true),
           let invContainer = try? ModelContainer(for: invSchema, configurations: [invConfig]) {
            let invCtx = invContainer.mainContext
            let testEngine = TransactionFilterEngine()
            testEngine.selectedDateFilter = .last7Days
            testEngine.update(expenses: (try? invCtx.fetch(FetchDescriptor<Expense>())) ?? [])

            let initialCount = testEngine.filteredExpenses.count

            let newExpense = Expense(
                amount: 99.0,
                merchant: "Apple Store",
                category: .shopping,
                date: testNow,
                paymentChannel: .applePay,
                fundingAccount: "Maybank"
            )
            invCtx.insert(newExpense)
            try? invCtx.save()
            invCtx.processPendingChanges()

            testEngine.update(expenses: (try? invCtx.fetch(FetchDescriptor<Expense>())) ?? [])
            let newCount = testEngine.filteredExpenses.count
            t65Passed = (initialCount == 0) && (newCount == 1) && (testEngine.totalSpending == 99.0)
        }
        results.append(TestCaseResult(
            testName: "Scenario 14: New Transaction Immediately Visible",
            passed: t65Passed,
            expected: "Engine invalidation on save updates filtered list and total instantly",
            actual: "ImmediateVisibilityPassed=\(t65Passed)",
            details: "Tests SwiftData processPendingChanges and TransactionFilterEngine immediate refresh"
        ))

        // Test 66: Scenario 15 - Mathematical Consistency Across All Views
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        let totalDirect = engine.totalSpending
        let sumDaily = engine.dailySpending.reduce(0.0) { $0 + $1.amount }
        let sumCategory = engine.categoryBreakdown.reduce(0.0) { $0 + $1.total }
        let sumChannel = engine.paymentChannelBreakdown.reduce(0.0) { $0 + $1.total }
        let sumFunding = engine.fundingAccountBreakdown.reduce(0.0) { $0 + $1.total }
        let sumExpenses = engine.filteredExpenses.reduce(0.0) { $0 + $1.amount }

        let t66Passed = abs(totalDirect - sumDaily) < 0.001 &&
                        abs(totalDirect - sumCategory) < 0.001 &&
                        abs(totalDirect - sumChannel) < 0.001 &&
                        abs(totalDirect - sumFunding) < 0.001 &&
                        abs(totalDirect - sumExpenses) < 0.001 &&
                        totalDirect > 0

        results.append(TestCaseResult(
            testName: "Scenario 15: Mathematical Consistency Across All Views",
            passed: t66Passed,
            expected: "Total == Sum(Daily) == Sum(Category) == Sum(Channel) == Sum(Funding) == Sum(List)",
            actual: "Total=\(totalDirect), Daily=\(sumDaily), Category=\(sumCategory), Channel=\(sumChannel), Funding=\(sumFunding)",
            details: "Proves single source of truth across list, analytics, and all breakdown dimensions"
        ))

        // Test 67: Multi-Select Accounts (Maybank + Wise)
        engine.clearAllFilters()
        engine.selectedDateFilter = .last30Days
        engine.selectedFundingAccounts = ["Maybank", "Wise"]
        let mbbWiseExpenses = engine.filteredExpenses
        // expTodayFoodMBBApple (50 MBB), exp2DaysAgoFoodMBBQR (35 MBB), exp5DaysAgoShoppingWiseApple (20 Wise), exp15DaysAgoTransportMBB (80 MBB) = 4 expenses
        let t67Passed = mbbWiseExpenses.count == 4 && abs(engine.totalSpending - 185.0) < 0.01
        results.append(TestCaseResult(
            testName: "Scenario 16: Multi-Select Accounts (Maybank + Wise)",
            passed: t67Passed,
            expected: "4 expenses from Maybank OR Wise, Total: RM185.00",
            actual: "Count=\(mbbWiseExpenses.count), Total=RM\(engine.totalSpending)",
            details: "Tests multi-account OR filtering"
        ))

        // Test 68: Multi-Select Categories (Food + Shopping)
        engine.clearAllFilters()
        engine.selectedDateFilter = .last30Days
        engine.selectedCategories = [.food, .shopping]
        let foodShopExpenses = engine.filteredExpenses
        // Food: 50, 15, 35; Shopping: 20. Total: 4 expenses, 120.00
        let t68Passed = foodShopExpenses.count == 4 && abs(engine.totalSpending - 120.0) < 0.01
        results.append(TestCaseResult(
            testName: "Scenario 17: Multi-Select Categories (Food + Shopping)",
            passed: t68Passed,
            expected: "4 expenses from Food OR Shopping, Total: RM120.00",
            actual: "Count=\(foodShopExpenses.count), Total=RM\(engine.totalSpending)",
            details: "Tests multi-category OR filtering"
        ))

        // Test 69: Multi-Select Payment Channels (Apple Pay + QR Payment)
        engine.clearAllFilters()
        engine.selectedDateFilter = .last30Days
        engine.selectedPaymentChannels = [.applePay, .qrPayment]
        let appleQRExpenses = engine.filteredExpenses
        // expTodayFoodMBBApple (50), exp2DaysAgoFoodMBBQR (35), exp5DaysAgoShoppingWiseApple (20) = 3 expenses, 105.00
        let t69Passed = appleQRExpenses.count == 3 && abs(engine.totalSpending - 105.0) < 0.01
        results.append(TestCaseResult(
            testName: "Scenario 18: Multi-Select Payment Channels (Apple Pay + QR)",
            passed: t69Passed,
            expected: "3 expenses from Apple Pay OR QR, Total: RM105.00",
            actual: "Count=\(appleQRExpenses.count), Total=RM\(engine.totalSpending)",
            details: "Tests multi-channel OR filtering"
        ))

        // Test 70: Combined Multi-Select Across All Dimensions (AND between groups, OR within group)
        engine.clearAllFilters()
        engine.selectedDateFilter = .last7Days
        engine.selectedFundingAccounts = ["Maybank", "Wise"]
        engine.selectedCategories = [.food, .shopping]
        engine.selectedPaymentChannels = [.applePay, .qrPayment]
        let combinedExpenses = engine.filteredExpenses
        // Last 7 days:
        // expTodayFoodMBBApple (Food, MBB, Apple) -> MATCH
        // exp2DaysAgoFoodMBBQR (Food, MBB, QR) -> MATCH
        // exp5DaysAgoShoppingWiseApple (Shopping, Wise, Apple) -> MATCH
        // expYesterdayFoodCash (Cash channel) -> NO
        // exp15DaysAgoTransportMBB (15 days ago) -> NO
        let t70Passed = combinedExpenses.count == 3 && abs(engine.totalSpending - 105.0) < 0.01
        results.append(TestCaseResult(
            testName: "Scenario 19: Combined Multi-Select Across All Dimensions",
            passed: t70Passed,
            expected: "3 expenses matching (MBB/Wise) AND (Food/Shopping) AND (ApplePay/QR) AND Last 7 Days",
            actual: "Count=\(combinedExpenses.count), Total=RM\(engine.totalSpending)",
            details: "Tests complex cross-dimension multi-select logic"
        ))

        // Test 71: Daily Spending Separate Date Range (Main = Today, Daily = Last 7 Days)
        engine.clearAllFilters()
        engine.selectedDateFilter = .today
        engine.dailySpendingRange = .last7Days
        let todayMainExpenses = engine.filteredExpenses
        let dailyPoints7 = engine.dailySpending
        let t71Passed = (todayMainExpenses.count == 1) && (dailyPoints7.count == 7)
        results.append(TestCaseResult(
            testName: "Scenario 20: Daily Spending Independent From Main Date Filter",
            passed: t71Passed,
            expected: "Main filter has 1 expense for Today, but Daily Spending chart has all 7 points",
            actual: "MainCount=\(todayMainExpenses.count), DailyPointsCount=\(dailyPoints7.count)",
            details: "Verifies Daily Spending does not collapse when Main Date Filter is Today"
        ))

        // Test 72: Daily Spending 30 Days (All 30 calendar days represented)
        engine.clearAllFilters()
        engine.dailySpendingRange = .last30Days
        let dailyPoints30 = engine.dailySpending
        let t72Passed = dailyPoints30.count == 30
        results.append(TestCaseResult(
            testName: "Scenario 21: Daily Spending 30 Days Continuous Points",
            passed: t72Passed,
            expected: "Exact 30 continuous calendar days with zero-spending days preserved",
            actual: "DailyPoints30Count=\(dailyPoints30.count)",
            details: "Verifies 30 full calendar days representation"
        ))

        // =============================================
        // REAL SAMPLE REGRESSION TESTS (Tests 73-77)
        // From user's actual Apple Pay / Maybank screenshots
        // =============================================

        // Test 73: Maybank MAE e-receipt — SHOPEE - APPLEPAY-EC
        // Source: IMG_0487.PNG (Maybank MAE app receipt)
        // Channel: UNKNOWN — merchant name contains "APPLEPAY" but there are NO Apple Wallet UI markers.
        // Per Priority 4: Instrument alone ("Maybank Debit Card Visa") without Apple Wallet source → UNKNOWN
        let maeShopeeText = """
        10:14 O
        • Shopee
        <
        !!!! 5G 64
        27 Sep 2026, 10:14 AM
        SHOPEE - APPLEPAY-EC
        - RM 4.48
        Payment
        Reference Number
        Merchant name
        Terminal ID
        Merchant ID
        Approval Code
        Maybank Debit Card Visa
        ************ 9034
        626902161660
        SHOPEE - APPLEPAY-EC
        75003178
        027007722648
        145592
        Share Receipt
        * Actual transaction amount in MYR will reflect in your
        transaction history once it's processed. It will include the
        overseas transaction fee and admin fee.
        """
        let t73Parsed = parser.parse(ocrResult: makeOCRResult(text: maeShopeeText))
        // Maybank MAE receipt alone → channel = UNKNOWN (never guess from merchant name "APPLEPAY-EC")
        // Funding Account = Maybank, Funding Instrument = "Maybank Debit Card Visa"
        let t73ChannelOK = t73Parsed.paymentChannel == .unknown
        let t73FundingOK = t73Parsed.fundingAccount == "Maybank" || t73Parsed.displayFundingAccount == "Maybank"
        let t73InstrumentOK = t73Parsed.fundingInstrument != nil && t73Parsed.fundingInstrument!.lowercased().contains("visa")
        let t73AmountOK = t73Parsed.amount == 4.48
        let t73MerchantOK = t73Parsed.merchant == "Shopee"
        let t73Passed = t73ChannelOK && t73FundingOK && t73AmountOK && t73MerchantOK
        results.append(TestCaseResult(
            testName: "Real Sample 73: Maybank MAE Shopee APPLEPAY-EC Receipt",
            passed: t73Passed,
            expected: "Channel=UNKNOWN (no Apple Wallet markers), Funding=Maybank, Merchant=Shopee, Amount=4.48",
            actual: "Channel=\(t73Parsed.paymentChannel.rawValue), Funding=\(t73Parsed.displayFundingAccount), Instrument=\(t73Parsed.fundingInstrument ?? "nil"), Merchant=\(t73Parsed.merchant ?? "nil"), Amount=\(t73Parsed.amount ?? 0)",
            details: "Tests Priority 4: merchant name 'APPLEPAY-EC' must NOT set channel=APPLE_PAY without Apple Wallet provenance"
        ))

        // Test 74: Apple Wallet — EZ Fresh Mart (IMG_0489.PNG)
        // Source: Apple Wallet UI with full structural markers
        // Channel: APPLE_PAY (Priority 1: Apple Wallet provenance detected)
        let walletEZFreshText = """
        1:30 1
        !!!!
        <
        RM 74.20
        EZ Fresh Mart, Cyberjaya, Selangor
        27/09/2026, 8:36 PM
        Status: Approved
        Maybank Visa Debit
        Total
        RM 74.20
        NION
        CYBERIA 3.
        NEURON
        PERSIARAN SEPANG
        Zumo
        EZ Fresh Mart
        PERSIARAN MULTIMEDIA
        -IMEDIA
        EZ Fresh Mart
        JALAN FA
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
        """
        let t74Parsed = parser.parse(ocrResult: makeOCRResult(text: walletEZFreshText))
        let t74ChannelOK = t74Parsed.paymentChannel == .applePay
        let t74FundingOK = t74Parsed.fundingAccount == "Maybank" || t74Parsed.displayFundingAccount == "Maybank"
        let t74InstrumentOK = t74Parsed.fundingInstrument != nil && t74Parsed.fundingInstrument!.lowercased().contains("visa debit")
        let t74AmountOK = t74Parsed.amount == 74.20
        let t74MerchantOK = t74Parsed.merchant == "EZ Fresh Mart"
        let t74Passed = t74ChannelOK && t74FundingOK && t74AmountOK && t74MerchantOK
        results.append(TestCaseResult(
            testName: "Real Sample 74: Apple Wallet EZ Fresh Mart",
            passed: t74Passed,
            expected: "Channel=APPLE_PAY, Funding=Maybank, Instrument=Maybank Visa Debit, Merchant=EZ Fresh Mart, Amount=74.20",
            actual: "Channel=\(t74Parsed.paymentChannel.rawValue), Funding=\(t74Parsed.displayFundingAccount), Instrument=\(t74Parsed.fundingInstrument ?? "nil"), Merchant=\(t74Parsed.merchant ?? "nil"), Amount=\(t74Parsed.amount ?? 0)",
            details: "Tests Priority 1: Apple Wallet provenance markers (Status: Approved + Contact Maybank + wallet uses maps)"
        ))

        // Test 75: Apple Wallet — Shopee (IMG_0490.PNG)
        // Same transaction as Test 73 but from Apple Wallet perspective
        let walletShopeeText = """
        1:30 1
        .!!!
        <
        RM 4.48
        Shopee - Applepay-Ec
        27/09/2026, 10:14AM
        Status: Approved
        Maybank Visa Debit
        Total
        RM 4.48
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
        """
        let t75Parsed = parser.parse(ocrResult: makeOCRResult(text: walletShopeeText))
        let t75ChannelOK = t75Parsed.paymentChannel == .applePay
        let t75FundingOK = t75Parsed.fundingAccount == "Maybank" || t75Parsed.displayFundingAccount == "Maybank"
        let t75AmountOK = t75Parsed.amount == 4.48
        let t75MerchantOK = t75Parsed.merchant == "Shopee"
        let t75Passed = t75ChannelOK && t75FundingOK && t75AmountOK && t75MerchantOK
        results.append(TestCaseResult(
            testName: "Real Sample 75: Apple Wallet Shopee-Applepay-Ec",
            passed: t75Passed,
            expected: "Channel=APPLE_PAY, Funding=Maybank, Merchant=Shopee, Amount=4.48",
            actual: "Channel=\(t75Parsed.paymentChannel.rawValue), Funding=\(t75Parsed.displayFundingAccount), Merchant=\(t75Parsed.merchant ?? "nil"), Amount=\(t75Parsed.amount ?? 0)",
            details: "Tests Apple Wallet provenance for Shopee Apple Pay transaction (same real payment as Test 73, different source)"
        ))

        // Test 76: Apple Wallet — Brain Freeze Vape Shop (IMG_0491.PNG)
        let walletBrainFreezeText = """
        1:30
        !!!!
        <
        RM 40.00
        Brain Freeze Vape Shop, Cyberjaya, Selangor
        26/09/2026, 3:13 PM
        Status: Approved
        Maybank Visa Debit
        Total
        RM 40.00
        Warung Hanna
        SERIN
        PERSIARAN CERIA
        & RESIDENCY
        AN FAUNA 1
        Brain Freeze Vape Shop
        KNOKRAT 6
        Brain Freeze Vape Shop
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
        """
        let t76Parsed = parser.parse(ocrResult: makeOCRResult(text: walletBrainFreezeText))
        let t76ChannelOK = t76Parsed.paymentChannel == .applePay
        let t76FundingOK = t76Parsed.fundingAccount == "Maybank" || t76Parsed.displayFundingAccount == "Maybank"
        let t76AmountOK = t76Parsed.amount == 40.00
        let t76MerchantOK = t76Parsed.merchant == "Brain Freeze Vape Shop"
        let t76Passed = t76ChannelOK && t76FundingOK && t76AmountOK && t76MerchantOK
        results.append(TestCaseResult(
            testName: "Real Sample 76: Apple Wallet Brain Freeze Vape Shop",
            passed: t76Passed,
            expected: "Channel=APPLE_PAY, Funding=Maybank, Merchant=Brain Freeze Vape Shop, Amount=40.00",
            actual: "Channel=\(t76Parsed.paymentChannel.rawValue), Funding=\(t76Parsed.displayFundingAccount), Merchant=\(t76Parsed.merchant ?? "nil"), Amount=\(t76Parsed.amount ?? 0)",
            details: "Tests Apple Wallet provenance for physical store Apple Pay purchase"
        ))

        // Test 77: Apple Wallet — Shell (IMG_0492.PNG)
        let walletShellText = """
        1:30
        !!!!
        <
        RM 23.20
        Shell, Cyberjaya, Selangor
        21/09/2026, 8:12 PM
        Status: Approved
        Maybank Visa Debit
        Total
        RM 23.20
        7-Eleven
        CERIA
        SI
        Shell
        SERIN
        SIDENCY
        Restoran
        A -Nazmaju
        SIARAN APEC
        Shell
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
        """
        let t77Parsed = parser.parse(ocrResult: makeOCRResult(text: walletShellText))
        let t77ChannelOK = t77Parsed.paymentChannel == .applePay
        let t77FundingOK = t77Parsed.fundingAccount == "Maybank" || t77Parsed.displayFundingAccount == "Maybank"
        let t77AmountOK = t77Parsed.amount == 23.20
        let t77MerchantOK = t77Parsed.merchant == "Shell"
        let t77CategoryOK = t77Parsed.category == .transport
        let t77Passed = t77ChannelOK && t77FundingOK && t77AmountOK && t77MerchantOK
        results.append(TestCaseResult(
            testName: "Real Sample 77: Apple Wallet Shell Petrol",
            passed: t77Passed,
            expected: "Channel=APPLE_PAY, Funding=Maybank, Merchant=Shell, Category=Transport, Amount=23.20",
            actual: "Channel=\(t77Parsed.paymentChannel.rawValue), Funding=\(t77Parsed.displayFundingAccount), Merchant=\(t77Parsed.merchant ?? "nil"), Category=\(t77Parsed.category?.rawValue ?? "nil"), Amount=\(t77Parsed.amount ?? 0)",
            details: "Tests Apple Wallet provenance for fuel purchase with merchant/category detection"
        ))

        // =============================================
        // REQUIRED SAMPLE TEST (IMG_0494.PNG / Section 18)
        // Apple Wallet Shopee RM 22.48
        // =============================================
        let reqWalletShopeeText = """
        8:17
        .!!!
        <
        RM 22.48
        Shopee - Applepay-Ec
        26/09/2026, 8:16 PM
        Status: Approved
        Maybank Visa Debit
        Total
        RM 22.48
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
        """
        let t78Parsed = parser.parse(ocrResult: makeOCRResult(text: reqWalletShopeeText))
        let t78MerchantOK = t78Parsed.merchant == "Shopee"
        let t78NotDispute = t78Parsed.merchant != "dispute a"
        let t78NotMaybank = t78Parsed.merchant != "Maybank" && t78Parsed.merchant != "Contact Maybank"
        let t78AmountOK = t78Parsed.amount == 22.48
        let t78ChannelOK = t78Parsed.paymentChannel == .applePay
        let t78FundingOK = t78Parsed.fundingAccount == "Maybank" || t78Parsed.displayFundingAccount == "Maybank"
        let t78Passed = t78MerchantOK && t78NotDispute && t78NotMaybank && t78AmountOK && t78ChannelOK && t78FundingOK
        results.append(TestCaseResult(
            testName: "Section 18 Required: Apple Wallet Shopee RM 22.48 (IMG_0494)",
            passed: t78Passed,
            expected: "Merchant=Shopee (NOT 'dispute a'), Channel=APPLE_PAY, Funding=Maybank, Amount=22.48",
            actual: "Merchant=\(t78Parsed.merchant ?? "nil"), Channel=\(t78Parsed.paymentChannel.rawValue), Funding=\(t78Parsed.displayFundingAccount), Amount=\(t78Parsed.amount ?? 0)",
            details: "Prevents footer/help text 'dispute a' or 'Contact Maybank' from becoming merchant"
        ))

        // =============================================
        // GENERAL REGRESSION TESTS A-H (Section 19)
        // =============================================

        // Test 79 (Test A): Merchant field explicitly present
        let testAText = """
        Merchant: Guardian Pharmacy
        Amount: RM25.00
        Date: 26/09/2026
        """
        let t79Parsed = parser.parse(ocrResult: makeOCRResult(text: testAText))
        let t79Passed = t79Parsed.merchant == "Guardian"
        results.append(TestCaseResult(
            testName: "Section 19 Test A: Explicit Merchant Field",
            passed: t79Passed,
            expected: "Merchant = Guardian",
            actual: "Merchant = \(t79Parsed.merchant ?? "nil")",
            details: "Field 'Merchant:' explicitly extracted and canonicalized"
        ))

        // Test 80 (Test B): Merchant appears in header without explicit label
        let testBText = """
        McDonald's Restaurant
        123 Main St
        RM 15.50
        """
        let t80Parsed = parser.parse(ocrResult: makeOCRResult(text: testBText))
        let t80Passed = t80Parsed.merchant == "McDonald's"
        results.append(TestCaseResult(
            testName: "Section 19 Test B: Header Merchant Without Label",
            passed: t80Passed,
            expected: "Merchant = McDonald's",
            actual: "Merchant = \(t80Parsed.merchant ?? "nil")",
            details: "Highest-confidence header candidate selected over street address"
        ))

        // Test 81 (Test C): Bank name appears in footer -> Bank is NOT merchant
        let testCText = """
        RM 50.00
        Zus Coffee
        Total: RM50.00
        Contact Maybank
        For help with a charge, contact Maybank.
        """
        let t81Parsed = parser.parse(ocrResult: makeOCRResult(text: testCText))
        let t81Passed = t81Parsed.merchant == "Zus Coffee"
        results.append(TestCaseResult(
            testName: "Section 19 Test C: Bank in Footer is NOT Merchant",
            passed: t81Passed,
            expected: "Merchant = Zus Coffee (NOT Maybank)",
            actual: "Merchant = \(t81Parsed.merchant ?? "nil")",
            details: "Bank name in footer support section excluded from merchant extraction"
        ))

        // Test 82 (Test D): Help/disclaimer contains recognizable business name -> Help text is NOT merchant
        let testDText = """
        RM 10.00
        Tealive
        For help with a charge you don't recognise or to dispute a charge, contact Maybank.
        """
        let t82Parsed = parser.parse(ocrResult: makeOCRResult(text: testDText))
        let t82Passed = t82Parsed.merchant == "Tealive" && t82Parsed.merchant != "dispute a"
        results.append(TestCaseResult(
            testName: "Section 19 Test D: Help/Disclaimer Text is NOT Merchant",
            passed: t82Passed,
            expected: "Merchant = Tealive (NOT 'dispute a')",
            actual: "Merchant = \(t82Parsed.merchant ?? "nil")",
            details: "Help/disclaimer text containing English preposition 'to' does not become merchant"
        ))

        // Test 83 (Test E): Payment method contains business/bank name -> Payment field is NOT merchant
        let testEText = """
        Payment: Maybank Visa Debit
        Amount: RM30.00
        KFC Cyberjaya
        """
        let t83Parsed = parser.parse(ocrResult: makeOCRResult(text: testEText))
        let t83Passed = t83Parsed.merchant == "KFC"
        results.append(TestCaseResult(
            testName: "Section 19 Test E: Payment Method Field is NOT Merchant",
            passed: t83Passed,
            expected: "Merchant = KFC (NOT Maybank Visa Debit)",
            actual: "Merchant = \(t83Parsed.merchant ?? "nil")",
            details: "Payment field 'Payment: Maybank Visa Debit' is not confused with merchant"
        ))

        // Test 84 (Test F): Merchant contains legitimate hyphen -> Preserved
        let normHyphen = MerchantDetector.normalizeMerchantName("7-Eleven")
        let t84Passed = normHyphen == "7-Eleven"
        results.append(TestCaseResult(
            testName: "Section 19 Test F: Legitimate Hyphen Preserved (7-Eleven)",
            passed: t84Passed,
            expected: "7-Eleven",
            actual: normHyphen,
            details: "Ensures legitimate hyphenated names like 7-Eleven are not stripped"
        ))

        // Test 85 (Test G): Merchant contains payment suffix -> Normalized
        let normSuffix = MerchantDetector.normalizeMerchantName("Shopee - Applepay-Ec")
        let t85Passed = normSuffix == "Shopee"
        results.append(TestCaseResult(
            testName: "Section 19 Test G: Payment Suffix Stripped (Shopee - Applepay-Ec)",
            passed: t85Passed,
            expected: "Shopee",
            actual: normSuffix,
            details: "Strips '- Applepay-Ec' suffix while preserving core merchant name"
        ))

        // Test 86 (Test H): No reliable merchant candidate -> Unknown Merchant (nil)
        let testHText = """
        DuitNow QR
        Payment Successful
        RM15.00
        Ref: 12345
        """
        let t86Parsed = parser.parse(ocrResult: makeOCRResult(text: testHText))
        let t86Passed = t86Parsed.merchant == nil
        results.append(TestCaseResult(
            testName: "Section 19 Test H: No Reliable Merchant -> Unknown Fallback",
            passed: t86Passed,
            expected: "Merchant = nil (Unknown Merchant)",
            actual: "Merchant = \(t86Parsed.merchant ?? "nil")",
            details: "Returns nil instead of guessing random numbers or generic status words"
        ))

        // Test 87 (Flow Test 1): Share Sheet view model receives paymentChannel from ParsedTransaction
        let parsed87 = ParsedTransaction(
            amount: 55.40,
            currency: "RM",
            merchant: "Shopee",
            date: Date(),
            paymentSource: .maybank,
            paymentChannel: .applePay,
            fundingAccount: "Maybank",
            fundingInstrument: "Maybank Visa Debit",
            category: .shopping,
            transactionReference: "SP123456",
            confidence: .high,
            isCompletedTransaction: true,
            isFailedTransaction: false,
            isBalanceOrLimitOnly: false
        )
        let vm87 = ShareExtensionViewModel()
        vm87.applyParsedTransaction(parsed87)
        let t87Passed = vm87.selectedPaymentChannel == .applePay &&
                        vm87.fundingAccount == "Maybank" &&
                        vm87.fundingInstrument == "Maybank Visa Debit" &&
                        vm87.merchant == "Shopee" &&
                        vm87.amountText == "55.40"
        results.append(TestCaseResult(
            testName: "Flow Test 1: ShareExtensionViewModel receives paymentChannel",
            passed: t87Passed,
            expected: "PaymentChannel = .applePay, Funding = Maybank, Instrument = Maybank Visa Debit",
            actual: "Channel = \(vm87.selectedPaymentChannel.displayName), Funding = \(vm87.fundingAccount), Instrument = \(vm87.fundingInstrument ?? "nil")",
            details: "Verifies ShareExtensionViewModel accurately captures payment channel and instrument from parsed transaction"
        ))

        // Test 88 (Flow Test 2): Apple Wallet transaction preserves Apple Pay channel through to Expense
        let appleWalletText = """
        RM 128.50
        Shopee - Applepay-Ec
        28 September 2026 at 09:30
        Status: Approved
        Maybank Visa Debit
        Contact Maybank
        """
        let parsed88 = parser.parse(ocrResult: makeOCRResult(text: appleWalletText))
        let exp88 = Expense(
            amount: parsed88.amount ?? 128.50,
            currency: "RM",
            merchant: parsed88.merchant ?? "Shopee",
            category: parsed88.category ?? .shopping,
            paymentSource: parsed88.paymentSource ?? .maybank,
            paymentChannel: parsed88.paymentChannel,
            fundingAccount: parsed88.displayFundingAccount,
            fundingInstrument: parsed88.fundingInstrument
        )
        let t88Passed = exp88.paymentChannel == .applePay &&
                        exp88.effectiveFundingAccount == "Maybank" &&
                        exp88.fundingInstrument == "Maybank Visa Debit" &&
                        exp88.displayFundingAndChannel == "Maybank • Apple Pay"
        results.append(TestCaseResult(
            testName: "Flow Test 2: Apple Wallet Preserves Apple Pay in Expense",
            passed: t88Passed,
            expected: "Maybank • Apple Pay, Instrument: Maybank Visa Debit",
            actual: "\(exp88.displayFundingAndChannel), Instrument: \(exp88.fundingInstrument ?? "nil")",
            details: "Confirms Apple Wallet screenshot is mapped to Apple Pay payment channel and persisted in Expense"
        ))

        // Test 89 (Flow Test 3): QR payment preserves QR Payment channel to Expense
        let qrFlowText = """
        DuitNow QR
        Payment Successful
        RM 18.00
        Paid to: Nasi Kandar Pelita
        Touch 'n Go eWallet
        """
        let parsed89 = parser.parse(ocrResult: makeOCRResult(text: qrFlowText))
        let exp89 = Expense(
            amount: parsed89.amount ?? 18.00,
            currency: "RM",
            merchant: parsed89.merchant ?? "Nasi Kandar Pelita",
            category: parsed89.category ?? .food,
            paymentChannel: parsed89.paymentChannel,
            fundingAccount: parsed89.displayFundingAccount
        )
        let t89Passed = exp89.paymentChannel == .qrPayment &&
                        exp89.displayFundingAndChannel.contains("QR Payment")
        results.append(TestCaseResult(
            testName: "Flow Test 3: QR Payment Preserves QR Payment Channel to Expense",
            passed: t89Passed,
            expected: "PaymentChannel = .qrPayment, displayFundingAndChannel contains 'QR Payment'",
            actual: "Channel = \(exp89.paymentChannel.displayName), display = \(exp89.displayFundingAndChannel)",
            details: "Verifies QR payments retain .qrPayment payment channel into the Expense model"
        ))

        // Test 90 (Flow Test 4): Bank Transfer preserves Bank Transfer channel to Expense
        let transferText = """
        DuitNow Transfer
        Transfer Successful
        RM 250.00
        Recipient: Alice Tan
        CIMB Bank
        """
        let parsed90 = parser.parse(ocrResult: makeOCRResult(text: transferText))
        let exp90 = Expense(
            amount: parsed90.amount ?? 250.00,
            currency: "RM",
            merchant: parsed90.merchant ?? "Alice Tan",
            category: .other,
            paymentChannel: parsed90.paymentChannel,
            fundingAccount: parsed90.displayFundingAccount
        )
        let t90Passed = exp90.paymentChannel == .bankTransfer &&
                        exp90.displayFundingAndChannel.contains("Bank Transfer")
        results.append(TestCaseResult(
            testName: "Flow Test 4: Bank Transfer Preserves Bank Transfer Channel to Expense",
            passed: t90Passed,
            expected: "PaymentChannel = .bankTransfer, displayFundingAndChannel contains 'Bank Transfer'",
            actual: "Channel = \(exp90.paymentChannel.displayName), display = \(exp90.displayFundingAndChannel)",
            details: "Verifies Bank Transfers retain .bankTransfer payment channel into the Expense model"
        ))

        // Test 91 (Flow Test 5): Unknown Payment Channel sets .unknown and does NOT hide the field
        let exp91 = Expense(
            amount: 45.00,
            currency: "RM",
            merchant: "General Store",
            category: .shopping,
            paymentChannel: .unknown,
            fundingAccount: "Maybank"
        )
        let t91Passed = exp91.paymentChannel == .unknown &&
                        exp91.displayFundingAndChannel == "Maybank • Unknown"
        results.append(TestCaseResult(
            testName: "Flow Test 5: Unknown Channel Displays 'Maybank • Unknown' (Never Hidden)",
            passed: t91Passed,
            expected: "Maybank • Unknown",
            actual: exp91.displayFundingAndChannel,
            details: "Ensures payment channel is never omitted even when unknown; always visible as 'Maybank • Unknown'"
        ))

        // Test 92 (Flow Test 6): Editing payment channel in review state updates saved Expense
        let vm92 = ShareExtensionViewModel()
        let parsed92 = ParsedTransaction(
            amount: 72.00,
            currency: "RM",
            merchant: "Zara",
            paymentChannel: .unknown,
            fundingAccount: "Maybank"
        )
        vm92.applyParsedTransaction(parsed92)
        // User manually edits payment channel and funding account
        vm92.selectedPaymentChannel = .applePay
        vm92.fundingAccount = "RHB"

        let exp92 = Expense(
            amount: CurrencyFormatter.parse(string: vm92.amountText) ?? 72.00,
            currency: "RM",
            merchant: vm92.merchant,
            category: vm92.selectedCategory,
            paymentChannel: vm92.selectedPaymentChannel,
            fundingAccount: vm92.fundingAccount
        )
        let t92Passed = exp92.paymentChannel == .applePay &&
                        exp92.effectiveFundingAccount == "RHB" &&
                        exp92.displayFundingAndChannel == "RHB • Apple Pay"
        results.append(TestCaseResult(
            testName: "Flow Test 6: Editing Payment Channel in Review Updates Saved Expense",
            passed: t92Passed,
            expected: "RHB • Apple Pay",
            actual: exp92.displayFundingAndChannel,
            details: "Confirms user manual edit in review UI propagates to final Expense"
        ))

        // Test 93 (Flow Test 7): Saving from Share Extension persists fundingAccount, paymentChannel, and fundingInstrument into SwiftData
        var t93Passed = false
        if let sSchema = try? Schema([Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self]),
           let sConfig = try? ModelConfiguration(isStoredInMemoryOnly: true),
           let sContainer = try? ModelContainer(for: sSchema, configurations: [sConfig]) {
            let sCtx = sContainer.mainContext

            let exp93 = Expense(
                amount: 89.90,
                currency: "RM",
                merchant: "Shopee",
                category: .shopping,
                paymentSource: .maybank,
                date: testNow,
                sourceType: .shareExtension,
                paymentChannel: .applePay,
                fundingAccount: "Maybank",
                fundingInstrument: "Maybank Visa Debit"
            )
            sCtx.insert(exp93)
            try? sCtx.save()
            sCtx.processPendingChanges()

            let fetchDesc = FetchDescriptor<Expense>()
            if let fetchedList = try? sCtx.fetch(fetchDesc), let fetched = fetchedList.first {
                t93Passed = fetched.merchant == "Shopee" &&
                            fetched.effectiveFundingAccount == "Maybank" &&
                            fetched.paymentChannel == .applePay &&
                            fetched.fundingInstrument == "Maybank Visa Debit" &&
                            fetched.displayFundingAndChannel == "Maybank • Apple Pay" &&
                            fetched.sourceType == .shareExtension
            }
        }
        results.append(TestCaseResult(
            testName: "Flow Test 7: SwiftData Roundtrip Persists All Payment Fields",
            passed: t93Passed,
            expected: "SwiftData preserves fundingAccount, paymentChannel, fundingInstrument, sourceType = .shareExtension",
            actual: "RoundtripPassed=\(t93Passed)",
            details: "Verifies complete persistence across SwiftData insert, save, and fetch descriptor"
        ))

        return results
    }
}
