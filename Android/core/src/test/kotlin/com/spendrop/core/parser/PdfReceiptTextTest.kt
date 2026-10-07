package com.spendrop.core.parser

import com.spendrop.core.model.PaymentChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

/**
 * Port of the text/selection parts of iOS `PDFImportTests` (OCR/ImagePipelineDiagnostics.swift). Rendering, PDFKit,
 * Vision OCR and share-sheet routing are platform code; here the page texts / OCR results are given directly.
 */
class PdfReceiptTextTest {
    private val receiptLines = listOf(
        "Maybank", "DuitNow QR", "Successful", "RM 15.00", "Recipient", "RANASOHEL",
        "Reference ID", "QR80504572", "Date & Time", "06 Oct 2026, 12:31 PM", "From Account", "Savings Account-i",
    )
    private fun page(lines: List<String>) = lines.joinToString("\n")
    private fun parse(ocr: OcrResult) = TransactionParser.parse(ocr, ZoneOffset.UTC)

    @Test fun textPdfUsesNativeTextAndParses() {
        var asked = 0
        val decision = PdfReceiptText.decide(1) { asked++; page(receiptLines) }
        assertTrue(decision is PdfReceiptText.TextDecision.UseText)
        decision as PdfReceiptText.TextDecision.UseText
        assertEquals(listOf(0), decision.pagesUsed)
        assertEquals(1, asked)
        val p = parse(decision.ocrResult)
        assertEquals(1500L, p.amountMinor)
        assertEquals("RANASOHEL", p.merchant)
        assertEquals("QR80504572", p.transactionReference)
        assertEquals("2026-10-06", p.dateString)
        assertTrue(p.timeString!!.startsWith("12:31"))
        // Funding account and payment channel stay separate.
        assertEquals("Maybank", p.displayFundingAccount)
        assertEquals(PaymentChannel.DUITNOW_QR, p.paymentChannel)
        assertNotNull(p.transactionStatus)
    }

    @Test fun receiptWithoutChannelWording() {
        val p = parse(OcrResult.fromLines(listOf("Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN", "Reference ID", "MB12345678")))
        assertEquals("Maybank", p.displayFundingAccount)
        assertEquals(4250L, p.amountMinor)
        assertEquals("MB12345678", p.transactionReference)
        assertEquals(PaymentChannel.UNKNOWN, p.paymentChannel)
    }

    @Test fun multiPageUsesOnlyThePaymentPage() {
        val pages = listOf(
            page(listOf("Maybank2u", "Transaction receipt", "Thank you for banking with us")),
            page(receiptLines),
            page(listOf("Terms and conditions apply", "Please keep this receipt for your records")),
        )
        val decision = PdfReceiptText.decide(pages) as PdfReceiptText.TextDecision.UseText
        assertEquals(listOf(1), decision.pagesUsed)
        assertEquals(1500L, parse(decision.ocrResult).amountMinor)
    }

    @Test fun onlyFirstFivePagesInspected() {
        val asked = mutableListOf<Int>()
        PdfReceiptText.decide(9) { asked += it; null }
        assertEquals(listOf(0, 1, 2, 3, 4), asked)
    }

    @Test fun imageOnlyPdfNeedsOcrOfFirstThreePages() {
        val decision = PdfReceiptText.decide(listOf("", null, "  ", "", "", "", ""))
        assertEquals(PdfReceiptText.TextDecision.NeedsOcr(listOf(0, 1, 2)), decision)
        assertEquals(PdfReceiptText.TextDecision.NeedsOcr(listOf(0)), PdfReceiptText.decide(listOf<String?>(null)))
    }

    @Test fun usableTextWithoutAmountIsStillNativeText() {
        // Letters and a digit but no amount: every usable page is used (iOS: withAmount empty -> all usable pages).
        val decision = PdfReceiptText.decide(listOf("Order number 12345 confirmed", "nothing", "Receipt for invoice 778 thanks"))
        assertEquals(listOf(0, 2), (decision as PdfReceiptText.TextDecision.UseText).pagesUsed)
    }

    @Test fun ocrResultSelection() {
        val cover = OcrResult.fromLines(listOf("Maybank2u", "Transaction receipt", "Thank you 2026"))
        val receipt = OcrResult.fromLines(receiptLines, 0.9f)
        val empty = OcrResult("", emptyList(), 0f)
        val chosen = PdfReceiptText.chooseOcrResult(listOf(0 to empty, 1 to cover, 2 to receipt))!!
        assertEquals(listOf(2), chosen.pagesUsed)
        assertEquals(PdfReceiptText.Method.OCR, chosen.method)
        assertEquals(1500L, parse(chosen.ocrResult).amountMinor)
        assertEquals("QR80504572", parse(chosen.ocrResult).transactionReference)
        // No page reads like a payment: the first page with text.
        assertEquals(listOf(1), PdfReceiptText.chooseOcrResult(listOf(0 to null, 1 to cover))!!.pagesUsed)
        // Nothing readable -> null (ImportError.NO_TEXT).
        assertNull(PdfReceiptText.chooseOcrResult(listOf(0 to empty, 1 to null)))
    }

    @Test fun emptyPdf() {
        assertEquals(PdfReceiptText.TextDecision.Empty, PdfReceiptText.decide(0) { "x" })
    }

    @Test fun linesAndHeuristics() {
        assertEquals(listOf("a", "b c", "d"), PdfReceiptText.lines("  a \r\n\n\tb c d\n   "))
        assertTrue(PdfReceiptText.isUsable(listOf("Maybank", "RM 1")))
        assertTrue(!PdfReceiptText.isUsable(listOf("Maybank receipt"))) // no digit
        assertTrue(!PdfReceiptText.isUsable(listOf("RM 15.00")))        // too few letters
        assertTrue(PdfReceiptText.looksLikePayment(listOf("Maybank receipt", "RM 15,00")))
        assertTrue(!PdfReceiptText.looksLikePayment(listOf("Maybank receipt", "Ref 1500")))
    }
}
