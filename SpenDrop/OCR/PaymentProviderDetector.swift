import Foundation

/// Identifies the source/provenance of an OCR text (e.g. Apple Wallet UI vs bank app receipt)
public enum DetectedTransactionSource: String {
    case appleWallet = "APPLE_WALLET"
    case bankApp = "BANK_APP"
    case physicalReceipt = "PHYSICAL_RECEIPT"
    case unknown = "UNKNOWN"
}

public struct ProviderDetectionResult {
    public let provider: PaymentSource
    public let normalizedId: String
    public let confidence: Double
    public let displayName: String
    public let underlyingBank: PaymentSource?
    public let underlyingBankNormalizedId: String?
    public let paymentMethod: String
    public let fundingInstrument: String?
    public let detectedSource: DetectedTransactionSource

    public init(
        provider: PaymentSource,
        normalizedId: String,
        confidence: Double,
        displayName: String,
        underlyingBank: PaymentSource? = nil,
        underlyingBankNormalizedId: String? = nil,
        paymentMethod: String? = nil,
        fundingInstrument: String? = nil,
        detectedSource: DetectedTransactionSource = .unknown
    ) {
        self.provider = provider
        self.normalizedId = normalizedId
        self.confidence = confidence
        self.displayName = displayName
        self.underlyingBank = underlyingBank
        self.underlyingBankNormalizedId = underlyingBankNormalizedId
        self.paymentMethod = paymentMethod ?? provider.defaultPaymentMethod
        self.fundingInstrument = fundingInstrument
        self.detectedSource = detectedSource
    }
}

