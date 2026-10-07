package com.spendrop.core.backup

import com.spendrop.core.backup.TestKit.MYT
import com.spendrop.core.backup.TestKit.NEW_YORK
import com.spendrop.core.backup.TestKit.UTC
import com.spendrop.core.backup.TestKit.date
import com.spendrop.core.model.FinanceSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Port of the iOS "Restore ranges" suite (CloudTests.swift RestoreRangeTests). Fixed dates and zones only. */
class RestoreRangeTest {
    private fun days(range: RestoreRange, reference: Long, zone: ZoneId = MYT): String {
        val i = range.interval(reference, zone) ?: return "all"
        val f = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(zone)
        return "${f.format(Instant.ofEpochMilli(i.start))}…${f.format(Instant.ofEpochMilli(i.end - 1000))}"
    }

    private val ref = date(2026, 10, 5, 1, 32)

    @Test fun rangesFromA5OctBackup() {
        assertEquals("2026-09-29…2026-10-05", days(RestoreRange.LAST_7_DAYS, ref))
        assertEquals("2026-09-06…2026-10-05", days(RestoreRange.LAST_30_DAYS, ref))
        assertEquals("2026-08-06…2026-10-05", days(RestoreRange.LAST_2_MONTHS, ref))
        assertEquals("2026-07-06…2026-10-05", days(RestoreRange.LAST_3_MONTHS, ref))
        assertEquals("all", days(RestoreRange.Everything, ref))
    }

    @Test fun monthEndsAndYearBoundary() {
        val mar31 = date(2026, 3, 31)
        assertEquals("2026-02-01…2026-03-31", days(RestoreRange.LAST_2_MONTHS, mar31))
        assertEquals("2026-01-01…2026-03-31", days(RestoreRange.LAST_3_MONTHS, mar31))
        assertEquals("2026-12-17…2027-01-15", days(RestoreRange.LAST_30_DAYS, date(2027, 1, 15)))
        assertEquals("2026-11-11…2027-02-10", days(RestoreRange.LAST_3_MONTHS, date(2027, 2, 10)))
    }

    @Test fun leapYears() {
        assertEquals("2028-02-23…2028-02-29", days(RestoreRange.LAST_7_DAYS, date(2028, 2, 29)))
        assertEquals("2028-02-24…2028-03-01", days(RestoreRange.LAST_7_DAYS, date(2028, 3, 1)))
        assertEquals("2028-03-01…2028-05-31", days(RestoreRange.LAST_3_MONTHS, date(2028, 5, 31)))
        assertEquals("2027-02-23…2027-03-01", days(RestoreRange.LAST_7_DAYS, date(2027, 3, 1)))
    }

    @Test fun midnightBoundaries() {
        val week = RestoreRange.LAST_7_DAYS.interval(ref, MYT)!!
        assertTrue(week.contains(date(2026, 9, 29, 0, 0, 0)))
        assertTrue(week.contains(date(2026, 10, 5, 23, 59, 59)))
        assertFalse(week.contains(date(2026, 9, 28, 23, 59, 59)))
        assertFalse(week.contains(date(2026, 10, 6, 0, 0, 0)))
    }

    @Test fun timeZonesAndDst() {
        val earlyMorning = date(2026, 10, 5, 1, 0) // = 4 Oct 17:00 UTC
        assertEquals("2026-09-29…2026-10-05", days(RestoreRange.LAST_7_DAYS, earlyMorning))
        assertEquals("2026-09-28…2026-10-04", days(RestoreRange.LAST_7_DAYS, earlyMorning, UTC))
        val ny = date(2026, 11, 5, 12, zone = NEW_YORK)
        assertEquals("2026-10-30…2026-11-05", days(RestoreRange.LAST_7_DAYS, ny, NEW_YORK))
        assertEquals(7 * 86_400_000L + 3_600_000L, RestoreRange.LAST_7_DAYS.interval(ny, NEW_YORK)!!.durationMillis)
    }

