package com.spendrop.core.classify

import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.parser.CategoryDetector
import com.spendrop.core.parser.CategorySuggestion
import com.spendrop.core.parser.ChannelDetector
import com.spendrop.core.parser.DirectionDetector
import com.spendrop.core.parser.MerchantDetector
import com.spendrop.core.parser.OcrLine
import com.spendrop.core.parser.OcrResult
import com.spendrop.core.parser.ParsedTransaction
import com.spendrop.core.parser.TransactionParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

/**
 * Port of the classifier parts of iOS Data/Tests/Phase7Tests.swift (`Phase7Tests`: payment channels, ClassificationRule,
 * direction detection) and `ClassifierTests` sections 1–8. Sections 9–10 (backup payloads, SwiftData migration) belong
 * to the backup / storage modules. iOS mutates a SwiftData context; here every learn() result is upserted into a list.
 */
class ClassifierTest {
    private var clock = 1_000L
    private fun now() = ++clock

    private fun parse(lines: List<String>, confidence: Float = 1f): ParsedTransaction =
        TransactionParser.parse(OcrResult.fromLines(lines, confidence), ZoneOffset.UTC)

    private fun evidence(p: ParsedTransaction) =
        CategorySuggestion(p.category ?: ExpenseCategory.OTHER, if (p.category == null) 0.0 else p.categoryConfidence, p.categoryReason ?: "")

    // MARK: Phase 7 — payment channels

    @Test fun phase7_channelDetectionNeverGuesses() {
        assertEquals(PaymentChannel.UNKNOWN, ChannelDetector.detect("Thank you"))
        assertEquals(PaymentChannel.DUITNOW_QR, ChannelDetector.detect("DuitNow QR payment"))
        assertEquals(PaymentChannel.QR_PAYMENT, ChannelDetector.detect("Scan & Pay"))
        // Stored values are unchanged; an unknown raw value falls back to Unknown.
        assertEquals(listOf("APPLE_PAY", "QR_PAYMENT", "BANK_TRANSFER", "CARD", "CASH", "OTHER", "UNKNOWN"),
            listOf(PaymentChannel.APPLE_PAY, PaymentChannel.QR_PAYMENT, PaymentChannel.BANK_TRANSFER, PaymentChannel.CARD, PaymentChannel.CASH,
                PaymentChannel.OTHER, PaymentChannel.UNKNOWN).map { it.raw })
        assertEquals(PaymentChannel.UNKNOWN, PaymentChannel.fromRaw("SOMETHING_NEW"))
    }

    // MARK: Phase 7 — ClassificationRule

    @Test fun phase7_rulesKeyedOnceNotTrustedTwiceTrustedCorrectionResets() {
        var rules = emptyList<ClassificationRule>()
        assertEquals("mcdonald's", TransactionClassifier.merchantKey("  McDonald’s  "))
        assertNull(TransactionClassifier.merchantKey("Unknown"))

        rules = rules.upsert(TransactionClassifier.learn("McDonald's", ExpenseCategory.SHOPPING, rules, now = now()))
        val once = TransactionClassifier.suggestCategory("mcdonald's", ExpenseCategory.FOOD, rules)
        rules = rules.upsert(TransactionClassifier.learn("MCDONALD'S", ExpenseCategory.SHOPPING, rules, now = now()))
        val twice = TransactionClassifier.suggestCategory("McDonald's", ExpenseCategory.FOOD, rules)
        rules = rules.upsert(TransactionClassifier.learn("McDonald's", ExpenseCategory.FOOD, rules, now = now())) // correction
        val rule = TransactionClassifier.rule("mcdonald's", rules)

        assertEquals(TransactionClassifier.Choice(ExpenseCategory.FOOD, TransactionClassifier.Source.DETERMINISTIC), once)
        assertEquals(TransactionClassifier.Choice(ExpenseCategory.SHOPPING, TransactionClassifier.Source.LEARNED), twice)
        assertEquals(ExpenseCategory.FOOD.raw, rule?.categoryRaw)
        assertEquals(1, rule?.hitCount)
        assertEquals(1, rules.size)
    }

    @Test fun phase7_priorityFallsBackToGenericThenUnknown() {
        val generic = TransactionClassifier.suggestCategory("Shell Petrol", null, emptyList())
        val unknown = TransactionClassifier.suggestCategory("Zyx Qwv", ExpenseCategory.OTHER, emptyList())
        assertEquals(TransactionClassifier.Choice(ExpenseCategory.TRANSPORT, TransactionClassifier.Source.GENERIC), generic)
        assertEquals(TransactionClassifier.Choice(ExpenseCategory.OTHER, TransactionClassifier.Source.UNKNOWN), unknown)
    }

