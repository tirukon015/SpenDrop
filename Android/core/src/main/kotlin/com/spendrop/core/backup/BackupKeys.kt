package com.spendrop.core.backup

import com.spendrop.core.model.PaymentChannel

/** Normalised identities used by the iOS backup merge (AccountLinker / TransactionClassifier). */
object BackupKeys {
    private val ignoredAccountKeys: Set<String> =
        setOf("", "unknown", "other", "none", "n/a", "na", "-", "null", "nil") +
            PaymentChannel.entries.filter { it != PaymentChannel.CASH && it != PaymentChannel.E_WALLET }.map { it.displayName.lowercase() } +
            setOf("physical card", "qr", "duitnow")

    private val ignoredMerchants = setOf("", "unknown", "unknown merchant", "food / dining")

    private fun collapse(raw: String): String =
        raw.replace('’', '\'').split { it.isWhitespace() }.filter { it.isNotEmpty() }.joinToString(" ")

    private fun String.split(isSep: (Char) -> Boolean): List<String> {
        val parts = mutableListOf<String>()
        val cur = StringBuilder()
        for (c in this) if (isSep(c)) { parts += cur.toString(); cur.clear() } else cur.append(c)
        parts += cur.toString()
        return parts
    }

    /** iOS `AccountLinker.normalizedKey`: " MAYBANK " -> "maybank"; null for "Unknown", "Apple Pay", empty… */
    fun accountKey(raw: String?): String? {
        if (raw == null) return null
        val key = collapse(raw).lowercase()
        return if (key in ignoredAccountKeys) null else key
    }

    /** iOS `TransactionClassifier.merchantKey`: "  McDonald’s  " -> "mcdonald's"; null for placeholders. */
    fun merchantKey(merchant: String?): String? {
        if (merchant == null) return null
        val key = collapse(merchant.lowercase())
        return if (key in ignoredMerchants) null else key
    }
}