    @Test fun customRange() {
        val backwards = RestoreRange.Custom(date(2026, 9, 1), date(2026, 8, 1))
        assertNotNull(backwards.validationProblem(MYT))
        assertNull(backwards.interval(ref, MYT))
        val sameDay = RestoreRange.Custom(date(2026, 10, 1, 18), date(2026, 10, 1, 6))
        assertNull(sameDay.validationProblem(MYT))
        val i = sameDay.interval(ref, MYT)!!
        assertTrue(i.contains(date(2026, 10, 1, 0, 0))); assertTrue(i.contains(date(2026, 10, 1, 23, 59, 59)))
        assertFalse(i.contains(date(2026, 10, 2, 0, 0)))
        assertNull(RestoreRange.LAST_7_DAYS.validationProblem(MYT))
        assertEquals("29 Sep 2026 – 5 Oct 2026", RestoreRange.LAST_7_DAYS.interval(ref, MYT)!!.description(MYT, Locale.US))
        assertEquals("Last 7 days", RestoreRange.LAST_7_DAYS.title)
        assertEquals("Last 2 months", RestoreRange.LAST_2_MONTHS.title)
    }

    // ---- Plans: filtering and dependencies ----

    private val f = TestKit.RangeFixture()
    private val full = f.payload
    private fun plan(range: RestoreRange, local: LocalRecordIds = LocalRecordIds(), backup: BackupPayload = full) =
        BackupRestore.makeRestorePlan(backup, range, MYT, local)

    @Test fun fullBackupAndEverything() {
        assertEquals(5, full.expenses.size); assertEquals(4, full.accounts!!.size); assertEquals(3, full.moneyMovements!!.size)
        assertEquals(3, full.paybookProfiles.size); assertEquals(2, full.classificationRules!!.size)
        val everything = plan(RestoreRange.Everything)
        assertNull(everything.interval)
        assertEquals(RecordCounts(expenses = 5, accounts = 4, movements = 3, profiles = 3, rules = 2), everything.counts)
        assertFalse(everything.isEmpty)
    }

    @Test fun sevenDaysBringsDependencies() {
        val week = plan(RestoreRange.LAST_7_DAYS)
        val w = week.payload
        assertEquals(setOf("McDonald's", "Dinner"), w.expenses.map { it.merchant }.toSet())
        assertEquals(setOf("Maybank", "Touch 'n Go"), w.accounts!!.map { it.name }.toSet())
        assertEquals(setOf("Bijoy", "Ali"), w.paybookProfiles.map { it.name }.toSet())
        assertEquals(listOf("mcdonald's"), w.classificationRules!!.map { it.merchantKey })
        assertEquals(2, w.moneyMovements!!.size)
        assertFalse(w.moneyMovements!!.any { it.kindRaw == "income" })
        assertEquals(1, week.linksOutsideRange)
    }

    @Test fun thirtyDaysRestoresFundingAccountByName() {
        val month = plan(RestoreRange.LAST_30_DAYS).payload
        assertEquals(setOf("McDonald's", "Dinner", "Grab"), month.expenses.map { it.merchant }.toSet())
        assertEquals(setOf("Maybank", "Touch 'n Go", "CIMB"), month.accounts!!.map { it.name }.toSet())
    }

    @Test fun monthRanges() {
        val m2 = plan(RestoreRange.LAST_2_MONTHS); val m3 = plan(RestoreRange.LAST_3_MONTHS)
        val m8 = plan(RestoreRange.LastMonths(8)); val m9 = plan(RestoreRange.LastMonths(9))
        assertEquals(3, m2.counts.expenses); assertEquals(3, m3.counts.expenses); assertEquals(2, m3.counts.movements)
        assertFalse(m8.payload.expenses.any { it.merchant == "Uniqlo" }); assertEquals(3, m8.counts.expenses); assertEquals(1, m8.linksOutsideRange)
        assertEquals(5, m9.counts.expenses); assertEquals(3, m9.counts.movements); assertEquals(0, m9.linksOutsideRange)
    }

    @Test fun customRangeIncludesBothBoundaryDays() {
        val custom = plan(RestoreRange.Custom(date(2026, 1, 15), date(2026, 2, 2))).payload
        assertEquals(setOf("Uniqlo", "Old Lunch"), custom.expenses.map { it.merchant }.toSet())
        assertEquals(setOf("Wise"), custom.accounts!!.map { it.name }.toSet())
        assertEquals(listOf("Old Friend"), custom.paybookProfiles.map { it.name })
    }

