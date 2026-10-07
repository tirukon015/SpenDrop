package com.spendrop.app.ui.importing

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

/** Launchers for in-app import: the system photo picker (screenshots, photos) and the file picker (PDF, images). */
class ImportPickers(val photos: () -> Unit, val files: () -> Unit, val camera: (() -> Unit)? = null, val bulk: (() -> Unit)? = null)

/** Up to this many screenshots in one Bulk Import (same limit as iOS and Web). */
const val BULK_IMPORT_MAX = 30

/**
 * [onPicked] gets single files (one-by-one review); [onBulk] gets two or more screenshots, which open the Bulk Import
 * review queue instead.
 */
@Composable
fun rememberImportPickers(onPicked: (List<Uri>) -> Unit, onBulk: (List<Uri>) -> Unit = onPicked): ImportPickers {
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(BULK_IMPORT_MAX)) {
        when { it.size >= 2 -> onBulk(it); it.isNotEmpty() -> onPicked(it) }
    }
    val doc = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { if (it.isNotEmpty()) onPicked(it) }
    val launchPhotos = { photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    return ImportPickers(
        photos = launchPhotos,
        files = { doc.launch(arrayOf("application/pdf", "image/*")) },
        bulk = launchPhotos,
    )
}

/** "Scan" menu: Screenshot or photo / PDF or file. */
@Composable
fun ImportMenu(expanded: Boolean, onDismiss: () -> Unit, pickers: ImportPickers) {
    DropdownMenu(expanded, onDismiss) {
        DropdownMenuItem({ Text("Screenshot or Photo") }, { onDismiss(); pickers.photos() }, leadingIcon = { Icon(Icons.Filled.PhotoLibrary, null) })
        DropdownMenuItem({ Text("PDF or File") }, { onDismiss(); pickers.files() }, leadingIcon = { Icon(Icons.Filled.Description, null) })
        pickers.bulk?.let { b -> DropdownMenuItem({ Text("Bulk Import Screenshots") }, { onDismiss(); b() }, leadingIcon = { Icon(Icons.Filled.Collections, null) }) }
        pickers.camera?.let { cam -> DropdownMenuItem({ Text("Take Photo of Receipt") }, { onDismiss(); cam() }, leadingIcon = { Icon(Icons.Filled.PhotoCamera, null) }) }
    }
}
