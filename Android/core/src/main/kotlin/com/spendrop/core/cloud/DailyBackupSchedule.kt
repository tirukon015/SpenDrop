package com.spendrop.core.cloud

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

enum class BackupKind { MANUAL, AUTOMATIC }

/**
 * The automatic daily backup decisions of iOS `CloudBackupService` (pure; epoch ms + a time zone).
 *
 * Settings (per signed-in user): "Cloud Backup" consent switch (default OFF; signing in never uploads), "Automatic
 * Daily Backup" (default ON once Cloud Backup is on), time = minutes after local midnight (default 180 = 03:00,
 * clamped to 0…1439). Turning Cloud Backup on runs the first (manual) backup immediately, then schedules.
 * Exactly one pending background request at a time: cancel, then submit [nextRun] (if [shouldSchedule]).
 * [isDue] is checked when the background task fires, when the app becomes active and when the network returns;
 * a failed or offline attempt is not a success, so a later opportunity retries (catch-up). An automatic run whose
 * content hash is unchanged counts as a success for the day.
 */
object DailyBackupSchedule {
    const val DEFAULT_MINUTES = 3 * 60

    fun clampMinutes(minutes: Int): Int = minutes.coerceIn(0, 24 * 60 - 1)

    /** True when an automatic backup already succeeded on [date]'s local day. */
    fun hasSuccessfulAutomaticBackup(lastAutomaticSuccess: Long?, date: Long, zone: ZoneId): Boolean =
        lastAutomaticSuccess != null && day(lastAutomaticSuccess, zone) == day(date, zone)

    /** The scheduled time on [date]'s local day. A time skipped by a DST change moves to the next valid time. */
    fun scheduledTime(date: Long, minutes: Int, zone: ZoneId): Long = at(day(date, zone), minutes, zone)

    /**
     * Today's time if it is still ahead and today's automatic backup hasn't succeeded, otherwise tomorrow's.
     */
    fun nextRun(now: Long, minutes: Int, lastAutomaticSuccess: Long?, zone: ZoneId): Long {
        val today = scheduledTime(now, minutes, zone)
        if (!hasSuccessfulAutomaticBackup(lastAutomaticSuccess, now, zone) && today > now) return today
        return at(day(now, zone).plusDays(1), minutes, zone)
    }

    /** Whether a background request should exist at all. */
    fun shouldSchedule(configured: Boolean, signedIn: Boolean, cloudBackupEnabled: Boolean, dailyEnabled: Boolean): Boolean =
        configured && signedIn && cloudBackupEnabled && dailyEnabled

    /** iOS `runAutomaticBackupIfDue` guard: on, not yet succeeded today, and today's time has passed. */
    fun isDue(
        now: Long, minutes: Int, lastAutomaticSuccess: Long?, zone: ZoneId,
        signedIn: Boolean, cloudBackupEnabled: Boolean, dailyEnabled: Boolean,
    ): Boolean = signedIn && cloudBackupEnabled && dailyEnabled &&
        !hasSuccessfulAutomaticBackup(lastAutomaticSuccess, now, zone) && now >= scheduledTime(now, minutes, zone)

    private fun day(ms: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    /** Like Foundation's `.nextTime` matching policy: a wall time inside a DST gap becomes the first instant after the gap. */
    private fun at(day: LocalDate, minutes: Int, zone: ZoneId): Long {
        val m = clampMinutes(minutes)
        val local = LocalDateTime.of(day, LocalTime.of(m / 60, m % 60))
        val rules = zone.rules
        if (rules.getValidOffsets(local).isEmpty()) return rules.getTransition(local).instant.toEpochMilli()
        return local.atZone(zone).toInstant().toEpochMilli()
    }
}
