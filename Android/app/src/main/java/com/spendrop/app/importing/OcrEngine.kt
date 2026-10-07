package com.spendrop.app.importing

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.spendrop.core.parser.OcrBox
import com.spendrop.core.parser.OcrLine
import com.spendrop.core.parser.OcrResult
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * On-device OCR with Google ML Kit (bundled Latin model: English + Malay). Nothing is uploaded, like iOS Vision.
 * The bundled model works without Google Play Services, so it runs on any manufacturer's Android.
 */
class OcrEngine {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** Lines with normalised boxes (0..1, top-left origin) in iOS reading order. */
    suspend fun recognize(bitmap: Bitmap): OcrResult {
        val result: Text = suspendCancellableCoroutine { cont ->
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resumeWithException(OcrFailed(it)) }
        }
        val w = bitmap.width.toFloat().coerceAtLeast(1f)
        val h = bitmap.height.toFloat().coerceAtLeast(1f)
        val lines = result.textBlocks.flatMap { block ->
            block.lines.mapNotNull { line ->
                val text = line.text.trim()
                if (text.isEmpty()) return@mapNotNull null
                val b = line.boundingBox
                val conf = line.confidence.takeIf { it > 0f } ?: 1f
                OcrLine(text, conf, b?.let { OcrBox(it.left / w, it.top / h, it.right / w, it.bottom / h) })
            }
        }
        return OcrResult.fromRecognizedLines(lines)
    }

    fun close() = recognizer.close()
}

class OcrFailed(cause: Throwable) : Exception("Text couldn't be read from this image.", cause)
