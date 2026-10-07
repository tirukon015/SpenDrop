package com.spendrop.core.ledger

import com.spendrop.core.Ids
import com.spendrop.core.Money
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.model.Person

/** The record types offered by the Add sheet. Expense stays the default. */
enum class TransactionEntryType(val raw: String, val title: String, val icon: String) {
    EXPENSE("expense", "Expense", "cart"),
    MONEY_IN("moneyIn", "Money In", "arrow.down.circle"),
    MONEY_OUT("moneyOut", "Money Out", "arrow.up.right.circle"),
    TRANSFER("transfer", "Transfer", "arrow.left.arrow.right.circle");

    /** Kinds offered for this entry type, most common first. */
    val kinds: List<MoneyMovementKind>
        get() = when (this) {
            EXPENSE -> emptyList()
            MONEY_IN -> listOf(MoneyMovementKind.INCOME, MoneyMovementKind.REPAYMENT_RECEIVED, MoneyMovementKind.LOAN_RECEIVED,
                MoneyMovementKind.REFUND, MoneyMovementKind.OTHER_IN)
            MONEY_OUT -> listOf(MoneyMovementKind.LOAN_GIVEN, MoneyMovementKind.REPAYMENT_MADE, MoneyMovementKind.OTHER_OUT)
            TRANSFER -> listOf(MoneyMovementKind.OWN_TRANSFER)
        }

    companion object {
        fun of(kind: MoneyMovementKind): TransactionEntryType = when (kind.direction) {
            MoneyDirection.IN -> MONEY_IN
            MoneyDirection.OUT -> MONEY_OUT
            MoneyDirection.INTERNAL -> TRANSFER
        }
    }
}

/**
 * Editable, validated form state for a Money In / Money Out / Transfer record (iOS `MoneyMovementDraft`).
 * Immutable; accounts are referenced by id. Saving returns the record to insert/update.
 */
