package com.spendrop.app.importing

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID

/** One thing the user gave SpenDrop: a file copied into private storage, or shared text. */
sealed interface IntakeItem {
    val id: String
    data class Image(override val id: String, val file: File, val displayName: String?) : IntakeItem
    data class Pdf(override val id: String, val file: File, val displayName: String?) : IntakeItem
    data class SharedText(override val id: String, val text: String) : IntakeItem
    data class Unreadable(override val id: String, val displayName: String?, val reason: String) : IntakeItem
}

/**
 * Reads Android share / open intents and picker results. Content URIs are only readable for a short time, so
 * every file is copied into the app's private cache immediately. No storage permission and no file paths are used:
 * this works with any gallery, file manager or app on any manufacturer's Android.
 */
object Intake {
    const val MAX_FILE_BYTES = 40L * 1024 * 1024
    const val MAX_ITEMS = 10
    private const val DIR = "imports"

    fun isImportIntent(intent: Intent?): Boolean = when (intent?.action) {
        Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> true
        Intent.ACTION_VIEW -> intent.data?.scheme == "content" || intent.data?.scheme == "file"
        else -> false
    }

    /** Must run off the main thread. */
    fun fromIntent(context: Context, intent: Intent): List<IntakeItem> {
        val uris = LinkedHashSet<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> intent.streamUri()?.let(uris::add)
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(intent.streamUris())
            Intent.ACTION_VIEW -> intent.data?.let(uris::add)
        }
        intent.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add) }
        val items = uris.take(MAX_ITEMS).map { copy(context, it, intent.type) }.toMutableList()
        if (uris.isEmpty()) {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
                ?: intent.clipData?.text()
            if (!text.isNullOrBlank()) items += IntakeItem.SharedText(UUID.randomUUID().toString(), text.take(20_000))
        }
        return items
    }

    fun fromUris(context: Context, uris: List<Uri>): List<IntakeItem> = uris.take(MAX_ITEMS).map { copy(context, it, null) }

    fun copy(context: Context, uri: Uri, hintMime: String?): IntakeItem {
        val id = UUID.randomUUID().toString()
        val resolver = context.contentResolver
        val name = runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        }.getOrNull()
        val mime = (runCatching { resolver.getType(uri) }.getOrNull() ?: hintMime?.takeUnless { it.endsWith("/*") }
            ?: name?.substringAfterLast('.', "")?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase()) }).orEmpty()
        val kind = when {
            mime.startsWith("image/") -> "img"
            mime == "application/pdf" -> "pdf"
            name?.endsWith(".pdf", true) == true -> "pdf"
            else -> return IntakeItem.Unreadable(id, name, "SpenDrop can read screenshots, photos and PDF files. This file type isn't supported.")
        }
        val dir = File(context.cacheDir, DIR).apply { mkdirs() }
        val target = File(dir, "$id.${if (kind == "pdf") "pdf" else "img"}")
        return try {
            val input = resolver.openInputStream(uri) ?: return IntakeItem.Unreadable(id, name, "SpenDrop couldn't open this file. Try sharing it again, or use Import in the app.")
            var total = 0L
            input.use { inp ->
                target.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = inp.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > MAX_FILE_BYTES) {
                            target.delete()
                            return IntakeItem.Unreadable(id, name, "This file is too large (over 40 MB).")
                        }
                        out.write(buf, 0, n)
                    }
                }
            }
            if (total == 0L) { target.delete(); return IntakeItem.Unreadable(id, name, "This file is empty.") }
            if (kind == "pdf") IntakeItem.Pdf(id, target, name) else IntakeItem.Image(id, target, name)
        } catch (_: SecurityException) {
            target.delete()
            IntakeItem.Unreadable(id, name, "SpenDrop no longer has permission to read this file. Share it again, or use Import in the app.")
        } catch (_: Exception) {
            target.delete()
            IntakeItem.Unreadable(id, name, "SpenDrop couldn't read this file. Try sharing it again, or use Import in the app.")
        }
    }

    /** Removes copied files older than a day (imports that were abandoned). */
    fun cleanup(context: Context, olderThanMillis: Long = 24 * 3600_000L) {
        val cutoff = System.currentTimeMillis() - olderThanMillis
        File(context.cacheDir, DIR).listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
    }

    fun discard(item: IntakeItem) {
        when (item) {
            is IntakeItem.Image -> item.file.delete()
            is IntakeItem.Pdf -> item.file.delete()
            else -> Unit
        }
    }

    @Suppress("DEPRECATION")
    private fun Intent.streamUri(): Uri? =
        if (Build.VERSION.SDK_INT >= 33) getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun Intent.streamUris(): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else getParcelableArrayListExtra(Intent.EXTRA_STREAM)).orEmpty()

    private fun ClipData.text(): String? = (0 until itemCount).mapNotNull { getItemAt(it).text?.toString() }.joinToString("\n").ifBlank { null }
}
