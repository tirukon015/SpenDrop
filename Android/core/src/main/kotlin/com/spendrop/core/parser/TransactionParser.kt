package com.spendrop.core.parser

import com.spendrop.core.Money
import com.spendrop.core.model.PaymentSource
import java.time.Clock
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Turns recognised receipt text into a [ParsedTransaction] (iOS `TransactionParser`). Pure and deterministic:
 * [zone] interprets the receipt's local date/time (iOS uses `Calendar.current`), [clock] only resolves two-digit
 * years. Both default to the device.
 */
object TransactionParser {

    /**
     * Parses newline-joined OCR lines (ML Kit lines in reading order, shared text, or PDF text). Empty lines are
     * dropped; every line gets [lineConfidence] (used to ignore channel words read with low confidence).
     */
    fun parse(
        text: String,
        lineConfidence: Float = 1f,
        zone: ZoneId = ZoneId.systemDefault(),
        clock: Clock = Clock.system(zone),
    ): ParsedTransaction = parse(OcrResult.fromText(text, lineConfidence), zone, clock)

    fun parse(ocr: OcrResult, zone: ZoneId = ZoneId.systemDefault(), clock: Clock = Clock.system(zone)): ParsedTransaction {
        val fullText = ocr.fullText
        val lines = ocr.lines.map { it.text }
        val lowerFull = fullText.lowercase()

        // 1. Bank / payment provider
        val providerResult = PaymentProviderDetector.detect(lines, fullText)
        val detectedPaymentSource: PaymentSource? =
            if (providerResult.provider != PaymentSource.UNKNOWN) providerResult.provider else detectPaymentSource(lowerFull)
        val underlyingBank = providerResult.underlyingBank
        val transactionSource = providerResult.detectedSource

        val suggestedRemark = if (providerResult.provider == PaymentSource.APPLE_PAY || transactionSource == DetectedTransactionSource.APPLE_WALLET) {
            underlyingBank?.let { "Paid via Apple Pay • ${it.raw}" } ?: "Paid via Apple Pay"
        } else null

        // 2. Context checks (failed payment, balance / limit screens)
        val isFailed = checkFailedTransaction(lowerFull)
        val isBalanceOrLimit = checkBalanceOrLimitOnly(lines, lowerFull)

        // 3. Money amounts
        val amounts = extractAndClassifyAmounts(ocr, isBalanceOrLimit)
        val selectedAmount = amounts.amountMinor
        val amountConfidence = amounts.confidence

        // 4. Merchant and category (category from the merchant first, then weakly the wording; never the bank)
        val (detectedMerchant, _) = MerchantDetector.detect(lines, fullText)
        val categorySuggestion = CategoryDetector.suggest(detectedMerchant, fullText)

        // 5. Date & time
        val dt = extractDateTimeAndStrings(lines, fullText, clock)

        // 6. Reference
        val transactionReference = extractReferenceNumber(lines)

        // 7. Status
        val isCompleted = checkCompletedTransaction(lowerFull) && !isFailed && !isBalanceOrLimit
        val normalizedStatus = detectNormalizedStatus(lowerFull, isFailed, isBalanceOrLimit)

        // 8. Overall confidence
        val hasAmount = selectedAmount != null && selectedAmount > 0
        val confidence = when {
            isBalanceOrLimit || isFailed -> ParsingConfidence.LOW
            isCompleted && hasAmount -> when {
                amountConfidence >= 0.85 && (detectedMerchant != null || detectedPaymentSource != null) -> ParsingConfidence.HIGH
                amountConfidence >= 0.60 -> ParsingConfidence.MEDIUM
                else -> ParsingConfidence.LOW
            }
            hasAmount -> if (amountConfidence >= 0.80) ParsingConfidence.MEDIUM else ParsingConfidence.LOW
            else -> ParsingConfidence.LOW
        }

        // Channel only from what the receipt says, using lines read with reasonable confidence.
        val evidenceText = ocr.lines.filter { it.confidence >= 0.5f }.joinToString("\n") { it.text }
        val channel = ChannelDetector.suggest(evidenceText, detectedPaymentSource, transactionSource)
        val detectedFunding = underlyingBank?.raw
            ?: if (detectedPaymentSource != null && detectedPaymentSource !in ParsedTransaction.CHANNEL_LIKE_SOURCES) detectedPaymentSource.raw else "Unknown"

        // 9. Direction suggestion (additive)
        val direction = DirectionDetector.detect(fullText)

        return ParsedTransaction(
            amountMinor = selectedAmount,
            amountConfidence = amountConfidence,
            currency = amounts.currency,
            merchant = detectedMerchant,
            date = dt.dateTime?.atZone(zone)?.toInstant()?.toEpochMilli(),
            localDateTime = dt.dateTime,
            dateString = dt.dateString,
            timeString = dt.timeString,
            paymentSource = detectedPaymentSource,
            provider = providerResult.normalizedId,
            providerConfidence = providerResult.confidence,
            paymentMethod = providerResult.paymentMethod,
            paymentChannel = channel.channel,
            fundingAccount = detectedFunding,
            fundingInstrument = providerResult.fundingInstrument,
            underlyingBank = underlyingBank,
            underlyingBankNormalizedId = providerResult.underlyingBankNormalizedId,
            suggestedRemark = suggestedRemark,
            category = categorySuggestion.category,
            transactionReference = transactionReference,
            transactionStatus = normalizedStatus,
            confidence = confidence,
            rawOCRText = fullText,
            detectedLines = lines,
            amountCandidates = amounts.candidates,
            suggestedMovementKind = direction.kind,
            categoryConfidence = categorySuggestion.confidence,
            categoryReason = categorySuggestion.reason,
            channelConfidence = channel.confidence,
            channelReason = channel.reason,
            directionReason = direction.reason,
            isCompletedTransaction = isCompleted,
            isFailedTransaction = isFailed,
            isBalanceOrLimitOnly = isBalanceOrLimit,
        )
    }

