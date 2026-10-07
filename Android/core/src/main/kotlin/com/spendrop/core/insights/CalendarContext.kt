package com.spendrop.core.insights

import com.spendrop.core.Money
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The calendar the insight calculations run in (iOS `Calendar.current`): local days in [zone], weeks starting on
 * [firstDayOfWeek], month / day names in [locale].
 *
 * Week start choice: iOS uses `Calendar.current.firstWeekday`, which comes from the device region. SpenDrop is a
 * Malaysian app and CLDR's first day for MY (and most regions) is Monday, so the default here is MONDAY. Use
 * [device] to follow the Android device region instead. Note that the "This Week" / "Last Week" quick filters always
 * pick the Monday of the week containing "now" (iOS sets `weekday = 2`), exactly like iOS, whatever the first day is.
 */
data class CalendarContext(
    val zone: ZoneId = ZoneId.systemDefault(),
    val firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY,
    val locale: Locale = Locale.ENGLISH,
) {
    fun date(millis: Long): LocalDate = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
    fun zoned(millis: Long): ZonedDateTime = Instant.ofEpochMilli(millis).atZone(zone)

    /** First instant of a local day. */
    fun startOfDay(day: LocalDate): Long = day.atStartOfDay(zone).toInstant().toEpochMilli()
    fun startOfDay(millis: Long): Long = startOfDay(date(millis))

    /** iOS `date(bySettingHour: 23, minute: 59, second: 59, of:)` — note: 23:59:59.000, not .999. */
    fun endOfDay(day: LocalDate): Long = day.atTime(23, 59, 59).atZone(zone).toInstant().toEpochMilli()
    fun endOfDay(millis: Long): Long = endOfDay(date(millis))

    /** First day of the week (per [firstDayOfWeek]) that contains [day]. */
    fun weekStart(day: LocalDate): LocalDate =
        day.minusDays(((day.dayOfWeek.value - firstDayOfWeek.value + 7) % 7).toLong())

    fun isSameDay(a: Long, b: Long): Boolean = date(a) == date(b)

    fun format(millis: Long, pattern: String): String =
        DateTimeFormatter.ofPattern(pattern, locale).format(zoned(millis))

    fun format(day: LocalDate, pattern: String): String = DateTimeFormatter.ofPattern(pattern, locale).format(day)

    companion object {
        /** Device zone, and the device region's first day of week (closest to iOS `Calendar.current`). */
        fun device(): CalendarContext =
            CalendarContext(ZoneId.systemDefault(), WeekFields.of(Locale.getDefault()).firstDayOfWeek, Locale.getDefault())
    }
}

/** Display helpers matching iOS `CurrencyFormatter.format(amount:)` ("RM 1,234.50"; NumberFormatter rounds half-even). */
object MoneyText {
    fun format(minor: Long, currency: String = "RM"): String = Money.format(minor, currency)

    /** For averages that are not whole sen (values in sen as Double). */
    fun format(minor: Double, currency: String = "RM"): String {
        if (minor.isNaN() || minor.isInfinite()) return Money.format(0, currency)
        val rounded = BigDecimal.valueOf(minor).setScale(0, RoundingMode.HALF_EVEN).toLong()
        return Money.format(rounded, currency)
    }

    /** iOS `String(format: "%.2f", amount)` for a minor amount (used by search). */
    fun plain(minor: Long): String = Money.plain(minor)
}
