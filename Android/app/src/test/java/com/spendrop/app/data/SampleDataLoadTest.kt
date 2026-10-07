package com.spendrop.app.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.testContainer
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.sample.SampleData
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class SampleDataLoadTest {
    @Test fun loadsIntoDatabase() = runBlocking {
        val c = testContainer()
        val set = SampleData.load(FinanceSnapshot(), System.currentTimeMillis(), CalendarContext.device())
        assertNotNull(set)
        set!!
        c.repository.apply(Changes(people = set.people, paymentMethods = set.paymentMethods, accounts = set.accounts, expenses = set.expenses,
            shares = set.shares, movements = set.movements, allocations = set.allocations, sampleRecords = set.sampleRecords))
        val s = c.repository.snapshot.filterNotNull().first { it.expenses.isNotEmpty() }
        assertTrue(SampleData.isLoaded(s))
    }
}