    // MARK: - Amounts

    data class AmountResult(val amountMinor: Long?, val confidence: Double, val currency: String, val candidates: List<MonetaryCandidate>)

    private val amountPatterns = listOf(
        """(?:[-–—]\s*)?(?:RM|MYR)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))""", // RM 22.00 or -RM12.00
        """([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2}))\s*(?:RM|MYR)""",              // 22.00 RM
        """(?:[-–—]\s*)?(?:RM|MYR)\s*([0-9]+(?:\.[0-9]{2})?)""",                  // RM450 or -RM12.00
        """\b(?:Amount|Total|Jumlah|Paid)\s*[:\-]?\s*(?:[-–—]\s*)?(?:RM|MYR)?\s*([0-9]+(?:\.[0-9]{2})?)""",
        """(?:[-–—]\s*)?([0-9]{1,4}\.[0-9]{2})\b""",                             // standalone decimal amount
    ).map { icuRegex(it, caseInsensitive = true) }

    private val adKeywords = listOf(
        "advertisement", "advert", "sponsored", "promo", "promotions", "promotion",
        "voucher", "vouchers", "deal", "deals", "discount", "discounts",
        "shop now", "buy now", "save up to", "cashback up to", "win up to", "reward",
        "panasonic", "samsung", "air conditioner", "appliances", "catalogue", "featured",
        "discover more", "explore more", "campaign", "contest", "banner",
        "terms & conditions", "terms and conditions", "t&c", "special offer", "exclusive offer",
        "apply now", "lucky draw", "claim now", "grab your", "hot deals", "best price",
        "minimum spend", "min spend", "min. spend", "gong cha", "gongcha",
        "baskin-robbins", "baskin robbins", "near me!", "near me", "validity:",
    )
    private val feeKeywords = listOf("service fee", "processing fee", "fee", "caj perkhidmatan", "caj", "tax", "sst", "gst", "handling fee")
    private val balanceKeywords = listOf("available balance", "account balance", "wallet balance", "baki akaun", "baki tersedia", "baki", "credit limit", "available credit")
    private val cashbackKeywords = listOf("cashback", "rebate", "rebat", "duit pulangan", "pulangan tunai")
    private val discountKeywords = listOf("discount", "diskaun", "potongan", "voucher applied", "promo applied")
    private val totalKeywords = listOf("grand total", "total paid", "total amount", "total", "jumlah bayaran", "jumlah keseluruhan", "jumlah bersih", "net amount")
    private val transactionKeywords = listOf(
        "amount transferred", "amount paid", "amount received", "payment amount",
        "transaction amount", "transfer amount", "amount", "transferred", "paid to",
        "receiver", "recipient", "bayar kepada", "jumlah pindahan", "diterima",
    )
    private val statusNearby = listOf("transferred", "payment successful", "transfer successful", "successful", "berjaya")
    private val receiverNearby = listOf("receiver", "recipient", "paid to", "penerima")
    private val wordSplit = Regex("[^\\p{L}\\p{N}]+")

