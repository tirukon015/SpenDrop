package com.spendrop.app.ui.importing

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

/** Launchers for in-app import: the system photo picker (screenshots, photos) and the file picker (PDF, images). */
class ImportPickers(val photos: () -> Unit, val files: () -> Unit)

@Composable
fun rememberImportPickers(onPicked: (List<Uri>) -> Unit): ImportPickers {
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { if (it.isNotEmpty()) onPicked(it) }
    val doc = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { if (it.isNotEmpty()) onPicked(it) }
    return ImportPickers(
        photos = { photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        files = { doc.launch(arrayOf("application/pdf", "image/*")) },
    )
}

/** "Scan" menu: Screenshot or photo / PDF or file. */
@Composable
fun ImportMenu(expanded: Boolean, onDismiss: () -> Unit, pickers: ImportPickers) {
    DropdownMenu(expanded, onDismiss) {
        DropdownMenuItem({ Text("Screenshot or Photo") }, { onDismiss(); pickers.photos() }, leadingIcon = { Icon(Icons.Filled.PhotoLibrary, null) })
        DropdownMenuItem({ Text("PDF or File") }, { onDismiss(); pickers.files() }, leadingIcon = { Icon(Icons.Filled.Description, null) })
    }
}
