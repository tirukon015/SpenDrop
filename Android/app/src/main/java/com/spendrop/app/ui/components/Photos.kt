package com.spendrop.app.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import com.spendrop.app.AppContainer
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.importing.Intake
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Local-only images: person photos and receipt screenshots (app-private storage, never uploaded). */
object PhotoStore {
    fun peopleDir(context: Context) = File(context.filesDir, "people").apply { mkdirs() }
    fun receiptsDir(context: Context) = File(context.filesDir, "receipts").apply { mkdirs() }

    /** Copies a picked image, downscaled to 512 px, as the person's photo. Returns the file name or null. */
    fun savePersonPhoto(context: Context, personId: String, uri: Uri): String? {
        val item = Intake.copy(context, uri, "image/*") as? com.spendrop.app.importing.IntakeItem.Image ?: return null
        return try {
            val bmp = ImageTools.decodeOriented(item.file, 512) ?: return null
            val name = "$personId.jpg"
            ImageTools.writeReceiptJpeg(bmp, File(peopleDir(context), name), maxEdge = 512, quality = 85)
            bmp.recycle()
            name
        } finally { item.file.delete() }
    }

    fun loadThumb(file: File, edge: Int): Bitmap? = if (file.exists()) ImageTools.decodeOriented(file, edge) else null
}

@Composable
fun PersonAvatar(container: AppContainer, personId: String, initials: String, size: Dp, overrideUri: Uri? = null, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var bitmap by remember(personId, overrideUri) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(personId, overrideUri) {
        bitmap = withContext(Dispatchers.IO) {
            if (overrideUri != null) runCatching {
                context.contentResolver.openInputStream(overrideUri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, android.graphics.BitmapFactory.Options().apply { inSampleSize = 4 }) }
            }.getOrNull()
            else container.repository.personPhoto(personId)?.let { PhotoStore.loadThumb(File(PhotoStore.peopleDir(context), it), 256) }
        }
    }
    val b = bitmap
    if (b != null) Image(b.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = modifier.size(size).clip(CircleShape))
    else androidx.compose.foundation.layout.Box(modifier) { InitialsAvatar(initials, size) }
}
