package com.spendrop.app.data

import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.data.db.SpenDropDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.io.File

/**
 * A phone with the version-1 database (before Fixed Amount Per Person) upgrades to version 2 without losing anything:
 * the database is built from the exported v1 schema (before Hybrid Split), filled, then opened by the current app (Room validates every
 * table after the migration and would fail on any mismatch).
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class DatabaseMigrationTest {
    @Test fun version1DatabaseUpgradesAndKeepsExistingSplits() {
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        val schema = Json.parseToJsonElement(File("schemas/com.spendrop.app.data.db.SpenDropDatabase/1.json").readText()).jsonObject["database"]!!.jsonObject
        val file = context.getDatabasePath("spendrop.db").apply { parentFile?.mkdirs(); delete() }
        SQLiteDatabase.openOrCreateDatabase(file, null).use { db ->
            for (entity in schema["entities"]!!.jsonArray) {
                val e = entity.jsonObject
                db.execSQL(e["createSql"]!!.jsonPrimitive.content.replace("\${TABLE_NAME}", e["tableName"]!!.jsonPrimitive.content))
                e["indices"]?.jsonArray?.forEach { i -> db.execSQL(i.jsonObject["createSql"]!!.jsonPrimitive.content.replace("\${TABLE_NAME}", e["tableName"]!!.jsonPrimitive.content)) }
            }
            schema["setupQueries"]!!.jsonArray.forEach { db.execSQL(it.jsonPrimitive.content) }
            db.execSQL("INSERT INTO expenses (id, amountMinor, currency, merchant, categoryRaw, fundingAccount, paymentChannelRaw, paymentSourceRaw, date, matchingStatusRaw, sourceTypeRaw, isSampleData, paidByMe, splitMethodRaw, createdAt, updatedAt) " +
                "VALUES ('e1', 20000, 'RM', 'Dinner', 'Food', 'Cash', 'CASH', 'Unknown', 0, 'unmatched', 'manual', 0, 1, 'equal', 0, 0)")
            db.execSQL("INSERT INTO expense_shares (id, expenseId, personId, isMe, nameSnapshot, amountMinor, parts, enteredMinor, sortIndex, createdAt, updatedAt, deletedAt) VALUES ('s0', 'e1', NULL, 1, 'Me', 10000, NULL, NULL, 0, 0, 0, NULL)")
            db.execSQL("INSERT INTO expense_shares (id, expenseId, personId, isMe, nameSnapshot, amountMinor, parts, enteredMinor, sortIndex, createdAt, updatedAt, deletedAt) VALUES ('s1', 'e1', NULL, 0, 'Vijay', 10000, NULL, NULL, 1, 0, 0, NULL)")
            db.version = 1
        }

        val room = SpenDropDatabase.create(context)
        try {
            val shares = runBlocking { room.finance().observeShares().first() }
            assertEquals(listOf(10000L, 10000L), shares.sortedBy { it.sortIndex }.map { it.amountMinor })
            val expense = runBlocking { room.finance().observeExpenses().first() }.single()
            assertEquals("equal", expense.splitMethodRaw)
            assertNull(expense.splitRule) // new column, empty for existing expenses
            assertEquals(2, room.openHelper.readableDatabase.version)
        } finally {
            room.close()
        }
    }
}
