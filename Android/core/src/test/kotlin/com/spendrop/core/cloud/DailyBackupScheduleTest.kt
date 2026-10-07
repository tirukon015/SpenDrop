package com.spendrop.core.cloud

import com.spendrop.core.backup.TestKit.MYT
import com.spendrop.core.backup.TestKit.NEW_YORK
import com.spendrop.core.backup.TestKit.date
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Port of the pure decisions in the iOS "Daily backup" suite (CloudTests.swift DailyBackupTests). */
class DailyBackupScheduleTest {
    private val s = DailyBackupSchedule

    @Test fun defaultsAndScheduling() {
        assertEquals(180, s.DEFAULT_MINUTES)
        assertFalse(s.shouldSchedule(configured = true, signedIn = true, cloudBackupEnabled = false, dailyEnabled = true))
        assertTrue(s.shouldSchedule(configured = true, signedIn = true, cloudBackupEnabled = true, dailyEnabled = true))
        assertFalse(s.shouldSchedule(configured = true, signedIn = true, cloudBackupEnabled = true, dailyEnabled = false))
        assertFalse(s.shouldSchedule(configured = false, signedIn = true, cloudBackupEnabled = true, dailyEnabled = true))
        assertEquals(0, s.clampMinutes(-5)); assertEquals(1439, s.clampMinutes(5000))
    }

    @Test fun enablingAtNoonSchedulesTomorrowAt3() {
        // The first backup is manual (doesn't count as the automatic one); 03:00 has passed today -> tomorrow 03:00.
        assertEquals(date(2026, 10, 6, 3), s.nextRun(date(2026, 10, 5, 12), 180, lastAutomaticSuccess = null, zone = MYT))
        assertEquals(date(2026, 10, 6, 5, 30), s.nextRun(date(2026, 10, 5, 12), 330, null, MYT))
    }

    @Test fun beforeTodaysTimeTheRunIsToday() {
        assertEquals(date(2026, 10, 6, 5, 30), s.nextRun(date(2026, 10, 6, 1), 330, null, MYT))
        // Already succeeded today -> tomorrow even if today's time is ahead.
        assertEquals(date(2026, 10, 7, 5, 30), s.nextRun(date(2026, 10, 6, 1), 330, date(2026, 10, 6, 0, 30), MYT))
    }

    @Test fun dstGapMovesToNextValidTime() {
        val now = date(2026, 3, 7, 23, zone = NEW_YORK)
        val next = Instant.ofEpochMilli(s.nextRun(now, 2 * 60 + 30, null, NEW_YORK)).atZone(NEW_YORK)
        assertEquals(3, next.monthValue); assertEquals(8, next.dayOfMonth); assertEquals(3, next.hour)
    }

    @Test fun oneAutomaticSuccessPerLocalDayWithCatchUp() {
        fun due(now: Long, last: Long?) = s.isDue(now, 180, last, MYT, signedIn = true, cloudBackupEnabled = true, dailyEnabled = true)
        assertFalse(due(date(2026, 10, 5, 2, 59), null))          // not before 3:00
        assertTrue(due(date(2026, 10, 5, 3, 4), null))            // due
        assertTrue(due(date(2026, 10, 5, 22), null))              // failed/offline earlier -> still due (catch-up)
        val success = date(2026, 10, 5, 3, 10)
        assertFalse(due(date(2026, 10, 5, 22), success))          // only one per day
        assertTrue(due(date(2026, 10, 6, 3, 10), success))        // next day runs again
        assertTrue(s.hasSuccessfulAutomaticBackup(date(2026, 10, 6, 3, 10), date(2026, 10, 6, 23), MYT))
        assertFalse(s.hasSuccessfulAutomaticBackup(date(2026, 10, 6, 3, 10), date(2026, 10, 7, 1), MYT))
        assertFalse(s.isDue(date(2026, 10, 5, 4), 180, null, MYT, signedIn = true, cloudBackupEnabled = false, dailyEnabled = true))
        assertFalse(s.isDue(date(2026, 10, 5, 4), 180, null, MYT, signedIn = false, cloudBackupEnabled = true, dailyEnabled = true))
    }
}