    /** Below this (exclusive) an amount is taken as real; RM 500,000 and above is ignored, as on iOS. */
    private const val MAX_AMOUNT_MINOR = 50_000_000L

    /**
     * Finds every money amount, classifies it (total, transaction amount, fee, balance, cashback, discount, advert)
     * and picks the transaction amount: totals first, then the highest score.
     */
    fun extractAndClassifyAmounts(ocr: OcrResult, isBalanceOrLimit: Boolean): AmountResult {
        if (isBalanceOrLimit) return AmountResult(null, 0.0, "RM", emptyList())

        val lineTexts = ocr.lines.map { it.text }
        val totalLinesCount = maxOf(lineTexts.size, 1)

        data class Raw(val amountMinor: Long, val lineIndex: Int, val line: String, val box: OcrBox?, val hasCurrency: Boolean)
        val rawFound = mutableListOf<Raw>()
        ocr.lines.forEachIndexed { idx, ocrLine ->
            val line = ocrLine.text
            for (pattern in amountPatterns) {
                val m = pattern.matcher(line)
                while (m.find()) {
                    val capture = m.group(1) ?: continue
                    val minor = Money.parseMinor(capture.replace(",", "")) ?: continue
                    if (minor in 1 until MAX_AMOUNT_MINOR) {
                        val upper = line.uppercase()
                        val hasCurrency = upper.contains("RM") || upper.contains("MYR")
                        // One candidate per amount per line
                        if (rawFound.none { it.lineIndex == idx && it.amountMinor == minor }) {
                            rawFound += Raw(minor, idx, line, ocrLine.box, hasCurrency)
                        }
                    }
                }
            }
        }
        if (rawFound.isEmpty()) return AmountResult(null, 0.0, "RM", emptyList())

        val classified = rawFound.map { c ->
            val idx = c.lineIndex
            val lineLower = c.line.lowercase()
            val nearby = lineTexts.subList(maxOf(0, idx - 2), minOf(totalLinesCount - 1, idx + 2) + 1).joinToString(" ").lowercase()
            // Bottom 35% of the page (box), else of the lines.
            val isNearBottom = if (c.box != null) c.box.centerY > 0.65f else idx.toDouble() / totalLinesCount > 0.65
            val words = lineLower.split(wordSplit).filter { it.isNotEmpty() }.toSet()
            val hasAdWordExact = "ad" in words || "ads" in words || "promo" in words || "off" in words
            val prevLine = lineTexts.getOrNull(idx - 1)?.lowercase()
            val nextLine = if (idx + 1 < totalLinesCount) lineTexts.getOrNull(idx + 1)?.lowercase() else null

            val (type, score, reason) = when {
                balanceKeywords.any { lineLower.contains(it) } ||
                    (prevLine != null && balanceKeywords.any { prevLine.trimWs().startsWith(it) }) ->
                    Triple(MonetarySemanticType.BALANCE, 0.0, "Identified as balance / credit limit statement")
                hasAdWordExact || adKeywords.any { lineLower.contains(it) } ||
                    (prevLine != null && adKeywords.any { prevLine.contains(it) }) ||
                    (nextLine != null && adKeywords.any { nextLine.contains(it) }) ||
                    (isNearBottom && adKeywords.any { nearby.contains(it) }) ->
                    Triple(MonetarySemanticType.ADVERTISEMENT, 0.0, "Identified as promotional advertisement / banner amount")
                feeKeywords.any { lineLower.contains(it) } -> Triple(MonetarySemanticType.FEE, 0.05, "Identified as service/processing fee")
                cashbackKeywords.any { lineLower.contains(it) } -> Triple(MonetarySemanticType.CASHBACK, 0.05, "Identified as cashback or rebate reward")
                discountKeywords.any { lineLower.contains(it) } -> Triple(MonetarySemanticType.DISCOUNT, 0.05, "Identified as discount deduction")
                totalKeywords.any { lineLower.contains(it) } && !lineLower.contains("subtotal") ->
                    Triple(MonetarySemanticType.TOTAL, 0.98, "Identified as total payment amount")
                transactionKeywords.any { lineLower.contains(it) } ->
                    Triple(MonetarySemanticType.TRANSACTION_AMOUNT, 0.96, "Explicitly labeled transaction amount")
                else -> {
                    // Unlabelled amount in the main area (TNG, MAE, OCTO transfer screens)
                    val hasStatus = statusNearby.any { nearby.contains(it) }
                    val hasReceiver = receiverNearby.any { nearby.contains(it) }
                    when {
                        hasStatus && hasReceiver -> Triple(MonetarySemanticType.TRANSACTION_AMOUNT, 0.97, "Prominent amount between payment status and recipient")
                        hasStatus || hasReceiver -> Triple(MonetarySemanticType.TRANSACTION_AMOUNT, 0.90, "Prominent amount near payment status or recipient")
                        c.hasCurrency && !isNearBottom -> Triple(MonetarySemanticType.TRANSACTION_AMOUNT, 0.75, "Currency formatted amount in upper receipt area")
                        else -> Triple(MonetarySemanticType.UNKNOWN, if (isNearBottom) 0.20 else 0.40, "Unclassified monetary candidate")
                    }
                }
            }
            MonetaryCandidate(
                amountMinor = c.amountMinor, currency = "RM", rawString = c.line, lineIndex = idx, lineText = c.line, box = c.box,
                semanticType = type, confidenceScore = score, reasoning = reason,
            )
        }

        // Totals first, then by score (stable: earlier candidates win ties).
        val best = classified.filter { !it.semanticType.isExcludedFromTransactionAmount }
            .sortedWith(compareBy<MonetaryCandidate> { it.semanticType != MonetarySemanticType.TOTAL }.thenByDescending { it.confidenceScore })
            .firstOrNull()
        if (best != null) return AmountResult(best.amountMinor, best.confidenceScore, "RM", classified)

        // Everything excluded (e.g. only fees): the best non-zero one at half confidence.
        val fallback = classified.maxByOrNull { it.confidenceScore }
        if (fallback != null && fallback.confidenceScore > 0) {
            return AmountResult(fallback.amountMinor, fallback.confidenceScore * 0.5, "RM", classified)
        }
        return AmountResult(null, 0.0, "RM", classified)
    }

