package com.spendrop.core.parser

import com.spendrop.core.model.PaymentSource

/** Where the OCR text came from (Apple Wallet UI vs bank app receipt). */
enum class DetectedTransactionSource(val raw: String) {
    APPLE_WALLET("APPLE_WALLET"), BANK_APP("BANK_APP"), PHYSICAL_RECEIPT("PHYSICAL_RECEIPT"), UNKNOWN("UNKNOWN")
}

data class ProviderDetectionResult(
    val provider: PaymentSource,
    val normalizedId: String,
    val confidence: Double,
    val displayName: String,
    val underlyingBank: PaymentSource? = null,
    val underlyingBankNormalizedId: String? = null,
    val paymentMethod: String = provider.defaultPaymentMethod,
    val fundingInstrument: String? = null,
    val detectedSource: DetectedTransactionSource = DetectedTransactionSource.UNKNOWN,
)

/** A funding instrument found on the receipt, e.g. "Maybank Visa Debit" (bank may be unknown). */
data class FundingInstrument(val bank: PaymentSource?, val bankId: String?, val name: String?) {
    companion object {
        val NONE = FundingInstrument(null, null, null)
    }
}

/** Detects the sending bank / wallet (the funding provider) of a receipt (iOS `PaymentProviderDetector`). */
object PaymentProviderDetector {
    private val contactBanks = listOf(
        "contact maybank", "contact cimb", "contact rhb", "contact public bank", "contact bank islam", "contact ambank",
        "contact hong leong", "contact wise",
    )

