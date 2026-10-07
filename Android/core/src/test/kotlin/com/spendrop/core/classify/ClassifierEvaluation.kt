package com.spendrop.core.classify

import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.PaymentChannel

/**
 * Port of iOS `ClassifierEvaluation` (OCR/ImagePipelineDiagnostics.swift): 25 synthetic, anonymised Malaysian receipts
 * with the expected merchant, category, payment channel and funding account. `expectedCategory == null` means "too
 * ambiguous to decide": the correct result is Other / low confidence, never a confident guess.
 */
object ClassifierEvaluation {
    data class Case(
        val name: String,
        val lines: List<String>,
        val merchantContains: String?,
        val expectedCategory: ExpenseCategory?,
        val expectedChannel: PaymentChannel,
        val expectedFunding: String,
    )

    data class Output(
        val merchant: String?,
        val category: ExpenseCategory,
        /** false = shown as a suggestion that needs review (low confidence). */
        val categoryConfident: Boolean,
        val channel: PaymentChannel,
        val funding: String,
    )

    fun tng(type: String, merchant: String, amount: String = "12.50"): List<String> = listOf(
        "Transaction Details", "Successful", "- RM $amount", "Transaction Type", type, "Merchant", merchant,
        "Payment Method", "eWallet Balance", "Date/Time", "05/10/2026 13:22", "Transaction No.", "2026100512345678",
    )

    private const val TNG = "Touch 'n Go"

    val cases: List<Case> = listOf(
        // Touch 'n Go (funding account) with different merchants and channels
        Case("TNG DuitNow QR restaurant", tng("DuitNow QR", "NASI KANDAR PELITA"), "pelita", ExpenseCategory.FOOD, PaymentChannel.DUITNOW_QR, TNG),
        Case("TNG payment McDonald's", tng("Payment", "MCDONALD'S BANGSAR"), "mcdonald", ExpenseCategory.FOOD, PaymentChannel.UNKNOWN, TNG),
        Case("TNG payment grocery", tng("Payment", "JAYA GROCER"), "jaya grocer", ExpenseCategory.GROCERIES, PaymentChannel.UNKNOWN, TNG),
        Case("TNG payment transport", tng("Payment", "PRASARANA RAPID KL"), "rapid", ExpenseCategory.TRANSPORT, PaymentChannel.UNKNOWN, TNG),
        Case("TNG online Shopee", tng("Online Payment", "SHOPEE MALAYSIA"), "shopee", ExpenseCategory.SHOPPING, PaymentChannel.OTHER, TNG),
        Case("TNG unknown merchant", tng("Payment", "AH SENG ENTERPRISE"), "ah seng", null, PaymentChannel.UNKNOWN, TNG),
        Case("TNG QR warung", tng("Touch 'n Go QR", "WARUNG MAK LONG"), "warung", ExpenseCategory.FOOD, PaymentChannel.TNG_QR, TNG),
        Case("TNG GrabFood", tng("Payment", "GRABFOOD"), "grab", ExpenseCategory.FOOD, PaymentChannel.UNKNOWN, TNG),
        Case("TNG GrabCar", tng("Payment", "GRABCAR"), "grab", ExpenseCategory.TRANSPORT, PaymentChannel.UNKNOWN, TNG),
        Case("TNG Grab (no context)", tng("Payment", "GRAB"), "grab", null, PaymentChannel.UNKNOWN, TNG),
        // Maybank
        Case("Maybank DuitNow QR", listOf("Maybank", "Successful", "RM 15.00", "DuitNow QR", "Recipient", "TEALIVE KLCC", "Reference ID", "QR80504572", "Date & Time", "06 Oct 2026, 12:31 PM"),
            "tealive", ExpenseCategory.FOOD, PaymentChannel.DUITNOW_QR, "Maybank"),
        Case("Maybank transfer", listOf("Maybank", "Transfer Successful", "RM 50.00", "DuitNow Transfer", "Recipient's Name", "ALI BIN ABU", "Recipient's Bank", "CIMB Bank", "Reference ID", "MB20261006001"),
            "ali bin abu", null, PaymentChannel.BANK_TRANSFER, "Maybank"),
        Case("Maybank card", listOf("Maybank", "Card Purchase", "Maybank Visa Debit", "RM 32.90", "Merchant", "UNIQLO MID VALLEY", "Approval Code 123456", "06 Oct 2026"),
            "uniqlo", ExpenseCategory.SHOPPING, PaymentChannel.CARD, "Maybank"),
        Case("Maybank no channel", listOf("Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN SELERA", "Reference ID", "MB12345678"),
            "selera", ExpenseCategory.FOOD, PaymentChannel.UNKNOWN, "Maybank"),
        // CIMB
        Case("CIMB DuitNow QR", listOf("CIMB OCTO", "Payment successful", "RM 18.90", "DuitNow QR", "Paid to", "ZUS COFFEE SUNWAY", "OCTO Reference No.", "C2026100555"),
            "zus", ExpenseCategory.FOOD, PaymentChannel.DUITNOW_QR, "CIMB"),
        Case("CIMB transfer", listOf("CIMB OCTO", "Transfer successful", "RM 100.00", "Instant Transfer", "To", "AHMAD BIN ALI", "Recipient bank Maybank", "OCTO Reference No.", "C2026100777"),
            "ahmad", null, PaymentChannel.BANK_TRANSFER, "CIMB"),
        Case("CIMB card fuel", listOf("CIMB", "Card Purchase", "CIMB Mastercard Debit", "RM 120.00", "Merchant", "SHELL MALAYSIA TRADING", "Approval Code 654321"),
            "shell", ExpenseCategory.TRANSPORT, PaymentChannel.CARD, "CIMB"),
        Case("CIMB no channel", listOf("CIMB OCTO", "Successful", "RM 9.00", "Paid to", "KOPITIAM HAPPY", "OCTO Reference No.", "C1234567890"),
            "kopitiam", ExpenseCategory.FOOD, PaymentChannel.UNKNOWN, "CIMB"),
        // RHB
        Case("RHB DuitNow QR", listOf("RHB", "Transaction Successful", "RM 25.00", "DuitNow QR", "Merchant Name", "7-ELEVEN MALAYSIA", "Reference No.", "RHB20261005777"),
            "7-eleven", ExpenseCategory.GROCERIES, PaymentChannel.DUITNOW_QR, "RHB"),
        Case("RHB transfer", listOf("RHB", "Transaction Successful", "RM 300.00", "Fund Transfer", "Beneficiary Name", "SITI AMINAH", "Reference No.", "RHB123456789"),
            "siti", null, PaymentChannel.BANK_TRANSFER, "RHB"),
        Case("RHB card", listOf("RHB", "Card Purchase", "RHB Visa Debit", "RM 59.00", "Merchant", "WATSONS PERSONAL CARE", "Approval Code 111222"),
            "watsons", ExpenseCategory.HEALTH, PaymentChannel.CARD, "RHB"),
        Case("RHB no channel", listOf("RHB", "Successful", "RM 12.00", "Recipient", "ABC TRADING", "Reference No.", "RHB555666777"),
            "abc trading", null, PaymentChannel.UNKNOWN, "RHB"),
        // Other channels
        Case("Apple Pay", listOf("Apple Pay", "STARBUCKS PAVILION", "RM 18.50", "Maybank Visa Debit", "Status: Approved"),
            "starbucks", ExpenseCategory.FOOD, PaymentChannel.APPLE_PAY, "Maybank"),
        Case("Generic Scan & Pay", listOf("Payment Successful", "RM 6.00", "Scan & Pay", "Merchant", "PASAR MALAM STALL", "Date 05/10/2026"),
            "pasar malam", ExpenseCategory.GROCERIES, PaymentChannel.QR_PAYMENT, "Unknown"),
        Case("Business wording trap", tng("Payment", "SMART BUSINESS PROVIDER SDN BHD"), "smart business", null, PaymentChannel.UNKNOWN, TNG),
    )