public struct PaymentProviderDetector {
    public static func detect(lines: [String], fullText: String) -> ProviderDetectionResult {
        let lowerFull = fullText.lowercased()

        // PRIORITY 1: Apple Wallet Provenance Detection (structural UI markers)
        // Apple Wallet transaction detail screens contain distinctive markers:
        //   - "Wallet uses Maps to provide merchant name, category and location"
        //   - "Report Incorrect Merchant Info"
        //   - "Status: Approved" + "Contact <Bank>"
        let hasWalletMaps = lowerFull.contains("wallet uses maps")
        let hasReportMerchant = lowerFull.contains("report incorrect merchant info")
        let hasStatusApproved = lowerFull.contains("status: approved") || lowerFull.contains("status:approved")
        let hasContactBank = lowerFull.contains("contact maybank") || lowerFull.contains("contact cimb") ||
                              lowerFull.contains("contact rhb") || lowerFull.contains("contact public bank") ||
                              lowerFull.contains("contact bank islam") || lowerFull.contains("contact ambank") ||
                              lowerFull.contains("contact hong leong") || lowerFull.contains("contact wise")

        let isAppleWalletUI = hasWalletMaps || (hasReportMerchant && hasStatusApproved) || (hasStatusApproved && hasContactBank)

        if isAppleWalletUI {
            // Extract funding instrument from card line (e.g. "Maybank Visa Debit")
            let (walletBank, walletBankId, walletInstrument) = extractFundingInstrumentFromLines(lines: lines, lowerFull: lowerFull)

            let displayName: String
            if let bank = walletBank {
                displayName = "Apple Pay • \(bank.rawValue)"
            } else {
                displayName = "Apple Pay"
            }

            return ProviderDetectionResult(
                provider: walletBank ?? .applePay,
                normalizedId: walletBankId ?? "apple_pay",
                confidence: 0.99,
                displayName: displayName,
                underlyingBank: walletBank,
                underlyingBankNormalizedId: walletBankId,
                paymentMethod: "digital_wallet",
                fundingInstrument: walletInstrument,
                detectedSource: .appleWallet
            )
        }

        // PRIORITY 2: Explicit Apple Pay text (e.g. "Apple Pay", "Apple Wallet" in non-Wallet-UI contexts)
        let applePayKeywords = ["apple pay", "pay with apple", "apple cash"]
        let hasApplePay = applePayKeywords.contains(where: { lowerFull.contains($0) })

        if hasApplePay {
            var detectedUnderlyingBank: PaymentSource? = nil
            var underlyingId: String? = nil

            if lowerFull.contains("cimb") || lowerFull.contains("octo") {
                detectedUnderlyingBank = .cimb
                underlyingId = "cimb"
            } else if lowerFull.contains("maybank") || lowerFull.contains("mae") || lowerFull.contains("m2u") {
                detectedUnderlyingBank = .maybank
                underlyingId = "maybank"
            } else if lowerFull.contains("rhb") {
                detectedUnderlyingBank = .rhb
                underlyingId = "rhb"
            } else if lowerFull.contains("public bank") || lowerFull.contains("pb engage") {
                detectedUnderlyingBank = .publicBank
                underlyingId = "public_bank"
            } else if lowerFull.contains("bank islam") || lowerFull.contains("bimb") {
                detectedUnderlyingBank = .bankIslam
                underlyingId = "bank_islam"
            } else if lowerFull.contains("wise") || lowerFull.contains("transferwise") {
                detectedUnderlyingBank = .wise
                underlyingId = "wise"
            }

            let (_, _, instrument) = extractFundingInstrumentFromLines(lines: lines, lowerFull: lowerFull)

            let displayName: String
            if let bank = detectedUnderlyingBank {
                displayName = "Apple Pay • \(bank.rawValue)"
            } else {
                displayName = "Apple Pay"
            }

            return ProviderDetectionResult(
                provider: .applePay,
                normalizedId: "apple_pay",
                confidence: 0.98,
                displayName: displayName,
                underlyingBank: detectedUnderlyingBank,
                underlyingBankNormalizedId: underlyingId,
                paymentMethod: "digital_wallet",
                fundingInstrument: instrument
            )
        }

        // 2. Identify Recipient Banks to avoid misidentifying the destination bank as the sender provider
        var recipientBankIds: Set<String> = []
        for (idx, line) in lines.enumerated() {
            let lower = line.lowercased()
            let isRecipientHeader = lower.contains("receiving bank") ||
                                    lower.contains("recipient bank") ||
                                    lower.contains("beneficiary bank") ||
                                    lower.contains("to bank") ||
                                    lower.contains("recipient bank/e-wallet") ||
                                    lower.contains("bank/e-wallet")

            if isRecipientHeader {
                var candidateLines = [lower]
                if idx + 1 < lines.count { candidateLines.append(lines[idx + 1].lowercased()) }
                if idx + 2 < lines.count { candidateLines.append(lines[idx + 2].lowercased()) }
                for cl in candidateLines {
                    if cl.contains("maybank") || cl.contains("mbb") { recipientBankIds.insert("maybank") }
                    if cl.contains("cimb") { recipientBankIds.insert("cimb") }
                    if cl.contains("rhb") { recipientBankIds.insert("rhb") }
                    if cl.contains("public bank") || cl.contains("pbb") { recipientBankIds.insert("public_bank") }
                    if cl.contains("bank islam") || cl.contains("bimb") { recipientBankIds.insert("bank_islam") }
                }
            }

            // Also check key-value pair where line is "Bank" and next line is the bank name (e.g. RHB receipt)
            if lower.trimmingCharacters(in: .whitespacesAndNewlines) == "bank" && idx + 1 < lines.count {
                let next = lines[idx + 1].lowercased()
                if next.contains("cimb") { recipientBankIds.insert("cimb") }
                if next.contains("maybank") { recipientBankIds.insert("maybank") }
                if next.contains("rhb") { recipientBankIds.insert("rhb") }
                if next.contains("public bank") { recipientBankIds.insert("public_bank") }
                if next.contains("bank islam") { recipientBankIds.insert("bank_islam") }
            }
        }

        // 3. Sender Explicit Source Detection (from header lines, 'From' account, or notification prefixes)
        let headerLines = lines.prefix(5).map { $0.lowercased() }
        let headerText = headerLines.joined(separator: " ")

        // Check if "From" field specifies the sender account
        var fromAccountText = ""
        for (idx, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lower == "from" || lower.hasPrefix("from:") || lower.hasPrefix("from ") {
                var gathered = [lower]
                if idx + 1 < lines.count { gathered.append(lines[idx + 1].lowercased()) }
                if idx + 2 < lines.count { gathered.append(lines[idx + 2].lowercased()) }
                fromAccountText = gathered.joined(separator: " ")
                break
            }
        }

        // Determine specific payment method
        let detectedMethod = detectPaymentMethod(lowerFull: lowerFull)

        // SENDER DETECTION RULE 1: RHB
        let isRHBSender = fromAccountText.contains("rhb") ||
                          headerText.contains("rhb") ||
                          lowerFull.contains("rhb smart account") ||
                          lowerFull.contains("rhb reflex") ||
                          lowerFull.contains("rhb mobile") ||
                          lowerFull.contains("rhb now") ||
                          (lowerFull.contains("rhb") && !recipientBankIds.contains("rhb"))

        if isRHBSender && !fromAccountText.contains("cimb") && !fromAccountText.contains("maybank") {
            let method = detectedMethod ?? "bank_transfer"
            return ProviderDetectionResult(
                provider: .rhb,
                normalizedId: "rhb",
                confidence: 0.98,
                displayName: "RHB Bank",
                underlyingBank: .rhb,
                underlyingBankNormalizedId: "rhb",
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE 2: CIMB
        let isCIMBSender = fromAccountText.contains("cimb") ||
                           fromAccountText.contains("savings acct-i") ||
                           fromAccountText.contains("current acct-i") ||
                           headerText.contains("cimb") ||
                           headerText.contains("octo") ||
                           lowerFull.contains("cimb:") ||
                           lowerFull.contains("cimb octo") ||
                           lowerFull.contains("cimb clicks") ||
                           lowerFull.contains("cimb bank") ||
                           lowerFull.contains("octo reference no") ||
                           lowerFull.contains("with octo") ||
                           lowerFull.contains("savings acct-i plus") ||
                           (lowerFull.contains("cimb") && !recipientBankIds.contains("cimb"))

        if isCIMBSender && !fromAccountText.contains("maybank") {
            let method = detectedMethod ?? "bank_transfer"
            return ProviderDetectionResult(
                provider: .cimb,
                normalizedId: "cimb",
                confidence: 0.98,
                displayName: "CIMB Bank",
                underlyingBank: .cimb,
                underlyingBankNormalizedId: "cimb",
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE 3: Maybank / MAE
        let isMaybankSender = fromAccountText.contains("maybank") ||
                              fromAccountText.contains("mae") ||
                              headerText.contains("maybank") ||
                              headerText.contains("mae") ||
                              lowerFull.contains("mae by maybank2u") ||
                              lowerFull.contains("maybank2u") ||
                              lowerFull.contains("malayan banking") ||
                              lowerFull.contains("maybank islamic") ||
                              (lowerFull.contains("maybank") && !recipientBankIds.contains("maybank")) ||
                              (lowerFull.contains("mae") && (lowerFull.contains("scan & pay") || lowerFull.contains("duitnow") || lowerFull.contains("transfer")))

        if isMaybankSender {
            let (_, _, instrument) = extractFundingInstrumentFromLines(lines: lines, lowerFull: lowerFull)
            let isCard = instrument != nil || lowerFull.contains("debit card") || lowerFull.contains("credit card")
            let method = detectedMethod ?? (isCard ? "unknown" : "bank_transfer")
            return ProviderDetectionResult(
                provider: .maybank,
                normalizedId: "maybank",
                confidence: 0.98,
                displayName: "Maybank / MAE",
                underlyingBank: .maybank,
                underlyingBankNormalizedId: "maybank",
                paymentMethod: method,
                fundingInstrument: instrument
            )
        }

        // SENDER DETECTION RULE 4: Touch 'n Go eWallet
        let tngKeywords = [
            "touch 'n go ewallet", "touch 'n go", "touch n go", "tng ewallet",
            "tng digital", "tng reload pin", "tng card", "tng rfid", "go+", "goleader"
        ]
        let isTNGSender = tngKeywords.contains(where: { lowerFull.contains($0) }) ||
                          headerText.contains("touch 'n go") ||
                          headerText.contains("touch n go") ||
                          lowerFull.contains("transfer to wallet") ||
                          lowerFull.contains("ewallet balance") ||
                          lowerFull.contains("tngdmynb") ||
                          lowerFull.contains("near me!") ||
                          (lowerFull.contains("transferred") && (lowerFull.contains("receiver") || lowerFull.contains("fund transfer")) && lowerFull.contains("done")) ||
                          (lowerFull.contains("tng") && (lowerFull.contains("ewallet") || lowerFull.contains("transferred") || lowerFull.contains("transfer")))

        if isTNGSender {
            let method = detectedMethod ?? "ewallet"
            return ProviderDetectionResult(
                provider: .touchNGo,
                normalizedId: "touch_n_go",
                confidence: 0.98,
                displayName: "Touch 'n Go eWallet",
                underlyingBank: nil,
                underlyingBankNormalizedId: nil,
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE 5: Public Bank
        let publicBankKeywords = [
            "public bank", "pb engage", "pbe online", "pb enterprise", "public bank berhad"
        ]
        if publicBankKeywords.contains(where: { lowerFull.contains($0) }) && !recipientBankIds.contains("public_bank") {
            let method = detectedMethod ?? "bank_transfer"
            return ProviderDetectionResult(
                provider: .publicBank,
                normalizedId: "public_bank",
                confidence: 0.98,
                displayName: "Public Bank",
                underlyingBank: .publicBank,
                underlyingBankNormalizedId: "public_bank",
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE 6: Bank Islam
        let bankIslamKeywords = [
            "bank islam", "go by bank islam", "bimb"
        ]
        if bankIslamKeywords.contains(where: { lowerFull.contains($0) }) && !recipientBankIds.contains("bank_islam") {
            let method = detectedMethod ?? "bank_transfer"
            return ProviderDetectionResult(
                provider: .bankIslam,
                normalizedId: "bank_islam",
                confidence: 0.98,
                displayName: "Bank Islam",
                underlyingBank: .bankIslam,
                underlyingBankNormalizedId: "bank_islam",
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE: Wise
        let wiseKeywords = ["wise payments", "transferwise", "wise malaysia", "wise card", "wise account", "wise.com"]
        let isWiseSender = wiseKeywords.contains(where: { lowerFull.contains($0) }) ||
                           headerText.contains("wise") ||
                           fromAccountText.contains("wise") ||
                           (lowerFull.contains("wise") && (lowerFull.contains("spent") || lowerFull.contains("paid") || lowerFull.contains("sent") || lowerFull.contains("card")))

        if isWiseSender {
            let method = detectedMethod ?? "digital_wallet"
            return ProviderDetectionResult(
                provider: .wise,
                normalizedId: "wise",
                confidence: 0.98,
                displayName: "Wise",
                underlyingBank: .wise,
                underlyingBankNormalizedId: "wise",
                paymentMethod: method
            )
        }

        // SENDER DETECTION RULE 7: GrabPay
        if lowerFull.contains("grabpay") || lowerFull.contains("grab pay") || lowerFull.contains("grab wallet") {
            return ProviderDetectionResult(
                provider: .grabPay,
                normalizedId: "grabpay",
                confidence: 0.98,
                displayName: "GrabPay",
                underlyingBank: nil,
                underlyingBankNormalizedId: nil,
                paymentMethod: detectedMethod ?? "ewallet"
            )
        }

        // SENDER DETECTION RULE 8: Boost
        if lowerFull.contains("boost ewallet") || lowerFull.contains("boost bank") || lowerFull.contains("boost app") || lowerFull.contains("myboost") || lowerFull.contains("boost") {
            return ProviderDetectionResult(
                provider: .boost,
                normalizedId: "boost",
                confidence: 0.98,
                displayName: "Boost",
                underlyingBank: nil,
                underlyingBankNormalizedId: nil,
                paymentMethod: detectedMethod ?? "ewallet"
            )
        }

        // SENDER DETECTION RULE 9: DuitNow QR & DuitNow Transfer
        if lowerFull.contains("duitnow qr") || lowerFull.contains("qr pay") || lowerFull.contains("paynet qr") || lowerFull.contains("scan & pay") || lowerFull.contains("scan qr") {
            return ProviderDetectionResult(
                provider: .qrPayment,
                normalizedId: "duitnow",
                confidence: 0.95,
                displayName: "DuitNow QR",
                paymentMethod: "duitnow_qr"
            )
        }
        if lowerFull.contains("duitnow transfer") || lowerFull.contains("paynet") || lowerFull.contains("duitnow") {
            return ProviderDetectionResult(
                provider: .duitNow,
                normalizedId: "duitnow",
                confidence: 0.95,
                displayName: "DuitNow",
                paymentMethod: "duitnow"
            )
        }

        // SENDER DETECTION RULE 10: Card / Cash / Bank Transfer fallback
        if lowerFull.contains("visa") || lowerFull.contains("mastercard") || lowerFull.contains("credit card") || lowerFull.contains("debit card") {
            return ProviderDetectionResult(
                provider: .physicalCard,
                normalizedId: "physical_card",
                confidence: 0.85,
                displayName: "Card",
                paymentMethod: "card"
            )
        }

        if lowerFull.contains("tunai") || lowerFull.contains("cash") {
            return ProviderDetectionResult(
                provider: .cash,
                normalizedId: "cash",
                confidence: 0.85,
                displayName: "Cash",
                paymentMethod: "cash"
            )
        }

        // Fallback: Unknown provider
        return ProviderDetectionResult(
            provider: .unknown,
            normalizedId: "unknown",
            confidence: 0.0,
            displayName: "Unknown",
            underlyingBank: nil,
            underlyingBankNormalizedId: nil,
            paymentMethod: "unknown"
        )
    }

    /// Determines normalized payment method string based on contextual cues
    public static func detectPaymentMethod(lowerFull: String) -> String? {
        if lowerFull.contains("scan & pay") ||
           lowerFull.contains("duitnow qr") ||
           lowerFull.contains("duit now qr") ||
           lowerFull.contains("paynet qr") ||
           lowerFull.contains("qr pay") ||
           lowerFull.contains("via qr") {
            return "duitnow_qr"
        }
        if lowerFull.contains("duit now to account") ||
           lowerFull.contains("duitnow transfer") ||
           lowerFull.contains("duitnow (instant)") ||
           lowerFull.contains("duitnow") ||
           lowerFull.contains("duit now") {
            return "duitnow"
        }
        if lowerFull.contains("transfer to wallet") ||
           lowerFull.contains("ewallet balance") ||
           lowerFull.contains("wallet balance") {
            return "ewallet"
        }
        if lowerFull.contains("fpx payment") ||
           lowerFull.contains("fpx") ||
           lowerFull.contains("fund transfer") ||
           lowerFull.contains("interbank") ||
           lowerFull.contains("ibg") ||
           lowerFull.contains("giro") {
            return "bank_transfer"
        }
        return nil
    }

    /// Extracts funding instrument details from OCR lines (e.g. "Maybank Visa Debit")
    /// Returns: (bank: PaymentSource?, bankId: String?, instrumentName: String?)
    public static func extractFundingInstrumentFromLines(lines: [String], lowerFull: String) -> (PaymentSource?, String?, String?) {
        // Known card type patterns
        let cardTypePatterns = [
            "visa debit", "visa credit", "mastercard debit", "mastercard credit",
            "debit card", "credit card", "visa", "mastercard", "amex",
            "american express", "jcb", "unionpay"
        ]

        // Bank name mapping
        let bankMapping: [(keywords: [String], bank: PaymentSource, bankId: String)] = [
            (["maybank", "mae"], .maybank, "maybank"),
            (["cimb", "octo"], .cimb, "cimb"),
            (["rhb"], .rhb, "rhb"),
            (["public bank", "pb engage"], .publicBank, "public_bank"),
            (["bank islam", "bimb"], .bankIslam, "bank_islam"),
            (["hong leong", "hlb"], .unknown, "hong_leong"),
            (["ambank"], .unknown, "ambank"),
            (["wise", "transferwise"], .wise, "wise"),
        ]

        // Scan each line for instrument patterns like "Maybank Visa Debit"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            // Check if this line contains a card type keyword
            for cardType in cardTypePatterns {
                if lower.contains(cardType) {
                    // This line likely contains the funding instrument
                    let instrumentName = trimmed

                    // Try to extract the bank from this same line
                    for (keywords, bank, bankId) in bankMapping {
                        if keywords.contains(where: { lower.contains($0) }) {
                            return (bank, bankId, instrumentName)
                        }
                    }

                    // Card type found but no bank in this line — check full text for bank
                    for (keywords, bank, bankId) in bankMapping {
                        if keywords.contains(where: { lowerFull.contains($0) }) {
                            return (bank, bankId, instrumentName)
                        }
                    }

                    return (nil, nil, instrumentName)
                }
            }
        }

        // Also try regex for patterns like "Maybank Debit Card Visa **** 9034"
        let instrumentRegex = try? NSRegularExpression(
            pattern: #"((?:Maybank|CIMB|RHB|Public Bank|Bank Islam|Hong Leong|AmBank|Wise)\s+(?:Visa|Mastercard|Debit Card|Credit Card|Debit|Credit)[\w\s*]*)"#,
            options: [.caseInsensitive]
        )
        if let regex = instrumentRegex {
            let range = NSRange(lowerFull.startIndex..<lowerFull.endIndex, in: lowerFull)
            if let match = regex.firstMatch(in: lowerFull, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: lowerFull) {
                let captured = String(lowerFull[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Remove trailing card number mask (e.g. "**** 9034")
                let cleanedInstrument = captured.replacingOccurrences(of: #"\s*\*+\s*\d+$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Capitalize words
                let displayInstrument = cleanedInstrument.split(separator: " ").map { word in
                    word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }.joined(separator: " ")

                for (keywords, bank, bankId) in bankMapping {
                    if keywords.contains(where: { cleanedInstrument.contains($0) }) {
                        return (bank, bankId, displayInstrument)
                    }
                }

                return (nil, nil, displayInstrument)
            }
        }

        return (nil, nil, nil)
    }
}
