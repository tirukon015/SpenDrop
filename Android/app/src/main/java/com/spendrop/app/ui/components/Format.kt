package com.spendrop.app.ui.components

import com.spendrop.core.Money
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** Display formatting. Money text always comes from :core Money (same output as iOS / Web). */
object Fmt {
    fun money(minor: Long, currency: String = "RM") = Money.format(minor, currency)
    fun signed(minor: Long, currency: String = "RM") = (if (minor > 0) "+" else "") + Money.format(minor, currency)

    private val zone: ZoneId get() = ZoneId.systemDefault()
    private val dateMedium = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
    private val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
    private val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
    private val monthYear = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault())
    private val dayHeader = DateTimeFormatter.ofPattern("EEEE, d MMM yyyy", Locale.getDefault())

    fun date(millis: Long): String = dateMedium.format(Instant.ofEpochMilli(millis).atZone(zone))
    fun dateTime(millis: Long): String = dateTime.format(Instant.ofEpochMilli(millis).atZone(zone))
    fun time(millis: Long): String = time.format(Instant.ofEpochMilli(millis).atZone(zone))
    fun monthYear(millis: Long): String = monthYear.format(Instant.ofEpochMilli(millis).atZone(zone))
    fun dayHeader(millis: Long): String = dayHeader.format(Instant.ofEpochMilli(millis).atZone(zone))
}
