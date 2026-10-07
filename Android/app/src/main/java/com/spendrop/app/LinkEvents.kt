package com.spendrop.app

import com.spendrop.app.cloud.EmailLinkResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Result of the latest sign-in / email link, shown once as a dialog by the UI. */
class LinkEvents {
    private val _latest = MutableStateFlow<EmailLinkResult?>(null)
    val latest: StateFlow<EmailLinkResult?> = _latest
    fun deliver(result: EmailLinkResult?) { if (result != null) _latest.value = result }
    fun consume() { _latest.value = null }
}
