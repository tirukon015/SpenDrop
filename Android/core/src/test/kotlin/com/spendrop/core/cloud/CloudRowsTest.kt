package com.spendrop.core.cloud

import com.spendrop.core.backup.TestKit
import com.spendrop.core.backup.TestKit.date
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudRowsTest {
    private val f = TestKit.RangeFixture()

    @Test fun expenseRowHasExactColumnsAndExplicitNulls() {
        val e = f.grab.copy(id = f.grab.id.uppercase(), updatedAt = f.grab.updatedAt + 123)
        val json = CloudRows.toJson(CloudRows.toRow(e)).jsonObject
        assertEquals(
            setOf("id", "amount_minor", "currency", "merchant", "category", "payment_channel", "funding_account", "funding_instrument",
                "account_id", "payment_source", "date", "notes", "transaction_reference", "source_type", "paid_by_me", "payer_id",
                "payer_name_snapshot", "split_method", "receipt_path", "is_sample_data", "created_at", "updated_at", "deleted_at"),
            json.keys,
        )
        assertEquals(f.grab.id.lowercase(), json["id"]!!.jsonPrimitive.content)
        assertEquals(1480L, json["amount_minor"]!!.jsonPrimitive.content.toLong())
        assertEquals(JsonNull, json["deleted_at"])
        assertTrue(json["updated_at"]!!.jsonPrimitive.content.endsWith(".123Z"))
        assertFalse(json.containsKey("user_id")); assertFalse(json.containsKey("server_updated_at"))
    }

    @Test fun rowsRoundTrip() {
        val s = f.snapshot
        for (e in s.expenses) assertEquals(e, CloudRows.fromRow(CloudRows.toRow(e), e))
        for (x in s.shares) assertEquals(x, CloudRows.fromRow(CloudRows.toRow(x)))
        for (x in s.accounts) assertEquals(x, CloudRows.fromRow(CloudRows.toRow(x)))
        for (x in s.people) assertEquals(x, CloudRows.fromRow(CloudRows.toRow(x)))
        for (x in s.movements) assertEquals(x, CloudRows.fromRow(CloudRows.toRow(x)))
        for (x in s.classificationRules) assertEquals(x, CloudRows.fromRow(CloudRows.toRow(x)))
        // Columns the cloud lacks come from the local copy; without one they take defaults.
        val withOcr = f.mcd.copy(ocrText = "TOTAL 18.50", underlyingBankRaw = "Maybank")
        val back = CloudRows.fromRow(CloudRows.toRow(withOcr), withOcr)
        assertEquals("TOTAL 18.50", back.ocrText)
        assertNull(CloudRows.fromRow(CloudRows.toRow(withOcr)).ocrText)
        // Decoding a server row (microseconds, user_id, server_updated_at)
        val serverRow = """{"id":"${f.cimb.id}","user_id":"u","name":"CIMB","type":"bank","currency":"RM","icon":null,"is_archived":false,
            "sort_index":1,"created_at":"2025-02-01T04:00:00+00:00","updated_at":"2026-10-01T04:00:00.123456+00:00","deleted_at":null,
            "server_updated_at":"2026-10-01T04:00:01.5+00:00"}"""
        val row = CloudRows.json.decodeFromString(AccountRow.serializer(), serverRow)
        assertEquals("u", row.userId)
        assertEquals(date(2026, 10, 1, 12) + 123, CloudRows.fromRow(row).updatedAt)
    }

    @Test fun saveExpenseWithSharesArgs() {
        val shares = f.snapshot.sharesOf(f.dinner.id)
        val dead = shares[2].copy(deletedAt = date(2026, 10, 2))
        val args = CloudRows.saveExpenseArgs(f.dinner, shares.take(2) + dead)
        assertEquals(setOf("p_expense", "p_shares"), args.keys)
        assertEquals(f.dinner.id, args["p_expense"]!!.jsonObject["id"]!!.jsonPrimitive.content)
        val list = args["p_shares"]!!.jsonArray
        assertEquals(2, list.size)
        assertEquals(JsonNull, list[0].jsonObject["person_id"]) // "Me" never has a person
        assertEquals(true, list[0].jsonObject["is_me"]!!.jsonPrimitive.content.toBoolean())
    }

    @Test fun syncMergeLastWriterWinsWithTombstones() {
        val local = f.snapshot
        val t0 = f.mcd.updatedAt
        val remoteNewer = CloudRows.toRow(f.mcd.copy(merchant = "McD Bangsar", updatedAt = t0 + 1000))
        val remoteTomb = CloudRows.toRow(f.grab.copy(deletedAt = f.grab.updatedAt + 5000, updatedAt = f.grab.updatedAt + 5000))
        val remoteOlder = CloudRows.toRow(f.uniqlo.copy(merchant = "Old name", updatedAt = f.uniqlo.updatedAt - 1000))
        val remoteSame = CloudRows.toRow(f.dinner.copy(merchant = "Same time"))
        val newPerson = TestKit.person("Remote Person")
        val localDeleted = f.oldLunch.copy(deletedAt = f.oldLunch.updatedAt + 9000, updatedAt = f.oldLunch.updatedAt + 9000)
        val remoteStaleEdit = CloudRows.toRow(f.oldLunch.copy(merchant = "Edited earlier", updatedAt = f.oldLunch.updatedAt + 1000))
        val localWithDeletion = local.copy(expenses = local.expenses.map { if (it.id == f.oldLunch.id) localDeleted else it })

        val r = SyncMerge.merge(localWithDeletion, CloudPull(
            expenses = listOf(remoteNewer, remoteTomb, remoteOlder, remoteSame, remoteStaleEdit),
            people = listOf(CloudRows.toRow(newPerson)),
        ))
        val byId = r.merged.expenses.associateBy { it.id }
        assertEquals("McD Bangsar", byId.getValue(f.mcd.id).merchant)
        assertEquals(f.grab.updatedAt + 5000, byId.getValue(f.grab.id).deletedAt)       // remote tombstone deletes locally
        assertEquals("Uniqlo", byId.getValue(f.uniqlo.id).merchant)                       // older remote ignored
        assertEquals("Dinner", byId.getValue(f.dinner.id).merchant)                       // tie keeps local
        assertEquals(localDeleted.deletedAt, byId.getValue(f.oldLunch.id).deletedAt)      // newer local tombstone survives
        assertEquals(setOf(f.mcd.id, f.grab.id), r.applied.expenses.map { it.id }.toSet())
        assertEquals(setOf(f.uniqlo.id, f.oldLunch.id), r.localNewer.expenses.map { it.id }.toSet())
        assertEquals(4, r.merged.people.size)
        assertEquals(5, r.merged.expenses.size)
    }

    @Test fun lwwGeneric() {
        val m = TestKit.movement(MoneyMovementKind.INCOME, 100, date(2026, 10, 1))
        val res = SyncMerge.lww(listOf(m), listOf(m.copy(id = m.id.uppercase(), amountMinor = 200, updatedAt = m.updatedAt + 1),
            m.copy(amountMinor = 300, updatedAt = m.updatedAt + 2)), { it.id }, { it.updatedAt })
        assertEquals(1, res.merged.size); assertEquals(300L, res.merged.single().amountMinor)
        assertTrue(FinanceSnapshot().expenses.isEmpty())
        assertEquals("2026-10-01T04:00:01.500Z",
            CloudPull(accounts = listOf(CloudRows.toRow(f.cimb).copy(serverUpdatedAt = "2026-10-01T04:00:01.500Z"),
                CloudRows.toRow(f.wise).copy(serverUpdatedAt = "2026-09-01T04:00:00Z"))).maxServerUpdatedAt)
    }
}