    /** Backward compatible: the amount from plain lines (iOS `extractAmount`). */
    fun extractAmount(lines: List<String>, isBalanceOrLimit: Boolean): Pair<Long?, String> {
        val res = extractAndClassifyAmounts(OcrResult(lines.joinToString("\n"), lines.map { OcrLine(it, 0.95f) }, 0.95f), isBalanceOrLimit)
        return res.amountMinor to res.currency
    }

    // MARK: - Context checks

    fun checkFailedTransaction(lowerText: String): Boolean = listOf(
        "payment failed", "transaction failed", "unsuccessful", "payment unsuccessful",
        "declined", "card declined", "gagal", "transaksi gagal", "rejected", "cancelled",
    ).any { lowerText.contains(it) }

    fun checkBalanceOrLimitOnly(lines: List<String>, lowerFull: String): Boolean {
        val balance = listOf("available balance", "account balance", "baki akaun", "baki tersedia", "current balance")
        val limit = listOf("credit limit", "card limit", "had kredit", "available credit")
        val points = listOf("reward points", "point balance", "points earned", "mata ganjaran", "my rewards", "rewards", "points expiring", " points")
        val transactionIndicators = listOf("paid", "payment successful", "purchase", "total", "amount paid", "transferred", "debit", "resit", "receipt", "invoice")
        val nonExpense = (balance + limit + points).any { lowerFull.contains(it) }
        return nonExpense && transactionIndicators.none { lowerFull.contains(it) }
    }

