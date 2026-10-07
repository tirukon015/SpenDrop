package com.spendrop.core.parser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

/** Date/time and reference extraction details (iOS DateFormatter en_US_POSIX behaviour, label-on-next-line refs). */
class DateAndReferenceTest {
    private val clock = Clock.fixed(Instant.parse("2026-10-07T00:00:00Z"), ZoneOffset.UTC)
    private fun dt(vararg lines: String) = TransactionParser.extractDateTimeAndStrings(lines.toList(), lines.joinToString("\n"), clock)

    @Test fun dateLineFormats() {
        assertEquals("2026-09-16", dt("16 Sep 2026").dateString)
        assertEquals("2026-09-16", dt("16 September 2026").dateString)
        assertEquals("2026-09-06", dt("6 sep 2026").dateString)            // single-digit day, any case
        assertEquals("2026-09-16", dt("Date: 16/09/2026").dateString)
        assertEquals("2026-09-16", dt("Tarikh : 16-09-2026").dateString)
        assertEquals("2026-08-06", dt("06-Aug-2026").dateString)
        assertEquals("2026-09-16", dt("2026-09-16").dateString)
        // iOS quirk kept: "dd/MM/yyyy" is tried before "dd/MM/yy" and a non-lenient "yyyy" takes "26" literally.
        assertEquals("0026-09-16", dt("16/09/26").dateString)
        assertEquals("0026-09-16", dt("16 Sep 26").dateString)
        assertEquals("2026-09-16", dt("Sep 16, 2026").dateString)
        assertNull(dt("31/02/2026").dateString)                            // impossible date rejected
    }

    @Test fun timeFormatsAndDefaults() {
        assertEquals("21:42:00", dt("16 Sep 2026", "9:42 PM").timeString)
        assertEquals("00:15:00", dt("16 Sep 2026", "12:15 am").timeString)
        assertEquals("10:14:00", dt("16 Sep 2026", "10:14AM").timeString)
        assertEquals("13:49:06", dt("16 Sep 2026", "Time: 13:49:06").timeString)
        // No time: noon, no time string.
        val noon = dt("16 Sep 2026")
        assertNull(noon.timeString)
        assertEquals(LocalDateTime.of(2026, 9, 16, 12, 0, 0), noon.dateTime)
        // A time alone is not used without a date.
        assertEquals(TransactionParser.DateTimeResult(null, null, null), dt("13:49:06"))
    }

    @Test fun embeddedDateAndTime() {
        val r = dt("18 Sep 2026 2:17:49 PM")
        assertEquals("2026-09-18", r.dateString)
        assertEquals("14:17:49", r.timeString)
        assertEquals("2026-09-28", dt("28 September 2026 at 09:30").dateString)
        assertEquals("09:30:00", dt("28 September 2026 at 09:30").timeString)
        // "06-Aug-2026" inside a sentence is not matched by the embedded-date pattern (as on iOS).
        assertNull(dt("CIMB: FPX Payment RM932.46 to IPAY88 accepted on 06-Aug-2026, 23:13:56.").dateString)
        // "18:05 PM" is not a valid time on iOS (h is 1–12; HH:mm leaves " PM"): noon is used.
        assertNull(dt("06 Oct 2026, 18:05 PM").timeString)
    }

    @Test fun epochMillisUseTheGivenZone() {
        val kl = ZoneId.of("Asia/Kuala_Lumpur")
        val p = TransactionParser.parse("Paid RM 5.00\n16 Sep 2026 9:42 PM", zone = kl, clock = clock)
        assertEquals(LocalDateTime.of(2026, 9, 16, 21, 42).atZone(kl).toInstant().toEpochMilli(), p.date)
    }

    @Test fun references() {
        assertEquals("TNG992837194", TransactionParser.extractReferenceNumber(listOf("Ref No: TNG992837194")))
        assertEquals("MBB20260916892", TransactionParser.extractReferenceNumber(listOf("Reference: MBB20260916892")))
        assertEquals("QR80504572", TransactionParser.extractReferenceNumber(listOf("Reference ID", "QR80504572")))
        // Like iOS, a label ending in "." ("Reference No.", "Transaction No.") is not a label-only line.
        assertNull(TransactionParser.extractReferenceNumber(listOf("OCTO Reference No.", "C2026100555")))
        assertNull(TransactionParser.extractReferenceNumber(listOf("Transaction No.", "2026100512345678")))
        assertEquals("C2026100555", TransactionParser.extractReferenceNumber(listOf("Reference No", "C2026100555")))
        assertNull(TransactionParser.extractReferenceNumber(listOf("Reference", "ABCDEFGH"))) // a reference has a digit
        assertNull(TransactionParser.extractReferenceNumber(listOf("Ref: 12345")))             // too short
    }
}

class DatePatternParserTest {
    private val clock = Clock.fixed(Instant.parse("2026-10-07T00:00:00Z"), ZoneOffset.UTC)

    @Test fun twoDigitYearWindow() {
        assertEquals(2026, DatePatternParser("dd/MM/yy").parse("16/09/26", clock)?.year)
        assertEquals(1999, DatePatternParser("dd/MM/yy").parse("16/09/99", clock)?.year)
        assertEquals(2045, DatePatternParser("dd/MM/yy").parse("16/09/45", clock)?.year)
        assertEquals(1947, DatePatternParser("dd/MM/yy").parse("16/09/47", clock)?.year)
    }

    @Test fun wholeTextMustMatch() {
        assertNull(DatePatternParser("dd MMM yyyy").parse("16 Sep 2026 9:42 PM", clock))
        assertNull(DatePatternParser("HH:mm").parse("18:05 PM", clock))
        assertNull(DatePatternParser("h:mm a").parse("13:05 PM", clock))
        assertEquals(DatePatternParser.Parsed(hour = 0, minute = 5), DatePatternParser("h:mm a").parse("12:05 AM", clock))
    }
}
