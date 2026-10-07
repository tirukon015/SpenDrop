package com.spendrop.core.ledger

import com.spendrop.core.Money
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.model.Person
import com.spendrop.core.split.SplitDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS AccountFeatureTests "Money In / Money Out / Transfer drafts", HardeningTests and Phase7Tests draft cases. */
class MoneyMovementDraftTest {
    private val now = 1_800_000_000_000L
    private val shadin = Person(id = "p-shadin", name = "Shadin", createdAt = 0, updatedAt = 0)

    @Test fun validationAmountAndPerson() {
        var d = MoneyMovementDraft.new(TransactionEntryType.MONEY_IN, now)
        val defaultKind = d.kind
        val empty = d.issues
        d = d.copy(amountText = "0")
        val zero = d.issues
        d = d.copy(amountText = "12.50")
        val valid = d.isValid && d.amountMinor == 1250L
        d = d.setEntryType(TransactionEntryType.MONEY_OUT)
        assertEquals(MoneyMovementKind.INCOME, defaultKind)
        assertEquals(listOf(MoneyMovementDraft.Issue.INVALID_AMOUNT), empty)
        assertEquals(listOf(MoneyMovementDraft.Issue.INVALID_AMOUNT), zero)
        assertTrue(valid)
        assertEquals(MoneyMovementKind.LOAN_GIVEN, d.kind)
        assertEquals(listOf(MoneyMovementDraft.Issue.MISSING_PERSON), d.issues)
        assertEquals("Choose who this money is with.", d.issues[0].message)
        assertEquals("Enter an amount above RM0.00.", MoneyMovementDraft.Issue.INVALID_AMOUNT.message)
    }

    @Test fun transferNeedsTwoDifferentAccounts() {
        var t = MoneyMovementDraft.new(TransactionEntryType.TRANSFER, now).copy(amountText = "200")
        val missing = t.issues
        t = t.copy(accountId = "maybank", counterAccountId = "maybank")
        val same = t.issues
        t = t.copy(counterAccountId = "tng")
        assertEquals(MoneyMovementKind.OWN_TRANSFER, t.kind)
        assertEquals(listOf(MoneyMovementDraft.Issue.MISSING_FROM_ACCOUNT, MoneyMovementDraft.Issue.MISSING_TO_ACCOUNT), missing)
        assertEquals(listOf(MoneyMovementDraft.Issue.SAME_ACCOUNT), same)
        assertEquals("From and To must be different accounts.", same[0].message)
        assertTrue(t.isValid)
        // leaving Transfer clears the destination
        assertNull(t.setEntryType(TransactionEntryType.MONEY_IN).counterAccountId)
    }

    @Test fun saveLoanIncomeTransferInvalidRejected() {
        val loan = MoneyMovementDraft.new(TransactionEntryType.MONEY_OUT, now)
            .copy(amountText = "150", person = shadin, accountId = "maybank", note = "  for rent  ").newMovement(now)!!
        val income = MoneyMovementDraft.new(TransactionEntryType.MONEY_IN, now)
            .copy(amountText = "3000", person = shadin).newMovement(now)!!
        val transfer = MoneyMovementDraft.new(TransactionEntryType.TRANSFER, now)
            .copy(amountText = "200", accountId = "maybank", counterAccountId = "tng").newMovement(now)!!
        val rejected = MoneyMovementDraft.new(TransactionEntryType.MONEY_OUT, now).copy(amountText = "5").newMovement(now)
        assertEquals(MoneyMovementKind.LOAN_GIVEN, loan.kind)
        assertEquals(MoneyDirection.OUT, loan.direction)
        assertEquals(15000L, loan.amountMinor)
        assertEquals(shadin.id, loan.personId)
        assertEquals("Shadin", loan.personNameSnapshot)
        assertEquals("maybank", loan.accountId)
        assertEquals("for rent", loan.note)
        assertEquals(ExpenseSourceType.MANUAL.raw, loan.sourceTypeRaw)
        assertNull(income.personId) // not needed for income: must not be stored
        assertEquals(MoneyDirection.IN, income.direction)
        assertEquals("tng", transfer.counterAccountId)
        assertEquals(MoneyDirection.INTERNAL, transfer.direction)
        assertNull(rejected)

        // Edit an existing record in place
        var edit = MoneyMovementDraft.fromMovement(loan, shadin)
        val loaded = edit.amountText
        edit = edit.copy(amountText = "100", kind = MoneyMovementKind.REPAYMENT_MADE)
        val updated = edit.applyTo(loan, now + 1)!!
        assertEquals("150.00", loaded)
        assertEquals(loan.id, updated.id)
        assertEquals(10000L, updated.amountMinor)
        assertEquals(MoneyMovementKind.REPAYMENT_MADE, updated.kind)
        assertEquals("out", updated.directionRaw)
        assertEquals(now + 1, updated.updatedAt)
    }

