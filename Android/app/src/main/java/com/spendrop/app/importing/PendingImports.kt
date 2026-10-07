package com.spendrop.app.importing

import android.net.Uri

/** URIs picked inside the app, handed from the picker to the import screen (read and copied immediately there). */
class PendingImports {
    @Volatile private var uris: List<Uri> = emptyList()
    fun set(list: List<Uri>) { uris = list }
    fun take(): List<Uri> = uris.also { uris = emptyList() }
}