    @Test fun phase7_learnKeepsIdTypeAndAccount() {
        var rules = emptyList<ClassificationRule>()
        val first = TransactionClassifier.learn("Starbucks", ExpenseCategory.FOOD, rules, accountId = "acc-1", now = 10, newId = { "r1" })!!
        rules = rules.upsert(first)
        val second = TransactionClassifier.learn("STARBUCKS PAVILION", ExpenseCategory.FOOD, rules, now = 20)!!
        assertEquals("starbucks", first.merchantKey)
        assertEquals("r1", second.id)
        assertEquals(2, second.hitCount)
        assertEquals("acc-1", second.accountId)        // kept when not given
        assertEquals(10L, second.createdAt)
        assertEquals(20L, second.updatedAt)
        // A different type is a correction even with the same category.
        val asTransfer = TransactionClassifier.learn("Starbucks", ExpenseCategory.FOOD, rules.upsert(second), type = "transfer", now = 30)!!
        assertEquals(1, asTransfer.hitCount)
        assertNull(TransactionClassifier.learn("Unknown Merchant", ExpenseCategory.FOOD, rules))
        // Deleted rules are ignored.
        assertNull(TransactionClassifier.rule("Starbucks", listOf(first.copy(deletedAt = 5))))
    }

    // MARK: Phase 7 — direction detection

    @Test fun phase7_directionDetection() {
        val cases: List<Pair<String, MoneyMovementKind?>> = listOf(
            "DuitNow Transfer\nYou have received RM50.00 from BIJOY" to MoneyMovementKind.OTHER_IN,
            "Salary has been credited to your account RM3,000" to MoneyMovementKind.INCOME,
            "Refund processed RM30.00 Uniqlo" to MoneyMovementKind.REFUND,
            "Reload successful\nTouch 'n Go eWallet RM200" to MoneyMovementKind.OWN_TRANSFER,
            "Payment successful\nPaid to McDonald's RM18.50" to null,
            "Received from Ali\nTransfer to Bob RM20" to null,
        )
        assertEquals(cases.map { it.second }, cases.map { DirectionDetector.detect(it.first).kind })
    }

    // MARK: ClassifierTests 1 — evaluation set

    @Test fun classifier1_evaluationSetAllCorrect() {
        val score = ClassifierEvaluation.score { lines ->
            val p = parse(lines)
            val s = TransactionClassifier.suggestion(p.merchant, evidence(p), emptyList()).suggestion
            ClassifierEvaluation.Output(p.merchant, s.category, !s.needsReview, p.paymentChannel, p.displayFundingAccount)
        }
        val ok = score.category == score.total && score.channel == score.total && score.funding == score.total &&
            score.merchant == score.total && score.confidentWrongCategory == 0 && score.wrongChannelNotUnknown == 0
        assertTrue("$score", ok)
        assertEquals(25, score.total)
    }

    // MARK: ClassifierTests 2 — merchant normalisation

    @Test fun classifier2_merchantNormalization() {
        val wrong = ClassifierEvaluation.normalization.filter { MerchantDetector.knownMerchant(it.first)?.name != it.second }
        assertEquals(emptyList<Pair<String, String?>>(), wrong)
    }

    // MARK: ClassifierTests 3 — category: evidence only

    @Test fun classifier3_categoryEvidenceOnly() {
        val tngUnknown = parse(ClassifierEvaluation.tng("Payment", "AH SENG ENTERPRISE"))
        val mcd = CategoryDetector.suggest("MCD BANGSAR", "MCD BANGSAR")
        val warung = CategoryDetector.suggest("WARUNG MAK LONG", "WARUNG MAK LONG")
        val receiptOnly = CategoryDetector.suggest("AH SENG", "AH SENG\nNasi lemak ayam")
        assertEquals(ExpenseCategory.OTHER, tngUnknown.category ?: ExpenseCategory.OTHER)
        assertTrue(evidence(tngUnknown).needsReview)
        assertEquals(ExpenseCategory.FOOD, mcd.category); assertFalse(mcd.needsReview)
        assertEquals(ExpenseCategory.FOOD, warung.category); assertFalse(warung.needsReview)
        assertEquals(ExpenseCategory.FOOD, receiptOnly.category); assertTrue(receiptOnly.needsReview)
    }

