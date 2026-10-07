package com.spendrop.core.model

/** Expense categories. [raw] is the value stored by iOS (ExpenseCategory.rawValue) and in `expenses.category`. */
enum class ExpenseCategory(val raw: String) {
    FOOD("Food"), GROCERIES("Groceries"), TRANSPORT("Transport"), SHOPPING("Shopping"), BILLS("Bills"),
    ENTERTAINMENT("Entertainment"), EDUCATION("Education"), HEALTH("Health"), TRAVEL("Travel"),
    PERSONAL("Personal"), SUBSCRIPTION("Subscription"), OTHER("Other");

    val displayName: String get() = raw

    companion object {
        fun fromRaw(raw: String?): ExpenseCategory = entries.firstOrNull { it.raw == raw } ?: OTHER
        fun fromRawOrNull(raw: String?): ExpenseCategory? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * HOW a payment was made. Never a funding account. UNKNOWN is explicit and valid: never guess a channel.
 * Raw values match iOS PaymentChannel.rawValue and `expenses.payment_channel`.
 */
enum class PaymentChannel(val raw: String, val displayName: String) {
    APPLE_PAY("APPLE_PAY", "Apple Pay"),
    QR_PAYMENT("QR_PAYMENT", "QR Payment"),
    BANK_TRANSFER("BANK_TRANSFER", "Bank Transfer"),
    CARD("CARD", "Card"),
    CASH("CASH", "Cash"),
    DUITNOW_QR("DUITNOW_QR", "DuitNow QR"),
    ONLINE_BANKING("ONLINE_BANKING", "Online Banking"),
    E_WALLET("E_WALLET", "E-Wallet"),
    OTHER("OTHER", "Other"),
    UNKNOWN("UNKNOWN", "Unknown"),
    TNG_QR("TNG_QR", "Touch 'n Go QR");

    companion object {
        fun fromRaw(raw: String?): PaymentChannel = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        fun fromRawOrNull(raw: String?): PaymentChannel? = entries.firstOrNull { it.raw == raw }
        /** Order used in pickers (matches Common/Constants/payment-channels.json). */
        val pickerOrder = listOf(APPLE_PAY, QR_PAYMENT, DUITNOW_QR, TNG_QR, BANK_TRANSFER, ONLINE_BANKING, CARD, E_WALLET, CASH, OTHER, UNKNOWN)
    }
}

/** Funding account type (WHERE the money came from). */
enum class AccountType(val raw: String, val displayName: String) {
    BANK("bank", "Bank"), E_WALLET("eWallet", "E-Wallet"), CASH("cash", "Cash"), OTHER("other", "Other");

    companion object {
        fun fromRaw(raw: String?): AccountType = entries.firstOrNull { it.raw == raw } ?: OTHER
    }
}

enum class ExpenseSourceType(val raw: String, val displayName: String) {
    MANUAL("manual", "Manual Entry"),
    SCREENSHOT("screenshot", "Screenshot"),
    PHOTO("photo", "Photo"),
    RECEIPT("receipt", "Receipt"),
    SHARE_EXTENSION("shareExtension", "Shared to SpenDrop"),
    APPLE_WALLET("appleWallet", "Apple Pay Automation");

    companion object {
        fun fromRaw(raw: String?): ExpenseSourceType = entries.firstOrNull { it.raw == raw } ?: MANUAL
    }
}

/** How a shared expense was divided (`expenses.split_method`; null = not shared). */
enum class SplitMethod(val raw: String, val displayName: String) {
    EQUAL("equal", "Split Equally"), PARTS("parts", "Parts"), AMOUNTS("amounts", "Custom Amount");

    companion object {
        fun fromRaw(raw: String?): SplitMethod? = entries.firstOrNull { it.raw == raw }
    }
}

enum class MoneyDirection(val raw: String) {
    IN("in"), OUT("out"),
    /** Between the user's own accounts. Never counted as spending, money in or money out. */
    INTERNAL("internal");

    companion object {
        fun fromRaw(raw: String?): MoneyDirection = entries.firstOrNull { it.raw == raw } ?: OUT
    }
}

enum class MoneyMovementKind(val raw: String, val displayName: String, val direction: MoneyDirection, val personBalanceSign: Int) {
    INCOME("income", "Income", MoneyDirection.IN, 0),
    LOAN_RECEIVED("loanReceived", "Loan received", MoneyDirection.IN, -1),
    REPAYMENT_RECEIVED("repaymentReceived", "Repayment received", MoneyDirection.IN, -1),
    REFUND("refund", "Refund", MoneyDirection.IN, 0),
    OTHER_IN("otherIn", "Other money in", MoneyDirection.IN, 0),
    LOAN_GIVEN("loanGiven", "Loan given", MoneyDirection.OUT, 1),
    REPAYMENT_MADE("repaymentMade", "Repayment made", MoneyDirection.OUT, 1),
    OTHER_OUT("otherOut", "Other money out", MoneyDirection.OUT, 0),
    OWN_TRANSFER("ownTransfer", "Own transfer", MoneyDirection.INTERNAL, 0);

    val requiresPerson: Boolean get() = personBalanceSign != 0

    companion object {
        fun fromRaw(raw: String?, direction: MoneyDirection? = null): MoneyMovementKind =
            entries.firstOrNull { it.raw == raw } ?: if (direction == MoneyDirection.IN) OTHER_IN else OTHER_OUT
        val moneyInKinds = entries.filter { it.direction == MoneyDirection.IN }
        val moneyOutKinds = entries.filter { it.direction == MoneyDirection.OUT }
    }
}

enum class PaymentMethodType(val raw: String, val identifierFieldLabel: String) {
    BANK_ACCOUNT("Bank Account", "Account Number"),
    E_WALLET("E-Wallet", "Phone Number / Wallet ID"),
    PAYMENT_ID("Payment ID", "Payment ID"),
    OTHER("Other", "Payment Identifier");

    companion object {
        fun fromRaw(raw: String?): PaymentMethodType = entries.firstOrNull { it.raw == raw } ?: BANK_ACCOUNT
        val commonProviders = listOf(
            "CIMB Bank", "Maybank", "RHB Bank", "Affin Bank", "Public Bank", "Hong Leong Bank", "AmBank", "Bank Islam",
            "Bank Rakyat", "OCBC Bank", "UOB", "HSBC", "Standard Chartered", "Touch 'n Go", "GrabPay", "DuitNow", "Other",
        )
    }
}

enum class SettlementKind(val raw: String) {
    /** Part of a new payment recorded together with this allocation (undo removes the payment too). */
    PAYMENT("payment"),
    /** Assigns part of an existing, earlier payment (undo removes only this allocation). */
    ASSIGN("assign"),
    /** "Settle All": a debt in one direction cancelled against one in the other. No money moved. */
    OFFSET("offset");

    companion object {
        fun fromRaw(raw: String?): SettlementKind = entries.firstOrNull { it.raw == raw } ?: PAYMENT
    }
}

/** Legacy iOS PaymentSource (kept for old records and backups). */
enum class PaymentSource(val raw: String, val defaultPaymentMethod: String) {
    TOUCH_N_GO("Touch 'n Go", "ewallet"), MAYBANK("Maybank", "bank_transfer"), CIMB("CIMB", "bank_transfer"),
    RHB("RHB", "bank_transfer"), PUBLIC_BANK("Public Bank", "bank_transfer"), BANK_ISLAM("Bank Islam", "bank_transfer"),
    GRAB_PAY("GrabPay", "ewallet"), BOOST("Boost", "ewallet"), DUITNOW("DuitNow", "bank_transfer"), WISE("Wise", "digital_wallet"),
    APPLE_PAY("Apple Pay", "digital_wallet"), PHYSICAL_CARD("Physical Card", "card"), QR_PAYMENT("QR Payment", "qr_code"),
    CASH("Cash", "cash"), BANK_TRANSFER("Bank Transfer", "bank_transfer"), OTHER("Other", "unknown"), UNKNOWN("Unknown", "unknown");

    /** Sources that describe HOW, not WHERE — never a funding account. */
    val isChannelLike: Boolean get() = this in setOf(APPLE_PAY, QR_PAYMENT, BANK_TRANSFER, PHYSICAL_CARD, UNKNOWN, OTHER)

    companion object {
        fun fromRaw(raw: String?): PaymentSource = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        fun fromRawOrNull(raw: String?): PaymentSource? = entries.firstOrNull { it.raw == raw }
    }
}
