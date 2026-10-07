package com.spendrop.core.parser

import com.spendrop.core.Money
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import java.time.LocalDateTime

enum class MonetarySemanticType(val raw: String, val displayName: String) {
    TRANSACTION_AMOUNT("transaction_amount", "Transaction Amount"),
    TOTAL("total", "Total"),
    FEE("fee", "Fee"),
    BALANCE("balance", "Balance"),
    CASHBACK("cashback", "Cashback"),
    DISCOUNT("discount", "Discount"),
    PROMOTION("promotion", "Promotion"),
    ADVERTISEMENT("advertisement", "Advertisement"),
    PRODUCT_PRICE("product_price", "Product Price"),
    UNKNOWN("unknown", "Unknown");

    val isExcludedFromTransactionAmount: Boolean
        get() = this in setOf(FEE, BALANCE, CASHBACK, DISCOUNT, PROMOTION, ADVERTISEMENT, PRODUCT_PRICE)
}

/** One money amount found on the receipt, with what the parser thinks it is (iOS `MonetaryCandidate`). */
data class MonetaryCandidate(
    val amountMinor: Long,
    val currency: String = "RM",
    val rawString: String,
    val lineIndex: Int,
    val lineText: String,
    val box: OcrBox? = null,
    val semanticType: MonetarySemanticType = MonetarySemanticType.UNKNOWN,
    /** 0.0 to 1.0 */
    val confidenceScore: Double = 0.5,
    val reasoning: String = "",
)

enum class ParsingConfidence(val raw: String) {
    HIGH("High"), MEDIUM("Medium"), LOW("Low");

    val isConfident: Boolean get() = this == HIGH || this == MEDIUM
}

/** Everything the parser read from one receipt (iOS `ParsedTransaction`). Money is sen. */
data class ParsedTransaction(
    val amountMinor: Long? = null,
    val amountConfidence: Double = 0.5,
    val currency: String = "RM",
    val merchant: String? = null,
    /** The transaction moment as epoch millis (local date/time interpreted in the parser's zone). */
    val date: Long? = null,
    /** The same moment as read from the receipt (no zone). */
    val localDateTime: LocalDateTime? = null,
    /** "yyyy-MM-dd" */
    val dateString: String? = null,
    /** "HH:mm:ss" */
    val timeString: String? = null,
    val paymentSource: PaymentSource? = null,
    /** Normalised provider id, e.g. "touch_n_go", "maybank", "unknown". */
    val provider: String = "unknown",
    val providerConfidence: Double = 0.0,
    val paymentMethod: String? = null,
    val paymentChannel: PaymentChannel = PaymentChannel.UNKNOWN,
    val fundingAccount: String? = null,
    val fundingInstrument: String? = null,
    val underlyingBank: PaymentSource? = null,
    val underlyingBankNormalizedId: String? = null,
    val suggestedRemark: String? = null,
    val category: ExpenseCategory? = null,
    val transactionReference: String? = null,
    val transactionStatus: String? = null,
    val confidence: ParsingConfidence = ParsingConfidence.LOW,
    val rawOCRText: String = "",
    val detectedLines: List<String> = emptyList(),
    val amountCandidates: List<MonetaryCandidate> = emptyList(),
    /** Suggested non-expense type from clear wording (money received, refund, top-up). null = expense / unsure. */
    val suggestedMovementKind: MoneyMovementKind? = null,
    /** How sure the parser is about [category] (0…1). Below 0.7 the review screen asks to check it. */
    val categoryConfidence: Double = 1.0,
    val categoryReason: String? = null,
    /** How sure the parser is about [paymentChannel]. Unknown means "the receipt doesn't say". */
    val channelConfidence: Double = 1.0,
    val channelReason: String? = null,
    val directionReason: String? = null,
    val isCompletedTransaction: Boolean = false,
    val isFailedTransaction: Boolean = false,
    val isBalanceOrLimitOnly: Boolean = false,
) {
    /** Legacy Double view of the amount (display only). */
    val amount: Double? get() = amountMinor?.let { Money.major(it) }

    /** iOS `toNormalizedDictionary()`. */
    fun toNormalizedMap(): Map<String, Any?> {
        val map = linkedMapOf<String, Any?>(
            "paymentProvider" to provider,
            "provider" to provider,
            "providerConfidence" to providerConfidence,
            "paymentMethod" to (paymentMethod ?: "unknown"),
            "currency" to (if (currency == "RM") "MYR" else currency),
            "status" to (transactionStatus?.lowercase() ?: "unknown"),
            "underlyingBank" to underlyingBankNormalizedId,
        )
        amountMinor?.let { map["amount"] = Money.major(it); map["amountMinor"] = it; map["amountConfidence"] = amountConfidence }
        merchant?.let { map["merchant"] = it }
        dateString?.let { map["date"] = it }
        timeString?.let { map["time"] = it }
        return map
    }

    val displayMerchant: String get() = merchant ?: "Unknown Merchant"
    val displayPaymentSource: PaymentSource get() = paymentSource ?: PaymentSource.UNKNOWN
    val displayCategory: ExpenseCategory get() = category ?: ExpenseCategory.OTHER
    fun displayDate(nowMillis: Long = System.currentTimeMillis()): Long = date ?: nowMillis

    /** WHERE the money came from: the stated funding account, else the bank behind it, else a non-channel source. */
    val displayFundingAccount: String
        get() {
            val fa = fundingAccount
            if (!fa.isNullOrEmpty() && fa != "Unknown") return fa
            val bank = underlyingBank
            if (bank != null && bank != PaymentSource.UNKNOWN) return bank.raw
            val src = paymentSource
            if (src != null && src !in CHANNEL_LIKE_SOURCES) return src.raw
            return "Unknown"
        }

    internal companion object {
        /** Payment sources that describe HOW, not WHERE (never shown as a funding account). */
        val CHANNEL_LIKE_SOURCES = setOf(
            PaymentSource.APPLE_PAY, PaymentSource.QR_PAYMENT, PaymentSource.BANK_TRANSFER, PaymentSource.PHYSICAL_CARD, PaymentSource.UNKNOWN,
        )
    }
}
