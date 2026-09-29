import Foundation
import UIKit

public struct AmountCandidate {
    public let amount: Double
    public let line: String
    public let priority: Int
    public let hasCurrencyPrefix: Bool

    public init(amount: Double, line: String, priority: Int, hasCurrencyPrefix: Bool) {
        self.amount = amount
        self.line = line
        self.priority = priority
        self.hasCurrencyPrefix = hasCurrencyPrefix
    }
}

public final class TransactionParser {
    public static let shared = TransactionParser()

    public init() {}

    /// Parses OCRResult into a structured ParsedTransaction with normalized model and candidate classification
    public func parse(ocrResult: OCRResult, image: UIImage? = nil) -> ParsedTransaction {
        let fullText = ocrResult.fullText
        let lines = ocrResult.lines.map { $0.text }
        let lowerFull = fullText.lowercased()

        // 1. Automatic Bank / Payment Provider Detection (Issue 2)
        let providerResult = PaymentProviderDetector.detect(lines: lines, fullText: fullText)
        let detectedPaymentSource = providerResult.provider != .unknown ? providerResult.provider : detectPaymentSource(lowerFull: lowerFull)
        let normalizedProvider = providerResult.normalizedId
        let providerConfidence = providerResult.confidence
        let paymentMethod = providerResult.paymentMethod
        let underlyingBank = providerResult.underlyingBank
        let underlyingBankNormalizedId = providerResult.underlyingBankNormalizedId
        let fundingInstrument = providerResult.fundingInstrument
        let transactionSource = providerResult.detectedSource

        // Structured remark suggestion (Section 6)
        var suggestedRemark: String? = nil
        if providerResult.provider == .applePay || transactionSource == .appleWallet {
            if let bank = underlyingBank {
                suggestedRemark = "Paid via Apple Pay • \(bank.rawValue)"
            } else {
                suggestedRemark = "Paid via Apple Pay"
            }
        }

        // 2. Context Checks (Failed Transaction & Balance / Limit false positive protection)
        let isFailed = checkFailedTransaction(lowerFull)
        let isBalanceOrLimit = checkBalanceOrLimitOnly(lines: lines, lowerFull: lowerFull)

        // 3. Monetary Candidate Classification & Extraction (Issue 1, 3, 4)
        let (selectedAmount, amountConfidence, detectedCurrency, allCandidates) = extractAndClassifyAmounts(
            ocrResult: ocrResult,
            isBalanceOrLimit: isBalanceOrLimit,
            providerResult: providerResult
        )

        // 4. Detect Merchant & Suggested Category
        let (detectedMerchant, merchantCategory) = MerchantDetector.detect(lines: lines, fullText: fullText, recognizedLines: ocrResult.lines)
        let finalCategory = CategoryDetector.detect(text: fullText, detectedMerchant: detectedMerchant, merchantCategory: merchantCategory)

        // 5. Detect Date & Time with Normalized String Representations
        let (detectedDate, dateString, timeString) = extractDateTimeAndStrings(lines: lines, fullText: fullText)

        // 6. Extract Transaction Reference
        let transactionReference = extractReferenceNumber(lines: lines)

        // 7. Determine Transaction Context & Normalized Status
        let isCompleted = checkCompletedTransaction(lowerFull) && !isFailed && !isBalanceOrLimit
        let normalizedStatus = detectNormalizedStatus(lowerFull: lowerFull, isFailed: isFailed, isBalanceOrLimit: isBalanceOrLimit)

        // 8. Calculate Overall Confidence (Issue 5)
        var confidence: ParsingConfidence = .low
        if isBalanceOrLimit || isFailed {
            confidence = .low
        } else if isCompleted && selectedAmount != nil && selectedAmount! > 0 {
            if amountConfidence >= 0.85 && (detectedMerchant != nil || detectedPaymentSource != nil) {
                confidence = .high
            } else if amountConfidence >= 0.60 {
                confidence = .medium
            } else {
                confidence = .low
            }
        } else if selectedAmount != nil && selectedAmount! > 0 {
            confidence = amountConfidence >= 0.80 ? .medium : .low
        }

        var statusDisplayText = "Expense Detected"
        if isFailed {
            statusDisplayText = "Payment Failed"
        } else if isBalanceOrLimit {
            statusDisplayText = "Account Balance (Non-Expense)"
        } else if confidence == .low {
            statusDisplayText = "Possible Expense"
        }

        let detectedChannel = PaymentChannel.detect(from: fullText, paymentSource: detectedPaymentSource, paymentMethod: paymentMethod, detectedSource: transactionSource)
        let detectedFunding: String = underlyingBank?.rawValue ?? (detectedPaymentSource != .applePay && detectedPaymentSource != .qrPayment && detectedPaymentSource != .bankTransfer && detectedPaymentSource != .physicalCard && detectedPaymentSource != .unknown && detectedPaymentSource != nil ? detectedPaymentSource!.rawValue : "Unknown")

        var parsed = ParsedTransaction(
            amount: selectedAmount,
            amountConfidence: amountConfidence,
            currency: detectedCurrency,
            merchant: detectedMerchant,
            date: detectedDate,
            dateString: dateString,
            timeString: timeString,
            paymentSource: detectedPaymentSource,
            provider: normalizedProvider,
            providerConfidence: providerConfidence,
            paymentMethod: paymentMethod,
            paymentChannel: detectedChannel,
            fundingAccount: detectedFunding,
            fundingInstrument: fundingInstrument,
            underlyingBank: underlyingBank,
            underlyingBankNormalizedId: underlyingBankNormalizedId,
            suggestedRemark: suggestedRemark,
            category: finalCategory,
            transactionReference: transactionReference,
            transactionStatus: normalizedStatus,
            confidence: confidence,
            rawOCRText: fullText,
            detectedLines: lines,
            amountCandidates: allCandidates,
            originalImage: image,
            isCompletedTransaction: isCompleted,
            isFailedTransaction: isFailed,
            isBalanceOrLimitOnly: isBalanceOrLimit
        )

        // 9. Direction suggestion (additive; does not change any field above)
        let direction = DirectionDetector.detect(text: fullText)
        parsed.suggestedMovementKind = direction.kind
        parsed.directionReason = direction.reason
        return parsed
    }

