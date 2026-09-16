import Foundation
import UIKit

public struct AmountCandidate {
    public let amount: Double
    public let line: String
    public let priority: Int // Higher is better (e.g. Total = 10, Amount = 8, Subtotal = 3, Balance = -100)
    public let hasCurrencyPrefix: Bool
}

public final class TransactionParser {
    public static let shared = TransactionParser()

    public init() {}

    /// Parses OCRResult into a structured ParsedTransaction
    public func parse(ocrResult: OCRResult, image: UIImage? = nil) -> ParsedTransaction {
        let fullText = ocrResult.fullText
        let lines = ocrResult.lines.map { $0.text }
        let lowerFull = fullText.lowercased()

        // 1. Check for Failed Transaction
        let isFailed = checkFailedTransaction(lowerFull)

        // 2. Check for Balance / Limit Only screenshot (False Positive Protection)
        let isBalanceOrLimit = checkBalanceOrLimitOnly(lines: lines, lowerFull: lowerFull)

        // 3. Detect Amount
        let (amount, detectedCurrency) = extractAmount(lines: lines, isBalanceOrLimit: isBalanceOrLimit)

        // 4. Detect Payment Source
        let paymentSource = detectPaymentSource(lowerFull: lowerFull)

        // 5. Detect Merchant & Suggested Category
        let (detectedMerchant, merchantCategory) = MerchantDetector.detect(lines: lines, fullText: fullText)
        let finalCategory = CategoryDetector.detect(text: fullText, detectedMerchant: detectedMerchant, merchantCategory: merchantCategory)

        // 6. Detect Date & Time
        let detectedDate = extractDateTime(lines: lines, fullText: fullText)

        // 7. Extract Transaction Reference
        let transactionReference = extractReferenceNumber(lines: lines)

        // 8. Determine Transaction Context & Status
        let isCompleted = checkCompletedTransaction(lowerFull) && !isFailed && !isBalanceOrLimit

        // 9. Calculate Overall Confidence
        var confidence: ParsingConfidence = .low
        if isBalanceOrLimit || isFailed {
            confidence = .low
        } else if isCompleted && amount != nil && amount! > 0 {
            if detectedMerchant != nil && paymentSource != nil {
                confidence = .high
            } else if detectedMerchant != nil || paymentSource != nil {
                confidence = .medium
            } else {
                confidence = .medium
            }
        } else if amount != nil && amount! > 0 {
            confidence = .low
        }

        var statusText = "Expense Detected"
        if isFailed {
            statusText = "Payment Failed"
        } else if isBalanceOrLimit {
            statusText = "Account Balance (Non-Expense)"
        } else if confidence == .low {
            statusText = "Possible Expense"
        }

        return ParsedTransaction(
            amount: amount,
            currency: detectedCurrency,
            merchant: detectedMerchant,
            date: detectedDate,
            paymentSource: paymentSource,
            category: finalCategory,
            transactionReference: transactionReference,
            transactionStatus: statusText,
            confidence: confidence,
            rawOCRText: fullText,
            detectedLines: lines,
            originalImage: image,
            isCompletedTransaction: isCompleted,
            isFailedTransaction: isFailed,
            isBalanceOrLimitOnly: isBalanceOrLimit
        )
    }

    // MARK: - Context Checks

    private func checkFailedTransaction(_ lowerText: String) -> Bool {
        let failedKeywords = [
            "payment failed", "transaction failed", "unsuccessful", "payment unsuccessful",
            "declined", "card declined", "gagal", "transaksi gagal", "rejected", "cancelled"
        ]
        return failedKeywords.contains { lowerText.contains($0) }
    }

