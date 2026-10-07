package com.spendrop.core.cloud

import com.spendrop.core.Ids
import com.spendrop.core.backup.SwiftDates
import com.spendrop.core.model.Account
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SettlementAllocation
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement

/*
 * Per-record cloud rows (migration 20261007000000_spendrop_cloud_records.sql; NOT deployed yet — future live sync).
 * Column names are exact. Ids are lower-case UUID text; timestamps are ISO-8601 strings with milliseconds
 * ("2026-10-07T03:00:00.123Z"); money is amount_minor (bigint).
 *
 * `user_id` and `server_updated_at` are server-owned: default null and NEVER sent (encode with [CloudRows.json],
 * which skips defaults); every other column is always sent, nulls included, so an upsert can clear a value.
 *
 * Writes (PostgREST): `POST rest/v1/<table>` with `Prefer: resolution=merge-duplicates,return=minimal` (upsert by id);
 * no DELETE (deleting = sending deleted_at). Expenses + shares go through
 * `POST rest/v1/rpc/save_expense_with_shares` with [SaveExpenseWithSharesArgs] (server ignores writes older than
 * the stored updated_at). Pull: `GET rest/v1/<table>?select=*&server_updated_at=gt.<cursor>&order=server_updated_at.asc`.
 */

@Serializable
data class AccountRow(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    val icon: String?,
    @SerialName("is_archived") val isArchived: Boolean,
    @SerialName("sort_index") val sortIndex: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class PersonRow(
    val id: String,
    val name: String,
    val notes: String?,
    @SerialName("is_frequent") val isFrequent: Boolean,
    @SerialName("is_archived") val isArchived: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class PersonPaymentMethodRow(
    val id: String,
    @SerialName("person_id") val personId: String,
    @SerialName("payment_type") val paymentType: String,
    val provider: String,
    @SerialName("custom_provider_name") val customProviderName: String?,
    @SerialName("account_identifier") val accountIdentifier: String,
    val label: String?,
    val notes: String?,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class ExpenseRow(
    val id: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val merchant: String,
    val category: String,
    @SerialName("payment_channel") val paymentChannel: String,
    @SerialName("funding_account") val fundingAccount: String,
    @SerialName("funding_instrument") val fundingInstrument: String?,
    @SerialName("account_id") val accountId: String?,
    @SerialName("payment_source") val paymentSource: String?,
    val date: String,
    val notes: String?,
    @SerialName("transaction_reference") val transactionReference: String?,
    @SerialName("source_type") val sourceType: String,
    @SerialName("paid_by_me") val paidByMe: Boolean,
    @SerialName("payer_id") val payerId: String?,
    @SerialName("payer_name_snapshot") val payerNameSnapshot: String?,
    @SerialName("split_method") val splitMethod: String?,
    /**
     * Hybrid Split rule (migration 20261008000000_hybrid_split). [SPLIT_RULE_MISSING] when the server doesn't send the
     * column (not migrated yet), so a pull never wipes the rule this device has.
     */
    @SerialName("split_rule") val splitRule: String? = SPLIT_RULE_MISSING,
    @SerialName("receipt_path") val receiptPath: String?,
    @SerialName("is_sample_data") val isSampleData: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class ExpenseShareRow(
    val id: String,
    @SerialName("expense_id") val expenseId: String,
    @SerialName("person_id") val personId: String?,
    @SerialName("is_me") val isMe: Boolean,
    @SerialName("name_snapshot") val nameSnapshot: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val parts: Int?,
    @SerialName("entered_minor") val enteredMinor: Long?,
    @SerialName("sort_index") val sortIndex: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class MoneyMovementRow(
    val id: String,
    val kind: String,
    val direction: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val date: String,
    @SerialName("person_id") val personId: String?,
    @SerialName("person_name_snapshot") val personNameSnapshot: String?,
    @SerialName("linked_expense_id") val linkedExpenseId: String?,
    @SerialName("linked_expense_snapshot") val linkedExpenseSnapshot: String?,
    @SerialName("account_id") val accountId: String?,
    @SerialName("counter_account_id") val counterAccountId: String?,
    val note: String?,
    @SerialName("transaction_reference") val transactionReference: String?,
    @SerialName("source_type") val sourceType: String,
    @SerialName("payment_channel") val paymentChannel: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class SettlementAllocationRow(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val kind: String,
    @SerialName("payment_id") val paymentId: String?,
    @SerialName("expense_id") val expenseId: String?,
    @SerialName("loan_id") val loanId: String?,
    @SerialName("person_id") val personId: String,
    val direction: Int,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val date: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class ClassificationRuleRow(
    val id: String,
    @SerialName("merchant_key") val merchantKey: String,
    val category: String?,
    @SerialName("suggested_type") val suggestedType: String?,
    @SerialName("account_id") val accountId: String?,
    @SerialName("hit_count") val hitCount: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class ChannelRuleRow(
    val id: String,
    @SerialName("merchant_key") val merchantKey: String,
    @SerialName("funding_key") val fundingKey: String,
    val channel: String,
    @SerialName("hit_count") val hitCount: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/** Body of `POST rest/v1/rpc/save_expense_with_shares`. Shares not listed are tombstoned by the server. */
@Serializable
data class SaveExpenseWithSharesArgs(
    @SerialName("p_expense") val expense: ExpenseRow,
    @SerialName("p_shares") val shares: List<ExpenseShareRow>,
)

/** Table names, in a foreign-key-safe push order. */
object CloudTables {
    const val ACCOUNTS = "accounts"
    const val PEOPLE = "people"
    const val PERSON_PAYMENT_METHODS = "person_payment_methods"
    const val EXPENSES = "expenses"
    const val EXPENSE_SHARES = "expense_shares"
    const val MONEY_MOVEMENTS = "money_movements"
    const val SETTLEMENT_ALLOCATIONS = "settlement_allocations"
    const val CLASSIFICATION_RULES = "classification_rules"
    const val CHANNEL_RULES = "channel_rules"
    val pushOrder = listOf(ACCOUNTS, PEOPLE, PERSON_PAYMENT_METHODS, EXPENSES, EXPENSE_SHARES, MONEY_MOVEMENTS,
        SETTLEMENT_ALLOCATIONS, CLASSIFICATION_RULES, CHANNEL_RULES)
}

/** Mappers between :core records and cloud rows. */
/** Default of [ExpenseRow.splitRule]: the key wasn't in the server's row. Never sent (equal to the default). */
const val SPLIT_RULE_MISSING = "\u0000missing"

object CloudRows {
    /** Writes every column except server-owned defaults (user_id, server_updated_at); nulls are sent explicitly. */
    val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = true }

    inline fun <reified T> toJson(value: T): JsonElement = json.encodeToJsonElement(value)
    fun saveExpenseArgs(expense: Expense, shares: List<ExpenseShare>): JsonObject =
        json.encodeToJsonElement(SaveExpenseWithSharesArgs(toRow(expense), shares.filter { it.deletedAt == null }.map(::toRow))) as JsonObject

    private fun ts(ms: Long) = SwiftDates.formatMillis(ms)
    private fun tsOrNull(ms: Long?) = ms?.let(::ts)
    private fun ms(text: String): Long = SwiftDates.parse(text) ?: throw IllegalArgumentException("Bad timestamp $text")
    private fun msOrNull(text: String?): Long? = text?.let(::ms)
    private fun id(v: String) = Ids.normalize(v)
    private fun idOrNull(v: String?) = v?.let(Ids::normalize)

    fun toRow(a: Account) = AccountRow(id(a.id), a.name, a.typeRaw, a.currency, a.icon, a.isArchived, a.sortIndex,
        ts(a.createdAt), ts(a.updatedAt), tsOrNull(a.deletedAt))
    fun fromRow(r: AccountRow) = Account(id(r.id), r.name, r.type, r.currency, r.icon, r.isArchived, r.sortIndex,
        ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))

    fun toRow(p: Person) = PersonRow(id(p.id), p.name, p.notes, p.isFrequent, p.isArchived, ts(p.createdAt), ts(p.updatedAt), tsOrNull(p.deletedAt))
    fun fromRow(r: PersonRow) = Person(id(r.id), r.name, r.notes, r.isFrequent, r.isArchived, ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))

    fun toRow(m: PersonPaymentMethod) = PersonPaymentMethodRow(id(m.id), id(m.personId), m.paymentTypeRaw, m.provider, m.customProviderName,
        m.accountIdentifier, m.label, m.notes, ts(m.createdAt), ts(m.updatedAt), tsOrNull(m.deletedAt))
    fun fromRow(r: PersonPaymentMethodRow) = PersonPaymentMethod(id(r.id), id(r.personId), r.paymentType, r.provider, r.customProviderName,
        r.accountIdentifier, r.label, r.notes, ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))

    fun toRow(e: Expense) = ExpenseRow(
        id = id(e.id), amountMinor = e.amountMinor, currency = e.currency, merchant = e.merchant, category = e.categoryRaw,
        paymentChannel = e.paymentChannelRaw, fundingAccount = e.fundingAccount, fundingInstrument = e.fundingInstrument,
        accountId = idOrNull(e.accountId), paymentSource = e.paymentSourceRaw, date = ts(e.date), notes = e.notes,
        transactionReference = e.transactionReference, sourceType = e.sourceTypeRaw, paidByMe = e.paidByMe,
        payerId = idOrNull(e.payerId), payerNameSnapshot = e.payerNameSnapshot, splitMethod = e.splitMethodRaw,
        // Left out when empty: the save RPC treats a missing key as null, and older servers never see it.
        splitRule = e.splitRule ?: SPLIT_RULE_MISSING, receiptPath = e.receiptPath, isSampleData = e.isSampleData, createdAt = ts(e.createdAt), updatedAt = ts(e.updatedAt),
        deletedAt = tsOrNull(e.deletedAt),
    )

    /**
     * Row -> Expense. Columns the cloud doesn't have (OCR text, local image, underlying bank, payment method,
     * matching data, confidence, external id) are kept from [base] (the local copy) when given.
     */
    fun fromRow(r: ExpenseRow, base: Expense? = null): Expense {
        val start = base ?: Expense(id = id(r.id), amountMinor = r.amountMinor, date = ms(r.date), createdAt = ms(r.createdAt), updatedAt = ms(r.updatedAt))
        return start.copy(
            id = id(r.id), amountMinor = r.amountMinor, currency = r.currency, merchant = r.merchant, categoryRaw = r.category,
            paymentChannelRaw = r.paymentChannel, fundingAccount = r.fundingAccount, fundingInstrument = r.fundingInstrument,
            accountId = idOrNull(r.accountId), paymentSourceRaw = r.paymentSource ?: start.paymentSourceRaw, date = ms(r.date),
            notes = r.notes, transactionReference = r.transactionReference, sourceTypeRaw = r.sourceType, paidByMe = r.paidByMe,
            payerId = idOrNull(r.payerId), payerNameSnapshot = r.payerNameSnapshot, splitMethodRaw = r.splitMethod,
            splitRule = if (r.splitRule == SPLIT_RULE_MISSING) start.splitRule else r.splitRule, receiptPath = r.receiptPath, isSampleData = r.isSampleData, createdAt = ms(r.createdAt), updatedAt = ms(r.updatedAt),
            deletedAt = msOrNull(r.deletedAt),
        )
    }

    fun toRow(s: ExpenseShare) = ExpenseShareRow(id(s.id), id(s.expenseId), if (s.isMe) null else idOrNull(s.personId), s.isMe,
        s.nameSnapshot, s.amountMinor, s.parts, s.enteredMinor, s.sortIndex, ts(s.createdAt), ts(s.updatedAt), tsOrNull(s.deletedAt))
    fun fromRow(r: ExpenseShareRow) = ExpenseShare(id(r.id), id(r.expenseId), idOrNull(r.personId), r.isMe, r.nameSnapshot, r.amountMinor,
        r.parts, r.enteredMinor, r.sortIndex, ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))

    fun toRow(m: MoneyMovement) = MoneyMovementRow(id(m.id), m.kindRaw, m.directionRaw, m.amountMinor, m.currency, ts(m.date),
        idOrNull(m.personId), m.personNameSnapshot, idOrNull(m.linkedExpenseId), m.linkedExpenseSnapshot, idOrNull(m.accountId),
        idOrNull(m.counterAccountId), m.note, m.transactionReference, m.sourceTypeRaw, m.paymentChannelRaw,
        ts(m.createdAt), ts(m.updatedAt), tsOrNull(m.deletedAt))
    fun fromRow(r: MoneyMovementRow) = MoneyMovement(
        id = id(r.id), kindRaw = r.kind, directionRaw = r.direction, amountMinor = r.amountMinor, currency = r.currency, date = ms(r.date),
        personId = idOrNull(r.personId), personNameSnapshot = r.personNameSnapshot, linkedExpenseId = idOrNull(r.linkedExpenseId),
        linkedExpenseSnapshot = r.linkedExpenseSnapshot, accountId = idOrNull(r.accountId), counterAccountId = idOrNull(r.counterAccountId),
        note = r.note, transactionReference = r.transactionReference, sourceTypeRaw = r.sourceType, paymentChannelRaw = r.paymentChannel,
        createdAt = ms(r.createdAt), updatedAt = ms(r.updatedAt), deletedAt = msOrNull(r.deletedAt),
    )

    fun toRow(a: SettlementAllocation) = SettlementAllocationRow(id(a.id), id(a.groupId), a.kindRaw, idOrNull(a.paymentId),
        idOrNull(a.expenseId), idOrNull(a.loanId), id(a.personId), a.direction, a.amountMinor, a.currency, ts(a.date),
        ts(a.createdAt), ts(a.updatedAt), tsOrNull(a.deletedAt))
    fun fromRow(r: SettlementAllocationRow) = SettlementAllocation(
        id = id(r.id), groupId = id(r.groupId), kindRaw = r.kind, paymentId = idOrNull(r.paymentId), expenseId = idOrNull(r.expenseId),
        loanId = idOrNull(r.loanId), personId = id(r.personId), direction = r.direction, amountMinor = r.amountMinor, currency = r.currency,
        date = ms(r.date), createdAt = ms(r.createdAt), updatedAt = ms(r.updatedAt), deletedAt = msOrNull(r.deletedAt),
    )

    fun toRow(r: ClassificationRule) = ClassificationRuleRow(id(r.id), r.merchantKey, r.categoryRaw, r.suggestedTypeRaw,
        idOrNull(r.accountId), r.hitCount, ts(r.createdAt), ts(r.updatedAt), tsOrNull(r.deletedAt))
    fun fromRow(r: ClassificationRuleRow) = ClassificationRule(id(r.id), r.merchantKey, r.category, r.suggestedType, idOrNull(r.accountId),
        r.hitCount, ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))

    fun toRow(r: ChannelRule) = ChannelRuleRow(id(r.id), r.merchantKey, r.fundingKey, r.channelRaw, r.hitCount,
        ts(r.createdAt), ts(r.updatedAt), tsOrNull(r.deletedAt))
    fun fromRow(r: ChannelRuleRow) = ChannelRule(id(r.id), r.merchantKey, r.fundingKey, r.channel, r.hitCount,
        ms(r.createdAt), ms(r.updatedAt), msOrNull(r.deletedAt))
}