    fun checkCompletedTransaction(lowerText: String): Boolean = listOf(
        "payment successful", "successful", "berjaya", "transaksi berjaya",
        "paid", "purchase", "transaction", "amount paid", "total", "jumlah",
        "transferred", "transfer successful", "debit", "approved", "receipt", "tax invoice",
    ).any { lowerText.contains(it) }

    fun detectNormalizedStatus(lowerFull: String, isFailed: Boolean, isBalanceOrLimit: Boolean): String = when {
        isFailed -> "failed"
        isBalanceOrLimit -> "balance_inquiry"
        lowerFull.contains("transferred") || lowerFull.contains("transfer successful") -> "transferred"
        lowerFull.contains("payment successful") || lowerFull.contains("paid") || lowerFull.contains("berjaya") -> "payment_successful"
        lowerFull.contains("approved") -> "approved"
        else -> "completed"
    }

    // MARK: - Payment source (backward compatible keyword fallback)

    fun detectPaymentSource(lowerFull: String): PaymentSource? {
        fun has(vararg k: String) = k.any { lowerFull.contains(it) }
        return when {
            has("touch 'n go", "tng ewallet", "tng digital", "touch n go") -> PaymentSource.TOUCH_N_GO
            has("maybank", "mae by maybank2u", "maybank2u", "m2u") -> PaymentSource.MAYBANK
            has("cimb", "cimb clicks", "cimb octo") -> PaymentSource.CIMB
            has("rhb", "rhb now", "rhb mobile") -> PaymentSource.RHB
            has("public bank", "pbe", "pb engage") -> PaymentSource.PUBLIC_BANK
            has("bank islam", "bimb") -> PaymentSource.BANK_ISLAM
            has("grabpay", "grab pay") -> PaymentSource.GRAB_PAY
            has("boost") -> PaymentSource.BOOST
            has("duitnow qr", "paynet qr", "qr pay") -> PaymentSource.QR_PAYMENT
            has("duitnow transfer", "duitnow") -> PaymentSource.DUITNOW
            has("apple pay", "apple wallet") -> PaymentSource.APPLE_PAY
            has("visa", "mastercard", "credit card", "debit card") -> PaymentSource.PHYSICAL_CARD
            has("interbank transfer", "bank transfer", "ibg") -> PaymentSource.BANK_TRANSFER
            has("cash", "tunai") -> PaymentSource.CASH
            else -> null
        }
    }

    // MARK: - Date & time

    data class DateTimeResult(val dateTime: LocalDateTime?, val dateString: String?, val timeString: String?)