data class MoneyMovementDraft(
    val entryType: TransactionEntryType,
    val kind: MoneyMovementKind = entryType.kinds.firstOrNull() ?: MoneyMovementKind.OTHER_OUT,
    val amountText: String = "",
    val currency: String = "RM",
    val date: Long,
    val person: Person? = null,
    val accountId: String? = null,
    val counterAccountId: String? = null,
    val note: String = "",
    // Carried over from scans/imports so the saved record keeps its provenance.
    val transactionReference: String? = null,
    val sourceType: ExpenseSourceType = ExpenseSourceType.MANUAL,
    val paymentChannel: PaymentChannel = PaymentChannel.UNKNOWN,
) {
    enum class Issue(val message: String) {
        INVALID_AMOUNT("Enter an amount above RM0.00."),
        MISSING_PERSON("Choose who this money is with."),
        MISSING_FROM_ACCOUNT("Choose the account the money left."),
        MISSING_TO_ACCOUNT("Choose the account the money went to."),
        SAME_ACCOUNT("From and To must be different accounts."),
    }

    /** Switches entry type, picking that type's default kind. */
    fun setEntryType(newType: TransactionEntryType): MoneyMovementDraft {
        if (newType == entryType) return this
        return copy(
            entryType = newType,
            kind = newType.kinds.firstOrNull() ?: MoneyMovementKind.OTHER_OUT,
            counterAccountId = if (newType != TransactionEntryType.TRANSFER) null else counterAccountId,
        )
    }

    val amountMinor: Long? get() = Money.parseMinor(amountText)

    val issues: List<Issue>
        get() {
            val issues = ArrayList<Issue>()
            if ((amountMinor ?: 0) <= 0) issues += Issue.INVALID_AMOUNT
            if (kind.requiresPerson && person == null) issues += Issue.MISSING_PERSON
            if (kind == MoneyMovementKind.OWN_TRANSFER) {
                if (accountId == null) issues += Issue.MISSING_FROM_ACCOUNT
                if (counterAccountId == null) issues += Issue.MISSING_TO_ACCOUNT
                if (accountId != null && counterAccountId != null && accountId == counterAccountId) issues += Issue.SAME_ACCOUNT
            }
            return issues
        }

    val isValid: Boolean get() = issues.isEmpty()

    /** A new movement for this draft, or null when invalid. */
    fun newMovement(now: Long, sourceType: ExpenseSourceType? = null, id: String = Ids.new()): MoneyMovement? {
        if (!isValid) return null
        val base = MoneyMovement(
            id = id, kindRaw = kind.raw, directionRaw = kind.direction.raw, amountMinor = amountMinor ?: return null,
            currency = currency, date = date, transactionReference = transactionReference,
            sourceTypeRaw = (sourceType ?: this.sourceType).raw, paymentChannelRaw = paymentChannel.raw,
            createdAt = now, updatedAt = now,
        )
        return applyTo(base, now)
    }

    /** Writes the draft into an existing movement (edit; same id). Null when the draft is invalid. */
    fun applyTo(movement: MoneyMovement, now: Long): MoneyMovement? {
        if (!isValid) return null
        val amount = amountMinor ?: return null
        val linkedPerson = if (kind.requiresPerson) person else null
        val trimmed = note.trim()
        return movement.copy(
            kindRaw = kind.raw,
            directionRaw = kind.direction.raw,
            amountMinor = amount,
            currency = currency,
            date = date,
            personId = linkedPerson?.id,
            personNameSnapshot = linkedPerson?.name,
            accountId = accountId,
            counterAccountId = if (kind == MoneyMovementKind.OWN_TRANSFER) counterAccountId else null,
            note = trimmed.ifEmpty { null },
            updatedAt = now,
        )
    }

    companion object {
        fun new(entryType: TransactionEntryType, now: Long): MoneyMovementDraft = MoneyMovementDraft(entryType = entryType, date = now)

        /** Loads an existing movement for editing. [person] = the movement's person, if it still exists. */
        fun fromMovement(movement: MoneyMovement, person: Person?): MoneyMovementDraft = MoneyMovementDraft(
            entryType = TransactionEntryType.of(movement.kind),
            kind = movement.kind,
            amountText = Money.plain(movement.amountMinor),
            currency = movement.currency,
            date = movement.date,
            person = person,
            accountId = movement.accountId,
            counterAccountId = movement.counterAccountId,
            note = movement.note ?: "",
            transactionReference = movement.transactionReference,
            sourceType = ExpenseSourceType.fromRaw(movement.sourceTypeRaw),
            paymentChannel = movement.paymentChannel,
        )

        /**
         * Draft for a scanned screenshot saved as Money In / Money Out / Transfer. The account is resolved from the
         * detected funding account name by [resolveAccountId] (the caller's AccountLinker: returns an existing or newly
         * created account id, or null for Unknown — never invented here). For an own transfer from a wallet top-up
         * (Touch 'n Go / GrabPay / Boost) the wallet becomes the destination account when it differs from the source.
         */
        fun fromParsed(
            amountMinor: Long,
            date: Long,
            fundingAccount: String,
            merchant: String,
            reference: String?,
            channel: PaymentChannel,
            walletSource: PaymentSource?,
            kind: MoneyMovementKind,
            source: ExpenseSourceType,
            resolveAccountId: (String) -> String?,
        ): MoneyMovementDraft {
            val accountId = resolveAccountId(fundingAccount)
            var counter: String? = null
            if (kind == MoneyMovementKind.OWN_TRANSFER && walletSource != null &&
                walletSource in setOf(PaymentSource.TOUCH_N_GO, PaymentSource.GRAB_PAY, PaymentSource.BOOST)
            ) {
                val to = resolveAccountId(walletSource.raw)
                if (to != accountId) counter = to
            }
            val trimmed = merchant.trim()
            return MoneyMovementDraft(
                entryType = TransactionEntryType.of(kind),
                kind = kind,
                amountText = Money.plain(amountMinor),
                date = date,
                accountId = accountId,
                counterAccountId = counter,
                note = if (trimmed == "Unknown") "" else trimmed,
                transactionReference = reference,
                sourceType = source,
                paymentChannel = channel,
            )
        }
    }
}
