package com.spendrop.core.model

import com.spendrop.core.insights.iosPaymentChannel

/*
 * SpenDrop records. One shape for every platform:
 *  - ids are UUID strings (lower case), kept for the life of the record (iOS, Web and Android share them);
 *  - money is integer minor units (sen), never floating point;
 *  - times are epoch milliseconds (UTC instants); `date` is the moment of the transaction;
 *  - `updatedAt` is the client's edit time (last writer wins); `deletedAt` is a tombstone (sync), never shown.
 * Mirrors iOS SwiftData models and the cloud tables in Supabase/supabase/migrations/20261007000000_*.sql.
 */

data class Expense(
    val id: String,
    val amountMinor: Long,
    val currency: String = "RM",
    val merchant: String = "Unknown",
    val categoryRaw: String = ExpenseCategory.OTHER.raw,
    /** WHERE the money came from, as text (historical snapshot, like iOS). */
    val fundingAccount: String = "Unknown",
    val accountId: String? = null,
    /** HOW it was paid. */
    val paymentChannelRaw: String = PaymentChannel.UNKNOWN.raw,
    val fundingInstrument: String? = null,
    val paymentSourceRaw: String = PaymentSource.UNKNOWN.raw,
    val underlyingBankRaw: String? = null,
    val paymentMethodRaw: String? = null,
    val date: Long,
    val notes: String? = null,
    val transactionReference: String? = null,
    val externalTransactionId: String? = null,
    val matchingStatusRaw: String = "UNMATCHED",
    val matchingConfidence: Double? = null,
    val sourceTypeRaw: String = ExpenseSourceType.MANUAL.raw,
    val ocrText: String? = null,
    val confidence: Double? = null,
    /** Local receipt image file name (app private storage). */
    val imageRelativePath: String? = null,
    /** Cloud receipt path in the private `receipts` bucket (`<user id>/<file>`), when uploaded. */
    val receiptPath: String? = null,
    val isSampleData: Boolean = false,
    val paidByMe: Boolean = true,
    val payerId: String? = null,
    val payerNameSnapshot: String? = null,
    val splitMethodRaw: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
    /** Hybrid Split rule (canonical JSON, Common/BusinessRules/split-hybrid.md). null = a normal split. */
    val splitRule: String? = null,
) {
    val category: ExpenseCategory get() = ExpenseCategory.fromRaw(categoryRaw)
    /** The stored channel; for an unrecognised stored value (old records) the iOS conservative fallback. */
    val paymentChannel: PaymentChannel get() = iosPaymentChannel
    val sourceType: ExpenseSourceType get() = ExpenseSourceType.fromRaw(sourceTypeRaw)
    val splitMethod: SplitMethod? get() = SplitMethod.fromRaw(splitMethodRaw)
    val isReconciled: Boolean get() = matchingStatusRaw == "RECONCILED" || matchingStatusRaw == "MATCHED"

    /** iOS `effectiveFundingAccount`: the stored text, else legacy bank / source names, else "Unknown". */
    val effectiveFundingAccount: String
        get() {
            val trimmed = fundingAccount.trim()
            if (trimmed.isNotEmpty() && trimmed != "Unknown") return trimmed
            val bank = underlyingBankRaw?.trim()
            if (!bank.isNullOrEmpty() && bank != "Unknown") return bank
            val src = PaymentSource.fromRawOrNull(paymentSourceRaw)
            if (paymentSourceRaw.isNotBlank() && (src == null || !src.isChannelLike)) return paymentSourceRaw
            return "Unknown"
        }

    val displayFundingAndChannel: String
        get() {
            val funding = effectiveFundingAccount
            val channel = paymentChannel
            if (funding == "Unknown" && channel == PaymentChannel.UNKNOWN) return "Unknown"
            return "$funding • ${channel.displayName}"
        }
}

/** One participant's share of a shared expense. Exactly one `isMe` share; all shares add up to the amount. */
data class ExpenseShare(
    val id: String,
    val expenseId: String,
    val personId: String? = null,
    val isMe: Boolean = false,
    val nameSnapshot: String,
    val amountMinor: Long,
    val parts: Int? = null,
    val enteredMinor: Long? = null,
    val sortIndex: Int = 0,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
)

/** A funding account (Maybank, Touch 'n Go, Cash). No balance by design. */
data class Account(
    val id: String,
    val name: String,
    val typeRaw: String = AccountType.OTHER.raw,
    val currency: String = "RM",
    val icon: String? = null,
    val isArchived: Boolean = false,
    val sortIndex: Int = 0,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
) {
    val type: AccountType get() = AccountType.fromRaw(typeRaw)
}