    /** Merchant-name variants that should (or must not) normalise to a known merchant. */
    val normalization: List<Pair<String, String?>> = listOf(
        "McDonald's" to "McDonald's", "MCD" to "McDonald's", "McD" to "McDonald's", "MCDONALDS" to "McDonald's",
        "MCDONALD'S MALAYSIA" to "McDonald's", "7 ELEVEN" to "7-Eleven", "7-ELEVEN" to "7-Eleven", "7ELEVEN" to "7-Eleven",
        "Lotus's" to "Lotus's", "LOTUSS MALAYSIA" to "Lotus's", "GRABFOOD" to "GrabFood", "SHELL MALAYSIA TRADING" to "Shell",
        "MCDERMOTT LAW" to null, "SHELLY BEAUTY" to null, "DIGITAL STORE" to null, "ATMOS CAFE" to null, "AMAZARA TRAVEL" to null,
        "TMART KEDAI" to null,
    )

    data class Score(
        var total: Int = 0, var category: Int = 0, var channel: Int = 0, var funding: Int = 0, var merchant: Int = 0,
        var confidentWrongCategory: Int = 0, var wrongChannelNotUnknown: Int = 0, var lowConfidence: Int = 0,
        val misses: MutableList<String> = mutableListOf(),
    )

    fun score(classify: (List<String>) -> Output): Score {
        val s = Score()
        for (c in cases) {
            val out = classify(c.lines)
            s.total += 1
            val categoryOK: Boolean
            if (c.expectedCategory != null) {
                categoryOK = out.category == c.expectedCategory
                if (!categoryOK && out.categoryConfident) s.confidentWrongCategory += 1
            } else {
                categoryOK = out.category == ExpenseCategory.OTHER || !out.categoryConfident
                if (!categoryOK) s.confidentWrongCategory += 1
            }
            if (!out.categoryConfident) s.lowConfidence += 1
            if (categoryOK) s.category += 1 else s.misses += "${c.name}: category ${out.category.raw}${if (out.categoryConfident) "" else "?"}"
            if (out.channel == c.expectedChannel) s.channel += 1 else {
                s.misses += "${c.name}: channel ${out.channel.raw}"
                if (out.channel != PaymentChannel.UNKNOWN) s.wrongChannelNotUnknown += 1
            }
            if (out.funding.lowercase() == c.expectedFunding.lowercase()) s.funding += 1 else s.misses += "${c.name}: funding ${out.funding}"
            val m = c.merchantContains
            if (m != null && (out.merchant ?: "").lowercase().contains(m)) s.merchant += 1
            else if (m != null) s.misses += "${c.name}: merchant ${out.merchant ?: "nil"}"
        }
        return s
    }
}
