package com.spendrop.core.bulk

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.time.LocalDate

/** Common/BusinessRules/bulk-import-vectors.json: identical results on iOS, Android and Web. */
class ScreenshotSplitterVectorsTest {
    @Test fun vectors() {
        val root = Json.parseToJsonElement(File(System.getProperty("spendrop.common"), "BusinessRules/bulk-import-vectors.json").readText()).jsonObject
        for (c in root["cases"]!!.jsonArray.map { it.jsonObject }) {
            val name = c["name"]!!.jsonPrimitive.content
            val lines = c["lines"]!!.jsonArray.map { it.jsonPrimitive.content }
            val result = ScreenshotSplitter.classify(lines, LocalDate.parse(c["importDate"]!!.jsonPrimitive.content))
            val expect = c["expect"]!!.jsonObject
            val items = expect["items"]!!.jsonArray.map { it.jsonObject }
            when (expect["kind"]!!.jsonPrimitive.content) {
                "single" -> assertEquals(name, ScreenshotSplitter.Result.Single, result)
                else -> {
                    val rows = (result as? ScreenshotSplitter.Result.Multiple)?.rows ?: error("$name: expected list, got $result")
                    assertEquals(name, items.size, rows.size)
                    items.zip(rows).forEach { (e, r) ->
                        assertEquals(name, e["merchant"]!!.jsonPrimitive.content, r.merchant)
                        assertEquals(name, e["amountMinor"]!!.jsonPrimitive.long, r.amountMinor)
                        assertEquals(name, e["direction"]!!.jsonPrimitive.content, r.direction)
                        assertEquals(name, e["date"]!!.jsonPrimitive.content, r.date.toString())
                        assertEquals(name, e["time"]!!.jsonPrimitive.content, r.time.toString())
                    }
                }
            }
        }
    }
}
