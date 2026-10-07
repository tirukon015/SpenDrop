package com.spendrop.core.backup

import com.spendrop.core.backup.TestKit.MYT
import com.spendrop.core.backup.TestKit.date
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PersonPaymentMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupMergeTest {
    private val now = date(2026, 10, 7)

    private fun dto(id: String, amount: Double, merchant: String, date: Long, ref: String? = null, updatedAt: Long? = null,
                    category: String = "Food", source: String = "Cash") = ExpenseDto(
        id = id, amount = amount, currency = "RM", merchant = merchant, categoryRaw = category, paymentSourceRaw = source,
        date = date, transactionReference = ref, sourceTypeRaw = "screenshot", isSampleData = false, createdAt = date, updatedAt = updatedAt,
    )

    private fun payload(expenses: List<ExpenseDto> = emptyList(), profiles: List<PayBookProfileDto> = emptyList(), version: Int = 1) =
        BackupPayload(version = version, accountName = "A", exportDate = now, expenses = expenses, paybookProfiles = profiles)

    /** DataSafetyTests 12: same id updates; a new id is imported even if it looks like a duplicate (flagged). */
    @Test fun importMatchesByIdAndNeverSkipsNewRecords() {
        val day = date(2026, 10, 6, 13)
        val existing = TestKit.expense("Mamak", 10.0, day, ref = "REF-1", updatedAt = day - 3_600_000)
        val changed = dto(existing.id, 12.0, "Mamak", day, ref = "REF-1")
        val lookalike = dto(TestKit.id(), 10.0, "Mamak", day, ref = "REF-1")
        val r = BackupMerge.apply(payload(listOf(changed, lookalike)), FinanceSnapshot(expenses = listOf(existing)), now, MYT)
        assertEquals(1, r.summary.expensesUpdated); assertEquals(1, r.summary.expensesAdded)
        assertEquals(1, r.summary.possibleDuplicateExpenses); assertEquals(2, r.merged.expenses.size)
        assertEquals(1200L, r.merged.expenses.first { it.id == existing.id }.amountMinor)
    }

    @Test fun signatureDuplicateWithoutReferenceIsFlagged() {
        val day = date(2026, 10, 6, 9)
        val existing = TestKit.expense("Kopi", 4.5, day)
        val r = BackupMerge.apply(payload(listOf(dto(TestKit.id(), 4.5, "KOPI", date(2026, 9, 6, 22)))), FinanceSnapshot(expenses = listOf(existing)), now, MYT)
        assertEquals(1, r.summary.possibleDuplicateExpenses) // same merchant (case-insensitive), amount and day of month
        assertEquals("kopi_4.5_6", BackupMerge.signature("Kopi", 4.5, day, MYT))
    }

    /** DataSafetyTests 13: a newer record on the device is not overwritten by an older backup. */
    @Test fun newerDeviceRecordIsKept() {
        val local = TestKit.expense("Grab", 20.0, date(2026, 10, 1), updatedAt = now)
        val old = dto(local.id, 15.0, "Grab", local.date, updatedAt = now - 86_400_000)
        val r = BackupMerge.apply(payload(listOf(old)), FinanceSnapshot(expenses = listOf(local)), now, MYT)
        assertEquals(1, r.summary.expensesKeptNewer)
        assertEquals(2000L, r.merged.expenses.single().amountMinor)
        assertTrue(r.changes.expenses.isEmpty())
    }

    /** DataSafetyTests 14: people are matched by id, never merged by name; methods updated, not duplicated. */
    @Test fun peopleMatchedByIdNeverByName() {
        val bijoy = TestKit.person("Bijoy", created = now - 3_600_000)
        val method = PersonPaymentMethod(id = TestKit.id(), personId = bijoy.id, provider = "Maybank", accountIdentifier = "111", label = "Old",
            createdAt = now - 3_600_000, updatedAt = now - 3_600_000)
        val otherBijoy = PayBookProfileDto(id = TestKit.id(), name = "Bijoy", paymentMethods = emptyList())
        val sameBijoy = PayBookProfileDto(id = bijoy.id, name = "Bijoy K", paymentMethods = listOf(
            PayBookMethodDto(id = method.id, paymentTypeRaw = "Bank Account", provider = "Maybank", accountIdentifier = "111", label = "Main")))
        val r = BackupMerge.apply(payload(profiles = listOf(otherBijoy, sameBijoy)),
            FinanceSnapshot(people = listOf(bijoy), paymentMethods = listOf(method)), now, MYT)
        assertEquals(2, r.merged.people.size)
        assertEquals(1, r.summary.profilesAdded); assertEquals(1, r.summary.profilesUpdated); assertEquals(1, r.summary.profilesSharingName)
        assertEquals("Bijoy K", r.merged.people.first { it.id == bijoy.id }.name)
        assertEquals(1, r.merged.paymentMethods.size)
        assertEquals("Main", r.merged.paymentMethods.single().label)
    }

    /** FinancialModelTests "Backup V2": round trip restores every relationship; re-import adds nothing; v1 never clears v2 data. */
    @Test fun version2RelationshipsIdempotenceAndV1Safety() {
        val maybank = TestKit.account("Maybank"); val tng = TestKit.account("Touch 'n Go", "eWallet")
        val bijoy = TestKit.person("Bijoy").copy(isFrequent = true); val shadin = TestKit.person("Shadin").copy(isArchived = true)
        val (dinner, shares) = TestKit.split(TestKit.expense("Dinner", 30.0, accountId = maybank.id, funding = "Maybank"), listOf(bijoy), bijoy)
        val purchase = TestKit.expense("Uniqlo", 100.0)
        val refund = TestKit.movement(MoneyMovementKind.REFUND, 3000, date(2026, 10, 2), accountId = maybank.id, linkedExpenseId = purchase.id)
        val loan = TestKit.movement(MoneyMovementKind.LOAN_GIVEN, 15000, date(2026, 10, 2), personId = shadin.id, accountId = maybank.id)
        val transfer = TestKit.movement(MoneyMovementKind.OWN_TRANSFER, 20000, date(2026, 10, 2), accountId = maybank.id, counterAccountId = tng.id)
        val source = FinanceSnapshot(expenses = listOf(dinner, purchase), shares = shares, accounts = listOf(maybank, tng),
            people = listOf(bijoy, shadin), movements = listOf(refund, loan, transfer))
        val decoded = BackupCodec.decode(BackupCodec.encode(BackupCodec.makePayload(source, "A", now)))
        assertEquals(BackupPayload.CURRENT_VERSION, decoded.version)
        assertEquals(2, decoded.accounts!!.size); assertEquals(3, decoded.moneyMovements!!.size)
        assertEquals(2, decoded.expenses.first { it.id == dinner.id }.shares!!.size)

        val first = BackupMerge.apply(decoded, FinanceSnapshot(), now, MYT)
        val t = first.merged
        val rDinner = t.expenses.first { it.id == dinner.id }
        assertEquals(maybank.id, rDinner.accountId); assertEquals(bijoy.id, rDinner.payerId); assertEquals(false, rDinner.paidByMe)
        assertEquals("equal", rDinner.splitMethodRaw); assertEquals(2, t.sharesOf(dinner.id).size)
        assertEquals(bijoy.id, t.sharesOf(dinner.id).first { !it.isMe }.personId)
        assertEquals(purchase.id, t.movements.first { it.id == refund.id }.linkedExpenseId)
        assertEquals(shadin.id, t.movements.first { it.id == loan.id }.personId)
        assertEquals(tng.id, t.movements.first { it.id == transfer.id }.counterAccountId)
        assertTrue(t.people.first { it.id == bijoy.id }.isFrequent); assertTrue(t.people.first { it.id == shadin.id }.isArchived)
        assertEquals(0, first.summary.missingReferences)

        val second = BackupMerge.apply(decoded, t, now, MYT)
        assertEquals(0, second.summary.expensesAdded); assertEquals(0, second.summary.movementsAdded); assertEquals(0, second.summary.accountsAdded)
        assertEquals(2, second.merged.expenses.size); assertEquals(2, second.merged.shares.size); assertEquals(3, second.merged.movements.size)

        val v1 = payload(listOf(dto(dinner.id, 30.0, "Dinner", dinner.date)), version = 1)
        val third = BackupMerge.apply(v1, second.merged, now, MYT).merged
        val d3 = third.expenses.first { it.id == dinner.id }
        assertEquals(2, third.sharesOf(dinner.id).size); assertEquals(bijoy.id, d3.payerId); assertEquals(maybank.id, d3.accountId)
    }

    /** FinancialModelTests: accounts are matched by name when ids differ (no second "Maybank"). */
    @Test fun sameNamedAccountIsReused() {
        val local = TestKit.account("Maybank")
        val backupAccount = TestKit.account("maybank")
        val e = TestKit.expense("Kedai", 12.0, funding = "Maybank", accountId = backupAccount.id)
        val payload = BackupCodec.makePayload(FinanceSnapshot(expenses = listOf(e), accounts = listOf(backupAccount)), "A", now)
        val r = BackupMerge.apply(payload, FinanceSnapshot(accounts = listOf(local)), now, MYT)
        assertEquals(1, r.merged.accounts.size)
        assertEquals(local.id, r.merged.expenses.single().accountId)
        assertEquals(1, r.summary.accountsMatchedByName)
    }

    @Test fun backupShareListIsTheTruthAndMissingLinksAreCounted() {
        val bijoy = TestKit.person("Bijoy"); val ali = TestKit.person("Ali")
        val (dinner, shares) = TestKit.split(TestKit.expense("Dinner", 90.0), listOf(bijoy, ali), bijoy)
        val local = FinanceSnapshot(expenses = listOf(dinner), shares = shares, people = listOf(bijoy, ali))
        // The backup has the same expense split only with Bijoy (Ali removed), and a payer nobody knows.
        val (d2, s2) = TestKit.split(dinner.copy(updatedAt = dinner.updatedAt + 60_000), listOf(bijoy), bijoy)
        val keep = s2.mapIndexed { i, s -> s.copy(id = shares[i].id) }
        val p = BackupCodec.makePayload(FinanceSnapshot(expenses = listOf(d2), shares = keep, people = listOf(bijoy)), "A", now)
        val r = BackupMerge.apply(p, local, now, MYT)
        assertEquals(listOf(shares[2].id), r.removedShareIds)
        assertEquals(2, r.merged.sharesOf(dinner.id).count { it.deletedAt == null })
        assertEquals(now, r.merged.shares.first { it.id == shares[2].id }.deletedAt)
        assertEquals(4500L, r.merged.sharesOf(dinner.id).first { it.isMe }.amountMinor)

        val ghost = p.copy(expenses = p.expenses.map { it.copy(payerId = TestKit.id()) }, paybookProfiles = emptyList())
        val r2 = BackupMerge.apply(ghost, FinanceSnapshot(), now, MYT)
        assertNull(r2.merged.expenses.single().payerId)
        assertTrue(r2.summary.missingReferences >= 2) // payer + Bijoy's share person
    }

    @Test fun tombstonedLocalRecordComesBackFromBackup() {
        val e = TestKit.expense("Coffee", 9.0)
        val p = BackupCodec.makePayload(FinanceSnapshot(expenses = listOf(e)), "A", now)
        val local = FinanceSnapshot(expenses = listOf(e.copy(deletedAt = now - 1000, updatedAt = now - 1000)))
        val r = BackupMerge.apply(p, local, now, MYT)
        assertEquals(1, r.summary.expensesAdded)
        val back = r.merged.expenses.single()
        assertNull(back.deletedAt); assertEquals(now, back.updatedAt)
    }

    @Test fun rulesByMerchantKeyNewerWinsAndSettlementsOnlyAdded() {
        val localRule = TestKit.rule("kfc", "Food", at = date(2026, 9, 10))
        val backupRule = ClassificationRuleDto(id = TestKit.id(), merchantKey = "kfc", categoryRaw = "Personal", hitCount = 5,
            createdAt = date(2026, 9, 1), updatedAt = date(2026, 9, 20))
        val olderRule = backupRule.copy(id = TestKit.id(), merchantKey = "kfc", categoryRaw = "Bills", updatedAt = date(2026, 9, 5))
        val alloc = SettlementAllocationDto(id = TestKit.id(), groupID = TestKit.id(), kindRaw = "payment", personID = TestKit.id(), direction = 1,
            amountMinor = 100, currency = "RM", date = now, createdAt = now)
        val p = payload(version = 4).copy(classificationRules = listOf(backupRule, olderRule), settlementAllocations = listOf(alloc),
            sampleRecords = listOf(SampleRecordDto(TestKit.id(), "expense", now), SampleRecordDto(TestKit.id(), "bogus", now)))
        val r = BackupMerge.apply(p, FinanceSnapshot(classificationRules = listOf(localRule)), now, MYT)
        assertEquals(1, r.merged.classificationRules.size)
        assertEquals("Personal", r.merged.classificationRules.single().categoryRaw)
        assertEquals(localRule.id, r.merged.classificationRules.single().id)
        assertEquals(1, r.summary.rulesRestored)
        assertEquals(1, r.summary.settlementsRestored)
        assertEquals(1, r.merged.sampleRecords.size)
        val again = BackupMerge.apply(p, r.merged, now, MYT)
        assertEquals(0, again.summary.settlementsRestored)
    }

    @Test fun makeExpenseNormalisesLikeIosInit() {
        val e = BackupMerge.makeExpense(ExpenseDto(id = TestKit.id(), amount = 100.98999999, currency = "RM", merchant = "  ",
            categoryRaw = "Weird", paymentSourceRaw = "Nope", date = now, notes = "   ", sourceTypeRaw = "??", isSampleData = false,
            createdAt = now, paymentMethodRaw = "card"))
        assertEquals(10099L, e.amountMinor)
        assertEquals("Unknown", e.merchant); assertEquals("Personal", e.categoryRaw); assertEquals("Touch 'n Go", e.paymentSourceRaw)
        assertEquals("Touch 'n Go", e.fundingAccount); assertEquals("CARD", e.paymentChannelRaw); assertNull(e.notes)
        assertEquals("screenshot", e.sourceTypeRaw); assertEquals(now, e.updatedAt)
        val applePay = BackupMerge.makeExpense(ExpenseDto(id = TestKit.id(), amount = 5.0, currency = "RM", merchant = "X", categoryRaw = "Food",
            paymentSourceRaw = "Apple Pay", underlyingBankRaw = "CIMB", date = now, sourceTypeRaw = "manual", isSampleData = false, createdAt = now))
        assertEquals("CIMB", applePay.fundingAccount); assertEquals("APPLE_PAY", applePay.paymentChannelRaw)
        assertEquals("digital_wallet", applePay.paymentMethodRaw)
        assertNotNull(applePay.underlyingBankRaw)
    }
}
