package com.spendrop.core.insights

import com.spendrop.core.accounts.AccountFormValidation
import com.spendrop.core.accounts.AccountLinker
import com.spendrop.core.accounts.nameKey
import com.spendrop.core.finance.FinancialCalculator
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.MoneyMovementKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ports of iOS AccountFeatureTests (Phase 3: activity, resolve/relink, funding options, form validation),
 * FinancialModelTests "Accounts and the linker" and HardeningTests "Transfers both ways" / "rename, archive".
 */
class AccountLinkerTest {
    private val now = TK.NOW

    @Test fun accountActivity_phase3() {
        val maybank = TK.account("Maybank", AccountType.BANK); val tng = TK.account("Touch 'n Go", AccountType.E_WALLET)
        val bijoy = TK.person("Bijoy")
        val lunch = TK.expense(25.0, "McDonald's", accountId = maybank.id)
        val paidByOther = TK.expense(30.0, "Dinner", accountId = maybank.id).copy(paidByMe = false, payerId = bijoy.id, payerNameSnapshot = "Bijoy")
        val foreign = TK.expense(10.0, "Abroad", currency = "USD", accountId = maybank.id)
        val salary = TK.movement(MoneyMovementKind.INCOME, 100000, accountId = maybank.id)
        val loan = TK.movement(MoneyMovementKind.LOAN_GIVEN, 15000, person = bijoy, accountId = maybank.id)
        val transfer = TK.movement(MoneyMovementKind.OWN_TRANSFER, 20000, accountId = maybank.id, counterAccountId = tng.id)
        val ex = listOf(lunch, paidByOther, foreign); val mv = listOf(salary, loan, transfer)
        val m = FinancialCalculator.accountActivity(maybank.id, "RM", ex, mv)
        val t = FinancialCalculator.accountActivity(tng.id, "RM", ex, mv)
        assertEquals(FinancialCalculator.AccountActivity(100000, 37500), m)
        assertEquals(62500L, m.netMinor)
        assertEquals(FinancialCalculator.AccountActivity(20000, 0), t)
    }

    @Test fun resolveAccount_phase3() {
        val maybank = TK.account("Maybank", AccountType.BANK, sortIndex = 0)
        val wise = TK.account("Wise", AccountType.OTHER, sortIndex = 1, archived = true)
        var accounts = listOf(maybank, wise)
        val same = AccountLinker.resolveAccount(" maybank ", accounts, now = now)!!
        val archived = AccountLinker.resolveAccount("WISE", accounts, now = now)!!
        val created = AccountLinker.resolveAccount("Bank Rakyat", accounts, now = now)!!
        accounts = accounts + created.account
        val unknown = AccountLinker.resolveAccount("Unknown", accounts, now = now)
        assertSame(maybank, same.account); assertFalse(same.isNew)
        assertSame(wise, archived.account)
        assertTrue(created.isNew)
        assertEquals("Bank Rakyat", created.account.name)
        assertEquals(AccountType.BANK, created.account.type)
        assertEquals(2, created.account.sortIndex)
        assertNull(unknown)
        assertEquals(3, accounts.size)
        // An active match wins over an archived one with the same key
        val activeWise = TK.account("wise", sortIndex = 5)
        assertSame(activeWise, AccountLinker.resolveAccount("Wise", listOf(wise, activeWise), now = now)!!.account)
    }

    @Test fun relink_phase3() {
        val maybank = TK.account("Maybank", AccountType.BANK); val cimb = TK.account("CIMB", AccountType.BANK)
        var accounts = listOf(maybank, cimb)
        var expense = TK.expense(12.0, "Kedai", fundingAccount = "Maybank", accountId = maybank.id)

        val r1 = AccountLinker.relink(expense, accounts, now)
        val unchanged = r1.expense.accountId == maybank.id && r1.newAccount == null && !r1.changed
        expense = r1.expense.copy(fundingAccount = "CIMB")                  // user edits the expense
        val r2 = AccountLinker.relink(expense, accounts, now)
        expense = r2.expense
        val movedToCIMB = expense.accountId == cimb.id && r2.newAccount == null
        expense = expense.copy(fundingAccount = "GXBank")
        val r3 = AccountLinker.relink(expense, accounts, now)
        accounts = accounts + listOfNotNull(r3.newAccount)
        expense = r3.expense
        val createdNew = r3.newAccount?.name == "GXBank" && expense.accountId == r3.newAccount?.id
        expense = expense.copy(fundingAccount = "Unknown")
        val r4 = AccountLinker.relink(expense, accounts, now)
        val cleared = r4.expense.accountId == null && r4.account == null
        assertTrue(unchanged); assertTrue(movedToCIMB); assertTrue(createdNew); assertTrue(cleared)
        assertEquals(3, accounts.size)
        assertEquals("Unknown", r4.expense.fundingAccount)
    }