/** A PayBook person (iOS PayBookProfile). */
data class Person(
    val id: String,
    val name: String,
    val notes: String? = null,
    val isFrequent: Boolean = false,
    val isArchived: Boolean = false,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
) {
    val initials: String
        get() {
            // Words with their punctuation removed: "Ravi (Sample)" -> "RS", not "R(".
            val parts = name.split(" ").map { w -> w.filter { it.isLetterOrDigit() } }.filter { it.isNotEmpty() }
            return when {
                parts.size >= 2 -> "${parts[0].take(1)}${parts[1].take(1)}".uppercase()
                parts.size == 1 -> parts[0].take(2).uppercase()
                else -> "?"
            }
        }
}

data class PersonPaymentMethod(
    val id: String,
    val personId: String,
    val paymentTypeRaw: String = PaymentMethodType.BANK_ACCOUNT.raw,
    val provider: String,
    val customProviderName: String? = null,
    val accountIdentifier: String,
    val label: String? = null,
    val notes: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
) {
    val paymentType: PaymentMethodType get() = PaymentMethodType.fromRaw(paymentTypeRaw)
    val displayProvider: String
        get() = if (provider.equals("other", true) && !customProviderName.isNullOrEmpty()) customProviderName else provider
    val maskedIdentifier: String
        get() {
            val clean = accountIdentifier.filter { it.isLetterOrDigit() }
            return if (clean.length > 4) "••••" + clean.takeLast(4) else accountIdentifier
        }
    val normalizedIdentifier: String get() = accountIdentifier.filter { it.isLetterOrDigit() }.lowercase()
}

/** Money that is not spending: income, refunds, loans, repayments, own transfers. Amount is always positive. */
data class MoneyMovement(
    val id: String,
    val kindRaw: String,
    val directionRaw: String,
    val amountMinor: Long,
    val currency: String = "RM",
    val date: Long,
    val personId: String? = null,
    val personNameSnapshot: String? = null,
    val linkedExpenseId: String? = null,
    val linkedExpenseSnapshot: String? = null,
    val accountId: String? = null,
    val counterAccountId: String? = null,
    val note: String? = null,
    val transactionReference: String? = null,
    val sourceTypeRaw: String = ExpenseSourceType.MANUAL.raw,
    val paymentChannelRaw: String = PaymentChannel.UNKNOWN.raw,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
) {
    val direction: MoneyDirection get() = MoneyDirection.fromRaw(directionRaw)
    val kind: MoneyMovementKind get() = MoneyMovementKind.fromRaw(kindRaw, direction)
    val paymentChannel: PaymentChannel get() = PaymentChannel.fromRaw(paymentChannelRaw)
}

/** Which payment settled which debt (iOS SettlementAllocation). Linked by id. */
data class SettlementAllocation(
    val id: String,
    val groupId: String,
    val kindRaw: String = SettlementKind.PAYMENT.raw,
    val paymentId: String? = null,
    val expenseId: String? = null,
    val loanId: String? = null,
    val personId: String,
    /** +1: the person owed me (they paid me); -1: I owed the person (I paid them). */
    val direction: Int,
    val amountMinor: Long,
    val currency: String = "RM",
    val date: Long,
    val createdAt: Long,
    val updatedAt: Long = createdAt,
    val deletedAt: Long? = null,
) {
    val kind: SettlementKind get() = SettlementKind.fromRaw(kindRaw)
}

/** A locally learned category / type / account suggestion for a merchant. */
data class ClassificationRule(
    val id: String,
    val merchantKey: String,
    val categoryRaw: String? = null,
    /** "expense", "moneyIn", "moneyOut" or "transfer". */
    val suggestedTypeRaw: String? = null,
    val accountId: String? = null,
    val hitCount: Int = 1,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
)

/** Learned payment channel per merchant AND funding account. */
data class ChannelRule(
    val id: String,
    val merchantKey: String,
    val fundingKey: String,
    val channelRaw: String,
    val hitCount: Int = 1,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
)

/** Marks a record as demo data created by "Load Sample Data". */
data class SampleRecord(val recordId: String, val entityRaw: String, val createdAt: Long)

/** An expense together with its split shares (sorted by sortIndex). */
data class ExpenseWithShares(val expense: Expense, val shares: List<ExpenseShare>)

/** Everything the financial calculations need, already filtered to non-deleted records. */
data class FinanceSnapshot(
    val expenses: List<Expense> = emptyList(),
    val shares: List<ExpenseShare> = emptyList(),
    val accounts: List<Account> = emptyList(),
    val people: List<Person> = emptyList(),
    val paymentMethods: List<PersonPaymentMethod> = emptyList(),
    val movements: List<MoneyMovement> = emptyList(),
    val allocations: List<SettlementAllocation> = emptyList(),
    val classificationRules: List<ClassificationRule> = emptyList(),
    val channelRules: List<ChannelRule> = emptyList(),
    val sampleRecords: List<SampleRecord> = emptyList(),
) {
    val sharesByExpense: Map<String, List<ExpenseShare>> by lazy {
        shares.groupBy { it.expenseId }.mapValues { (_, v) -> v.sortedBy { it.sortIndex } }
    }
    fun sharesOf(expenseId: String): List<ExpenseShare> = sharesByExpense[expenseId].orEmpty()
}
