package com.spendrop.core.insights

import com.spendrop.core.model.Expense
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource

/**
 * iOS `Expense.paymentChannel` getter: the stored channel, or — only for an unrecognised raw value (old records) —
 * a conservative fallback from the legacy payment source / method. (Core's `Expense.paymentChannel` maps unknown raw
 * values straight to UNKNOWN; this keeps the iOS fallback.)
 */
val Expense.iosPaymentChannel: PaymentChannel
    get() {
        PaymentChannel.fromRawOrNull(paymentChannelRaw)?.let { return it }
        return when {
            paymentSourceRaw == PaymentSource.APPLE_PAY.raw || paymentMethodRaw == "digital_wallet" -> PaymentChannel.APPLE_PAY
            paymentSourceRaw == PaymentSource.QR_PAYMENT.raw || paymentMethodRaw == "duitnow_qr" -> PaymentChannel.QR_PAYMENT
            paymentSourceRaw == PaymentSource.BANK_TRANSFER.raw || paymentMethodRaw == "bank_transfer" -> PaymentChannel.BANK_TRANSFER
            paymentSourceRaw == PaymentSource.PHYSICAL_CARD.raw || paymentMethodRaw == "card" -> PaymentChannel.CARD
            paymentSourceRaw == PaymentSource.CASH.raw && (paymentMethodRaw == "cash" || fundingAccount == "Cash") -> PaymentChannel.CASH
            else -> PaymentChannel.UNKNOWN
        }
    }

/** Swift `split(whereSeparator: \.isWhitespace).joined(separator: " ")`: words separated by single spaces. */
fun String.collapseWhitespace(): String {
    val sb = StringBuilder()
    var pendingSpace = false
    for (c in this) {
        if (c.isWhitespace()) {
            pendingSpace = sb.isNotEmpty()
        } else {
            if (pendingSpace) sb.append(' ')
            pendingSpace = false
            sb.append(c)
        }
    }
    return sb.toString()
}
