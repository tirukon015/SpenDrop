package com.spendrop.core.parser

/**
 * A line's position on the page, normalised to 0…1 with the origin at the TOP-LEFT (Android / ML Kit convention:
 * divide the ML Kit pixel box by the image width / height). iOS Vision uses a bottom-left origin; the parser converts.
 */
data class OcrBox(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val centerY: Float get() = (top + bottom) / 2f
}

/** One recognised text line (iOS `RecognizedTextLine`). [box] null = unknown position (shared text, PDF text). */
data class OcrLine(val text: String, val confidence: Float = 1f, val box: OcrBox? = null)

/** Recognised text (iOS `OCRResult`): full text is the lines joined with "\n". */
data class OcrResult(val fullText: String, val lines: List<OcrLine>, val averageConfidence: Float) {
    companion object {
        /**
         * iOS `PDFReceiptImporter.ocrResult(from:confidence:)`: plain text lines (shared text, a PDF's own text) in the
         * same shape as OCR output. No boxes; the parser falls back to line order for positions.
         */
        fun fromLines(lines: List<String>, confidence: Float = 1f): OcrResult =
            OcrResult(lines.joinToString("\n"), lines.map { OcrLine(it, confidence) }, confidence)

        /**
         * Newline-joined OCR text as the iOS test harness / share path builds it: every non-empty line becomes a
         * recognised line; [fullText] keeps the text exactly as given.
         */
        fun fromText(text: String, confidence: Float = 1f): OcrResult =
            OcrResult(text, text.split("\n").filter { it.isNotEmpty() }.map { OcrLine(it, confidence) }, confidence)

        /**
         * iOS `OCRService.recognizeText` post-processing for engine output with boxes (e.g. ML Kit lines): lines are
         * ordered top-to-bottom in quantised row bands (1.8% of the page height), then left-to-right inside a band,
         * and joined with "\n". Lines without a box keep their relative order after the boxed ones.
         */
        fun fromRecognizedLines(lines: List<OcrLine>): OcrResult {
            val ordered = orderReadingLines(lines)
            val avg = if (ordered.isEmpty()) 0f else ordered.map { it.confidence }.sum() / ordered.size
            return OcrResult(ordered.joinToString("\n") { it.text }, ordered, avg)
        }

        /** Row-band height used by iOS to sort Vision observations (fraction of the page height). */
        const val ROW_BAND_HEIGHT = 0.018f

        fun orderReadingLines(lines: List<OcrLine>): List<OcrLine> {
            val (boxed, unboxed) = lines.partition { it.box != null }
            val sorted = boxed.sortedWith(compareBy<OcrLine>({ (it.box!!.centerY / ROW_BAND_HEIGHT).toInt() }, { it.box!!.left }))
            return sorted + unboxed
        }
    }
}