    private func checkBalanceOrLimitOnly(lines: [String], lowerFull: String) -> Bool {
        let balanceKeywords = ["available balance", "account balance", "baki akaun", "baki tersedia", "current balance"]
        let limitKeywords = ["credit limit", "card limit", "had kredit", "available credit"]
        let pointsKeywords = ["reward points", "point balance", "points earned", "mata ganjaran"]

        // If explicitly a balance or limit or points statement without transaction context
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

    private func checkCompletedTransaction(_ lowerText: String) -> Bool {
        let completedKeywords = [
            "payment successful", "successful", "berjaya", "transaksi berjaya",
            "paid", "purchase", "transaction", "amount paid", "total", "jumlah",
            "transferred", "transfer successful", "debit", "approved", "receipt", "tax invoice"
        ]
        return completedKeywords.contains { lowerText.contains($0) }
    }

    // MARK: - Amount Extraction

    public func extractAmount(lines: [String], isBalanceOrLimit: Bool) -> (Double?, String) {
        if isBalanceOrLimit {
            return (nil, "RM")
        }

        var candidates: [AmountCandidate] = []

        // Regex patterns for Malaysian Ringgit:
        // RM25.90, RM 25.90, MYR 25.90, 25.90 MYR, 25.90, 1,250.00
        let currencyPatterns = [
            #"(?:RM|MYR)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))"#, // RM 25.90 or RM 1,250.00
            #"([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))\s*(?:RM|MYR)"#, // 25.90 RM
            #"(?:RM|MYR)\s*([0-9]+(?:\.[0-9]{2})?)"#,                  // RM25 or RM25.90
            #"Amount\s*[:\-]?\s*([0-9]+(?:\.[0-9]{2}))"#,             // Amount: 25.90
            #"Total\s*[:\-]?\s*([0-9]+(?:\.[0-9]{2}))"#               // Total: 25.90
        ]

        for line in lines {
            let lowerLine = line.lowercased()

            // Skip lines that indicate balance, reward points, limit, phone, or account number
            if lowerLine.contains("balance") || lowerLine.contains("baki") ||
               lowerLine.contains("limit") || lowerLine.contains("point") ||
               lowerLine.contains("account no") || lowerLine.contains("card no") ||
               lowerLine.contains("phone") || lowerLine.contains("tel:") {
                continue
            }

            var priority = 0
            if lowerLine.contains("total") || lowerLine.contains("grand total") || lowerLine.contains("jumlah") || lowerLine.contains("amount paid") {
                priority = 10
            } else if lowerLine.contains("paid") || lowerLine.contains("payment") || lowerLine.contains("amount") {
                priority = 7
            } else if lowerLine.contains("subtotal") || lowerLine.contains("tax") || lowerLine.contains("sst") || lowerLine.contains("service") {
                priority = 2 // Subtotals and tax have lower priority than grand total
            } else {
                priority = 4
            }

            // Test currency patterns
            for pattern in currencyPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    let matches = regex.matches(in: line, options: [], range: range)
                    for match in matches {
                        if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: line) {
                            let rawValue = String(line[captureRange]).replacingOccurrences(of: ",", with: "")
                            if let val = Double(rawValue), val > 0 && val < 500000 {
                                candidates.append(AmountCandidate(
                                    amount: val,
                                    line: line,
                                    priority: priority + (line.uppercased().contains("RM") || line.uppercased().contains("MYR") ? 3 : 0),
                                    hasCurrencyPrefix: line.uppercased().contains("RM") || line.uppercased().contains("MYR")
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Also test stand-alone decimal numbers if no currency prefix candidate was found with high priority
        if candidates.isEmpty {
            let standalonePattern = #"\b([0-9]{1,4}\.[0-9]{2})\b"#
            if let regex = try? NSRegularExpression(pattern: standalonePattern, options: []) {
                for line in lines {
                    let lowerLine = line.lowercased()
                    if lowerLine.contains("balance") || lowerLine.contains("limit") || lowerLine.contains("date") || lowerLine.contains("time") {
                        continue
                    }
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    let matches = regex.matches(in: line, options: [], range: range)
                    for match in matches {
                        if let captureRange = Range(match.range(at: 1), in: line) {
                            let rawValue = String(line[captureRange])
                            if let val = Double(rawValue), val > 0 && val < 500000 {
                                candidates.append(AmountCandidate(
                                    amount: val,
                                    line: line,
                                    priority: 1,
                                    hasCurrencyPrefix: false
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Sort candidates: highest priority first, and if tied, highest amount (e.g. Total vs Subtotal)
        let sorted = candidates.sorted { c1, c2 in
            if c1.priority != c2.priority {
                return c1.priority > c2.priority
            }
            return c1.amount > c2.amount
        }

        if let best = sorted.first {
            return (best.amount, "RM")
        }

        return (nil, "RM")
    }

    // MARK: - Payment Source Detection

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
        if lowerFull.contains("apple pay") || lowerFull.contains("apple wallet") {
            return .applePay
        }
        if lowerFull.contains("duitnow qr") || lowerFull.contains("qr pay") || lowerFull.contains("paynet qr") || lowerFull.contains("scan qr") {
            return .qrPayment
        }
        if lowerFull.contains("visa") || lowerFull.contains("mastercard") || lowerFull.contains("credit card") || lowerFull.contains("debit card") {
            return .physicalCard
        }
        if lowerFull.contains("duitnow transfer") || lowerFull.contains("interbank transfer") || lowerFull.contains("bank transfer") || lowerFull.contains("ibg") {
            return .bankTransfer
        }
        if lowerFull.contains("cash") || lowerFull.contains("tunai") {
            return .cash
        }
        return nil
    }

    // MARK: - Date & Time Extraction

    public func extractDateTime(lines: [String], fullText: String) -> Date? {
        let calendar = Calendar.current

        // Date patterns:
        // 16 Sep 2026, 16 September 2026, 16/09/2026, 16-09-2026, 2026-09-16
        let dateFormats = [
            "dd MMM yyyy",
            "dd MMMM yyyy",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "yyyy-MM-dd",
            "dd/MM/yy",
            "MMM dd, yyyy"
        ]

        let timeFormats = [
            "h:mm:ss a",
            "h:mm a",
            "HH:mm:ss",
            "HH:mm"
        ]

        var detectedDateComponents: DateComponents?
        var detectedTimeComponents: DateComponents?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Try date formats
            if detectedDateComponents == nil {
                for fmt in dateFormats {
                    let df = DateFormatter()
                    df.dateFormat = fmt
                    df.locale = Locale(identifier: "en_US_POSIX")
                    if let d = df.date(from: trimmed) {
                        detectedDateComponents = calendar.dateComponents([.year, .month, .day], from: d)
                        break
                    }
                }
            }

            // Try time formats
            if detectedTimeComponents == nil {
                for fmt in timeFormats {
                    let tf = DateFormatter()
                    tf.dateFormat = fmt
                    tf.locale = Locale(identifier: "en_US_POSIX")
                    if let t = tf.date(from: trimmed) {
                        detectedTimeComponents = calendar.dateComponents([.hour, .minute, .second], from: t)
                        break
                    }
                }
            }
        }

        // If not matched per line, use regex for embedded date and time
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

        // Combine date and time if found
        var finalComponents = DateComponents()
        if let d = detectedDateComponents {
            finalComponents.year = d.year
            finalComponents.month = d.month
            finalComponents.day = d.day
        } else {
            return nil
        }

        if let t = detectedTimeComponents {
            finalComponents.hour = t.hour
            finalComponents.minute = t.minute
            finalComponents.second = t.second ?? 0
        } else {
            finalComponents.hour = 12
            finalComponents.minute = 0
            finalComponents.second = 0
        }

        return calendar.date(from: finalComponents)
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