    private val dateFormats = listOf(
        "dd MMM yyyy", "dd MMMM yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "dd-MMM-yyyy", "yyyy-MM-dd", "dd/MM/yy", "MMM dd, yyyy", "dd MMM yy",
    ).map(::DatePatternParser)
    private val timeFormats = listOf("h:mm:ss a", "h:mm a", "h:mma", "h:mm:ssa", "HH:mm:ss", "HH:mm").map(::DatePatternParser)
    private val labelPrefixes = listOf("date:", "date :", "tarikh:", "tarikh :", "time:", "time :", "masa:", "masa :")
    private val embeddedDate = icuRegex(
        """\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\b""",
        caseInsensitive = true,
    )
    private val embeddedTime = icuRegex("""\b(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp][Mm])?)\b""")

    private fun parseDate(text: String, clock: Clock) = dateFormats.firstNotNullOfOrNull { it.parse(text, clock) }
    private fun parseTime(text: String, clock: Clock) = timeFormats.firstNotNullOfOrNull { it.parse(text, clock) }

    /**
     * The receipt's date and time: a line that is exactly a date / a time (after "Date:", "Time:", "Tarikh:", "Masa:"
     * labels), else the first date / time embedded in the text. No date → nothing (a time alone is not used);
     * no time → 12:00:00.
     */
    fun extractDateTimeAndStrings(lines: List<String>, fullText: String, clock: Clock = Clock.systemDefaultZone()): DateTimeResult {
        var date: DatePatternParser.Parsed? = null
        var time: DatePatternParser.Parsed? = null

        for (line in lines) {
            var cleaned = line.trimWs()
            for (p in labelPrefixes) {
                if (cleaned.lowercase().startsWith(p)) cleaned = cleaned.drop(p.length).trimWs()
            }
            val cleanedDate = cleaned.trim { it == ' ' || it == ',' }
            if (date == null) date = parseDate(cleanedDate, clock)
            if (time == null) time = parseTime(cleaned, clock)
        }

        if (date == null) {
            embeddedDate.firstGroup(fullText)?.let { date = parseDate(it, clock) }
        }
        if (time == null) {
            val m = embeddedTime.matcher(fullText)
            while (m.find()) {
                time = parseTime(m.group(1).trimWs(), clock)
                if (time != null) break
            }
        }

        val d = date ?: return DateTimeResult(null, null, null)
        val year = d.year!!; val month = d.month!!; val day = d.day!!
        val dateString = "%04d-%02d-%02d".format(year, month, day)
        val t = time
        val hour = t?.hour ?: 12
        val minute = t?.minute ?: 0
        val second = t?.second ?: 0
        val timeString = if (t?.hour != null && t.minute != null) "%02d:%02d:%02d".format(hour, minute, second) else null
        return DateTimeResult(LocalDateTime.of(year, month, day, hour, minute, second), dateString, timeString)
    }

    // MARK: - Reference

    private const val REF_LABEL = """(?:ref(?:\.|erence)?\s*(?:no|id)?|trans(?:action)?\s*(?:id|no)|receipt\s*(?:no|#)?|no\.\s*rujukan)"""
    // A reference always contains a digit; this also stops a label fragment ("erence") being read as the value.
    private const val REF_VALUE = """((?=[A-Za-z0-9\-]*\d)[A-Za-z0-9\-]{6,30})"""
    private val refSameLine = icuRegex(REF_LABEL + """\s*[:\-]?\s*""" + REF_VALUE, caseInsensitive = true)
    private val refLabelOnly = icuRegex("^\\s*" + REF_LABEL + """\s*[:\-]?\s*$""", caseInsensitive = true)
    private val refValueOnly = icuRegex("^\\s*" + REF_VALUE + "\\s*$")

    /** The transaction reference: "Ref No: X", or a reference label alone on a line with the value on the next line. */
    fun extractReferenceNumber(lines: List<String>): String? {
        lines.forEachIndexed { index, line ->
            refSameLine.firstGroup(line)?.let { return it.trimWs() }
            if (refLabelOnly.containsMatchIn(line) && index + 1 < lines.size) {
                refValueOnly.firstGroup(lines[index + 1])?.let { return it }
            }
        }
        return null
    }
}
