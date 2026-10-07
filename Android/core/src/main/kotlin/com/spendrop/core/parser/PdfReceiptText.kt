package com.spendrop.core.parser

/**
 * The pure part of iOS `PDFReceiptImporter`: deciding which page text to use, and when to fall back to OCR.
 * The Android caller extracts page text (PdfBox), renders pages and runs ML Kit; this object only decides.
 *
 * Flow (identical to iOS):
 * 1. Only the first [MAX_PAGES] pages are inspected (receipts are short).
 * 2. Native text: the pages that look like a payment (an amount such as "15.00"), else every page with usable text.
 *    If the chosen text is usable, it is parsed directly (no rendering, no OCR), confidence 1.
 * 3. Otherwise the PDF is image-only: render and OCR the first [MAX_OCR_PAGES] pages one at a time; stop at the first
 *    page that reads like a payment, else use the first page that produced any text; else there is nothing to read.
 */
object PdfReceiptText {
    /** Receipts are short; pages past this are not inspected. */
    const val MAX_PAGES = 5
    const val MAX_OCR_PAGES = 3

    enum class Method { NATIVE_TEXT, OCR }

    enum class ImportError(val message: String) {
        UNREADABLE("SpenDrop couldn't open this PDF."),
        EMPTY("This PDF has no pages."),
        NO_TEXT("No receipt details could be read from this PDF."),
    }

    /** Outcome of the native-text step. */
    sealed interface TextDecision {
        /** Parse this text (same shape as OCR output). [pagesUsed] are 0-based page indexes. */
        data class UseText(val ocrResult: OcrResult, val pagesUsed: List<Int>) : TextDecision
        /** No usable text layer: render and OCR these pages (0-based, in order), then call [chooseOcrResult]. */
        data class NeedsOcr(val pagesToOcr: List<Int>) : TextDecision
        /** The PDF has no pages. */
        data object Empty : TextDecision
    }

    data class Selection(val ocrResult: OcrResult, val method: Method, val pagesUsed: List<Int>)

    /**
     * Step 1–2. [pageCount] is the document's page count; [pageText] returns a page's own text (null when the page
     * can't be read or has none). Only pages below [MAX_PAGES] are asked for.
     */
    fun decide(pageCount: Int, pageText: (Int) -> String?): TextDecision {
        if (pageCount <= 0) return TextDecision.Empty
        val pages = (0 until minOf(pageCount, MAX_PAGES)).toList()
        val texts = pages.map { it to lines(pageText(it) ?: "") }
        val withAmount = texts.filter { looksLikePayment(it.second) }
        val chosen = withAmount.ifEmpty { texts.filter { isUsable(it.second) } }
        val nativeLines = chosen.flatMap { it.second }
        if (isUsable(nativeLines)) return TextDecision.UseText(OcrResult.fromLines(nativeLines, 1f), chosen.map { it.first })
        return TextDecision.NeedsOcr(pages.take(MAX_OCR_PAGES))
    }

    /** Convenience for already-extracted page texts (index = page number; pass all pages so the count is right). */
    fun decide(pageTexts: List<String?>): TextDecision = decide(pageTexts.size) { pageTexts.getOrNull(it) }

    /**
     * Step 3, given OCR results in page order (a null result = rendering or OCR failed for that page). Returns the
     * first page that reads like a payment, else the first page with any text, else null ([ImportError.NO_TEXT]).
     * A caller may stop OCR early as soon as [looksLikePayment] is true for a page; the answer is the same.
     */
    fun chooseOcrResult(results: List<Pair<Int, OcrResult?>>): Selection? {
        var fallback: Pair<Int, OcrResult>? = null
        for ((index, result) in results.take(MAX_OCR_PAGES)) {
            if (result == null || result.lines.isEmpty()) continue
            if (looksLikePayment(result.lines.map { it.text })) return Selection(result, Method.OCR, listOf(index))
            if (fallback == null) fallback = index to result
        }
        return fallback?.let { Selection(it.second, Method.OCR, listOf(it.first)) }
    }

    /** Text lines of a page: split on any newline, trimmed of spaces/tabs, empty lines dropped. */
    fun lines(text: String): List<String> =
        text.split(Regex("\r\n|[\n\r\u000B\u000C\u0085  ]")).map { it.trimSpaces() }.filter { it.isNotEmpty() }

    /** Enough real text to parse: at least 8 letters and at least one digit. */
    fun isUsable(lines: List<String>): Boolean {
        val text = lines.joinToString(" ")
        return text.countCodePoints { isLetterChar(it) } >= 8 && text.anyCodePoint { isNumberChar(it) }
    }

    private val amountLike = Regex("""\d+[.,]\d{2}\b""")

    /** Usable and contains something that looks like a money amount ("RM 15.00", "15.00", "15,00"). */
    fun looksLikePayment(lines: List<String>): Boolean = isUsable(lines) && lines.any { amountLike.containsMatchIn(it) }
}
