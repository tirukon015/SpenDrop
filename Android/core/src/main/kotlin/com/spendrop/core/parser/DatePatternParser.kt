package com.spendrop.core.parser

import java.time.Clock
import java.time.LocalDate
import java.time.ZonedDateTime

/**
 * Parses text with a Unicode date pattern the way iOS `DateFormatter` (locale en_US_POSIX, non-lenient) does for the
 * patterns the receipt parser uses: the WHOLE text must match; numeric fields take any number of digits (so "dd"
 * accepts "6") and are range-checked; "MMM"/"MMMM" accept full or short English month names, any case; "a" is AM/PM;
 * a two-digit "yy" year falls within 80 years before / 20 after now; impossible dates (31 Feb) are rejected.
 */
internal class DatePatternParser(pattern: String) {
    private sealed interface Token
    private data class Field(val letter: Char, val count: Int) : Token
    private data class Literal(val char: Char) : Token

    private val tokens: List<Token> = buildList {
        var i = 0
        while (i < pattern.length) {
            val c = pattern[i]
            if (c.isLetter()) {
                var j = i
                while (j < pattern.length && pattern[j] == c) j++
                add(Field(c, j - i)); i = j
            } else {
                add(Literal(c)); i++
            }
        }
    }

    /** Date fields (only those present in the pattern are non-null). */
    data class Parsed(
        val year: Int? = null, val month: Int? = null, val day: Int? = null,
        val hour: Int? = null, val minute: Int? = null, val second: Int? = null,
    )

    fun parse(text: String, clock: Clock): Parsed? {
        var pos = 0
        var year: Int? = null; var month: Int? = null; var day: Int? = null
        var hour12: Int? = null; var hour24: Int? = null; var minute: Int? = null; var second: Int? = null
        var pm: Boolean? = null

        fun readNumber(): Pair<Int, Int>? {
            val start = pos
            while (pos < text.length && text[pos] in '0'..'9') pos++
            if (pos == start || pos - start > 9) return null
            return text.substring(start, pos).toInt() to (pos - start)
        }

        for (token in tokens) {
            when (token) {
                is Literal -> {
                    if (token.char == ' ') {
                        val start = pos
                        while (pos < text.length && isWhitespaceChar(text[pos].code)) pos++
                        if (pos == start) return null
                    } else {
                        if (pos >= text.length || text[pos] != token.char) return null
                        pos++
                    }
                }
                is Field -> when (token.letter) {
                    'd' -> day = readNumber()?.first ?: return null
                    'M' -> if (token.count >= 3) {
                        month = matchMonth(text, pos)?.let { (m, len) -> pos += len; m } ?: return null
                    } else {
                        month = readNumber()?.first ?: return null
                    }
                    'y' -> {
                        val (value, digits) = readNumber() ?: return null
                        year = if (token.count <= 2 && digits == 2) twoDigitYear(value, clock) else value
                    }
                    'h' -> hour12 = readNumber()?.first ?: return null
                    'H' -> hour24 = readNumber()?.first ?: return null
                    'm' -> minute = readNumber()?.first ?: return null
                    's' -> second = readNumber()?.first ?: return null
                    'a' -> {
                        val rest = text.substring(pos)
                        pm = when {
                            rest.startsWith("AM", ignoreCase = true) -> false
                            rest.startsWith("PM", ignoreCase = true) -> true
                            else -> return null
                        }
                        pos += 2
                    }
                    else -> return null
                }
            }
        }
        if (pos != text.length) return null

        // Range checks (non-lenient)
        if (month != null && month !in 1..12) return null
        if (day != null && day !in 1..31) return null
        if (year != null && month != null && day != null) {
            if (runCatching { LocalDate.of(year, month, day) }.isFailure) return null
        }
        if (minute != null && minute !in 0..59) return null
        if (second != null && second !in 0..59) return null
        val hour: Int? = when {
            hour24 != null -> if (hour24 in 0..23) hour24 else return null
            hour12 != null -> {
                if (hour12 !in 0..12) return null
                (hour12 % 12) + if (pm == true) 12 else 0
            }
            else -> null
        }
        return Parsed(year, month, day, hour, minute, second)
    }

    private fun twoDigitYear(value: Int, clock: Clock): Int {
        val start = ZonedDateTime.now(clock).year - 80
        var y = (start / 100) * 100 + value
        if (y < start) y += 100
        return y
    }

    private companion object {
        val fullMonths = listOf("january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december")
        val shortMonths = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

        /** Longest full month name, else short name, at [pos] (case-insensitive). Returns (month, length). */
        fun matchMonth(text: String, pos: Int): Pair<Int, Int>? {
            for (names in listOf(fullMonths, shortMonths)) {
                var best: Pair<Int, Int>? = null
                names.forEachIndexed { i, name ->
                    if (text.regionMatches(pos, name, 0, name.length, ignoreCase = true) && (best == null || name.length > best!!.second)) {
                        best = (i + 1) to name.length
                    }
                }
                if (best != null) return best
            }
            return null
        }
    }
}
