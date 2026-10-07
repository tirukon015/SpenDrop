package com.spendrop.core

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Money is integer minor units (sen). This is the single boundary between text / Double amounts and sen
 * (iOS `Money`). Rules are pinned by Common/BusinessRules/money-test-vectors.json.
 */
object Money {
    const val MINOR_PER_MAJOR = 100

    /** RM7.50 -> 750. Half away from zero (absorbs binary noise like 100.98999…). */
    fun minorUnits(amount: Double): Long =
        BigDecimal.valueOf(amount).movePointRight(2).setScale(0, RoundingMode.HALF_UP).toLong()

    /** "7.50" -> 750, "RM 1,234.5" -> 123450, "MYR 12" -> 1200. Null when the text is not a plain number. */
    fun parseMinor(text: String): Long? {
        val cleaned = text.replace(Regex("(?i)RM|MYR"), "").replace(",", "").trim()
        if (cleaned.isEmpty() || !Regex("""^[+-]?(\d+\.?\d*|\.\d+)$""").matches(cleaned)) return null
        return try {
            BigDecimal(cleaned).movePointRight(2).setScale(0, RoundingMode.HALF_UP).toLong()
        } catch (_: NumberFormatException) {
            null
        }
    }

    /** 750 -> 7.5 (display / legacy Double fields only). */
    fun major(minor: Long): Double = minor / MINOR_PER_MAJOR.toDouble()

    /** 123450 -> "RM 1,234.50"; -500 -> "-RM 5.00". */
    fun format(minor: Long, currency: String = "RM"): String {
        val sign = if (minor < 0) "-" else ""
        val abs = kotlin.math.abs(minor)
        val whole = abs / MINOR_PER_MAJOR
        val cents = abs % MINOR_PER_MAJOR
        val grouped = whole.toString().reversed().chunked(3).joinToString(",").reversed()
        val code = currency.ifBlank { "RM" }
        return "$sign$code $grouped.${cents.toString().padStart(2, '0')}"
    }

    /** "1234.5" style plain text for editing fields: 123450 -> "1234.50". */
    fun plain(minor: Long): String {
        val abs = kotlin.math.abs(minor)
        return (if (minor < 0) "-" else "") + "${abs / 100}.${(abs % 100).toString().padStart(2, '0')}"
    }
}