    fun detect(lines: List<String>, fullText: String): ProviderDetectionResult {
        val lowerFull = fullText.lowercase()

        // PRIORITY 1: Apple Wallet provenance (structural UI markers)
        val hasWalletMaps = lowerFull.contains("wallet uses maps")
        val hasReportMerchant = lowerFull.contains("report incorrect merchant info")
        val hasStatusApproved = lowerFull.contains("status: approved") || lowerFull.contains("status:approved")
        val hasContactBank = contactBanks.any { lowerFull.contains(it) }
        val isAppleWalletUI = hasWalletMaps || (hasReportMerchant && hasStatusApproved) || (hasStatusApproved && hasContactBank)

        if (isAppleWalletUI) {
            val wallet = extractFundingInstrumentFromLines(lines, lowerFull)
            return ProviderDetectionResult(
                provider = wallet.bank ?: PaymentSource.APPLE_PAY,
                normalizedId = wallet.bankId ?: "apple_pay",
                confidence = 0.99,
                displayName = wallet.bank?.let { "Apple Pay • ${it.raw}" } ?: "Apple Pay",
                underlyingBank = wallet.bank,
                underlyingBankNormalizedId = wallet.bankId,
                paymentMethod = "digital_wallet",
                fundingInstrument = wallet.name,
                detectedSource = DetectedTransactionSource.APPLE_WALLET,
            )
        }

        // PRIORITY 2: explicit Apple Pay text
        if (listOf("apple pay", "pay with apple", "apple cash").any { lowerFull.contains(it) }) {
            val (bank, bankId) = when {
                lowerFull.contains("cimb") || lowerFull.contains("octo") -> PaymentSource.CIMB to "cimb"
                lowerFull.contains("maybank") || lowerFull.contains("mae") || lowerFull.contains("m2u") -> PaymentSource.MAYBANK to "maybank"
                lowerFull.contains("rhb") -> PaymentSource.RHB to "rhb"
                lowerFull.contains("public bank") || lowerFull.contains("pb engage") -> PaymentSource.PUBLIC_BANK to "public_bank"
                lowerFull.contains("bank islam") || lowerFull.contains("bimb") -> PaymentSource.BANK_ISLAM to "bank_islam"
                lowerFull.contains("wise") || lowerFull.contains("transferwise") -> PaymentSource.WISE to "wise"
                else -> null to null
            }
            val instrument = extractFundingInstrumentFromLines(lines, lowerFull).name
            return ProviderDetectionResult(
                provider = PaymentSource.APPLE_PAY,
                normalizedId = "apple_pay",
                confidence = 0.98,
                displayName = bank?.let { "Apple Pay • ${it.raw}" } ?: "Apple Pay",
                underlyingBank = bank,
                underlyingBankNormalizedId = bankId,
                paymentMethod = "digital_wallet",
                fundingInstrument = instrument,
            )
        }

        // Recipient banks, so the destination bank is not mistaken for the sender
        val recipientBankIds = mutableSetOf<String>()
        lines.forEachIndexed { idx, line ->
            val lower = line.lowercase()
            val isRecipientHeader = listOf(
                "receiving bank", "recipient bank", "recipient's bank", "beneficiary's bank", "beneficiary bank", "to bank",
                "recipient bank/e-wallet", "bank/e-wallet",
            ).any { lower.contains(it) }
            if (isRecipientHeader) {
                val candidateLines = listOfNotNull(lower, lines.getOrNull(idx + 1)?.lowercase(), lines.getOrNull(idx + 2)?.lowercase())
                for (cl in candidateLines) {
                    if (cl.contains("maybank") || cl.contains("mbb")) recipientBankIds += "maybank"
                    if (cl.contains("cimb")) recipientBankIds += "cimb"
                    if (cl.contains("rhb")) recipientBankIds += "rhb"
                    if (cl.contains("public bank") || cl.contains("pbb")) recipientBankIds += "public_bank"
                    if (cl.contains("bank islam") || cl.contains("bimb")) recipientBankIds += "bank_islam"
                }
            }
            // Key-value pair: a "Bank" line followed by the bank name (e.g. RHB receipt)
            if (lower.trimWs() == "bank" && idx + 1 < lines.size) {
                val next = lines[idx + 1].lowercase()
                if (next.contains("cimb")) recipientBankIds += "cimb"
                if (next.contains("maybank")) recipientBankIds += "maybank"
                if (next.contains("rhb")) recipientBankIds += "rhb"
                if (next.contains("public bank")) recipientBankIds += "public_bank"
                if (next.contains("bank islam")) recipientBankIds += "bank_islam"
            }
        }

        // Sender: header lines, the "From" account, notification prefixes
        val headerText = lines.take(5).joinToString(" ") { it.lowercase() }
        var fromAccountText = ""
        for ((idx, line) in lines.withIndex()) {
            val lower = line.lowercase().trimWs()
            if (lower == "from" || lower.startsWith("from:") || lower.startsWith("from ")) {
                fromAccountText = listOfNotNull(lower, lines.getOrNull(idx + 1)?.lowercase(), lines.getOrNull(idx + 2)?.lowercase()).joinToString(" ")
                break
            }
        }

        val detectedMethod = detectPaymentMethod(lowerFull)

        // RULE 1: RHB
        val isRHBSender = fromAccountText.contains("rhb") || headerText.contains("rhb") ||
            lowerFull.contains("rhb smart account") || lowerFull.contains("rhb reflex") || lowerFull.contains("rhb mobile") ||
            lowerFull.contains("rhb now") || (lowerFull.contains("rhb") && "rhb" !in recipientBankIds)
        if (isRHBSender && !fromAccountText.contains("cimb") && !fromAccountText.contains("maybank")) {
            return ProviderDetectionResult(PaymentSource.RHB, "rhb", 0.98, "RHB Bank", PaymentSource.RHB, "rhb", detectedMethod ?: "bank_transfer")
        }

        // RULE 2: CIMB
        val isCIMBSender = fromAccountText.contains("cimb") || fromAccountText.contains("savings acct-i") ||
            fromAccountText.contains("current acct-i") || headerText.contains("cimb") || headerText.contains("octo") ||
            lowerFull.contains("cimb:") || lowerFull.contains("cimb octo") || lowerFull.contains("cimb clicks") ||
            (lowerFull.contains("cimb bank") && "cimb" !in recipientBankIds) || lowerFull.contains("octo reference no") ||
            lowerFull.contains("with octo") || lowerFull.contains("savings acct-i plus") ||
            (lowerFull.contains("cimb") && "cimb" !in recipientBankIds)
        if (isCIMBSender && !fromAccountText.contains("maybank")) {
            return ProviderDetectionResult(PaymentSource.CIMB, "cimb", 0.98, "CIMB Bank", PaymentSource.CIMB, "cimb", detectedMethod ?: "bank_transfer")
        }

        // RULE 3: Maybank / MAE
        val isMaybankSender = fromAccountText.contains("maybank") || fromAccountText.contains("mae") ||
            headerText.contains("maybank") || headerText.contains("mae") || lowerFull.contains("mae by maybank2u") ||
            lowerFull.contains("maybank2u") || lowerFull.contains("malayan banking") || lowerFull.contains("maybank islamic") ||
            (lowerFull.contains("maybank") && "maybank" !in recipientBankIds) ||
            (lowerFull.contains("mae") && (lowerFull.contains("scan & pay") || lowerFull.contains("duitnow") || lowerFull.contains("transfer")))
        if (isMaybankSender) {
            val instrument = extractFundingInstrumentFromLines(lines, lowerFull).name
            val isCard = instrument != null || lowerFull.contains("debit card") || lowerFull.contains("credit card")
            return ProviderDetectionResult(
                PaymentSource.MAYBANK, "maybank", 0.98, "Maybank / MAE", PaymentSource.MAYBANK, "maybank",
                detectedMethod ?: (if (isCard) "unknown" else "bank_transfer"), instrument,
            )
        }

        // RULE 4: Touch 'n Go eWallet
        val tngKeywords = listOf(
            "touch 'n go ewallet", "touch 'n go", "touch n go", "tng ewallet", "tng digital", "tng reload pin", "tng card", "tng rfid", "go+", "goleader",
        )
        val isTNGSender = tngKeywords.any { lowerFull.contains(it) } || headerText.contains("touch 'n go") || headerText.contains("touch n go") ||
            lowerFull.contains("transfer to wallet") || lowerFull.contains("ewallet balance") || lowerFull.contains("tngdmynb") ||
            lowerFull.contains("near me!") ||
            (lowerFull.contains("transferred") && (lowerFull.contains("receiver") || lowerFull.contains("fund transfer")) && lowerFull.contains("done")) ||
            (lowerFull.contains("tng") && (lowerFull.contains("ewallet") || lowerFull.contains("transferred") || lowerFull.contains("transfer")))
        if (isTNGSender) {
            return ProviderDetectionResult(PaymentSource.TOUCH_N_GO, "touch_n_go", 0.98, "Touch 'n Go eWallet", null, null, detectedMethod ?: "ewallet")
        }

        // RULE 5: Public Bank
        if (listOf("public bank", "pb engage", "pbe online", "pb enterprise", "public bank berhad").any { lowerFull.contains(it) } &&
            "public_bank" !in recipientBankIds
        ) {
            return ProviderDetectionResult(PaymentSource.PUBLIC_BANK, "public_bank", 0.98, "Public Bank", PaymentSource.PUBLIC_BANK, "public_bank", detectedMethod ?: "bank_transfer")
        }

        // RULE 6: Bank Islam
        if (listOf("bank islam", "go by bank islam", "bimb").any { lowerFull.contains(it) } && "bank_islam" !in recipientBankIds) {
            return ProviderDetectionResult(PaymentSource.BANK_ISLAM, "bank_islam", 0.98, "Bank Islam", PaymentSource.BANK_ISLAM, "bank_islam", detectedMethod ?: "bank_transfer")
        }

        // RULE: Wise
        val isWiseSender = listOf("wise payments", "transferwise", "wise malaysia", "wise card", "wise account", "wise.com").any { lowerFull.contains(it) } ||
            headerText.contains("wise") || fromAccountText.contains("wise") ||
            (lowerFull.contains("wise") && (lowerFull.contains("spent") || lowerFull.contains("paid") || lowerFull.contains("sent") || lowerFull.contains("card")))
        if (isWiseSender) {
            return ProviderDetectionResult(PaymentSource.WISE, "wise", 0.98, "Wise", PaymentSource.WISE, "wise", detectedMethod ?: "digital_wallet")
        }

        // RULE 7: GrabPay
        if (lowerFull.contains("grabpay") || lowerFull.contains("grab pay") || lowerFull.contains("grab wallet")) {
            return ProviderDetectionResult(PaymentSource.GRAB_PAY, "grabpay", 0.98, "GrabPay", null, null, detectedMethod ?: "ewallet")
        }

        // RULE 8: Boost (any mention of "boost", as on iOS)
        if (lowerFull.contains("boost")) {
            return ProviderDetectionResult(PaymentSource.BOOST, "boost", 0.98, "Boost", null, null, detectedMethod ?: "ewallet")
        }

        // RULE 9: DuitNow QR & DuitNow transfer
        if (listOf("duitnow qr", "qr pay", "paynet qr", "scan & pay", "scan qr").any { lowerFull.contains(it) }) {
            return ProviderDetectionResult(PaymentSource.QR_PAYMENT, "duitnow", 0.95, "DuitNow QR", paymentMethod = "duitnow_qr")
        }
        if (lowerFull.contains("duitnow transfer") || lowerFull.contains("paynet") || lowerFull.contains("duitnow")) {
            return ProviderDetectionResult(PaymentSource.DUITNOW, "duitnow", 0.95, "DuitNow", paymentMethod = "duitnow")
        }

        // RULE 10: card / cash fallback
        if (lowerFull.contains("visa") || lowerFull.contains("mastercard") || lowerFull.contains("credit card") || lowerFull.contains("debit card")) {
            return ProviderDetectionResult(PaymentSource.PHYSICAL_CARD, "physical_card", 0.85, "Card", paymentMethod = "card")
        }
        if (lowerFull.contains("tunai") || lowerFull.contains("cash")) {
            return ProviderDetectionResult(PaymentSource.CASH, "cash", 0.85, "Cash", paymentMethod = "cash")
        }

        return ProviderDetectionResult(PaymentSource.UNKNOWN, "unknown", 0.0, "Unknown", paymentMethod = "unknown")
    }

