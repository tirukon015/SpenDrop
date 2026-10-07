package com.spendrop.app.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.testContainer
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.Person
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class FinanceRepositoryTest {
    private val t = 1_790_000_000_000L

    @Test fun saveExpenseReplacesSplitAndDeleteIsATombstone() = runBlocking {
        val c = testContainer()
        val repo = c.repository
        val p = Person("p1", "Vijay", createdAt = t, updatedAt = t)
        repo.apply(Changes(people = listOf(p)))
        val e = Expense("e1", 10000, merchant = "Dinner", date = t, createdAt = t, updatedAt = t, splitMethodRaw = "equal")
        repo.saveExpense(e, listOf(
            ExpenseShare("s1", "e1", isMe = true, nameSnapshot = "Me", amountMinor = 5000),
            ExpenseShare("s2", "e1", personId = "p1", nameSnapshot = "Vijay", amountMinor = 5000, sortIndex = 1),
        ))
        var snap = repo.snapshot.filterNotNull().first { it.expenses.isNotEmpty() && it.shares.size == 2 }
        assertEquals(2, snap.sharesOf("e1").size)

        // New split: s2 replaced by s3 -> s2 tombstoned, never shown
        repo.saveExpense(e.copy(updatedAt = t + 1), listOf(
            ExpenseShare("s1", "e1", isMe = true, nameSnapshot = "Me", amountMinor = 4000),
            ExpenseShare("s3", "e1", personId = "p1", nameSnapshot = "Vijay", amountMinor = 6000, sortIndex = 1),
        ))
        snap = repo.snapshot.filterNotNull().first { s -> s.shares.any { it.id == "s3" } }
        assertEquals(listOf("s1", "s3"), snap.sharesOf("e1").map { it.id })
        assertTrue(repo.fullSnapshot(true).shares.first { it.id == "s2" }.deletedAt != null)

        // Shares that don't add up are refused
        val refused = runCatching { repo.saveExpense(e, listOf(ExpenseShare("x", "e1", isMe = true, nameSnapshot = "Me", amountMinor = 1))) }
        assertTrue(refused.isFailure)

        repo.deleteExpense(e, t + 2)
        snap = repo.snapshot.filterNotNull().first { s -> s.expenses.isEmpty() && s.shares.none { it.expenseId == "e1" } }
        assertTrue(snap.shares.none { it.expenseId == "e1" })
        assertEquals(1, repo.fullSnapshot(true).expenses.size) // kept as tombstone for backups/sync
    }
}
