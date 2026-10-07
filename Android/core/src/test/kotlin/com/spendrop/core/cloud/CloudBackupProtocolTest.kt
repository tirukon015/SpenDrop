package com.spendrop.core.cloud

import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.TestKit
import com.spendrop.core.backup.TestKit.date
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the pure parts of the iOS "Cloud Backup" suite (CloudTests.swift CloudBackupTests + retention). */
class CloudBackupProtocolTest {
    private val device = BackupDevice(id = "device-A", name = "Pixel 9", appVersion = "1.0 (1)")
    private val payload = TestKit.RangeFixture().payload

    @Test fun uploadPathHeadersAndRow() {
        val backupId = "0f8fad5b-d9cb-469f-a165-70867728950e"
        val path = CloudBackupProtocol.objectPath("user-123", device.id, backupId)
        assertEquals("user-123/device-A/0F8FAD5B-D9CB-469F-A165-70867728950E.json", path)
        val bytes = BackupCodec.encodeToBytes(payload)
        val upload = CloudBackupProtocol.uploadObject(path, bytes)
        assertEquals("POST", upload.method)
        assertEquals("storage/v1/object/backups/$path", upload.path)
        assertEquals("false", upload.headers["x-upsert"]); assertEquals("application/json", upload.headers["Content-Type"])

        val record = CloudBackupProtocol.makeRecord(backupId, device, "user-123", payload, bytes.size, date(2026, 10, 5, 12) + 456)
        val insert = CloudBackupProtocol.insertRow(record)
        assertEquals("rest/v1/backups", insert.path); assertEquals("return=minimal", insert.headers["Prefer"])
        assertEquals(
            """{"accounts_count":4,"app_version":"1.0 (1)","backup_version":4,"created_at":"2026-10-05T04:00:00Z","device_id":"device-A",""" +
                """"device_name":"Pixel 9","expenses_count":5,"id":"0F8FAD5B-D9CB-469F-A165-70867728950E","movements_count":3,""" +
                """"object_path":"user-123\/device-A\/0F8FAD5B-D9CB-469F-A165-70867728950E.json","people_count":3,""" +
                """"schema_version":"5.0.0","size_bytes":${bytes.size}}""",
            insert.bodyText,
        )
        assertFalse(insert.bodyText!!.contains("user_id"))
        assertEquals("rest/v1/backups?select=id,object_path&id=eq.0F8FAD5B-D9CB-469F-A165-70867728950E", CloudBackupProtocol.verifyRowCall(backupId).path)
        assertEquals("storage/v1/object/authenticated/backups/$path", CloudBackupProtocol.verifyDownloadCall(path).path)
        assertEquals("""{"prefixes":["a\/b.json"]}""", CloudBackupProtocol.deleteObjects(listOf("a/b.json")).bodyText)
        assertEquals("DELETE", CloudBackupProtocol.deleteObjects(listOf("a/b.json")).method)
        assertEquals("storage/v1/object/backups", CloudBackupProtocol.deleteObjects(listOf("x")).path)
        assertEquals("rest/v1/backups?id=eq.0F8FAD5B-D9CB-469F-A165-70867728950E", CloudBackupProtocol.deleteRow(backupId).path)
        assertEquals("rest/v1/backups?select=*&order=created_at.desc&limit=30", CloudBackupProtocol.listCall().path)
        assertEquals("rest/v1/backups?id=not.is.null", CloudBackupProtocol.deleteAllRowsCall().path)
        assertEquals("rest/v1/rpc/delete_my_account", CloudBackupProtocol.deleteAccountCall().path)
        assertEquals("{}", CloudBackupProtocol.deleteAccountCall().bodyText)
    }

    @Test fun listDecodesServerTimestamps() {
        val body = """[{"id":"0f8fad5b-d9cb-469f-a165-70867728950e","user_id":"user-123","device_id":"device-A","device_name":"iPhone",
            "app_version":"1.4 (1)","schema_version":"5.0.0","backup_version":4,"created_at":"2026-09-29T10:00:00.123456+00:00",
            "object_path":"user-123/device-A/0F8FAD5B-D9CB-469F-A165-70867728950E.json","expenses_count":1,"people_count":1,
            "accounts_count":1,"movements_count":1,"size_bytes":2048},
            {"id":"1f8fad5b-d9cb-469f-a165-70867728950e","device_id":"device-B","device_name":"Pixel","app_version":"1","schema_version":"5.0.0",
            "backup_version":4,"created_at":"2026-10-01T10:00:00+00:00","object_path":"user-123/device-B/x.json","expenses_count":2,
            "people_count":0,"accounts_count":0,"movements_count":0,"size_bytes":10}]"""
        val list = CloudBackupProtocol.decodeList(body)
        assertEquals(2, list.size)
        assertEquals(com.spendrop.core.backup.SwiftDates.parse("2026-09-29T10:00:00Z")!! + 123, list[0].createdAt)
        assertEquals(listOf("device-B", "device-A"), CloudBackupProtocol.sortForList(list).map { it.deviceId })
    }

