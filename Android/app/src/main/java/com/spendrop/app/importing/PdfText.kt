package com.spendrop.app.importing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File

/** PDF access: embedded text (PdfBox) and page images for OCR (Android PdfRenderer). Pages are processed one at a time. */
class PdfText(private val context: Context) {
    @Volatile private var initialised = false

    /** Text of the first [maxPages] pages (empty strings for image-only pages). Throws on corrupt / protected files. */
    fun pageTexts(file: File, maxPages: Int): List<String> {
        if (!initialised) { PDFBoxResourceLoader.init(context.applicationContext); initialised = true }
        PDDocument.load(file).use { doc ->
            if (doc.isEncrypted) throw PdfUnreadable("This PDF is password-protected. Remove the password and try again.")
            val count = minOf(doc.numberOfPages, maxPages)
            val stripper = PDFTextStripper().apply { sortByPosition = true }
            return (1..count).map { page ->
                stripper.startPage = page
                stripper.endPage = page
                stripper.getText(doc).orEmpty()
            }
        }
    }

    fun pageCount(file: File): Int = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd -> PdfRenderer(fd).use { it.pageCount } }

    /** Renders one page to a white-background bitmap whose long edge is about [maxEdge] px (for OCR). */
    fun renderPage(file: File, index: Int, maxEdge: Int = 2200): Bitmap =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { renderer ->
                renderer.openPage(index).use { page ->
                    val scale = maxEdge.toFloat() / maxOf(page.width, page.height)
                    val bmp = Bitmap.createBitmap((page.width * scale).toInt().coerceAtLeast(1), (page.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    bmp
                }
            }
        }
}

class PdfUnreadable(message: String) : Exception(message)