    // MARK: - Amount Extraction & Semantic Classification (Issue 1, 4)

    public func extractAndClassifyAmounts(
        ocrResult: OCRResult,
        isBalanceOrLimit: Bool,
        providerResult: ProviderDetectionResult
    ) -> (amount: Double?, amountConfidence: Double, currency: String, candidates: [MonetaryCandidate]) {
        if isBalanceOrLimit {
            return (nil, 0.0, "RM", [])
        }

        let lines = ocrResult.lines
        let lineTexts = lines.map { $0.text }
        let totalLinesCount = max(lineTexts.count, 1)

        // Regex patterns for Malaysian Ringgit values
        let patterns = [
            #"(?:[-–—]\s*)?(?:RM|MYR)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))"#, // RM 22.00 or -RM12.00
            #"([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))\s*(?:RM|MYR)"#,              // 22.00 RM
            #"(?:[-–—]\s*)?(?:RM|MYR)\s*([0-9]+(?:\.[0-9]{2})?)"#,                  // RM450 or -RM12.00
            #"\b(?:Amount|Total|Jumlah|Paid)\s*[:\-]?\s*(?:[-–—]\s*)?(?:RM|MYR)?\s*([0-9]+(?:\.[0-9]{2})?)"#,
            #"(?:[-–—]\s*)?([0-9]{1,4}\.[0-9]{2})\b"#                             // Standalone decimal amount
        ]

        var rawFound: [(amount: Double, rawString: String, lineIndex: Int, lineText: String, boundingBox: CGRect, hasCurrency: Bool)] = []

        for (idx, ocrLine) in lines.enumerated() {
            let line = ocrLine.text
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    let matches = regex.matches(in: line, options: [], range: range)
                    for match in matches {
                        if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: line) {
                            let rawCapture = String(line[captureRange]).replacingOccurrences(of: ",", with: "")
                            if let val = Double(rawCapture), val > 0 && val < 500000 {
                                let hasCurr = line.uppercased().contains("RM") || line.uppercased().contains("MYR")
                                // Avoid duplicate candidate for the exact same amount on the exact same line
                                if !rawFound.contains(where: { $0.lineIndex == idx && abs($0.amount - val) < 0.001 }) {
                                    rawFound.append((val, line, idx, line, ocrLine.boundingBox, hasCurr))
                                }
                            }
                        }
                    }
                }
            }
        }

        guard !rawFound.isEmpty else {
            return (nil, 0.0, "RM", [])
        }

        // Promotional / Advertisement indicator keywords
        // Promotional / Advertisement indicator keywords
        let adKeywords = [
            "advertisement", "advert", "sponsored", "promo", "promotions", "promotion",
            "voucher", "vouchers", "deal", "deals", "discount", "discounts",
            "shop now", "buy now", "save up to", "cashback up to", "win up to", "reward",
            "panasonic", "samsung", "air conditioner", "appliances", "catalogue", "featured",
            "discover more", "explore more", "campaign", "contest", "banner",
            "terms & conditions", "terms and conditions", "t&c", "special offer", "exclusive offer",
            "apply now", "lucky draw", "claim now", "grab your", "hot deals", "best price",
            "minimum spend", "min spend", "min. spend", "gong cha", "gongcha",
            "baskin-robbins", "baskin robbins", "near me!", "near me", "validity:"
        ]

        // Fee keywords
        let feeKeywords = ["service fee", "processing fee", "fee", "caj perkhidmatan", "caj", "tax", "sst", "gst", "handling fee"]

        // Balance keywords
        let balanceKeywords = ["available balance", "account balance", "wallet balance", "baki akaun", "baki tersedia", "baki", "credit limit", "available credit"]

        // Cashback keywords
        let cashbackKeywords = ["cashback", "rebate", "rebat", "duit pulangan", "pulangan tunai"]

        // Discount keywords
        let discountKeywords = ["discount", "diskaun", "potongan", "voucher applied", "promo applied"]

        // Total keywords
        let totalKeywords = ["grand total", "total paid", "total amount", "total", "jumlah bayaran", "jumlah keseluruhan", "jumlah bersih", "net amount"]

        // Transaction amount keywords
        let transactionKeywords = [
            "amount transferred", "amount paid", "amount received", "payment amount",
            "transaction amount", "transfer amount", "amount", "transferred", "paid to",
            "receiver", "recipient", "bayar kepada", "jumlah pindahan", "diterima"
        ]

        var classifiedCandidates: [MonetaryCandidate] = []

        for candidate in rawFound {
            let lineIdx = candidate.lineIndex
            let lineTextLower = candidate.lineText.lowercased()

            // Nearby context window (-2 to +2 lines)
            let startIdx = max(0, lineIdx - 2)
            let endIdx = min(totalLinesCount - 1, lineIdx + 2)
            let nearbyLines = lineTexts[startIdx...endIdx].joined(separator: " ").lowercased()

            // Spatial positioning: In Vision coordinates, (0,0) is bottom-left, (1,1) is top-right.
            // If boundingBox is not available (e.g. zero), fallback to lineIndex relative to totalLines.
            let isNearBottom: Bool
            if candidate.boundingBox != .zero {
                isNearBottom = candidate.boundingBox.midY < 0.35 // Bottom 35% of the screen
            } else {
                isNearBottom = (Double(lineIdx) / Double(totalLinesCount)) > 0.65 // Lower 35% of lines
            }

            var semanticType: MonetarySemanticType = .unknown
            var score: Double = 0.50
            var reasoning: String = ""

            let wordsInLine = Set(lineTextLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
            let hasAdWordExact = wordsInLine.contains("ad") || wordsInLine.contains("ads") || wordsInLine.contains("promo") || wordsInLine.contains("off")

            // Rule 1: Balance check (current line or immediate preceding label)
            let isBalance = balanceKeywords.contains(where: { lineTextLower.contains($0) }) ||
                           (lineIdx > 0 && balanceKeywords.contains(where: { lineTexts[lineIdx - 1].lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix($0) }))
            if isBalance {
                semanticType = .balance
                score = 0.0
                reasoning = "Identified as balance / credit limit statement"
            }
            // Rule 2: Promotional / Advertisement check (Issue 1)
            else if hasAdWordExact ||
                    adKeywords.contains(where: { lineTextLower.contains($0) }) ||
                    (lineIdx > 0 && adKeywords.contains(where: { lineTexts[lineIdx - 1].lowercased().contains($0) })) ||
                    (lineIdx + 1 < totalLinesCount && adKeywords.contains(where: { lineTexts[lineIdx + 1].lowercased().contains($0) })) ||
                    (isNearBottom && adKeywords.contains(where: { nearbyLines.contains($0) })) {
                semanticType = .advertisement
                score = 0.0
                reasoning = "Identified as promotional advertisement / banner amount"
            }
            // Rule 3: Fee check (current line)
            else if feeKeywords.contains(where: { lineTextLower.contains($0) }) {
                semanticType = .fee
                score = 0.05
                reasoning = "Identified as service/processing fee"
            }
            // Rule 4: Cashback check (current line)
            else if cashbackKeywords.contains(where: { lineTextLower.contains($0) }) {
                semanticType = .cashback
                score = 0.05
                reasoning = "Identified as cashback or rebate reward"
            }
            // Rule 5: Discount check (current line)
            else if discountKeywords.contains(where: { lineTextLower.contains($0) }) {
                semanticType = .discount
                score = 0.05
                reasoning = "Identified as discount deduction"
            }
            // Rule 6: Total check (Highest priority in receipts/invoices)
            else if totalKeywords.contains(where: { lineTextLower.contains($0) }) && !lineTextLower.contains("subtotal") {
                semanticType = .total
                score = 0.98
                reasoning = "Identified as total payment amount"
            }
            // Rule 7: Transaction Amount (Explicit label or adjacent to status/receiver)
            else if transactionKeywords.contains(where: { lineTextLower.contains($0) }) {
                semanticType = .transactionAmount
                score = 0.96
                reasoning = "Explicitly labeled transaction amount"
            }
            // Rule 8: Unlabeled amount in primary transaction area (TNG, MAE, OCTO transfer screens)
            else {
                // Check if nearby lines indicate payment status ("transferred", "successful", "berjaya")
                let hasStatusNearby = ["transferred", "payment successful", "transfer successful", "successful", "berjaya"].contains {
                    nearbyLines.contains($0)
                }
                let hasReceiverNearby = ["receiver", "recipient", "paid to", "penerima"].contains {
                    nearbyLines.contains($0)
                }

                if hasStatusNearby && hasReceiverNearby {
                    semanticType = .transactionAmount
                    score = 0.97
                    reasoning = "Prominent amount between payment status and recipient"
                } else if hasStatusNearby || hasReceiverNearby {
                    semanticType = .transactionAmount
                    score = 0.90
                    reasoning = "Prominent amount near payment status or recipient"
                } else if candidate.hasCurrency && !isNearBottom {
                    semanticType = .transactionAmount
                    score = 0.75
                    reasoning = "Currency formatted amount in upper receipt area"
                } else {
                    semanticType = .unknown
                    score = isNearBottom ? 0.20 : 0.40
                    reasoning = "Unclassified monetary candidate"
                }
            }

            classifiedCandidates.append(MonetaryCandidate(
                amount: candidate.amount,
                currency: "RM",
                rawString: candidate.rawString,
                lineIndex: lineIdx,
                lineText: candidate.lineText,
                boundingBox: candidate.boundingBox,
                semanticType: semanticType,
                confidenceScore: score,
                reasoning: reasoning
            ))
        }

        // Exclude advertisement, balance, fee, cashback, discount amounts from being chosen
        let validCandidates = classifiedCandidates.filter { !$0.semanticType.isExcludedFromTransactionAmount }

        // Sort strategy:
        // 1. Total (.total) has priority over subtotal/fees
        // 2. Transaction Amount (.transactionAmount) with highest confidence score
        // 3. Score descending
        let sortedValid = validCandidates.sorted { c1, c2 in
            if c1.semanticType == .total && c2.semanticType != .total {
                return true
            }
            if c2.semanticType == .total && c1.semanticType != .total {
                return false
            }
            if abs(c1.confidenceScore - c2.confidenceScore) > 0.05 {
                return c1.confidenceScore > c2.confidenceScore
            }
            // If tied on confidence, prefer candidate with explicit currency prefix or higher amount in receipts
            return c1.confidenceScore > c2.confidenceScore
        }

        if let best = sortedValid.first {
            return (best.amount, best.confidenceScore, "RM", classifiedCandidates)
        }

        // Fallback: If all candidates were somehow excluded (e.g. only fees or raw digits), pick highest non-zero
        if let fallback = classifiedCandidates.max(by: { $0.confidenceScore < $1.confidenceScore }), fallback.confidenceScore > 0 {
            return (fallback.amount, fallback.confidenceScore * 0.5, "RM", classifiedCandidates)
        }

        return (nil, 0.0, "RM", classifiedCandidates)
    }

    // MARK: - Backward Compatible extractAmount

    public func extractAmount(lines: [String], isBalanceOrLimit: Bool) -> (Double?, String) {
        let textLines = lines.map { RecognizedTextLine(text: $0, confidence: 0.95) }
        let ocr = OCRResult(fullText: lines.joined(separator: "\n"), lines: textLines, averageConfidence: 0.95)
        let dummyProvider = ProviderDetectionResult(provider: .unknown, normalizedId: "unknown", confidence: 0.0, displayName: "Unknown")
        let res = extractAndClassifyAmounts(ocrResult: ocr, isBalanceOrLimit: isBalanceOrLimit, providerResult: dummyProvider)
        return (res.amount, res.currency)
    }

    // MARK: - Context Checks

    public func checkFailedTransaction(_ lowerText: String) -> Bool {
        let failedKeywords = [
            "payment failed", "transaction failed", "unsuccessful", "payment unsuccessful",
            "declined", "card declined", "gagal", "transaksi gagal", "rejected", "cancelled"
        ]
        return failedKeywords.contains { lowerText.contains($0) }
    }

    public func checkBalanceOrLimitOnly(lines: [String], lowerFull: String) -> Bool {
        let balanceKeywords = ["available balance", "account balance", "baki akaun", "baki tersedia", "current balance"]
        let limitKeywords = ["credit limit", "card limit", "had kredit", "available credit"]
        let pointsKeywords = ["reward points", "point balance", "points earned", "mata ganjaran", "my rewards", "rewards", "points expiring", " points"]

        let hasBalanceKeywords = balanceKeywords.contains { lowerFull.contains($0) }
        let hasLimitKeywords = limitKeywords.contains { lowerFull.contains($0) }
        let hasPointsOnly = pointsKeywords.contains { lowerFull.contains($0) }

        let transactionIndicators = ["paid", "payment successful", "purchase", "total", "amount paid", "transferred", "debit", "resit", "receipt", "invoice"]
        let hasTransactionIndicators = transactionIndicators.contains { lowerFull.contains($0) }

        if (hasBalanceKeywords || hasLimitKeywords || hasPointsOnly) && !hasTransactionIndicators {
            return true
        }

        return false
    }

    public func checkCompletedTransaction(_ lowerText: String) -> Bool {
        let completedKeywords = [
            "payment successful", "successful", "berjaya", "transaksi berjaya",
            "paid", "purchase", "transaction", "amount paid", "total", "jumlah",
            "transferred", "transfer successful", "debit", "approved", "receipt", "tax invoice"
        ]
        return completedKeywords.contains { lowerText.contains($0) }
    }

    public func detectNormalizedStatus(lowerFull: String, isFailed: Bool, isBalanceOrLimit: Bool) -> String {
        if isFailed {
            return "failed"
        }
        if isBalanceOrLimit {
            return "balance_inquiry"
        }
        if lowerFull.contains("transferred") || lowerFull.contains("transfer successful") {
            return "transferred"
        }
        if lowerFull.contains("payment successful") || lowerFull.contains("paid") || lowerFull.contains("berjaya") {
            return "payment_successful"
        }
        if lowerFull.contains("approved") {
            return "approved"
        }
        return "completed"
    }

    // MARK: - Payment Source Detection (Backward Compatible)

    public func detectPaymentSource(lowerFull: String) -> PaymentSource? {
        if lowerFull.contains("touch 'n go") || lowerFull.contains("tng ewallet") || lowerFull.contains("tng digital") || lowerFull.contains("touch n go") {
            return .touchNGo
        }
        if lowerFull.contains("maybank") || lowerFull.contains("mae by maybank2u") || lowerFull.contains("maybank2u") || lowerFull.contains("m2u") {
            return .maybank
        }
        if lowerFull.contains("cimb") || lowerFull.contains("cimb clicks") || lowerFull.contains("cimb octo") {
            return .cimb
        }
        if lowerFull.contains("rhb") || lowerFull.contains("rhb now") || lowerFull.contains("rhb mobile") {
            return .rhb
        }
        if lowerFull.contains("public bank") || lowerFull.contains("pbe") || lowerFull.contains("pb engage") {
            return .publicBank
        }
        if lowerFull.contains("bank islam") || lowerFull.contains("bimb") {
            return .bankIslam
        }
        if lowerFull.contains("grabpay") || lowerFull.contains("grab pay") {
            return .grabPay
        }
        if lowerFull.contains("boost") {
            return .boost
        }
        if lowerFull.contains("duitnow qr") || lowerFull.contains("paynet qr") || lowerFull.contains("qr pay") {
            return .qrPayment
        }
        if lowerFull.contains("duitnow transfer") || lowerFull.contains("duitnow") {
            return .duitNow
        }
        if lowerFull.contains("apple pay") || lowerFull.contains("apple wallet") {
            return .applePay
        }
        if lowerFull.contains("visa") || lowerFull.contains("mastercard") || lowerFull.contains("credit card") || lowerFull.contains("debit card") {
            return .physicalCard
        }
        if lowerFull.contains("interbank transfer") || lowerFull.contains("bank transfer") || lowerFull.contains("ibg") {
            return .bankTransfer
        }
        if lowerFull.contains("cash") || lowerFull.contains("tunai") {
            return .cash
        }
        return nil
    }

    // MARK: - Date & Time Extraction

    public func extractDateTime(lines: [String], fullText: String) -> Date? {
        return extractDateTimeAndStrings(lines: lines, fullText: fullText).date
    }

    public func extractDateTimeAndStrings(lines: [String], fullText: String) -> (date: Date?, dateString: String?, timeString: String?) {
        let calendar = Calendar.current

        let dateFormats = [
            "dd MMM yyyy",
            "dd MMMM yyyy",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "dd-MMM-yyyy",
            "yyyy-MM-dd",
            "dd/MM/yy",
            "MMM dd, yyyy",
            "dd MMM yy"
        ]

        let timeFormats = [
            "h:mm:ss a",
            "h:mm a",
            "h:mma",
            "h:mm:ssa",
            "HH:mm:ss",
            "HH:mm"
        ]

        var detectedDateComponents: DateComponents?
        var detectedTimeComponents: DateComponents?

        for line in lines {
            // Strip common label prefixes
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefixesToStrip = ["date:", "date :", "tarikh:", "tarikh :", "time:", "time :", "masa:", "masa :"]
            for p in prefixesToStrip {
                if cleaned.lowercased().hasPrefix(p) {
                    cleaned = String(cleaned.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            let cleanedDate = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))

            // Test date formats
            if detectedDateComponents == nil {
                for fmt in dateFormats {
                    let df = DateFormatter()
                    df.dateFormat = fmt
                    df.locale = Locale(identifier: "en_US_POSIX")
                    if let d = df.date(from: cleanedDate) {
                        detectedDateComponents = calendar.dateComponents([.year, .month, .day], from: d)
                        break
                    }
                }
            }

            // Test time formats
            if detectedTimeComponents == nil {
                for fmt in timeFormats {
                    let tf = DateFormatter()
                    tf.dateFormat = fmt
                    tf.locale = Locale(identifier: "en_US_POSIX")
                    if let t = tf.date(from: cleaned) {
                        detectedTimeComponents = calendar.dateComponents([.hour, .minute, .second], from: t)
                        break
                    }
                }
            }
        }

        // Regex fallback for embedded dates in full text
        if detectedDateComponents == nil {
            let regexPattern = #"\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\b"#
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) {
                let range = NSRange(fullText.startIndex..<fullText.endIndex, in: fullText)
                if let match = regex.firstMatch(in: fullText, options: [], range: range),
                   let r = Range(match.range(at: 1), in: fullText) {
                    let matchedString = String(fullText[r])
                    for fmt in dateFormats {
                        let df = DateFormatter()
                        df.dateFormat = fmt
                        df.locale = Locale(identifier: "en_US_POSIX")
                        if let d = df.date(from: matchedString) {
                            detectedDateComponents = calendar.dateComponents([.year, .month, .day], from: d)
                            break
                        }
                    }
                }
            }
        }

        // Regex fallback for embedded time in full text
        if detectedTimeComponents == nil {
            let timeRegexPattern = #"\b(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp][Mm])?)\b"#
            if let regex = try? NSRegularExpression(pattern: timeRegexPattern, options: []) {
                let range = NSRange(fullText.startIndex..<fullText.endIndex, in: fullText)
                let matches = regex.matches(in: fullText, options: [], range: range)
                for match in matches {
                    if let r = Range(match.range(at: 1), in: fullText) {
                        let matchedTime = String(fullText[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                        for fmt in timeFormats {
                            let tf = DateFormatter()
                            tf.dateFormat = fmt
                            tf.locale = Locale(identifier: "en_US_POSIX")
                            if let t = tf.date(from: matchedTime) {
                                detectedTimeComponents = calendar.dateComponents([.hour, .minute, .second], from: t)
                                break
                            }
                        }
                        if detectedTimeComponents != nil { break }
                    }
                }
            }
        }

        var finalComponents = DateComponents()
        var dateFormattedStr: String? = nil
        var timeFormattedStr: String? = nil

        if let d = detectedDateComponents {
            finalComponents.year = d.year
            finalComponents.month = d.month
            finalComponents.day = d.day

            if let y = d.year, let m = d.month, let day = d.day {
                dateFormattedStr = String(format: "%04d-%02d-%02d", y, m, day)
            }
        } else {
            return (nil, nil, nil)
        }

        if let t = detectedTimeComponents {
            finalComponents.hour = t.hour
            finalComponents.minute = t.minute
            finalComponents.second = t.second ?? 0

            if let h = t.hour, let min = t.minute {
                let sec = t.second ?? 0
                timeFormattedStr = String(format: "%02d:%02d:%02d", h, min, sec)
            }
        } else {
            finalComponents.hour = 12
            finalComponents.minute = 0
            finalComponents.second = 0
        }

        let combinedDate = calendar.date(from: finalComponents)
        return (combinedDate, dateFormattedStr, timeFormattedStr)
    }

    // MARK: - Transaction Reference Extraction

    public func extractReferenceNumber(lines: [String]) -> String? {
        let patterns = [
            #"(?:ref(?:\.|erence)?\s*(?:no|id)?|trans(?:action)?\s*(?:id|no)|receipt\s*(?:no|#)?|no\.\s*rujukan)\s*[:\-]?\s*([A-Za-z0-9\-]{6,30})"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for line in lines {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range),
                       match.numberOfRanges > 1,
                       let captureRange = Range(match.range(at: 1), in: line) {
                        return String(line[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return nil
    }
}
