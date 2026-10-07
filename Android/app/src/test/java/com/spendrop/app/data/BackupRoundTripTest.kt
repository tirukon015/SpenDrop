package com.spendrop.app.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.testContainer
import com.spendrop.core.backup.BackupCodec
import com.spendrop.core.backup.BackupRestore
import com.spendrop.core.backup.LocalRecordIds
import com.spendrop.core.backup.RestoreRange
import com.spendrop.core.insights.CalendarContext
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.sample.SampleData
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.time.ZoneId

/** Device A exports (iOS-format JSON), device B restores: same records, same money, splits and settlements. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class BackupRoundTripTest {
    @Test fun exportThenRestoreOnAnotherDevice() = runBlocking {
        val a = testContainer()
        val set = SampleData.load(FinanceSnapshot(), System.currentTimeMillis(), CalendarContext.device())!!
        a.repository.apply(Changes(people = set.people, paymentMethods = set.paymentMethods, accounts = set.accounts, expenses = set.expenses,
            shares = set.shares, movements = set.movements, allocations = set.allocations, sampleRecords = set.sampleRecords))
        val src = a.repository.snapshot.filterNotNull().first { it.expenses.isNotEmpty() }
        val json = BackupCodec.encode(a.cloudBackup.makePayload())

        val b = testContainer()
        val payload = BackupCodec.decode(json)
        val plan = BackupRestore.makeRestorePlan(payload, RestoreRange.Everything, ZoneId.systemDefault(), LocalRecordIds())
        b.repository.applyMerge(BackupRestore.applyRestorePlan(plan, FinanceSnapshot(), System.currentTimeMillis()).merge)
        val dst = b.repository.snapshot.filterNotNull().first { it.expenses.size == src.expenses.size }

        assertEquals(src.expenses.map { it.id to it.amountMinor }.toSet(), dst.expenses.map { it.id to it.amountMinor }.toSet())
        assertEquals(src.shares.map { it.id to it.amountMinor }.toSet(), dst.shares.map { it.id to it.amountMinor }.toSet())
        assertEquals(src.movements.size, dst.movements.size)
        assertEquals(src.allocations.size, dst.allocations.size)
        assertEquals(src.people.map { it.id }.toSet(), dst.people.map { it.id }.toSet())
        assertEquals(src.expenses.map { it.paymentChannelRaw to it.effectiveFundingAccount }.toSet(), dst.expenses.map { it.paymentChannelRaw to it.effectiveFundingAccount }.toSet())
    }
}
