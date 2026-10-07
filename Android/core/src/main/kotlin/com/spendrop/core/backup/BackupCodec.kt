package com.spendrop.core.backup

import com.spendrop.core.Ids
import com.spendrop.core.Money
import com.spendrop.core.model.Account
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SampleRecord
import com.spendrop.core.model.SettlementAllocation
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Why a backup file can't be used. Nothing is ever applied when one of these is thrown. */
sealed class BackupException(message: String) : Exception(message) {
    class Unreadable(cause: Throwable? = null) :
        BackupException("This file isn't a SpenDrop backup or it is damaged. Nothing was imported.") { init { cause?.let { initCause(it) } } }

    class UnsupportedVersion(val version: Int) :
        BackupException("This backup was made by a newer version of SpenDrop (format $version). Update the app to restore it. Nothing was restored.")
}

/**
 * Reads and writes SpenDrop backup files byte-compatible with iOS (`UserDataBackupService.makeEncoder/makeDecoder`):
 * pretty printed, sorted keys, `\/`-escaped slashes, whole-second ISO-8601 dates, upper-case UUIDs.
 */
object BackupCodec {
    /** Decoding: unknown keys ignored (forward compatible), missing optionals -> null. */
    val json: Json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    /** Name written to `accountName` when nobody is signed in (never the iOS developer's name). */
    const val DEFAULT_ACCOUNT_NAME = "SpenDrop user"

    fun toJsonElement(payload: BackupPayload): JsonElement = json.encodeToJsonElement(payload)

    /** The file content, exactly like Swift `JSONEncoder` with `[.prettyPrinted, .sortedKeys]` and `.iso8601`. */
    fun encode(payload: BackupPayload): String = SwiftJsonWriter.write(toJsonElement(payload), pretty = true)

    fun encodeToBytes(payload: BackupPayload): ByteArray = encode(payload).toByteArray(Charsets.UTF_8)

    /**
     * Parses a backup file. Throws [BackupException.UnsupportedVersion] for a newer format (checked before the
     * body so a future file is reported clearly) and [BackupException.Unreadable] for anything else.
     */
    fun decode(text: String): BackupPayload {
        val root: JsonObject = try {
            json.parseToJsonElement(text).jsonObject
        } catch (e: Exception) {
            throw BackupException.Unreadable(e)
        }
        val version = try { root["version"]?.jsonPrimitive?.intOrNull } catch (_: Exception) { null }
            ?: throw BackupException.Unreadable()
        if (version !in BackupPayload.SUPPORTED_VERSIONS) throw BackupException.UnsupportedVersion(version)
        return try {
            json.decodeFromJsonElement<BackupPayload>(root)
        } catch (e: Exception) {
            throw BackupException.Unreadable(e)
        }
    }

    fun decode(bytes: ByteArray): BackupPayload = decode(bytes.toString(Charsets.UTF_8))