    @Test fun nothingToRestore() {
        assertTrue(plan(RestoreRange.Custom(date(2020, 1, 1), date(2020, 12, 31))).isEmpty)
        val empty = BackupPayload(version = 3, accountName = "A", exportDate = ref, expenses = emptyList(), paybookProfiles = emptyList())
        assertTrue(plan(RestoreRange.LAST_30_DAYS, backup = empty).isEmpty)
        assertTrue(plan(RestoreRange.Custom(date(2026, 9, 1), date(2026, 8, 1))).isEmpty)
    }

    @Test fun mergingIntoAPhoneThatAlreadyHasData() {
        val now = date(2026, 10, 7)
        val localOld = TestKit.expense("Local January Coffee", 7.0, date(2026, 1, 3))
        val localMaybank = TestKit.account("Maybank")
        val localPerson = TestKit.person("Local Person")
        var phone = FinanceSnapshot(expenses = listOf(localOld), accounts = listOf(localMaybank), people = listOf(localPerson))

        val p30 = plan(RestoreRange.LAST_30_DAYS, LocalRecordIds.from(phone))
        val result = BackupRestore.applyRestorePlan(p30, phone, now, MYT)
        phone = result.merge.merged
        assertEquals(1, p30.alreadyOnDevice.accounts)
        assertEquals(3, result.added.expenses)
        assertEquals(4, phone.expenses.size)
        assertTrue(phone.expenses.any { it.merchant == "Local January Coffee" })
        assertTrue(phone.people.any { it.name == "Local Person" })
        val mcd = phone.expenses.first { it.merchant == "McDonald's" }
        assertEquals("APPLE_PAY", mcd.paymentChannelRaw)
        assertEquals(localMaybank.id, mcd.accountId)
        assertEquals(1, phone.accounts.count { it.name == "Maybank" })
        assertFalse(phone.accounts.any { it.name.lowercase().contains("apple pay") })

        val again = plan(RestoreRange.LAST_30_DAYS, LocalRecordIds.from(phone))
        val second = BackupRestore.applyRestorePlan(again, phone, now, MYT); phone = second.merge.merged
        val everything = BackupRestore.applyRestorePlan(plan(RestoreRange.Everything, LocalRecordIds.from(phone)), phone, now, MYT); phone = everything.merge.merged
        val week = BackupRestore.applyRestorePlan(plan(RestoreRange.LAST_7_DAYS, LocalRecordIds.from(phone)), phone, now, MYT); phone = week.merge.merged
        assertEquals(3, again.alreadyOnDevice.expenses)
        assertEquals(0, second.added.expenses); assertEquals(2, everything.added.expenses); assertEquals(0, week.added.expenses)
        assertEquals(6, phone.expenses.size); assertEquals(3, phone.movements.size)
        assertEquals(1, phone.accounts.count { it.name == "Maybank" })
        assertEquals(f.snapshot.shares.size, phone.shares.count { it.deletedAt == null })
    }

    @Test fun largeBackupFilteredBeforeMerging() {
        val account = TestKit.account("Maybank")
        val expenses = (0 until 5_000).map { i ->
            TestKit.expense("Shop ${i % 200}", (i % 50 + 1).toDouble(), ref - i * 7_000_000L, "Maybank", account.id)
        }
        val payload = BackupCodec.makePayload(FinanceSnapshot(expenses = expenses, accounts = listOf(account)), "A", ref)
        val interval = RestoreRange.LAST_30_DAYS.interval(ref, MYT)!!
        val expected = payload.expenses.count { interval.contains(it.date) }
        val started = System.nanoTime()
        val p = plan(RestoreRange.LAST_30_DAYS, LocalRecordIds(), payload)
        val r = BackupRestore.applyRestorePlan(p, FinanceSnapshot(), ref, MYT)
        val seconds = (System.nanoTime() - started) / 1e9
        assertEquals(expected, p.counts.expenses); assertEquals(expected, r.added.expenses)
        assertEquals(expected, r.merge.merged.expenses.size)
        assertTrue("took $seconds s", seconds < 10)
    }

    @Test fun refusesUnsupportedPlan() {
        val future = plan(RestoreRange.Everything).let { it.copy(payload = it.payload.copy(version = 5)) }
        try { BackupRestore.applyRestorePlan(future, FinanceSnapshot(), ref, MYT); org.junit.Assert.fail() } catch (e: BackupException.UnsupportedVersion) {
            assertEquals(5, e.version)
        }
    }
}
