package com.spendrop.core.bulk

import java.math.BigDecimal
import java.time.LocalDate
import java.time.LocalTime

/**
 * Bulk Import: decides whether one screenshot is a single receipt or a list of transactions (a payment / bank history),
 * following Common/BusinessRules/bulk-import.md and its vectors. Text only; conservative: anything that isn't clearly a
 * list is a single receipt for the existing TransactionParser.
 */
object ScreenshotSplitter {
    data class Row(
        val merchant: String,
        val amountMinor: Long,
        /** "in" for a leading +, otherwise "out". */
        val direction: String,
        val date: LocalDate,
        val time: LocalTime,
        /** The OCR line the row came from (category evidence for the editor). */
        val line: String = "",
    )

    sealed interface Result {
        object Single : Result
        data class Multiple(val rows: List<Row>) : Result
    }

    private const val MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec"
    private val amountRe = Regex("""(?<![\w.,])([+-])?\s?(?:(?:RM|MYR)\s?)?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d.])""", RegexOption.IGNORE_CASE)
    private val dateDmy = Regex("""\b(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})\b""")
    private val dateIso = Regex("""\b(\d{4})-(\d{2})-(\d{2})\b""")
    private val dateDMon = Regex("""\b(\d{1,2})\s+($MONTHS)[a-z]*\.?(?:\s+(\d{4}))?\b""", RegexOption.IGNORE_CASE)
    private val timeRe = Regex("""\b(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?\b""")
    private val singleMarkers = listOf("payment successful", "transaction successful", "successful", "receipt", "total", "ref no", "reference")

    fun classify(lines: List<String>, importDate: LocalDate): Result {
        val clean = lines.map { it.trim() }.filter { it.isNotEmpty() }
        val rows = clean.mapNotNull { row(it, importDate) }
        if (rows.size < 2) return Result.Single
        val lower = clean.joinToString("\n").lowercase()
        if (rows.size == 2 && singleMarkers.any { it in lower }) return Result.Single
        return Result.Multiple(rows)
    }

    internal fun row(line: String, importDate: LocalDate): Row? {
        val amounts = amountRe.findAll(line).toList()
        if (amounts.size != 1) return null
        val a = amounts[0]
        val (date, dateRange) = date(line, importDate) ?: return null
        var rest = line.removeRange(maxOf(a.range.first, 0), a.range.last + 1).let { it.replaceFirst(line.substring(dateRange), " ") }
        val t = timeRe.find(rest)
        val time = t?.let { m ->
            var h = m.groupValues[1].toInt(); val min = m.groupValues[2].toInt()
            when (m.groupValues[3].lowercase()) { "pm" -> if (h < 12) h += 12; "am" -> if (h == 12) h = 0 }
            if (h in 0..23 && min in 0..59) LocalTime.of(h, min) else null
        } ?: LocalTime.NOON
        if (t != null) rest = rest.removeRange(t.range)
        val merchant = rest.split(Regex("\\s+")).filter { it.isNotEmpty() && it !in setOf("—", "–", "-", "|", "·", "•", ":") }
            .joinToString(" ").trim(' ', '—', '–', '-', '|', '·', '•', ':').trim()
        if (merchant.count { it.isLetter() } < 2) return null
        val whole = a.groupValues[2].replace(",", "")
        val minor = BigDecimal("$whole.${a.groupValues[3]}").movePointRight(2).toLong()
        if (minor <= 0) return null
        return Row(merchant, minor, if (a.groupValues[1] == "+") "in" else "out", date, time, line)
    }

    private fun date(line: String, importDate: LocalDate): Pair<LocalDate, IntRange>? {
        dateIso.find(line)?.let { m -> return runCatching { LocalDate.of(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt()) to m.range }.getOrNull() }
        dateDmy.find(line)?.let { m ->
            val y = m.groupValues[3].toInt().let { if (it < 100) 2000 + it else it }
            return runCatching { LocalDate.of(y, m.groupValues[2].toInt(), m.groupValues[1].toInt()) to m.range }.getOrNull()
        }
        dateDMon.find(line)?.let { m ->
            val month = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec").indexOf(m.groupValues[2].lowercase().take(3)) + 1
            val day = m.groupValues[1].toInt()
            val explicit = m.groupValues[3].takeIf { it.isNotEmpty() }?.toInt()
            return runCatching {
                val d = LocalDate.of(explicit ?: importDate.year, month, day)
                (if (explicit == null && d.isAfter(importDate)) d.minusYears(1) else d) to m.range
            }.getOrNull()
        }
        return null
    }
}
