package com.spendrop.core.parser

import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource

/** A payment channel with how sure SpenDrop is and why (iOS `ChannelSuggestion`). */
data class ChannelSuggestion(val channel: PaymentChannel, val confidence: Double, val reason: String) {
    /** Unknown is a confident answer ("not enough evidence"). */
    val needsReview: Boolean get() = channel == PaymentChannel.UNKNOWN
}

/**
 * Evidence-first payment channel detection (iOS `PaymentChannel.suggest` / `detect`). HOW a payment was made, never
 * the funding account: a bank or wallet name alone (Maybank, Touch 'n Go) is never channel evidence, and neither is
 * a parser's default payment method. Without explicit wording the answer is Unknown.
 */
object ChannelDetector {
    /** Phrases that are explicit evidence for each channel (whole words; most specific first). */
    val evidence: List<Triple<PaymentChannel, Double, List<String>>> = listOf(
        Triple(PaymentChannel.APPLE_PAY, 0.98, listOf("apple pay", "pay with apple", "apple cash")),
        Triple(PaymentChannel.DUITNOW_QR, 0.97, listOf("duitnow qr", "duitnow-qr", "duit now qr", "d-qr", "paynet qr")),
        Triple(PaymentChannel.TNG_QR, 0.95, listOf("touch 'n go qr", "touch n go qr", "tng qr", "tng ewallet qr", "touchngo qr")),
        Triple(
            PaymentChannel.CARD, 0.92,
            listOf(
                "card purchase", "pos purchase", "pos card", "card present", "contactless", "chip & pin", "chip and pin",
                "card payment", "debit card purchase", "credit card purchase", "card transaction",
            ),
        ),
        Triple(
            PaymentChannel.BANK_TRANSFER, 0.9,
            listOf(
                "duitnow transfer", "fund transfer", "funds transfer", "interbank", "ibg", "instant transfer",
                "transfer to account", "transferred to", "giro", "fpx", "fpx payment", "bank transfer", "transfer successful",
                "online transfer", "jompay",
            ),
        ),
        Triple(PaymentChannel.QR_PAYMENT, 0.8, listOf("scan & pay", "scan and pay", "qr pay", "qr payment", "scan qr", "via qr", "qr code payment", "pay by qr")),
        Triple(PaymentChannel.OTHER, 0.75, listOf("online payment", "online purchase", "pay online", "online transaction")),
        Triple(PaymentChannel.CASH, 0.85, listOf("cash", "cash payment", "paid in cash", "tunai", "wang tunai")),
    )

    /** The channel with confidence and reason. Unknown (confidence 1) when the receipt has no channel wording. */
    fun suggest(
        evidenceText: String,
        paymentSource: PaymentSource? = null,
        detectedSource: DetectedTransactionSource = DetectedTransactionSource.UNKNOWN,
    ): ChannelSuggestion {
        if (detectedSource == DetectedTransactionSource.APPLE_WALLET) {
            return ChannelSuggestion(PaymentChannel.APPLE_PAY, 0.98, "Apple Wallet receipt")
        }
        val haystack = " " + MerchantDetector.normalizedWords(evidenceText) + " "
        for ((channel, confidence, phrases) in evidence) {
            val phrase = phrases.firstOrNull { haystack.contains(" " + MerchantDetector.normalizedWords(it) + " ") }
            if (phrase != null) return ChannelSuggestion(channel, confidence, "Receipt says '$phrase'")
        }
        // Older records: an explicit channel stored as the payment source.
        return when (paymentSource) {
            PaymentSource.APPLE_PAY -> ChannelSuggestion(PaymentChannel.APPLE_PAY, 0.9, "Paid with Apple Pay")
            PaymentSource.PHYSICAL_CARD -> ChannelSuggestion(PaymentChannel.CARD, 0.85, "Paid by card")
            else -> ChannelSuggestion(PaymentChannel.UNKNOWN, 1.0, "The receipt doesn't say how it was paid")
        }
    }

    /** Kept for existing callers: the channel only. */
    fun detect(
        text: String,
        paymentSource: PaymentSource? = null,
        detectedSource: DetectedTransactionSource = DetectedTransactionSource.UNKNOWN,
    ): PaymentChannel = suggest(text, paymentSource, detectedSource).channel
}