    /** Normalised payment method from contextual cues ("duitnow_qr", "duitnow", "ewallet", "bank_transfer"), or null. */
    fun detectPaymentMethod(lowerFull: String): String? {
        if (listOf("scan & pay", "duitnow qr", "duit now qr", "paynet qr", "qr pay", "via qr").any { lowerFull.contains(it) }) return "duitnow_qr"
        if (listOf("duit now to account", "duitnow transfer", "duitnow (instant)", "duitnow", "duit now").any { lowerFull.contains(it) }) return "duitnow"
        if (listOf("transfer to wallet", "ewallet balance", "wallet balance").any { lowerFull.contains(it) }) return "ewallet"
        if (listOf("fpx payment", "fpx", "fund transfer", "interbank", "ibg", "giro").any { lowerFull.contains(it) }) return "bank_transfer"
        return null
    }

    private val cardTypePatterns = listOf(
        "visa debit", "visa credit", "mastercard debit", "mastercard credit", "debit card", "credit card", "visa", "mastercard", "amex",
        "american express", "jcb", "unionpay",
    )

    private val bankMapping: List<Triple<List<String>, PaymentSource?, String>> = listOf(
        Triple(listOf("maybank", "mae"), PaymentSource.MAYBANK, "maybank"),
        Triple(listOf("cimb", "octo"), PaymentSource.CIMB, "cimb"),
        Triple(listOf("rhb"), PaymentSource.RHB, "rhb"),
        Triple(listOf("public bank", "pb engage"), PaymentSource.PUBLIC_BANK, "public_bank"),
        Triple(listOf("bank islam", "bimb"), PaymentSource.BANK_ISLAM, "bank_islam"),
        Triple(listOf("hong leong", "hlb"), PaymentSource.UNKNOWN, "hong_leong"),
        Triple(listOf("ambank"), PaymentSource.UNKNOWN, "ambank"),
        Triple(listOf("wise", "transferwise"), PaymentSource.WISE, "wise"),
    )