    @Test fun verificationRules() {
        val id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        val path = CloudBackupProtocol.objectPath("u", "d", id)
        val bytes = BackupCodec.encodeToBytes(payload)
        val rows = """[{"id":"0F8FAD5B-D9CB-469F-A165-70867728950E","object_path":"$path"}]"""
        assertTrue(CloudBackupProtocol.verifyUpload(id, path, bytes, rows, bytes.copyOf()))
        assertFalse(CloudBackupProtocol.verifyUpload(id, path, bytes, "[]", bytes))
        assertFalse(CloudBackupProtocol.verifyUpload(id, path, bytes, rows.replace(path, "other"), bytes))
        assertFalse(CloudBackupProtocol.verifyUpload(id, path, bytes, rows, bytes + 32))
        val junk = "{}".toByteArray()
        assertFalse(CloudBackupProtocol.verifyUpload(id, path, junk, rows, junk))
    }

    @Test fun contentHashIgnoresExportTimeAndOrderButSeesChanges() {
        val h = CloudBackupProtocol.contentHash(payload)
        assertEquals(64, h.length)
        assertEquals(h, CloudBackupProtocol.contentHash(payload.copy(exportDate = payload.exportDate + 86_400_000, accountName = "other")))
        assertEquals(h, CloudBackupProtocol.contentHash(payload.copy(expenses = payload.expenses.reversed(), accounts = payload.accounts!!.reversed())))
        assertEquals(h, CloudBackupProtocol.contentHash(payload.copy(channelRules = emptyList())))
        assertEquals(h, CloudBackupProtocol.contentHash(payload.copy(channelRules = null)))
        val changed = payload.copy(expenses = payload.expenses.map { if (it.merchant == "Grab") it.copy(amount = 14.9) else it })
        assertNotEquals(h, CloudBackupProtocol.contentHash(changed))
        assertFalse(CloudBackupProtocol.shouldUpload(force = false, hash = h, lastVerifiedHash = h))
        assertTrue(CloudBackupProtocol.shouldUpload(force = true, hash = h, lastVerifiedHash = h))
        assertTrue(CloudBackupProtocol.shouldUpload(force = false, hash = h, lastVerifiedHash = null))
    }

    /** iOS "Retention 30 days … 90 days keeps the 40-day one"; never the newest; unreadable dates kept. */
    @Test fun retentionPruneSelection() {
        val now = date(2026, 10, 5, 12)
        val rows = """[
            {"id":"NEW","object_path":"user-123/device-A/NEW.json","created_at":"2026-10-05T04:00:00+00:00"},
            {"id":"old-10","object_path":"user-123/device-A/old-10.json","created_at":"2026-09-25T10:00:00+00:00"},
            {"id":"old-40","object_path":"user-123/device-A/old-40.json","created_at":"2026-08-26T10:00:00+00:00"},
            {"id":"old-100","object_path":"user-123/device-A/old-100.json","created_at":"2026-06-27T10:00:00+00:00"},
            {"id":"bad-date","object_path":"user-123/device-A/bad.json","created_at":"whenever"}]"""
        val p30 = CloudBackupProtocol.selectExpired(rows, "new", now, 30)
        assertEquals(listOf("old-40", "old-100"), p30.ids)
        assertEquals(listOf("user-123/device-A/old-40.json", "user-123/device-A/old-100.json"), p30.paths)
        assertEquals(listOf("old-100"), CloudBackupProtocol.selectExpired(rows, "NEW", now, 90).ids)
        assertTrue(CloudBackupProtocol.selectExpired(rows, "old-100", date(2030, 1, 1), 30).ids.none { it == "old-100" })
        assertTrue(CloudBackupProtocol.selectExpired("[]", "x", now, 30).isEmpty)
        assertEquals("rest/v1/backups?select=id,object_path,created_at&device_id=eq.device-A&order=created_at.desc",
            CloudBackupProtocol.pruneListCall("device-A").path)
        assertEquals("rest/v1/backups?id=in.(old-40,old-100)", CloudBackupProtocol.deleteRows(p30.ids).path)
        assertEquals(30, CloudBackupProtocol.retentionDays(null)); assertEquals(30, CloudBackupProtocol.retentionDays(45))
        assertEquals(90, CloudBackupProtocol.retentionDays(90))
    }

    @Test fun deleteAllPaths() {
        assertEquals(listOf("u/a.json", "u/b.json"),
            CloudBackupProtocol.objectPaths("""[{"id":"1","object_path":"u/a.json"},{"id":"2","object_path":"u/b.json"}]"""))
        assertEquals("rest/v1/backups?select=id,object_path", CloudBackupProtocol.deleteAllListCall().path)
    }
}
