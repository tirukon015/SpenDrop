package com.spendrop.core.split

import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.ExpenseDto
import com.spendrop.core.cloud.CloudRows
import com.spendrop.core.cloud.ExpenseRow
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.Person
import com.spendrop.core.model.SplitMethod
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Hybrid Split (Common/BusinessRules/split-hybrid.md): group fixed + individual fixed + remaining. */
class HybridSplitTest {
    private fun person(name: String) = Person(id = "p-$name", name = name, createdAt = 0, updatedAt = 0)

    private fun draft(vararg names: String, payer: String? = null): SplitDraft {
        var d = SplitDraft()
        names.forEach { d = d.add(person(it)) }
        if (payer != null) d = d.setPayer(person(payer))
        return d.setHybridEnabled(true)
    }

    private fun SplitDraft.id(name: String) = participants.first { if (name == "Me") it.isMe else it.name == name }.id

    /** Replaces the starter group / rows with these layers. */
    private fun SplitDraft.layers(groups: List<Pair<String, List<String>>>, individuals: List<Pair<String?, String>>, remaining: List<String>): SplitDraft {
        var d = this
        d.hybrid!!.groups.forEach { d = d.removeGroup(it.id) }
        for ((amount, members) in groups) {
            d = d.addGroup()
            val g = d.hybrid!!.groups.last().id
            d = d.setGroupAmountText(g, amount)
            members.forEach { m -> d = d.setGroupMember(g, d.id(m), true) }
        }
        for ((who, amount) in individuals) {
            d = d.addIndividual(who?.let { d.id(it) })
            d = d.setIndividualAmountText(d.hybrid!!.individuals.last().id, amount)
        }
        d.participants.forEach { p -> d = d.setInRemainder(p.id, (if (p.isMe) "Me" else p.name) in remaining) }
        return d
    }

    private fun amountText(e: kotlinx.serialization.json.JsonElement?) = if (e == null || e is JsonNull) "" else SplitDraft.text(e.jsonPrimitive.long)

    @Test fun sharedVectors() {
        val root = System.getProperty("spendrop.common") ?: error("spendrop.common not set")
        val cases = Json.parseToJsonElement(File(root, "BusinessRules/split-hybrid-vectors.json").readText()).jsonObject["cases"]!!.jsonArray
        assertEquals(29, cases.size)
        for (e in cases) {
            val c = e.jsonObject
            val name = c["name"]!!.jsonPrimitive.content
            val total = c["total"]!!.jsonPrimitive.long
            val d = draft(*c["people"]!!.jsonArray.map { it.jsonPrimitive.content }.toTypedArray(), payer = c["payer"]?.jsonPrimitive?.content).layers(
                c["groups"]!!.jsonArray.map { g -> amountText(g.jsonObject["amount"]) to g.jsonObject["members"]!!.jsonArray.map { it.jsonPrimitive.content } },
                c["individuals"]!!.jsonArray.map { i -> i.jsonObject["person"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.content } to amountText(i.jsonObject["amount"]) },
                c["remaining"]!!.jsonArray.map { it.jsonPrimitive.content },
            )
            val expect = c["expect"]!!.jsonObject
            expect["problem"]?.let {
                assertEquals(name, it.jsonPrimitive.content, d.problem(total))
                assertNull(name, d.shares(total))
                assertNull(name, d.apply(Expense(id = "e", amountMinor = total, date = 0, createdAt = 0, updatedAt = 0), emptyList(), 1))
            }
            expect["shares"]?.let { s ->
                assertNull(name, d.problem(total))
                assertEquals(name, s.jsonArray.map { it.jsonPrimitive.long }, d.shares(total))
                assertEquals(name, expect["groupAllocation"]!!.jsonPrimitive.long, d.groupAllocationMinor)
                assertEquals(name, expect["individualAllocation"]!!.jsonPrimitive.long, d.individualAllocationMinor)
                assertEquals(name, expect["remaining"]!!.jsonPrimitive.long, d.hybridRemainingMinor(total))
                assertEquals(name, total, d.assignedMinor(total))
                assertEquals(name, 0L, d.remainingMinor(total))
            }
        }
    }

    private val example get() = draft("Riad", "Bijoy").layers(listOf("100" to listOf("Riad", "Bijoy")), listOf("Bijoy" to "20"), listOf("Me", "Riad", "Bijoy"))

    @Test fun personInAllThreeLayersHasEachPart() {
        val d = example
        val lines = d.hybridLines(20000).valueOrNull()!!.associateBy { it.participantId }
        val bijoy = lines[d.id("Bijoy")]!!
        assertEquals(5000L, bijoy.groupMinor); assertEquals(2000L, bijoy.individualMinor); assertEquals(2666L, bijoy.remainingMinor)
        assertEquals(9666L, bijoy.totalMinor)
        val riad = lines[d.id("Riad")]!!
        assertEquals(listOf(5000L, 0L, 2667L), listOf(riad.groupMinor, riad.individualMinor, riad.remainingMinor))
        assertEquals(3, lines.size) // one row per person
        assertEquals(mapOf(d.id("Riad") to 5000L, d.id("Bijoy") to 5000L), d.groupPreview(d.hybrid!!.groups[0].id))
    }