    @Test fun fundingOptions_phase3() {
        val dup = TK.account("maybank", sortIndex = 0); val extra = TK.account("Bank Rakyat", AccountType.BANK, sortIndex = 1)
        val archived = TK.account("Wise", sortIndex = 2, archived = true)
        assertEquals(listOf("Maybank", "CIMB", "Wise", "Bank Rakyat", "Other"),
            AccountLinker.fundingOptions(listOf("Maybank", "CIMB", "Wise", "Other"), listOf(dup, extra, archived)))
    }

    @Test fun accountFormValidation_phase3() {
        val maybank = TK.account("Maybank")
        val existing = listOf(maybank)
        val problems = listOf(
            AccountFormValidation.problem("  ", null, existing),
            AccountFormValidation.problem("Unknown", null, existing),
            AccountFormValidation.problem(" MAYBANK", null, existing),
            AccountFormValidation.problem("Maybank", maybank.id, existing),
            AccountFormValidation.problem("Bank Rakyat", null, existing),
        ).map { it != null }
        assertEquals(listOf(true, true, true, false, false), problems)
        assertEquals("An account with this name already exists.", AccountFormValidation.problem("maybank", null, existing))
    }

    @Test fun eachAccountHasItsOwnIdentity_phase2() {
        val a = TK.account("Maybank", AccountType.BANK); val b = TK.account("Maybank", AccountType.BANK)
        assertNotEquals(a.id, b.id)
        assertEquals(a.nameKey, b.nameKey)
        assertEquals("maybank", a.nameKey)
    }

    @Test fun normalizedKeyAndTypes() {
        assertEquals("touch 'n go", AccountLinker.normalizedKey("  Touch’n  \n Go ".replace("’n", " ’n")))
        assertEquals("touch 'n go", AccountLinker.normalizedKey("TOUCH 'N GO"))
        for (ignored in listOf("", " ", "Unknown", "OTHER", "n/a", "-", "Apple Pay", "qr payment", "Card", "DuitNow QR", "Touch 'n Go QR",
            "Online Banking", "Bank Transfer", "physical card", "QR", "duitnow", "null", "nil", "none", "na")) {
            assertNull(ignored, AccountLinker.normalizedKey(ignored))
        }
        assertEquals("cash", AccountLinker.normalizedKey("Cash"))
        assertEquals("e-wallet", AccountLinker.normalizedKey("E-Wallet"))
        assertNull(AccountLinker.normalizedKey(null))
        assertEquals(AccountType.CASH, AccountLinker.inferredType("cash"))
        assertEquals(AccountType.E_WALLET, AccountLinker.inferredType("TNG eWallet"))
        assertEquals(AccountType.E_WALLET, AccountLinker.inferredType("GrabPay"))
        assertEquals(AccountType.OTHER, AccountLinker.inferredType("Boosted Card"))
        assertEquals(AccountType.BANK, AccountLinker.inferredType("Maybank Savings"))
        assertEquals(AccountType.BANK, AccountLinker.inferredType("My UOB One"))
        assertEquals(AccountType.OTHER, AccountLinker.inferredType("Wise"))
        assertEquals(AccountType.OTHER, AccountLinker.inferredType("Unknown"))
    }

