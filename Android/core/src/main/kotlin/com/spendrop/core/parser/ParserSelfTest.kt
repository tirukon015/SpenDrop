package com.spendrop.core.parser

import com.spendrop.core.Money
import com.spendrop.core.duplicates.DuplicateDetector
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import java.time.ZoneOffset

/**
 * Settings → "Run OCR & Parser Self-Test" (iOS ParserSelfTestView). Runs Malaysian payment screenshots, false
 * positives, balances, multi-amount receipts and duplicate detection through the same parser the app uses.
 */
object ParserSelfTest {
    data class Result(val testName: String, val passed: Boolean, val details: String, val actual: String)

    private data class Case(val name: String, val details: String, val text: String, val check: (ParsedTransaction) -> Boolean)

    private val cases = listOf(
        Case("TNG McDonald's payment", "RM18.50, merchant McDonald's, Food", "Touch 'n Go eWallet\nPayment Successful\nRM18.50\nPaid to: McDonald's\n16 Sep 2026 9:42 PM\nRef No: TNG992837194") {
            it.amountMinor == 1850L && it.merchant == "McDonald's" && it.category == ExpenseCategory.FOOD
        },
        Case("Maybank transfer to MYDIN", "RM42.90, Groceries", "Maybank2u\nTransfer Successful\nAmount: RM42.90\nRecipient: MYDIN\n16/09/2026\nReference: MBB20260916892") {
            it.amountMinor == 4290L && it.merchant == "MYDIN" && it.category == ExpenseCategory.GROCERIES
        },
        Case("Apple Pay Starbucks", "RM25.90, merchant Starbucks", "Apple Pay\nPaid RM25.90\nStarbucks\n16 Sep 2026") {
            it.amountMinor == 2590L && it.merchant == "Starbucks"
        },
        Case("Receipt total beats subtotal and tax", "Total RM21.20", "KOPITIAM RESTORAN\nTax Invoice\nSubtotal RM20.00\nSST 6% RM1.20\nTotal RM21.20\nCash") { it.amountMinor == 2120L },
        Case("Account balance is not an expense", "Balance only, no amount", "Maybank2u\nWelcome Back\nAvailable Balance\nRM1,250.00\nAccount No: 114012345678") {
            it.isBalanceOrLimitOnly && it.amountMinor == null
        },
        Case("Credit limit is not an expense", "Limit only, no amount", "RHB Bank\nCredit Limit\nRM5,000.00\nAvailable Credit: RM4,500.00") { it.isBalanceOrLimitOnly && it.amountMinor == null },
        Case("Failed payment detected", "Marked as failed", "Touch 'n Go eWallet\nPayment Failed\nRM25.90\nReason: Insufficient Balance") { it.isFailedTransaction },
        Case("CIMB DuitNow to Shell", "RM50.00, Transport", "CIMB OCTO\nDuitNow Transfer Successful\nRM50.00\nPaid to: Shell") {
            it.amountMinor == 5000L && it.merchant == "Shell" && it.category == ExpenseCategory.TRANSPORT
        },
    )

    fun run(): List<Result> {
        val results = cases.map { c ->
            val p = runCatching { TransactionParser.parse(c.text, lineConfidence = 0.95f, zone = ZoneOffset.UTC) }.getOrNull()
            val actual = p?.let { "amount ${it.amountMinor?.let(Money::format) ?: "none"} · merchant ${it.merchant ?: "none"} · ${it.category?.raw ?: "no category"}" +
                (if (it.isFailedTransaction) " · failed" else "") + (if (it.isBalanceOrLimitOnly) " · balance/limit" else "") } ?: "parser error"
            Result(c.name, p != null && c.check(p), c.details, actual)
        }
        // Duplicate detection: same reference + amount within 48 h is a strong match; a different reference is not.
        val now = 1_790_000_000_000L
        val existing = Expense(id = "a", amountMinor = 1850, merchant = "McDonald's", transactionReference = "TNG992837194", date = now, createdAt = now, updatedAt = now)
        val strong = DuplicateDetector.checkDuplicate(1850, "McDonald's", now + 3_600_000, "TNG992837194", listOf(existing), now = now)
        val none = DuplicateDetector.checkDuplicate(1850, "McDonald's", now + 3 * 86_400_000L, "OTHER12345", listOf(existing), now = now)
        return results + Result("Duplicate detection", strong.isDuplicate && strong.isStrong && !none.isDuplicate,
            "Same reference is caught; a different payment is not", "strong=${strong.isStrong}, unrelated=${none.isDuplicate}")
    }
}