    @Test fun classifier3_grabAmbiguousSmartBusinessNotMart() {
        val grab = CategoryDetector.suggest("GRAB", "GRAB\nPayment")
        val grabFood = CategoryDetector.suggest("GRAB", "GRAB\nFood delivery order")
        val smart = CategoryDetector.suggest("SMART BUSINESS PROVIDER", "SMART BUSINESS PROVIDER")
        assertTrue(grab.needsReview)
        assertEquals(ExpenseCategory.FOOD, grabFood.category); assertTrue(grabFood.needsReview)
        assertEquals(ExpenseCategory.OTHER, smart.category); assertTrue(smart.needsReview)
    }

    // MARK: ClassifierTests 4 — payment channel: evidence only

    @Test fun classifier4_channelEvidenceOnly() {
        val tngPay = parse(ClassifierEvaluation.tng("Payment", "MCDONALD'S BANGSAR"))
        val tngQR = parse(ClassifierEvaluation.tng("Touch 'n Go QR", "WARUNG MAK LONG"))
        val tngDuit = parse(ClassifierEvaluation.tng("DuitNow QR", "NASI KANDAR PELITA"))
        val tngOnline = parse(ClassifierEvaluation.tng("Online Payment", "SHOPEE MALAYSIA"))
        assertEquals(PaymentChannel.UNKNOWN, tngPay.paymentChannel)
        assertEquals("Touch 'n Go", tngPay.displayFundingAccount)
        assertEquals(PaymentChannel.TNG_QR, tngQR.paymentChannel)
        assertEquals(PaymentChannel.DUITNOW_QR, tngDuit.paymentChannel)
        assertEquals(PaymentChannel.OTHER, tngOnline.paymentChannel)
    }

    @Test fun classifier4_bankReceiptWithoutChannelWording() {
        val bankNone = parse(listOf("Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN SELERA", "Reference ID", "MB12345678"))
        assertEquals(PaymentChannel.UNKNOWN, bankNone.paymentChannel)
        assertEquals("Maybank", bankNone.displayFundingAccount)
        assertFalse(bankNone.channelReason.isNullOrEmpty())
    }

    // MARK: ClassifierTests 5 — conflicts

    @Test fun classifier5_conflictsStrongestEvidenceWins() {
        val applePay = parse(listOf("Apple Pay", "STARBUCKS PAVILION", "RM 18.50", "Maybank Visa Debit", "Status: Approved"))
        val card = parse(listOf("Maybank", "Card Purchase", "Maybank Visa Debit", "RM 32.90", "Merchant", "UNIQLO MID VALLEY", "Approval Code 123456"))
        val qrOverTransfer = ChannelDetector.suggest("DuitNow QR\nfund transfer")
        assertEquals(PaymentChannel.APPLE_PAY, applePay.paymentChannel)
        assertEquals("Maybank", applePay.displayFundingAccount)
        assertEquals(PaymentChannel.CARD, card.paymentChannel)
        assertEquals("Maybank", card.displayFundingAccount)
        assertEquals(PaymentChannel.DUITNOW_QR, qrOverTransfer.channel)
    }

    // MARK: ClassifierTests 6 — low-confidence OCR lines are not channel evidence

    @Test fun classifier6_lowConfidenceChannelWordIgnored() {
        val texts = listOf("Maybank", "Successful", "RM 9.00", "DuitNow QR", "Recipient", "AH SENG")
        val blurry = TransactionParser.parse(
            OcrResult(texts.joinToString("\n"), texts.map { OcrLine(it, if (it == "DuitNow QR") 0.3f else 0.95f) }, 0.85f), ZoneOffset.UTC,
        )
        val clear = parse(texts, confidence = 0.95f)
        assertEquals(PaymentChannel.UNKNOWN, blurry.paymentChannel)
        assertEquals(PaymentChannel.DUITNOW_QR, clear.paymentChannel)
    }

    // MARK: ClassifierTests 7 — learned categories

