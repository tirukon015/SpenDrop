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

        return results
    }
}