    @Test fun liveRecalculationOnEveryChange() {
        var d = example
        assertEquals(listOf(2667L, 7667L, 9666L), d.shares(20000))
        d = d.setGroupAmountText(d.hybrid!!.groups[0].id, "120")                // group amount
        assertEquals(listOf(2000L, 8000L, 10000L), d.shares(20000))
        d = d.setIndividualAmountText(d.hybrid!!.individuals[0].id, "35")      // individual amount
        assertEquals(listOf(1500L, 7500L, 11000L), d.shares(20000))
        d = d.setIndividualPerson(d.hybrid!!.individuals[0].id, d.id("Riad"))  // individual person
        assertEquals(listOf(1500L, 11000L, 7500L), d.shares(20000))
        d = d.setGroupMember(d.hybrid!!.groups[0].id, d.id("Me"), true)         // group members
        assertEquals(listOf(5500L, 9000L, 5500L), d.shares(20000))
        d = d.setInRemainder(d.id("Riad"), false)                               // remaining members
        assertEquals(listOf(6250L, 7500L, 6250L), d.shares(20000))
        assertEquals(listOf(4250L, 7500L, 4250L), d.shares(16000))              // total
        d = d.addGroup()
        val g2 = d.hybrid!!.groups.last().id
        assertEquals(listOf(4250L, 7500L, 4250L), d.shares(16000))              // blank group ignored
        d = d.setGroupAmountText(g2, "3")
        assertEquals("Choose who shares group fixed amount 2.", d.problem(16000))
        d = d.setGroupMember(g2, d.id("Bijoy"), true)
        assertEquals(listOf(4100L, 7500L, 4400L), d.shares(16000))
        d = d.removeGroup(g2)
        assertEquals(listOf(4250L, 7500L, 4250L), d.shares(16000))
    }

    @Test fun addingAndRemovingPeople() {
        var d = example.add(person("Labib"))
        assertTrue(d.id("Labib") in d.hybrid!!.remainderIds)
        assertTrue(d.hybrid!!.groups.none { d.id("Labib") in it.memberIds })
        assertEquals(listOf(2000L, 7000L, 9000L, 2000L), d.shares(20000))
        // Removing Bijoy drops him from the group, his individual row and the remaining group
        d = d.remove(d.id("Bijoy"))
        assertTrue(d.hybrid!!.individuals.isEmpty())
        assertEquals(listOf(3334L, 13333L, 3333L), d.shares(20000))
    }

    @Test fun turningOnAndOff() {
        var d = SplitDraft().add(person("A")).add(person("B")).useParts()
        val before = d.shares(10000)
        d = d.setHybridEnabled(true)
        assertEquals(1, d.hybrid!!.groups.size); assertTrue(d.hybrid!!.groups[0].isBlank)
        assertTrue(d.hybrid!!.individuals.isEmpty())
        assertEquals(d.participants.map { it.id }.toSet(), d.hybrid!!.remainderIds)
        assertEquals("Add a group fixed amount or an individual fixed amount.", d.problem(10000))
        d = d.setHybridEnabled(false)
        assertEquals(SplitMethod.PARTS, d.method); assertEquals(before, d.shares(10000))
    }

    @Test fun existingSplitsBehaveExactlyAsBefore() {
        val d = SplitDraft().add(person("A")).add(person("B"))
        assertFalse(d.isHybrid)
        assertEquals(listOf(3334L, 3333L, 3333L), d.shares(10000))
        val custom = d.useCustomAmounts(20000).setFixed(5000, d.participants[1].id, 20000)!!
        assertEquals(listOf(5000L, 10000L, 5000L), custom.shares(20000))
        val save = d.apply(expense.copy(splitRule = "{\"type\":\"hybrid\"}"), emptyList(), 1)!!
        assertNull("a normal split clears an old rule", save.expense.splitRule)
    }

    @Test fun paidForSomeoneTurnsItOff() {
        val d = example.setPurpose(SplitDraft.Purpose.PAID_FOR)
        assertNull(d.hybrid)
        assertEquals(d, d.setHybridEnabled(true))
    }

    private val expense = Expense(id = "e1", amountMinor = 20000, date = 0, createdAt = 0, updatedAt = 0)
    private val people = listOf(person("Riad"), person("Bijoy"))