    @Test fun classifier7_learnedCategories() {
        val tngUnknown = parse(ClassifierEvaluation.tng("Payment", "AH SENG ENTERPRISE"))
        val mcd = CategoryDetector.suggest("MCD BANGSAR", "MCD BANGSAR")
        val old = Expense(id = "o1", amountMinor = 1200, merchant = "AH SENG ENTERPRISE", categoryRaw = ExpenseCategory.OTHER.raw,
            fundingAccount = "Touch 'n Go", date = 0, createdAt = 0, updatedAt = 0)
        val oldMcd = Expense(id = "o2", amountMinor = 900, merchant = "MCD BANGSAR", categoryRaw = ExpenseCategory.FOOD.raw,
            fundingAccount = "Maybank", date = 0, createdAt = 0, updatedAt = 0)

        var rules = emptyList<ClassificationRule>()
        rules = rules.upsert(TransactionClassifier.learn("AH SENG ENTERPRISE", ExpenseCategory.FOOD, rules, now = now()))
        val once = TransactionClassifier.suggestion("AH SENG ENTERPRISE", evidence(tngUnknown), rules)
        rules = rules.upsert(TransactionClassifier.learn("McDonald's", ExpenseCategory.SHOPPING, rules, now = now()))
        val mcdOnce = TransactionClassifier.suggestion("MCD BANGSAR", mcd, rules)
        rules = rules.upsert(TransactionClassifier.learn("MCDONALDS", ExpenseCategory.SHOPPING, rules, now = now()))
        val mcdTwice = TransactionClassifier.suggestion("MCD BANGSAR", mcd, rules)

        assertEquals(ExpenseCategory.FOOD, once.suggestion.category); assertEquals(TransactionClassifier.Source.LEARNED, once.source)
        assertEquals(ExpenseCategory.FOOD, mcdOnce.suggestion.category); assertNotEquals(TransactionClassifier.Source.LEARNED, mcdOnce.source)
        assertEquals(ExpenseCategory.SHOPPING, mcdTwice.suggestion.category); assertEquals(TransactionClassifier.Source.LEARNED, mcdTwice.source)
        assertFalse(mcdTwice.suggestion.needsReview)
        // Learning never rewrites saved transactions (pure functions: the records are untouched).
        assertEquals(ExpenseCategory.OTHER, old.category)
        assertEquals(ExpenseCategory.FOOD, oldMcd.category)
        assertEquals(2, rules.size)
    }

    // MARK: ClassifierTests 8 — learned channels

    @Test fun classifier8_learnedChannelsPerMerchantAndFunding() {
        var rules = emptyList<ChannelRule>()
        val tng = "Touch 'n Go"
        rules = rules.upsert(ChannelLearning.learn("AH SENG ENTERPRISE", tng, PaymentChannel.DUITNOW_QR, rules, now = now()))
        val channelOnce = ChannelLearning.suggestion("AH SENG ENTERPRISE", tng, PaymentChannel.UNKNOWN, rules)
        rules = rules.upsert(ChannelLearning.learn("AH SENG ENTERPRISE", tng, PaymentChannel.DUITNOW_QR, rules, now = now()))
        val channelTwice = ChannelLearning.suggestion("AH SENG ENTERPRISE", tng, PaymentChannel.UNKNOWN, rules)
        val otherFunding = ChannelLearning.suggestion("AH SENG ENTERPRISE", "Maybank", PaymentChannel.UNKNOWN, rules)
        val otherMerchant = ChannelLearning.suggestion("JAYA GROCER", tng, PaymentChannel.UNKNOWN, rules)
        val receiptSaysCard = ChannelLearning.suggestion("AH SENG ENTERPRISE", tng, PaymentChannel.CARD, rules)
        assertNull(channelOnce)
        assertEquals(PaymentChannel.DUITNOW_QR, channelTwice?.channel)
        assertEquals("You chose DuitNow QR for this merchant from Touch 'n Go before", channelTwice?.reason)
        assertNull(otherFunding)
        assertNull(otherMerchant)
        assertNull(receiptSaysCard)

        val unknownLearned = ChannelLearning.learn("KEDAI X", "Maybank", PaymentChannel.UNKNOWN, rules)
        rules = rules.upsert(ChannelLearning.learn("AH SENG ENTERPRISE", tng, PaymentChannel.TNG_QR, rules, now = now()))
        val corrected = ChannelLearning.rule("AH SENG ENTERPRISE", tng, rules)
        val afterCorrection = ChannelLearning.suggestion("AH SENG ENTERPRISE", tng, PaymentChannel.UNKNOWN, rules)
        assertNull(unknownLearned)
        assertEquals(PaymentChannel.TNG_QR.raw, corrected?.channelRaw)
        assertEquals(1, corrected?.hitCount)
        assertNull(afterCorrection)
        assertEquals(1, rules.size)
        assertEquals("touch 'n go", rules.single().fundingKey)
        assertEquals("ah seng enterprise", rules.single().merchantKey)
    }

    @Test fun channelLearning_fundingKeyNormalisation() {
        assertEquals("", ChannelLearning.fundingKey(null))
        assertEquals("", ChannelLearning.fundingKey("  Unknown "))
        assertEquals("", ChannelLearning.fundingKey("OTHER"))
        assertEquals("maybank", ChannelLearning.fundingKey(" Maybank "))
    }
}
