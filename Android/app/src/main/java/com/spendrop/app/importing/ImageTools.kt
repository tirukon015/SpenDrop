package com.spendrop.app.importing

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/** Memory-safe image handling for screenshots and receipts (any manufacturer, any resolution). */
object ImageTools {
    /** Decodes [file] with its EXIF orientation applied, sub-sampled so the long edge is at most [maxEdge]. */
    fun decodeOriented(file: File, maxEdge: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) sample *= 2
        val decoded = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val scaled = scaleDown(decoded, maxEdge)
        val rotation = runCatching {
            when (ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        }.getOrDefault(0f)
        if (rotation == 0f) return scaled
        val rotated = Bitmap.createBitmap(scaled, 0, 0, scaled.width, scaled.height, Matrix().apply { postRotate(rotation) }, true)
        if (rotated !== scaled) scaled.recycle()
        return rotated
    }

    fun scaleDown(bitmap: Bitmap, maxEdge: Int): Bitmap {
        val edge = max(bitmap.width, bitmap.height)
        if (edge <= maxEdge) return bitmap
        val f = maxEdge.toFloat() / edge
        val out = Bitmap.createScaledBitmap(bitmap, (bitmap.width * f).toInt().coerceAtLeast(1), (bitmap.height * f).toInt().coerceAtLeast(1), true)
        if (out !== bitmap) bitmap.recycle()
        return out
    }

    /** Small JPEG kept as the receipt image (iOS keeps an optimised copy: long edge ≤ 1800 px). */
    fun writeReceiptJpeg(bitmap: Bitmap, target: File, maxEdge: Int = 1800, quality: Int = 72) {
        val scaled = if (max(bitmap.width, bitmap.height) > maxEdge) {
            val f = maxEdge.toFloat() / max(bitmap.width, bitmap.height)
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * f).toInt(), (bitmap.height * f).toInt(), true)
        } else bitmap
        target.parentFile?.mkdirs()
        FileOutputStream(target).use { scaled.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        if (scaled !== bitmap) scaled.recycle()
    }
}
