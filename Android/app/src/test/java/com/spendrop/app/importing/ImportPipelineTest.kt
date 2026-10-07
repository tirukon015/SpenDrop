package com.spendrop.app.importing

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.core.model.ExpenseSourceType
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.io.File

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class ImportPipelineTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test fun sharedTextIsParsed() = runBlocking {
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "Maybank2u\nTransfer Successful\nAmount: RM42.90\nRecipient: MYDIN\n16/09/2026\nReference: MBB20260916892")
        val items = Intake.fromIntent(context, intent)
        assertEquals(1, items.size)
        val out = ImportProcessor(context).process(items[0])
        assertTrue(out is ImportOutcome.Parsed)
        out as ImportOutcome.Parsed
        assertEquals(4290L, out.parsed.amountMinor)
        assertEquals("MYDIN", out.parsed.merchant)
        assertEquals(ExpenseSourceType.SHARE_EXTENSION, out.sourceType)
    }

    @Test fun unsupportedFileGivesAReadableMessage() {
        val f = File(context.cacheDir, "x.zip").apply { writeText("zip") }
        val item = Intake.copy(context, Uri.fromFile(f), "application/zip")
        assertTrue(item is IntakeItem.Unreadable)
        assertTrue((item as IntakeItem.Unreadable).reason.contains("isn't supported"))
    }

    @Test fun emptyShareFailsGracefully() = runBlocking {
        assertTrue(Intake.fromIntent(context, Intent(Intent.ACTION_SEND).setType("image/*")).isEmpty())
    }

    @Test fun bankTransferPdfTextIsParsed() = runBlocking {
        PDFBoxResourceLoader.init(context)
        val pdf = File(context.cacheDir, "receipt.pdf")
        PDDocument().use { doc ->
            val page = PDPage(); doc.addPage(page)
            PDPageContentStream(doc, page).use { cs ->
                cs.beginText(); cs.setFont(PDType1Font.HELVETICA, 12f); cs.setLeading(16f); cs.newLineAtOffset(50f, 700f)
                listOf("CIMB OCTO", "DuitNow Transfer Successful", "Amount RM50.00", "Paid to: Shell", "Reference No: 998877665544").forEach { cs.showText(it); cs.newLine() }
                cs.endText()
            }
            doc.save(pdf)
        }
        val texts = PdfText(context).pageTexts(pdf, 5)
        assertTrue(texts.first().contains("RM50.00"))
        val parsed = com.spendrop.core.parser.PdfReceiptText.decide(texts)
        assertTrue(parsed is com.spendrop.core.parser.PdfReceiptText.TextDecision.UseText)
        val p = com.spendrop.core.parser.TransactionParser.parse((parsed as com.spendrop.core.parser.PdfReceiptText.TextDecision.UseText).ocrResult)
        assertEquals(5000L, p.amountMinor)
        assertEquals("Shell", p.merchant)
    }
}
