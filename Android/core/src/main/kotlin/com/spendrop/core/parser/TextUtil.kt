package com.spendrop.core.parser

import java.util.regex.Pattern

/*
 * Small helpers that reproduce the Swift / Foundation text semantics the iOS parser relies on
 * (Character.isNumber / isLetter / isPunctuation, NSRegularExpression flags, split without empty pieces).
 */

/** Swift `Character.isNumber`: any Unicode number (Nd, Nl, No). */
internal fun isNumberChar(cp: Int): Boolean = when (Character.getType(cp)) {
    Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
    else -> false
}

/** Swift `Character.isPunctuation`: Unicode general category P*. */
internal fun isPunctuationChar(cp: Int): Boolean = when (Character.getType(cp)) {
    Character.CONNECTOR_PUNCTUATION.toInt(), Character.DASH_PUNCTUATION.toInt(), Character.START_PUNCTUATION.toInt(),
    Character.END_PUNCTUATION.toInt(), Character.INITIAL_QUOTE_PUNCTUATION.toInt(), Character.FINAL_QUOTE_PUNCTUATION.toInt(),
    Character.OTHER_PUNCTUATION.toInt() -> true
    else -> false
}

internal fun isLetterChar(cp: Int): Boolean = Character.isLetter(cp)

internal fun isWhitespaceChar(cp: Int): Boolean = Character.isWhitespace(cp) || Character.isSpaceChar(cp)

internal inline fun String.allCodePoints(crossinline predicate: (Int) -> Boolean): Boolean = codePoints().allMatch { predicate(it) }

internal inline fun String.anyCodePoint(crossinline predicate: (Int) -> Boolean): Boolean = codePoints().anyMatch { predicate(it) }

internal fun String.countCodePoints(predicate: (Int) -> Boolean): Int = codePoints().filter { predicate(it) }.count().toInt()

/** Swift `String.count` (close enough for receipt text: counts code points, not UTF-16 units). */
internal val String.charCount: Int get() = codePointCount(0, length)

/** Swift `trimmingCharacters(in: .whitespacesAndNewlines)`. */
internal fun String.trimWs(): String = trim { isWhitespaceChar(it.code) }

/** Swift `trimmingCharacters(in: .whitespaces)` (spaces and tabs, not newlines). */
internal fun String.trimSpaces(): String = trim { it != '\n' && it != '\r' && isWhitespaceChar(it.code) }

/** Swift `split(separator:)`: empty pieces are omitted. */
internal fun String.splitNonEmpty(separator: Char): List<String> = split(separator).filter { it.isNotEmpty() }

/** Swift `split(whereSeparator: \.isWhitespace).joined(separator: " ")`. */
internal fun String.collapseWhitespace(): String =
    split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

/**
 * NSRegularExpression equivalent. ICU regexes are Unicode-aware (`\w`, `\b`, `\s`, `\d`, case folding), so the
 * Java pattern is compiled with UNICODE_CHARACTER_CLASS (and UNICODE_CASE when case-insensitive).
 */
internal fun icuRegex(pattern: String, caseInsensitive: Boolean = false): Pattern {
    var flags = Pattern.UNICODE_CHARACTER_CLASS
    if (caseInsensitive) flags = flags or Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE
    return Pattern.compile(pattern, flags)
}

/** First match's capture group 1, or null. */
internal fun Pattern.firstGroup(text: String, group: Int = 1): String? {
    val m = matcher(text)
    return if (m.find()) m.group(group) else null
}

internal fun Pattern.containsMatchIn(text: String): Boolean = matcher(text).find()
