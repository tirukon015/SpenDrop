package com.spendrop.core.split

import com.spendrop.core.Money
import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Shared cross-platform vectors in Common/BusinessRules (every platform must reproduce them exactly). */
class CommonVectorsTest {
    private fun common(file: String): JsonObject {
        val root = System.getProperty("spendrop.common") ?: error("spendrop.common system property not set")
        return Json.parseToJsonElement(File(root, "BusinessRules/$file").readText()).jsonObject
    }

    @Test fun moneyVectors() {
        val v = common("money-test-vectors.json")
        val parse = v["parse"]!!.jsonArray
        assertTrue(parse.isNotEmpty())
        for (case in parse) {
            val (text, minor) = case.jsonArray
            val expected = if (minor is JsonNull) null else minor.jsonPrimitive.long
            assertEquals("parse \"${text.jsonPrimitive.content}\"", expected, Money.parseMinor(text.jsonPrimitive.content))
        }
        for (case in v["format"]!!.jsonArray) {
            val (minor, text) = case.jsonArray
            assertEquals(text.jsonPrimitive.content, Money.format(minor.jsonPrimitive.long))
        }
    }

    @Test fun splitVectors() {
        val cases = common("split-test-vectors.json")["cases"]!!.jsonArray
        assertTrue(cases.size >= 15)
        for (element in cases) {
            val c = element.jsonObject
            val name = c["name"]!!.jsonPrimitive.content
            val total = c["total"]!!.jsonPrimitive.long
            var d = SplitDraft()
            c["people"]!!.jsonArray.forEachIndexed { i, n ->
                d = d.add(Person(id = "person-$i", name = n.jsonPrimitive.content, createdAt = 0, updatedAt = 0))
            }
            c["purpose"]?.jsonPrimitive?.content?.let {
                d = d.setPurpose(if (it == "paidFor") SplitDraft.Purpose.PAID_FOR else SplitDraft.Purpose.SHARED)
            }
            d = when (SplitMethod.fromRaw(c["method"]!!.jsonPrimitive.content)!!) {
                SplitMethod.AMOUNTS -> d.useCustomAmounts(total)
                SplitMethod.EQUAL -> d.useEqualSplit()
                SplitMethod.PARTS -> d.useParts()
            }
            fun idOf(who: String) = d.participants.first { if (who == "Me") it.isMe else it.name == who }.id
            for (opEl in (c["ops"] as? JsonArray).orEmpty()) {
                val op = opEl.jsonObject
                val who = op["who"]?.jsonPrimitive?.content
                d = when (op["op"]!!.jsonPrimitive.content) {
                    "type" -> d.setAmountText(op["text"]!!.jsonPrimitive.content, idOf(who!!), total)
                    "fixed" -> d.setFixed(op["minor"]!!.jsonPrimitive.long, idOf(who!!), total)!!
                    "parts" -> d.setParts(op["value"]!!.jsonPrimitive.int, idOf(who!!))
                    "autoCalculate" -> d.setAutoCalculate(op["value"]!!.jsonPrimitive.boolean, total)
                    else -> error("unknown op in $name")
                }
            }
            val expect = c["expect"]!!.jsonObject
            expect["shares"]?.let { s ->
                val expected = s.jsonArray.map { it.jsonPrimitive.long }
                assertEquals(name, expected, d.shares(total))
                assertEquals(name, total, expected.sum())
                assertNull(name, d.problem(total))
            }
            expect["problem"]?.let { assertEquals(name, it.jsonPrimitive.content, d.problem(total)) }
            expect["remaining"]?.let { assertEquals(name, it.jsonPrimitive.long, d.remainingMinor(total)) }
        }
    }
}
