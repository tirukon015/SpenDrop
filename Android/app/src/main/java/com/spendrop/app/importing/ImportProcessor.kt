package com.spendrop.app.importing

import android.content.Context
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.parser.OcrResult
import com.spendrop.core.parser.ParsedTransaction
import com.spendrop.core.parser.PdfReceiptText
import com.spendrop.core.parser.TransactionParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Outcome of reading one imported item. */
sealed interface ImportOutcome {
    val item: IntakeItem
    /** Details found: go to review. [imageFile] is kept as the receipt image (screenshots/photos, rendered PDF page). */
    data class Parsed(override val item: IntakeItem, val parsed: ParsedTransaction, val imageFile: File?, val sourceType: ExpenseSourceType) : ImportOutcome
    /** Nothing usable found: offer manual entry or retry (iOS "Couldn't read payment details"). */
    data class NoDetails(override val item: IntakeItem, val imageFile: File?, val message: String) : ImportOutcome
    data class Failed(override val item: IntakeItem, val message: String) : ImportOutcome
}

/**
 * Import pipeline: content arrives (share sheet or in-app picker) → copied file → image OCR (ML Kit) or PDF text
 * (PdfBox, falling back to OCR of rendered pages) or shared text → the ported iOS TransactionParser → review.
 * All work runs off the main thread; every failure becomes a readable message instead of a crash.
 */
class ImportProcessor(private val context: Context) {
    private val ocr by lazy { OcrEngine() }
    private val pdf by lazy { PdfText(context) }

    suspend fun process(item: IntakeItem): ImportOutcome = withContext(Dispatchers.Default) {
        try {
            when (item) {
                is IntakeItem.Image -> image(item)
                is IntakeItem.Pdf -> pdf(item)
                is IntakeItem.SharedText -> {
                    val parsed = TransactionParser.parse(OcrResult.fromText(item.text, 1f))
                    if (parsed.amountMinor == null && parsed.merchant == null) ImportOutcome.NoDetails(item, null, "No payment details were found in the shared text.")
                    else ImportOutcome.Parsed(item, parsed, null, ExpenseSourceType.SHARE_EXTENSION)
                }
                is IntakeItem.Unreadable -> ImportOutcome.Failed(item, item.reason)
            }
        } catch (e: OutOfMemoryError) {
            ImportOutcome.Failed(item, "This image is too large to read on this phone.")
        } catch (e: PdfUnreadable) {
            ImportOutcome.Failed(item, e.message ?: PdfReceiptText.ImportError.UNREADABLE.message)
        } catch (e: OcrFailed) {
            ImportOutcome.NoDetails(item, (item as? IntakeItem.Image)?.file, "Text couldn't be read from this image. Try again, or enter the details manually.")
        } catch (e: Exception) {
            ImportOutcome.Failed(item, "SpenDrop couldn't read this file. Try again, or enter the details manually.")
        }
    }

    private suspend fun image(item: IntakeItem.Image): ImportOutcome {
        // Long edge up to 2400 px keeps small receipt text readable without using too much memory on low-end phones.
        val bitmap = withContext(Dispatchers.IO) { ImageTools.decodeOriented(item.file, 2400) }
            ?: return ImportOutcome.Failed(item, "This image couldn't be opened. It may be damaged or in an unsupported format.")
        val result = try { ocr.recognize(bitmap) } finally { bitmap.recycle() }
        if (result.lines.isEmpty()) return ImportOutcome.NoDetails(item, item.file, "We couldn't detect transaction details in this screenshot. You can enter the expense manually or try scanning again.")
        val parsed = TransactionParser.parse(result)
        if (parsed.amountMinor == null && parsed.merchant == null) {
            return ImportOutcome.NoDetails(item, item.file, "We couldn't detect transaction details in this screenshot. You can enter the expense manually or try scanning again.")
        }
        return ImportOutcome.Parsed(item, parsed, item.file, ExpenseSourceType.SCREENSHOT)
    }

    private suspend fun pdf(item: IntakeItem.Pdf): ImportOutcome {
        val pageTexts = withContext(Dispatchers.IO) {
            try { pdf.pageTexts(item.file, PdfReceiptText.MAX_PAGES) } catch (e: PdfUnreadable) { throw e } catch (e: Exception) { null }
        }
        val pageCount = runCatching { pdf.pageCount(item.file) }.getOrElse {
            if (pageTexts == null) throw PdfUnreadable(PdfReceiptText.ImportError.UNREADABLE.message) else pageTexts.size
        }
        if (pageCount == 0) return ImportOutcome.Failed(item, PdfReceiptText.ImportError.EMPTY.message)
        val texts = pageTexts ?: List(minOf(pageCount, PdfReceiptText.MAX_PAGES)) { null }
        return when (val decision = PdfReceiptText.decide(texts)) {
            is PdfReceiptText.TextDecision.UseText -> {
                val image = renderPreview(item, decision.pagesUsed.firstOrNull() ?: 0)
                ImportOutcome.Parsed(item, TransactionParser.parse(decision.ocrResult), image, ExpenseSourceType.RECEIPT)
            }
            is PdfReceiptText.TextDecision.NeedsOcr -> {
                val results = decision.pagesToOcr.map { page ->
                    val bmp = withContext(Dispatchers.IO) { runCatching { pdf.renderPage(item.file, page) }.getOrNull() }
                    page to bmp?.let { b -> try { runCatching { ocr.recognize(b) }.getOrNull() } finally { b.recycle() } }
                }
                val sel = PdfReceiptText.chooseOcrResult(results)
                    ?: return ImportOutcome.NoDetails(item, null, PdfReceiptText.ImportError.NO_TEXT.message)
                ImportOutcome.Parsed(item, TransactionParser.parse(sel.ocrResult), renderPreview(item, sel.pagesUsed.firstOrNull() ?: 0), ExpenseSourceType.RECEIPT)
            }
            PdfReceiptText.TextDecision.Empty -> ImportOutcome.NoDetails(item, null, PdfReceiptText.ImportError.NO_TEXT.message)
        }
    }

    /** A JPEG of the page used, kept as the receipt image like a screenshot. */
    private suspend fun renderPreview(item: IntakeItem.Pdf, page: Int): File? = withContext(Dispatchers.IO) {
        runCatching {
            val bmp = pdf.renderPage(item.file, page, 1800)
            val out = File(item.file.parentFile, "${item.id}-page$page.jpg")
            ImageTools.writeReceiptJpeg(bmp, out)
            bmp.recycle()
            out
        }.getOrNull()
    }
}