    @Test fun linkUnlinkedExpenses_phase2() {
        val e = listOf(
            TK.expense(10.0, "A", fundingAccount = "Maybank"), TK.expense(20.0, "B", fundingAccount = " MAYBANK "),
            TK.expense(30.0, "C", fundingAccount = "CIMB"), TK.expense(40.0, "D", fundingAccount = "Unknown"),
            TK.expense(50.0, "E", fundingAccount = "Other"), TK.expense(60.0, "F", fundingAccount = "Touch 'n Go"),
            TK.expense(70.0, "G", fundingAccount = "Cash"),
        )
        val first = AccountLinker.linkUnlinkedExpenses(e, emptyList(), now)
        assertEquals(4, first.accountsCreated)
        assertEquals(5, first.expensesLinked)
        val linked = e.map { orig -> first.linkedExpenses.firstOrNull { it.id == orig.id } ?: orig }
        val accounts = first.newAccounts
        val second = AccountLinker.linkUnlinkedExpenses(linked, accounts, now)
        assertEquals(0, second.accountsCreated); assertEquals(0, second.expensesLinked)
        fun acc(i: Int): Account? = linked[i].accountId?.let { id -> accounts.first { it.id == id } }
        assertEquals(acc(0), acc(1))
        assertEquals("Maybank", acc(0)?.name)
        assertEquals("CIMB", acc(2)?.name)
        assertNull(acc(3)); assertNull(acc(4))
        assertEquals(" MAYBANK ", linked[1].fundingAccount)
        assertEquals("Unknown", linked[3].fundingAccount)
        assertEquals(listOf(AccountType.BANK, AccountType.E_WALLET, AccountType.CASH, AccountType.BANK), listOf(0, 5, 6, 2).map { acc(it)?.type })
        assertEquals("inverse: Maybank has 2 expenses", 2, linked.count { it.accountId == acc(0)?.id })
        assertEquals(listOf("Maybank", "CIMB", "Touch 'n Go", "Cash"), accounts.sortedBy { it.sortIndex }.map { it.name })
    }

    @Test fun linkerNeverChangesAnExistingLink_phase2() {
        val existing = TK.account("Maybank", AccountType.BANK)
        val manual = TK.expense(5.0, "Kept", fundingAccount = "CIMB", accountId = existing.id)
        val r = AccountLinker.linkUnlinkedExpenses(listOf(manual), listOf(existing), now)
        assertEquals(0, r.accountsCreated); assertEquals(0, r.expensesLinked)
    }

    @Test fun transfersBothWays_phase8() {
        val maybank = TK.account("Maybank", AccountType.BANK); val tng = TK.account("Touch 'n Go", AccountType.E_WALLET)
        val there = TK.movement(MoneyMovementKind.OWN_TRANSFER, 20000, accountId = maybank.id, counterAccountId = tng.id)
        val back = TK.movement(MoneyMovementKind.OWN_TRANSFER, 5000, accountId = tng.id, counterAccountId = maybank.id)
        val m = FinancialCalculator.accountActivity(maybank.id, "RM", emptyList(), listOf(there, back))
        val n = FinancialCalculator.accountActivity(tng.id, "RM", emptyList(), listOf(there, back))
        assertEquals(FinancialCalculator.AccountActivity(5000, 20000), m)
        assertEquals(FinancialCalculator.AccountActivity(20000, 5000), n)
        assertEquals(FinancialCalculator.Summary(), FinancialCalculator.summary(emptyList(), { emptyList() }, listOf(there, back)))
    }

    @Test fun renameArchiveKeepHistory_phase8() {
        val bank = TK.account("Maybank", AccountType.BANK)
        val e = TK.expense(8.0, "Kopi", fundingAccount = "Maybank", accountId = bank.id)
        val renamed = bank.copy(name = "Maybank Savings", isArchived = true)
        assertFalse(AccountLinker.fundingOptions(listOf("Other"), listOf(renamed)).contains("Maybank Savings"))
        assertEquals("Maybank", e.fundingAccount)
        assertEquals(bank.id, e.accountId)
        assertTrue(AccountLinker.fundingOptions(listOf("Other"), listOf(renamed.copy(isArchived = false))).contains("Maybank Savings"))
    }

    @Test fun moneyInVarietyAndPersonEffects_phase8() {
        val riyad = TK.person("Riyad")
        val items = listOf(
            TK.movement(MoneyMovementKind.OTHER_IN, 1000), TK.movement(MoneyMovementKind.LOAN_RECEIVED, 5000, person = riyad),
            TK.movement(MoneyMovementKind.OTHER_OUT, 700), TK.movement(MoneyMovementKind.INCOME, 200000),
        )
        val s = FinancialCalculator.summary(emptyList(), { emptyList() }, items)
        assertEquals(206000L, s.moneyInMinor); assertEquals(700L, s.moneyOutMinor); assertEquals(0L, s.spendingMinor)
        assertEquals(-5000L, FinancialCalculator.personBalances(emptyList(), { emptyList() }, items)[riyad.id])
    }
}