    @Test fun saveAndReloadRestoresEveryLayer() {
        val d = example.addGroup().let { it.setGroupAmountText(it.hybrid!!.groups.last().id, "") } // a blank group is not saved
        val save = d.apply(expense, emptyList(), 1)!!
        assertEquals(SplitMethod.AMOUNTS.raw, save.expense.splitMethodRaw)
        assertEquals(listOf(2667L, 7667L, 9666L), save.newShares.map { it.amountMinor })
        assertEquals(save.newShares.map { it.amountMinor }, save.newShares.map { it.enteredMinor })
        assertEquals(listOf(0, 1, 2), save.newShares.map { it.sortIndex })
        assertEquals(
            """{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}""",
            save.expense.splitRule,
        )
        val back = SplitDraft.fromExpense(save.expense, save.newShares, people)!!
        assertTrue(back.isHybrid)
        assertEquals("100.00", back.hybrid!!.groups.single().amountText)
        assertEquals(setOf("Riad", "Bijoy"), back.participants.filter { it.id in back.hybrid!!.groups.single().memberIds }.map { it.name }.toSet())
        assertEquals("Bijoy", back.participants.first { it.id == back.hybrid!!.individuals.single().participantId }.name)
        assertEquals(save.newShares.map { it.amountMinor }, back.shares(20000))
        // Edit after reload, save again: the same rule round-trips
        val again = back.apply(save.expense, save.newShares, 2)!!
        assertEquals(save.expense.splitRule, again.expense.splitRule)
    }

    @Test fun unreadableRuleOpensAsPlainAmounts() {
        val save = example.apply(expense, emptyList(), 1)!!
        for (bad in listOf("not json", """{"type":"other"}""", save.expense.splitRule!!.replace("[1,2]", "[1,7]"))) {
            val d = SplitDraft.fromExpense(save.expense.copy(splitRule = bad), save.newShares, people)!!
            assertFalse(bad, d.isHybrid)
            assertEquals(SplitMethod.AMOUNTS, d.method)
            assertEquals(save.newShares.map { it.amountMinor }, d.shares(20000))
        }
    }

    @Test fun oldExpensesLoadExactlyAsBefore() {
        val shares = listOf(
            ExpenseShare(id = "s0", expenseId = "e1", isMe = true, nameSnapshot = "Me", amountMinor = 10000, sortIndex = 0),
            ExpenseShare(id = "s1", expenseId = "e1", personId = "p-A", nameSnapshot = "A", amountMinor = 10000, sortIndex = 1),
        )
        val d = SplitDraft.fromExpense(expense.copy(splitMethodRaw = "equal"), shares, listOf(person("A")))!!
        assertNull(d.hybrid); assertEquals(SplitMethod.EQUAL, d.method); assertEquals(listOf(10000L, 10000L), d.shares(20000))
    }

    @Test fun amountChangeRecalculatesOrIsReported() {
        val save = example.apply(expense, emptyList(), 1)!!
        val r = SplitDraft.recalculateAfterAmountChange(save.expense.copy(amountMinor = 15000), save.newShares, people, 2)
        assertTrue(r.sharesMatch)
        assertEquals(listOf(1000L, 6000L, 8000L), r.save!!.newShares.map { it.amountMinor })
        val bad = SplitDraft.recalculateAfterAmountChange(save.expense.copy(amountMinor = 11000), save.newShares, people, 3)
        assertFalse(bad.sharesMatch); assertNull(bad.save)
    }

    @Test fun removingTheSplitClearsTheRule() {
        val save = example.apply(expense, emptyList(), 1)!!
        assertNull(SplitDraft.removeSplit(save.expense, save.newShares, 2).expense.splitRule)
    }

    @Test fun backupKeyIsOptional() {
        val rule = example.apply(expense, emptyList(), 1)!!.expense.splitRule!!
        val dto = BackupCodec.json.encodeToJsonElement(ExpenseDto.serializer(), BackupCodec.expenseDto(expense.copy(id = "00000000-0000-0000-0000-000000000001", splitRule = rule), emptyList())).jsonObject
        assertEquals(rule, dto["splitRule"]!!.jsonPrimitive.content)
        val plain = BackupCodec.json.encodeToJsonElement(ExpenseDto.serializer(), BackupCodec.expenseDto(expense.copy(id = "00000000-0000-0000-0000-000000000001"), emptyList())).jsonObject
        assertFalse("splitRule" in plain)
        assertNull(BackupCodec.json.decodeFromJsonElement(ExpenseDto.serializer(), JsonObject(plain)).splitRule)
    }

    @Test fun cloudPullBeforeTheMigrationKeepsTheLocalRule() {
        val local = expense.copy(id = "00000000-0000-0000-0000-0000000000e1", splitRule = "{\"type\":\"hybrid\"}")
        val pushed = CloudRows.json.encodeToJsonElement(ExpenseRow.serializer(), CloudRows.toRow(local)).jsonObject
        assertEquals("{\"type\":\"hybrid\"}", pushed["split_rule"]!!.jsonPrimitive.content)
        // Server without the column: the key is missing → keep what this device has
        val withoutColumn = JsonObject(pushed - "split_rule")
        val row = CloudRows.json.decodeFromJsonElement(ExpenseRow.serializer(), withoutColumn)
        assertEquals(local.splitRule, CloudRows.fromRow(row, local).splitRule)
        // Server with the column set to null (rule removed elsewhere) → cleared
        val cleared = CloudRows.json.decodeFromJsonElement(ExpenseRow.serializer(), JsonObject(pushed + ("split_rule" to JsonNull)))
        assertNull(CloudRows.fromRow(cleared, local).splitRule)
    }
}
