package com.spendrop.core.accounts

import com.spendrop.core.Ids
import com.spendrop.core.insights.collapseWhitespace
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.Expense
import com.spendrop.core.model.PaymentChannel

/** Identity used to avoid duplicate accounts ("Maybank", " maybank ", "MAYBANK" are the same account). */
val Account.nameKey: String? get() = AccountLinker.normalizedKey(name)

/** An account found for a name, or a NEW account the caller must insert ([isNew]). */
data class AccountResolution(val account: Account, val isNew: Boolean)

/** iOS `relink`: the expense with its `accountId` updated (fundingAccount text never changes) and any account to insert. */
data class RelinkResult(val expense: Expense, val account: Account?, val newAccount: Account?) {
    val changed: Boolean get() = newAccount != null || account?.id != expense.accountId
}

data class LinkResult(
    /** Accounts to insert. */
    val newAccounts: List<Account>,
    /** Expenses whose accountId was set (only previously unlinked ones). */
    val linkedExpenses: List<Expense>,
) {
    val accountsCreated: Int get() = newAccounts.size
    val expensesLinked: Int get() = linkedExpenses.size
}

/**
 * Creates Account records from the `fundingAccount` text and links expenses to them (iOS AccountLinker).
 * - Only meaningful values create accounts ("Unknown", "Other", empty… are ignored and stay unlinked).
 * - Names match case- and whitespace-insensitively.
 * - Only expenses without an account are linked by [linkUnlinkedExpenses]; the `fundingAccount` text is never modified.
 * Immutable: functions return the new / changed records instead of mutating a store.
 */
object AccountLinker {
    val ignoredKeys: Set<String> =
        setOf("", "unknown", "other", "none", "n/a", "na", "-", "null", "nil") +
            // Payment channels are never funding accounts (an Apple Pay tap is funded by a bank or card).
            PaymentChannel.entries.filter { it != PaymentChannel.CASH && it != PaymentChannel.E_WALLET }.map { it.displayName.lowercase() } +
            setOf("physical card", "qr", "duitnow")

    private val eWalletKeys = listOf("touch 'n go", "touch n go", "tng", "grabpay", "boost", "shopeepay", "bigpay", "setel", "mae")
    private val bankKeys = listOf(
        "maybank", "cimb", "rhb", "public bank", "bank islam", "hong leong", "ambank", "affin", "ocbc", "uob",
        "hsbc", "standard chartered", "bsn", "bank rakyat", "alliance", "agrobank", "bank muamalat", "citibank",
    )

    /** Normalised identity for an account name, or null when the value does not name a real account. */
    fun normalizedKey(raw: String?): String? {
        if (raw == null) return null
        val collapsed = raw.replace('\u2019', '\'').collapseWhitespace().lowercase()
        return if (collapsed in ignoredKeys) null else collapsed
    }

    fun inferredType(name: String): AccountType {
        val key = normalizedKey(name) ?: return AccountType.OTHER
        if (key == "cash") return AccountType.CASH
        if (eWalletKeys.any { key == it || key.startsWith("$it ") }) return AccountType.E_WALLET
        if (bankKeys.any { key.contains(it) }) return AccountType.BANK
        return AccountType.OTHER
    }

    private fun ordered(accounts: List<Account>) = accounts.sortedWith(compareBy<Account> { it.sortIndex }.thenBy { it.createdAt })

    /**
     * Finds the account for a funding-account name (case/space-insensitive; archived accounts included so no duplicate is
     * ever created; an active match wins), or returns a NEW account to insert. Null for "Unknown", "Other", empty…
     */
    fun resolveAccount(
        rawName: String,
        accounts: List<Account>,
        currency: String = "RM",
        now: Long,
        newId: () -> String = Ids::new,
    ): AccountResolution? {
        val key = normalizedKey(rawName) ?: return null
        val live = ordered(accounts.filter { it.deletedAt == null })
        val matches = live.filter { it.nameKey == key }
        (matches.firstOrNull { !it.isArchived } ?: matches.firstOrNull())?.let { return AccountResolution(it, false) }
        val name = rawName.trim()
        val account = Account(
            id = newId(), name = name, typeRaw = inferredType(name).raw, currency = currency,
            sortIndex = (live.maxOfOrNull { it.sortIndex } ?: -1) + 1, createdAt = now, updatedAt = now,
        )
        return AccountResolution(account, true)
    }

    /**
     * Makes the expense's account match its `fundingAccount` text (used when an expense is saved or edited, so the link
     * never goes stale). "Unknown"/empty text clears the link. `updatedAt` is not touched (iOS does not either).
     */
    fun relink(expense: Expense, accounts: List<Account>, now: Long, newId: () -> String = Ids::new): RelinkResult {
        val key = normalizedKey(expense.fundingAccount) ?: return RelinkResult(expense.copy(accountId = null), null, null)
        val current = expense.accountId?.let { id -> accounts.firstOrNull { it.id == id && it.deletedAt == null } }
        if (current != null && current.nameKey == key) return RelinkResult(expense, current, null)
        val resolved = resolveAccount(expense.fundingAccount, accounts, expense.currency, now, newId)
        return RelinkResult(expense.copy(accountId = resolved?.account?.id), resolved?.account, resolved?.account?.takeIf { resolved.isNew })
    }

    /**
     * Funding-account choices for the expense forms: the fixed list, plus any active account the user added, with
     * "Other" kept last. Names already in the list are not repeated.
     */
    fun fundingOptions(base: List<String>, accounts: List<Account>): List<String> {
        val options = base.filter { normalizedKey(it) != null }.toMutableList()
        val keys = options.mapNotNull { normalizedKey(it) }.toMutableSet()
        for (account in accounts.sortedBy { it.sortIndex }) if (!account.isArchived && account.deletedAt == null) {
            val key = account.nameKey
            if (key != null && key !in keys) { options += account.name; keys += key }
        }
        if ("Other" in base) options += "Other"
        return options
    }

    /** Links every unlinked expense (by date) to an account for its funding text, creating accounts as needed. */
    fun linkUnlinkedExpenses(expenses: List<Expense>, accounts: List<Account>, now: Long, newId: () -> String = Ids::new): LinkResult {
        val live = ordered(accounts.filter { it.deletedAt == null })
        val byKey = LinkedHashMap<String, Account>()
        for (a in live) a.nameKey?.let { byKey.putIfAbsent(it, a) }
        val liveIds = live.map { it.id }.toSet()
        var nextSort = (live.maxOfOrNull { it.sortIndex } ?: -1) + 1
        val created = mutableListOf<Account>()
        val linked = mutableListOf<Expense>()
        for (e in expenses.sortedBy { it.date }) {
            if (e.accountId != null && e.accountId in liveIds) continue
            val key = normalizedKey(e.fundingAccount) ?: continue
            val account = byKey[key] ?: run {
                val name = e.fundingAccount.trim()
                Account(id = newId(), name = name, typeRaw = inferredType(name).raw, currency = e.currency, sortIndex = nextSort,
                    createdAt = now, updatedAt = now).also { byKey[key] = it; nextSort++; created += it }
            }
            linked += e.copy(accountId = account.id)
        }
        return LinkResult(created, linked)
    }
}

/** Pure validation for the account form (iOS AccountFormValidation). Null = OK. */
object AccountFormValidation {
    fun problem(name: String, editingId: String?, existing: List<Account>): String? {
        val key = AccountLinker.normalizedKey(name) ?: return "Enter a name. \"Unknown\" and \"Other\" can't be used."
        if (existing.any { it.id != editingId && it.deletedAt == null && it.nameKey == key }) return "An account with this name already exists."
        return null
    }
}