    private val instrumentRegex = icuRegex(
        """((?:Maybank|CIMB|RHB|Public Bank|Bank Islam|Hong Leong|AmBank|Wise)\s+(?:Visa|Mastercard|Debit Card|Credit Card|Debit|Credit)[\w\s*]*)""",
        caseInsensitive = true,
    )
    private val maskSuffixRegex = Regex("""\s*\*+\s*\d+$""")

    /** The funding instrument on the receipt (e.g. "Maybank Visa Debit") and the bank behind it. */
    fun extractFundingInstrumentFromLines(lines: List<String>, lowerFull: String): FundingInstrument {
        fun bankIn(text: String) = bankMapping.firstOrNull { (keywords, _, _) -> keywords.any { text.contains(it) } }

        for (line in lines) {
            val trimmed = line.trimWs()
            val lower = trimmed.lowercase()
            if (cardTypePatterns.any { lower.contains(it) }) {
                // The bank on the same line, else anywhere on the receipt
                val hit = bankIn(lower) ?: bankIn(lowerFull)
                return if (hit != null) FundingInstrument(hit.second, hit.third, trimmed) else FundingInstrument(null, null, trimmed)
            }
        }

        // Patterns like "Maybank Debit Card Visa **** 9034"
        val captured = instrumentRegex.firstGroup(lowerFull)?.trimWs()
        if (captured != null) {
            val cleaned = captured.replace(maskSuffixRegex, "").trimWs()
            val display = cleaned.splitNonEmpty(' ').joinToString(" ") { word ->
                word.take(1).uppercase() + word.drop(1).lowercase()
            }
            val hit = bankIn(cleaned)
            return if (hit != null) FundingInstrument(hit.second, hit.third, display) else FundingInstrument(null, null, display)
        }
        return FundingInstrument.NONE
    }
}
