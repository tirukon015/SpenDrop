package com.spendrop.core.backup

import com.spendrop.core.backup.TestKit.date
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SampleRecord
import com.spendrop.core.model.SettlementAllocation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class BackupCodecTest {
    private val fixture = TestKit.resource("ios_backup_v4.json")

    @Test fun decodesRealisticIosV4Backup() {
        val p = BackupCodec.decode(fixture)
        assertEquals(4, p.version)
        assertEquals("me@example.com", p.accountName)
        assertEquals(date(2026, 10, 5, 1, 32), p.exportDate)
        assertEquals(2, p.expenses.size)
        val dinner = p.expenses[0]
        assertEquals("e0000000-0000-4000-8000-000000000001", dinner.id)
        assertEquals("a1b2c3d4-0000-4000-8000-00000000000a", dinner.accountId)
        assertEquals(30.0, dinner.amount, 0.0)
        assertEquals(false, dinner.paidByMe)
        assertEquals(2, dinner.shares!!.size)
        assertNull(dinner.shares!![0].personId)
        val mcd = p.expenses[1]
        assertEquals("receipts/mcd.jpg", mcd.imageRelativePath)
        assertEquals("Line 1\nTax \"incl.\" 6%", mcd.notes)
        assertEquals("McDonald’s", mcd.merchant)
        assertEquals(0.91, mcd.confidence!!, 0.0)
        assertEquals(1, p.channelRules!!.size)
        assertEquals(1, p.settlementAllocations!!.size)
        assertEquals("f0000000-0000-4000-8000-000000000001", p.settlementAllocations!![0].paymentID)
        assertEquals(RecordCount(expenses = 2, profiles = 1, accounts = 1, movements = 1, rules = 1), p.recordCount)
    }

    @Test fun reEncodingTheIosFileIsByteIdentical() {
        val p = BackupCodec.decode(fixture)
        assertEquals(fixture.trimEnd(), BackupCodec.encode(p))
    }

    @Test fun iosFixtureMapsToCoreRecords() {
        val merged = BackupMerge.apply(BackupCodec.decode(fixture), FinanceSnapshot(), now = date(2026, 10, 7)).merged
        val dinner = merged.expenses.first { it.merchant == "Dinner" }
        assertEquals(3000L, dinner.amountMinor)
        assertEquals("b0000000-0000-4000-8000-000000000001", dinner.payerId)
        assertEquals("a1b2c3d4-0000-4000-8000-00000000000a", dinner.accountId)
        assertEquals(2, merged.sharesOf(dinner.id).size)
        val mcd = merged.expenses.first { it.merchant.startsWith("McDonald") }
        assertEquals(1850L, mcd.amountMinor)
        assertEquals("APPLE_PAY", mcd.paymentChannelRaw)
        assertEquals("Maybank", mcd.fundingAccount)
        assertEquals("EXT-1", mcd.externalTransactionId)
        assertEquals(1, merged.paymentMethods.size)
        assertEquals("b0000000-0000-4000-8000-000000000001", merged.paymentMethods[0].personId)
        assertEquals(1, merged.allocations.size)
        assertEquals(1, merged.sampleRecords.size)
        assertEquals(1, merged.channelRules.size)
        assertTrue(merged.people.single().isFrequent)
    }

    /** DataSafetyTests 10: a version-1 file (before Phase 0) still decodes and restores. */
    @Test fun version1FileRestores() {
        val v1 = """
            {"accountName":"Test","appName":"SpenDrop","exportDate":"2026-09-01T10:00:00Z","version":1,
             "expenses":[{"id":"11111111-1111-1111-1111-111111111111","amount":18.5,"currency":"RM","merchant":"McDonald's",
               "categoryRaw":"Food","paymentSourceRaw":"Touch 'n Go","date":"2026-09-01T09:00:00Z","sourceTypeRaw":"screenshot",
               "isSampleData":false,"createdAt":"2026-09-01T09:05:00Z","paymentChannelRaw":"QR_PAYMENT","fundingAccount":"Touch 'n Go",
               "matchingStatusRaw":"UNMATCHED"}],
             "paybookProfiles":[{"id":"22222222-2222-2222-2222-222222222222","name":"Bijoy",
               "paymentMethods":[{"id":"33333333-3333-3333-3333-333333333333","paymentTypeRaw":"Bank Account","provider":"Maybank","accountIdentifier":"123"}]}]}
        """.trimIndent()
        val result = BackupRestore.importFromJson(v1, FinanceSnapshot(), now = date(2026, 10, 7))
        assertEquals(1, result.summary.expensesAdded)
        assertEquals(1, result.summary.profilesAdded)
        assertEquals(1, result.summary.methodsAdded)
        val e = result.merged.expenses.single()
        assertEquals("11111111-1111-1111-1111-111111111111", e.id)
        assertEquals(SwiftDates.parse("2026-09-01T09:05:00Z"), e.createdAt)
        assertEquals("QR_PAYMENT", e.paymentChannelRaw)
        assertEquals(1850L, e.amountMinor)
        assertEquals(e.createdAt, e.updatedAt)
    }

    @Test fun version2FileDecodes() {
        val v2 = """
            {"accountName":"A","appName":"SpenDrop","exportDate":"2026-09-01T10:00:00Z","version":2,
             "accounts":[{"id":"aaaaaaaa-0000-4000-8000-000000000001","name":"CIMB","typeRaw":"bank","currency":"RM","isArchived":false,"createdAt":"2026-01-01T00:00:00Z","sortIndex":0}],
             "moneyMovements":[{"id":"bbbbbbbb-0000-4000-8000-000000000001","directionRaw":"in","kindRaw":"income","amountMinor":500000,"currency":"RM",
               "date":"2026-08-31T00:00:00Z","accountId":"AAAAAAAA-0000-4000-8000-000000000001","sourceTypeRaw":"manual","paymentChannelRaw":"UNKNOWN",
               "createdAt":"2026-08-31T00:00:00Z","updatedAt":"2026-08-31T00:00:00Z"}],
             "expenses":[], "paybookProfiles":[]}
        """.trimIndent()
        val p = BackupCodec.decode(v2)
        assertEquals(2, p.version)
        assertNull(p.classificationRules)
        assertNull(p.channelRules)
        val merged = BackupMerge.apply(p, FinanceSnapshot(), date(2026, 10, 7)).merged
        assertEquals("aaaaaaaa-0000-4000-8000-000000000001", merged.movements.single().accountId)
    }

    @Test fun fractionalSecondsAndOffsetsDecode() {
        assertEquals(SwiftDates.parse("2026-10-07T03:00:00Z")!! + 123, SwiftDates.parse("2026-10-07T03:00:00.123456Z"))
        assertEquals(SwiftDates.parse("2026-10-07T03:00:00Z"), SwiftDates.parse("2026-10-07T11:00:00+08:00"))
        assertEquals(SwiftDates.parse("2026-10-07T03:00:00Z"), SwiftDates.parse("2026-10-07T03:00:00.000000+00:00"))
        assertEquals(SwiftDates.parse("2026-10-07T03:00:00Z"), SwiftDates.parse("2026-10-07 03:00:00+00"))
        assertEquals(SwiftDates.parse("2026-10-07T03:00:00Z"), SwiftDates.parse("2026-10-07T11:00:00+0800"))
        assertNull(SwiftDates.parse("yesterday"))
        val withFractions = fixture.replace("\"2026-10-04T17:32:00Z\"", "\"2026-10-04T17:32:00.250Z\"")
            .replace("\"2026-10-01T12:00:00Z\"", "\"2026-10-01T20:00:00.5+08:00\"")
        val p = BackupCodec.decode(withFractions)
        assertEquals(date(2026, 10, 5, 1, 32) + 250, p.exportDate)
        assertEquals(date(2026, 10, 1, 20) + 500, p.expenses[0].date)
    }

    @Test fun writtenDatesNeverHaveFractions() {
        val p = BackupCodec.decode(fixture).copy(exportDate = date(2026, 10, 7, 11) + 987)
        val text = BackupCodec.encode(p)
        assertTrue(text.contains("\"exportDate\" : \"2026-10-07T03:00:00Z\""))
        assertFalse(Regex("""\d{2}:\d{2}:\d{2}\.\d""").containsMatchIn(text))
        assertTrue(Regex(""""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"""").containsMatchIn(text))
    }

    @Test fun uuidsWrittenUpperCaseAndReadInAnyCase() {
        val lower = fixture.replace("E0000000-0000-4000-8000-000000000001", "e0000000-0000-4000-8000-000000000001")
        val p = BackupCodec.decode(lower)
        assertEquals("e0000000-0000-4000-8000-000000000001", p.expenses[0].id)
        val out = BackupCodec.encode(p)
        assertTrue(out.contains("\"E0000000-0000-4000-8000-000000000001\""))
        assertFalse(out.contains("e0000000-0000"))
        try { BackupCodec.decode(fixture.replace("E0000000-0000-4000-8000-000000000001", "not-a-uuid")); fail() } catch (_: BackupException.Unreadable) {}
    }

    @Test fun swiftFormatting() {
        assertEquals("22", SwiftJsonWriter.number("22.0"))
        assertEquals("25.9", SwiftJsonWriter.number("25.9"))
        assertEquals("0.01", SwiftJsonWriter.number("0.01"))
        assertEquals("12345678.9", SwiftJsonWriter.number("1.23456789E7"))
        assertEquals("1e-05", SwiftJsonWriter.number("1.0E-5"))
        assertEquals("750", SwiftJsonWriter.number("750"))
        val text = BackupCodec.encode(BackupCodec.decode(fixture))
        assertTrue(text.contains("\"amount\" : 30,"))
        assertTrue(text.contains("receipts\\/mcd.jpg"))
    }

    /** Swift sorts keys case-insensitively/numerically; for every SpenDrop key set that equals code-point order. */
    @Test fun keyOrderMatchesSwiftComparator() {
        val p = BackupCodec.decode(fixture)
        val objects = mutableListOf<kotlinx.serialization.json.JsonObject>()
        fun walk(e: kotlinx.serialization.json.JsonElement) {
            when (e) {
                is kotlinx.serialization.json.JsonObject -> { objects += e; e.values.forEach(::walk) }
                is kotlinx.serialization.json.JsonArray -> e.forEach(::walk)
                else -> {}
            }
        }
        walk(BackupCodec.toJsonElement(p))
        val swiftOrder = Comparator<String> { a, b ->
            val c = a.lowercase().compareTo(b.lowercase()); if (c != 0) c else a.compareTo(b)
        }
        for (o in objects) assertEquals(o.keys.sortedWith(swiftOrder), o.keys.sorted())
    }

    @Test fun roundTripThroughFileKeepsEveryRecord() {
        val f = TestKit.RangeFixture()
        val snapshot = f.snapshot.copy(
            paymentMethods = listOf(PersonPaymentMethod(id = TestKit.id(), personId = f.bijoy.id, provider = "Maybank", accountIdentifier = "111",
                createdAt = date(2026, 1, 1), updatedAt = date(2026, 1, 1))),
            allocations = listOf(SettlementAllocation(id = TestKit.id(), groupId = TestKit.id(), paymentId = null, expenseId = f.dinner.id,
                personId = f.bijoy.id, direction = 1, amountMinor = 3000, date = date(2026, 10, 2), createdAt = date(2026, 10, 2))),
            channelRules = listOf(ChannelRule(id = TestKit.id(), merchantKey = "mcdonald's", fundingKey = "maybank", channelRaw = "APPLE_PAY",
                createdAt = date(2026, 9, 1), updatedAt = date(2026, 9, 2))),
            sampleRecords = listOf(SampleRecord(f.grab.id, "expense", date(2026, 9, 1))),
        )
        val text = BackupCodec.encode(BackupCodec.makePayload(snapshot, "me@example.com", f.reference))
        val restored = BackupRestore.importFromJson(text, FinanceSnapshot(), now = date(2026, 10, 7)).merged
        assertEquals(snapshot.expenses.map { it.id }.toSet(), restored.expenses.map { it.id }.toSet())
        assertEquals(snapshot.shares.map { it.id }.toSet(), restored.shares.map { it.id }.toSet())
        assertEquals(snapshot.movements.map { it.id }.toSet(), restored.movements.map { it.id }.toSet())
        assertEquals(snapshot.accounts.map { it.id }.toSet(), restored.accounts.map { it.id }.toSet())
        assertEquals(snapshot.people.map { it.id }.toSet(), restored.people.map { it.id }.toSet())
        assertEquals(1, restored.paymentMethods.size); assertEquals(1, restored.allocations.size)
        assertEquals(1, restored.channelRules.size); assertEquals(1, restored.sampleRecords.size)
        assertEquals(2, restored.classificationRules.size)
        for (e in snapshot.expenses) {
            val r = restored.expenses.first { it.id == e.id }
            assertEquals(e.amountMinor, r.amountMinor); assertEquals(e.date, r.date); assertEquals(e.accountId, r.accountId)
            assertEquals(e.payerId, r.payerId); assertEquals(e.paidByMe, r.paidByMe); assertEquals(e.paymentChannelRaw, r.paymentChannelRaw)
        }
        assertEquals(f.uniqlo.id, restored.movements.first { it.kindRaw == "refund" }.linkedExpenseId)
        // Restoring the same file again changes nothing.
        val second = BackupRestore.importFromJson(text, restored, now = date(2026, 10, 8))
        assertEquals(0, second.summary.expensesAdded)
        assertEquals(restored.expenses.size, second.merged.expenses.size)
        assertTrue(second.changes.shares.isEmpty() && second.changes.accounts.isEmpty() && second.changes.movements.isEmpty())
    }

    @Test fun exportExcludesTombstonesUsesAccountNameAndEffectiveFunding() {
        val live = TestKit.expense("Shell", 50.0, funding = "Unknown").copy(underlyingBankRaw = "CIMB", paymentSourceRaw = "CIMB", receiptPath = "u/x.webp")
        val dead = TestKit.expense("Gone", 5.0).copy(deletedAt = date(2026, 10, 2))
        val p = BackupCodec.makePayload(FinanceSnapshot(expenses = listOf(live, dead)), BackupCodec.DEFAULT_ACCOUNT_NAME, date(2026, 10, 7))
        assertEquals(listOf("Shell"), p.expenses.map { it.merchant })
        assertEquals("CIMB", p.expenses[0].fundingAccount)
        assertEquals("SpenDrop user", p.accountName)
        assertEquals(BackupPayload.CURRENT_VERSION, p.version)
        assertNotNull(p.channelRules)
        val text = BackupCodec.encode(p)
        assertFalse(text.contains("receiptPath")); assertFalse(text.contains("deletedAt")); assertFalse(text.contains("Touhidul"))
        assertTrue(text.contains("\"shares\" : [\n\n      ]"))
    }

    @Test fun refusesNewerAndDamagedFiles() {
        try { BackupCodec.decode(fixture.replace("\"version\" : 4", "\"version\" : 5")); fail() } catch (e: BackupException.UnsupportedVersion) { assertEquals(5, e.version) }
        try { BackupCodec.decode("{not json"); fail() } catch (_: BackupException.Unreadable) {}
        try { BackupCodec.decode("{\"version\":4}"); fail() } catch (_: BackupException.Unreadable) {}
    }

    @Test fun recordCountIsSmaller() {
        val a = RecordCount(3, 1, 1, 1, 1)
        assertTrue(RecordCount(2, 1, 1, 1, 1).isSmaller(a))
        assertTrue(RecordCount(9, 9, 9, 9, 0).isSmaller(a))
        assertFalse(RecordCount(3, 1, 1, 1, 1).isSmaller(a))
        assertFalse(RecordCount(4, 2, 1, 1, 1).isSmaller(a))
    }
}