    // ---------------------------------------------------------------------------------------------------------
    // Export (iOS makePayload): a complete current-format snapshot. Tombstoned records are excluded.
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Builds the current-format (v4) payload of everything in [snapshot] that isn't tombstoned.
     * @param accountName the signed-in email, or [DEFAULT_ACCOUNT_NAME].
     */
    fun makePayload(snapshot: FinanceSnapshot, accountName: String, exportDate: Long): BackupPayload {
        val people = snapshot.people.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id }))
        val methodsByPerson = snapshot.paymentMethods.filter { it.deletedAt == null }
            .sortedWith(compareBy({ it.createdAt }, { it.id })).groupBy { Ids.normalize(it.personId) }
        val sharesByExpense = snapshot.shares.filter { it.deletedAt == null }.groupBy { Ids.normalize(it.expenseId) }
        return BackupPayload(
            version = BackupPayload.CURRENT_VERSION,
            appName = "SpenDrop",
            accountName = accountName,
            exportDate = exportDate,
            expenses = snapshot.expenses.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id }))
                .map { e -> expenseDto(e, sharesByExpense[Ids.normalize(e.id)].orEmpty()) },
            paybookProfiles = people.map { p -> profileDto(p, methodsByPerson[Ids.normalize(p.id)].orEmpty()) },
        ).copy(
            accounts = snapshot.accounts.filter { it.deletedAt == null }.sortedWith(compareBy({ it.sortIndex }, { it.createdAt }, { it.id })).map(::accountDto),
            moneyMovements = snapshot.movements.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id })).map(::movementDto),
            classificationRules = snapshot.classificationRules.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id })).map(::ruleDto),
            settlementAllocations = snapshot.allocations.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id })).map(::allocationDto),
            sampleRecords = snapshot.sampleRecords.sortedWith(compareBy({ it.createdAt }, { it.recordId })).map(::sampleDto),
            channelRules = snapshot.channelRules.filter { it.deletedAt == null }.sortedWith(compareBy({ it.createdAt }, { it.id })).map(::channelRuleDto),
        )
    }

    fun expenseDto(e: Expense, shares: List<ExpenseShare>): ExpenseDto = ExpenseDto(
        id = e.id, amount = Money.major(e.amountMinor), currency = e.currency, merchant = e.merchant,
        categoryRaw = e.categoryRaw, paymentSourceRaw = e.paymentSourceRaw, underlyingBankRaw = e.underlyingBankRaw,
        paymentMethodRaw = e.paymentMethodRaw, date = e.date, notes = e.notes, transactionReference = e.transactionReference,
        sourceTypeRaw = e.sourceTypeRaw, ocrText = e.ocrText, isSampleData = e.isSampleData, createdAt = e.createdAt,
        paymentChannelRaw = e.paymentChannelRaw, fundingAccount = e.effectiveFundingAccount, fundingInstrument = e.fundingInstrument,
        matchingStatusRaw = e.matchingStatusRaw, imageRelativePath = e.imageRelativePath, confidence = e.confidence,
        externalTransactionId = e.externalTransactionId, matchingConfidence = e.matchingConfidence, updatedAt = e.updatedAt,
        accountId = e.accountId, paidByMe = e.paidByMe, payerId = e.payerId, payerNameSnapshot = e.payerNameSnapshot,
        splitMethodRaw = e.splitMethodRaw, splitRule = e.splitRule,
        shares = shares.filter { it.deletedAt == null }.sortedBy { it.sortIndex }.map(::shareDto),
    )

    fun shareDto(s: ExpenseShare) = ExpenseShareDto(
        id = s.id, personId = if (s.isMe) null else s.personId, isMe = s.isMe, nameSnapshot = s.nameSnapshot,
        amountMinor = s.amountMinor, parts = s.parts, enteredMinor = s.enteredMinor, sortIndex = s.sortIndex,
    )

    fun profileDto(p: Person, methods: List<PersonPaymentMethod>) = PayBookProfileDto(
        id = p.id, name = p.name, notes = p.notes, paymentMethods = methods.map(::methodDto),
        createdAt = p.createdAt, updatedAt = p.updatedAt, isFrequent = p.isFrequent, isArchived = p.isArchived,
    )

    fun methodDto(m: PersonPaymentMethod) = PayBookMethodDto(
        id = m.id, paymentTypeRaw = m.paymentTypeRaw, provider = m.provider, customProviderName = m.customProviderName,
        accountIdentifier = m.accountIdentifier, label = m.label, notes = m.notes, createdAt = m.createdAt, updatedAt = m.updatedAt,
    )

    fun accountDto(a: Account) = AccountDto(
        id = a.id, name = a.name, typeRaw = a.typeRaw, currency = a.currency, icon = a.icon, isArchived = a.isArchived,
        createdAt = a.createdAt, sortIndex = a.sortIndex,
    )

    fun movementDto(m: MoneyMovement) = MoneyMovementDto(
        id = m.id, directionRaw = m.directionRaw, kindRaw = m.kindRaw, amountMinor = m.amountMinor, currency = m.currency,
        date = m.date, personId = m.personId, personNameSnapshot = m.personNameSnapshot, linkedExpenseId = m.linkedExpenseId,
        linkedExpenseSnapshot = m.linkedExpenseSnapshot, accountId = m.accountId, counterAccountId = m.counterAccountId,
        note = m.note, transactionReference = m.transactionReference, sourceTypeRaw = m.sourceTypeRaw,
        paymentChannelRaw = m.paymentChannelRaw, createdAt = m.createdAt, updatedAt = m.updatedAt,
    )

    fun allocationDto(a: SettlementAllocation) = SettlementAllocationDto(
        id = a.id, groupID = a.groupId, kindRaw = a.kindRaw, paymentID = a.paymentId, expenseID = a.expenseId, loanID = a.loanId,
        personID = a.personId, direction = a.direction, amountMinor = a.amountMinor, currency = a.currency, date = a.date,
        createdAt = a.createdAt,
    )

    fun sampleDto(r: SampleRecord) = SampleRecordDto(recordID = r.recordId, entityRaw = r.entityRaw, createdAt = r.createdAt)

    fun channelRuleDto(r: ChannelRule) = ChannelRuleDto(
        id = r.id, merchantKey = r.merchantKey, fundingKey = r.fundingKey, channelRaw = r.channelRaw, hitCount = r.hitCount,
        createdAt = r.createdAt, updatedAt = r.updatedAt,
    )

    fun ruleDto(r: ClassificationRule) = ClassificationRuleDto(
        id = r.id, merchantKey = r.merchantKey, categoryRaw = r.categoryRaw, suggestedTypeRaw = r.suggestedTypeRaw,
        accountId = r.accountId, hitCount = r.hitCount, createdAt = r.createdAt, updatedAt = r.updatedAt,
    )
}
