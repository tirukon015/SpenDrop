package com.spendrop.core.backup

import kotlinx.serialization.Serializable

/*
 * The SpenDrop backup file (iOS `UserDataBackupService.BackupPayload`, formats 1–4). Field names, optionality and
 * types match the Swift Codable structs exactly. In Kotlin: ids are lower-case UUID strings (written upper case),
 * dates are epoch milliseconds (written as whole-second ISO-8601 UTC), money is minor units except ExpenseDto.amount,
 * which Swift stores as a Double in major units.
 */

typealias SwiftDate = @Serializable(with = SwiftDateSerializer::class) Long
typealias SwiftUuid = @Serializable(with = SwiftUuidSerializer::class) String

@Serializable
data class BackupPayload(
    val version: Int,
    val appName: String = "SpenDrop",
    val accountName: String,
    val exportDate: SwiftDate,
    val expenses: List<ExpenseDto>,
    val paybookProfiles: List<PayBookProfileDto>,
    // Version 2 (absent in version 1 files)
    val accounts: List<AccountDto>? = null,
    val moneyMovements: List<MoneyMovementDto>? = null,
    // Version 3
    val classificationRules: List<ClassificationRuleDto>? = null,
    // Version 4
    val settlementAllocations: List<SettlementAllocationDto>? = null,
    val sampleRecords: List<SampleRecordDto>? = null,
    /** Learned payment channels (optional; absent in older version-4 files). */
    val channelRules: List<ChannelRuleDto>? = null,
) {
    val recordCount: RecordCount
        get() = RecordCount(
            expenses = expenses.size, profiles = paybookProfiles.size, accounts = accounts?.size ?: 0,
            movements = moneyMovements?.size ?: 0, rules = classificationRules?.size ?: 0,
        )

    val isSupportedVersion: Boolean get() = version in SUPPORTED_VERSIONS

    companion object {
        /** 1 = expenses + PayBook. 2 = accounts, movements, splits, payer/account links. 3 = classification rules.
         *  4 = settlements + sample-data register (+ optional channelRules). */
        const val CURRENT_VERSION = 4
        val SUPPORTED_VERSIONS = 1..CURRENT_VERSION
    }
}

/** iOS `RecordCount` (used by the local auto-backup "shrink" guard). */
data class RecordCount(val expenses: Int, val profiles: Int, val accounts: Int, val movements: Int, val rules: Int = 0) {
    /** True when any kind of record would disappear. */
    fun isSmaller(than: RecordCount): Boolean =
        expenses < than.expenses || profiles < than.profiles || accounts < than.accounts ||
            movements < than.movements || rules < than.rules
}

@Serializable
data class ExpenseDto(
    val id: SwiftUuid,
    /** Major units (RM 7.50 = 7.5). */
    val amount: Double,
    val currency: String,
    val merchant: String,
    val categoryRaw: String,
    val paymentSourceRaw: String,
    val underlyingBankRaw: String? = null,
    val paymentMethodRaw: String? = null,
    val date: SwiftDate,
    val notes: String? = null,
    val transactionReference: String? = null,
    val sourceTypeRaw: String,
    val ocrText: String? = null,
    val isSampleData: Boolean,
    val createdAt: SwiftDate,
    val paymentChannelRaw: String? = null,
    /** iOS exports `effectiveFundingAccount` here. */
    val fundingAccount: String? = null,
    val fundingInstrument: String? = null,
    val matchingStatusRaw: String? = null,
    // Phase 0
    val imageRelativePath: String? = null,
    val confidence: Double? = null,
    val externalTransactionId: String? = null,
    val matchingConfidence: Double? = null,
    val updatedAt: SwiftDate? = null,
    // Version 2
    val accountId: SwiftUuid? = null,
    val paidByMe: Boolean? = null,
    val payerId: SwiftUuid? = null,
    val payerNameSnapshot: String? = null,
    val splitMethodRaw: String? = null,
    val shares: List<ExpenseShareDto>? = null,
    /** Hybrid Split rule (optional string; omitted when null, absent in older backups). */
    val splitRule: String? = null,
)

@Serializable
data class ExpenseShareDto(
    val id: SwiftUuid,
    val personId: SwiftUuid? = null,
    val isMe: Boolean,
    val nameSnapshot: String,
    val amountMinor: Long,
    val parts: Int? = null,
    val enteredMinor: Long? = null,
    val sortIndex: Int,
)

@Serializable
data class PayBookMethodDto(
    val id: SwiftUuid,
    val paymentTypeRaw: String,
    val provider: String,
    val customProviderName: String? = null,
    val accountIdentifier: String,
    val label: String? = null,
    val notes: String? = null,
    val createdAt: SwiftDate? = null,
    val updatedAt: SwiftDate? = null,
)

@Serializable
data class PayBookProfileDto(
    val id: SwiftUuid,
    val name: String,
    val notes: String? = null,
    val paymentMethods: List<PayBookMethodDto>,
    val createdAt: SwiftDate? = null,
    val updatedAt: SwiftDate? = null,
    val isFrequent: Boolean? = null,
    val isArchived: Boolean? = null,
)

@Serializable
data class AccountDto(
    val id: SwiftUuid,
    val name: String,
    val typeRaw: String,
    val currency: String,
    val icon: String? = null,
    val isArchived: Boolean,
    val createdAt: SwiftDate,
    val sortIndex: Int,
)

@Serializable
data class MoneyMovementDto(
    val id: SwiftUuid,
    val directionRaw: String,
    val kindRaw: String,
    val amountMinor: Long,
    val currency: String,
    val date: SwiftDate,
    val personId: SwiftUuid? = null,
    val personNameSnapshot: String? = null,
    val linkedExpenseId: SwiftUuid? = null,
    val linkedExpenseSnapshot: String? = null,
    val accountId: SwiftUuid? = null,
    val counterAccountId: SwiftUuid? = null,
    val note: String? = null,
    val transactionReference: String? = null,
    val sourceTypeRaw: String,
    val paymentChannelRaw: String,
    val createdAt: SwiftDate,
    val updatedAt: SwiftDate,
)

@Serializable
data class SettlementAllocationDto(
    val id: SwiftUuid,
    val groupID: SwiftUuid,
    val kindRaw: String,
    val paymentID: SwiftUuid? = null,
    val expenseID: SwiftUuid? = null,
    val loanID: SwiftUuid? = null,
    val personID: SwiftUuid,
    val direction: Int,
    val amountMinor: Long,
    val currency: String,
    val date: SwiftDate,
    val createdAt: SwiftDate,
)

@Serializable
data class SampleRecordDto(
    val recordID: SwiftUuid,
    val entityRaw: String,
    val createdAt: SwiftDate,
)

@Serializable
data class ChannelRuleDto(
    val id: SwiftUuid,
    val merchantKey: String,
    val fundingKey: String,
    val channelRaw: String,
    val hitCount: Int,
    val createdAt: SwiftDate,
    val updatedAt: SwiftDate,
)

@Serializable
data class ClassificationRuleDto(
    val id: SwiftUuid,
    val merchantKey: String,
    val categoryRaw: String? = null,
    val suggestedTypeRaw: String? = null,
    val accountId: SwiftUuid? = null,
    val hitCount: Int,
    val createdAt: SwiftDate,
    val updatedAt: SwiftDate,
)
