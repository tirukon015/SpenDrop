package com.spendrop.core.backup

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Dates exactly as Swift `JSONEncoder.dateEncodingStrategy = .iso8601` writes them: `2026-10-07T03:00:00Z`
 * (UTC, whole seconds, NO fractional seconds — Swift's `.iso8601` decoder rejects fractions, so they are never written).
 * Parsing is lenient: fractions, offsets (`+08:00`, `+0800`, `+08`) and Postgres' space separator are accepted.
 */
object SwiftDates {
    private val writer: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)
    private val shortOffset = Regex("""T\d{2}:\d{2}(:\d{2}(\.\d+)?)?[+-]\d{2}$""")
    private val compactOffset = Regex("""([+-])(\d{2})(\d{2})$""")

    /** Epoch ms -> "2026-10-07T03:00:00Z" (sub-second part dropped, floor). */
    fun format(epochMillis: Long): String = writer.format(Instant.ofEpochSecond(Math.floorDiv(epochMillis, 1000L)))

    /** Epoch ms -> "2026-10-07T03:00:00.123Z" (milliseconds kept). For Postgres timestamptz columns only, never for backup files. */
    fun formatMillis(epochMillis: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis))
        .let { if (it.contains('.')) it else it.removeSuffix("Z") + ".000Z" }

    /** Lenient ISO-8601 parse to epoch ms (fractions beyond ms are truncated). Null when unreadable. */
    fun parse(text: String): Long? {
        var t = text.trim()
        if (t.length > 10 && t[10] == ' ') t = t.substring(0, 10) + "T" + t.substring(11)
        if (shortOffset.containsMatchIn(t)) t += ":00"
        else if (t.length > 19 && !t.endsWith("Z") && compactOffset.containsMatchIn(t.substring(19))) {
            t = t.replace(compactOffset, "$1$2:$3")
        }
        return try {
            OffsetDateTime.parse(t, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli()
        } catch (_: Exception) {
            try { Instant.parse(t).toEpochMilli() } catch (_: Exception) { null }
        }
    }
}

/** Swift `Date` (iso8601) <-> epoch ms. */
object SwiftDateSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("SwiftDate", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Long) = encoder.encodeString(SwiftDates.format(value))
    override fun deserialize(decoder: Decoder): Long {
        val text = decoder.decodeString()
        return SwiftDates.parse(text) ?: throw kotlinx.serialization.SerializationException("Bad date $text")
    }
}

/** Swift `UUID`: written upper case (`uuidString`), read in any case and normalised to lower case. */
object SwiftUuidSerializer : KSerializer<String> {
    private val pattern = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("SwiftUUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value.trim().uppercase())
    override fun deserialize(decoder: Decoder): String {
        val text = decoder.decodeString().trim()
        if (!pattern.matches(text)) throw kotlinx.serialization.SerializationException("Bad UUID $text")
        return text.lowercase()
    }
}

/**
 * Writes a [JsonElement] the way Swift's `JSONEncoder` does with `.sortedKeys` (and optionally `.prettyPrinted`):
 * - keys sorted (all SpenDrop keys sort identically by Swift's case-insensitive/numeric order and by code point);
 * - pretty: two-space indent, `"key" : value`, empty containers as `[\n\n<indent>]`;
 * - strings escape `"` `\` `/` (as `\/`) and control characters; non-ASCII is written as UTF-8;
 * - doubles like Swift (`22` not `22.0`, `25.9`, `0.01`).
 * `null` values are never produced by Swift's synthesized Codable (nil optionals are omitted); they are skipped here.
 */
object SwiftJsonWriter {
    fun write(element: JsonElement, pretty: Boolean): String = StringBuilder().also { write(it, element, pretty, 0) }.toString()

    private fun write(out: StringBuilder, e: JsonElement, pretty: Boolean, level: Int) {
        when (e) {
            is JsonObject -> {
                val entries = e.entries.filter { it.value !is JsonNull }.sortedWith { a, b -> a.key.compareTo(b.key) }
                out.append('{')
                if (pretty) out.append('\n')
                entries.forEachIndexed { i, (k, v) ->
                    if (i > 0) out.append(if (pretty) ",\n" else ",")
                    if (pretty) indent(out, level + 1)
                    string(out, k)
                    out.append(if (pretty) " : " else ":")
                    write(out, v, pretty, level + 1)
                }
                if (pretty) { out.append('\n'); indent(out, level) }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                if (pretty) out.append('\n')
                e.forEachIndexed { i, v ->
                    if (i > 0) out.append(if (pretty) ",\n" else ",")
                    if (pretty) indent(out, level + 1)
                    write(out, v, pretty, level + 1)
                }
                if (pretty) { out.append('\n'); indent(out, level) }
                out.append(']')
            }
            is JsonNull -> out.append("null")
            is JsonPrimitive -> if (e.isString) string(out, e.content) else out.append(number(e.content))
        }
    }

    private fun indent(out: StringBuilder, level: Int) { repeat(level) { out.append("  ") } }

    /** Swift Double formatting: shortest representation, no trailing ".0", exponent form only for tiny/huge values. */
    fun number(content: String): String {
        if (content == "true" || content == "false") return content
        if (!content.any { it == '.' || it == 'e' || it == 'E' }) return content
        val d = content.toDoubleOrNull() ?: return content
        val abs = kotlin.math.abs(d)
        if (d == 0.0) return if (1.0 / d < 0) "-0" else "0"
        val bd = BigDecimal(d.toString()).stripTrailingZeros()
        if (abs < 1e-4 || abs >= 1e16) {
            val exp = bd.precision() - bd.scale() - 1
            val mantissa = bd.movePointLeft(exp).stripTrailingZeros().toPlainString()
            val sign = if (exp < 0) "-" else "+"
            return mantissa + "e" + sign + kotlin.math.abs(exp).toString().padStart(2, '0')
        }
        return bd.toPlainString()
    }

    private fun string(out: StringBuilder, s: String) {
        out.append('"')
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '/' -> out.append("\\/")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ') out.append("\\u").append(Integer.toHexString(c.code).padStart(4, '0')) else out.append(c)
            }
        }
        out.append('"')
    }
}