    @Test fun invalidInputNeverProducesRecords() {
        assertEquals(listOf(-500L, null, 0L, 101L, 1235L), listOf("-5", "abc", "0", "1.005", "12.345").map { Money.parseMinor(it) })
        assertNull(MoneyMovementDraft.new(TransactionEntryType.MONEY_IN, now).copy(amountText = "-5").newMovement(now))
        val split = SplitDraft().add(Person(id = "x", name = "X", createdAt = 0, updatedAt = 0))
        assertNotNull(split.problem(0))
        val same = MoneyMovementDraft.new(TransactionEntryType.TRANSFER, now).copy(amountText = "1", accountId = "tng", counterAccountId = "tng")
        assertEquals(listOf(MoneyMovementDraft.Issue.SAME_ACCOUNT), same.issues)
    }

    @Test fun fromParsedResolvesAccountsAndKeepsProvenance() {
        val accounts = linkedMapOf("maybank" to "acc-maybank")
        val created = ArrayList<String>()
        val resolve: (String) -> String? = { raw ->
            val key = raw.trim().lowercase()
            if (key.isEmpty() || key == "unknown") null
            else accounts.getOrPut(key) { created += raw.trim(); "acc-$key" }
        }
        val date = 1_790_000_000_000L
        val incoming = MoneyMovementDraft.fromParsed(5000, date, "maybank", "BIJOY", "MBB1", PaymentChannel.BANK_TRANSFER, null,
            MoneyMovementKind.OTHER_IN, ExpenseSourceType.SCREENSHOT, resolve)
        val topUp = MoneyMovementDraft.fromParsed(20000, date, "Maybank", "Reload", null, PaymentChannel.UNKNOWN, PaymentSource.TOUCH_N_GO,
            MoneyMovementKind.OWN_TRANSFER, ExpenseSourceType.SCREENSHOT, resolve)
        val unknown = MoneyMovementDraft.fromParsed(500, date, "Unknown", "Unknown", null, PaymentChannel.UNKNOWN, null,
            MoneyMovementKind.OTHER_IN, ExpenseSourceType.SCREENSHOT, resolve)
        val saved = incoming.newMovement(now)!!
        assertEquals("acc-maybank", incoming.accountId)
        assertEquals("BIJOY", incoming.note)
        assertEquals("50.00", incoming.amountText)
        assertEquals(TransactionEntryType.MONEY_IN, incoming.entryType)
        assertEquals("acc-touch 'n go", topUp.counterAccountId)
        assertEquals(TransactionEntryType.TRANSFER, topUp.entryType)
        assertNull(unknown.accountId)
        assertEquals("", unknown.note)
        assertEquals(ExpenseSourceType.SCREENSHOT.raw, saved.sourceTypeRaw)
        assertEquals("MBB1", saved.transactionReference)
        assertEquals(PaymentChannel.BANK_TRANSFER, saved.paymentChannel)
        assertEquals(listOf("Touch 'n Go"), created) // Maybank reused, not duplicated
        // a wallet that is also the source is not used as the destination
        val selfTopUp = MoneyMovementDraft.fromParsed(100, date, "Touch 'n Go", "Reload", null, PaymentChannel.UNKNOWN, PaymentSource.TOUCH_N_GO,
            MoneyMovementKind.OWN_TRANSFER, ExpenseSourceType.SCREENSHOT, resolve)
        assertNull(selfTopUp.counterAccountId)
    }
}
