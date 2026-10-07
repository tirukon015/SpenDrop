package com.spendrop.app.data.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

// Local-first store. Columns mirror the shared record shape (:core model, cloud tables). Nothing is hard-deleted
// by normal use: deleting sets deleted_at (tombstone) so backups/sync never resurrect or lose data silently.

@Entity(tableName = "expenses", indices = [Index("date"), Index("accountId"), Index("payerId"), Index("deletedAt")])
data class ExpenseEntity(
    @PrimaryKey val id: String,
    val amountMinor: Long,
    val currency: String,
    val merchant: String,
    val categoryRaw: String,
    val fundingAccount: String,
    val accountId: String?,
    val paymentChannelRaw: String,
    val fundingInstrument: String?,
    val paymentSourceRaw: String,
    val underlyingBankRaw: String?,
    val paymentMethodRaw: String?,
    val date: Long,
    val notes: String?,
    val transactionReference: String?,
    val externalTransactionId: String?,
    val matchingStatusRaw: String,
    val matchingConfidence: Double?,
    val sourceTypeRaw: String,
    val ocrText: String?,
    val confidence: Double?,
    val imageRelativePath: String?,
    val receiptPath: String?,
    val isSampleData: Boolean,
    val paidByMe: Boolean,
    val payerId: String?,
    val payerNameSnapshot: String?,
    val splitMethodRaw: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "expense_shares", indices = [Index("expenseId"), Index("personId")])
data class ExpenseShareEntity(
    @PrimaryKey val id: String,
    val expenseId: String,
    val personId: String?,
    val isMe: Boolean,
    val nameSnapshot: String,
    val amountMinor: Long,
    val parts: Int?,
    val enteredMinor: Long?,
    val sortIndex: Int,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "accounts")
data class AccountEntity(
    @PrimaryKey val id: String,
    val name: String,
    val typeRaw: String,
    val currency: String,
    val icon: String?,
    val isArchived: Boolean,
    val sortIndex: Int,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "people")
data class PersonEntity(
    @PrimaryKey val id: String,
    val name: String,
    val notes: String?,
    val isFrequent: Boolean,
    val isArchived: Boolean,
    /** Local-only photo file name (photos are not part of backups on any platform). */
    val photoFile: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "person_payment_methods", indices = [Index("personId")])
data class PaymentMethodEntity(
    @PrimaryKey val id: String,
    val personId: String,
    val paymentTypeRaw: String,
    val provider: String,
    val customProviderName: String?,
    val accountIdentifier: String,
    val label: String?,
    val notes: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "money_movements", indices = [Index("date"), Index("personId"), Index("accountId")])
data class MovementEntity(
    @PrimaryKey val id: String,
    val kindRaw: String,
    val directionRaw: String,
    val amountMinor: Long,
    val currency: String,
    val date: Long,
    val personId: String?,
    val personNameSnapshot: String?,
    val linkedExpenseId: String?,
    val linkedExpenseSnapshot: String?,
    val accountId: String?,
    val counterAccountId: String?,
    val note: String?,
    val transactionReference: String?,
    val sourceTypeRaw: String,
    val paymentChannelRaw: String,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "settlement_allocations", indices = [Index("personId"), Index("groupId")])
data class AllocationEntity(
    @PrimaryKey val id: String,
    val groupId: String,
    val kindRaw: String,
    val paymentId: String?,
    val expenseId: String?,
    val loanId: String?,
    val personId: String,
    val direction: Int,
    val amountMinor: Long,
    val currency: String,
    val date: Long,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "classification_rules", indices = [Index("merchantKey", unique = true)])
data class ClassificationRuleEntity(
    @PrimaryKey val id: String,
    val merchantKey: String,
    val categoryRaw: String?,
    val suggestedTypeRaw: String?,
    val accountId: String?,
    val hitCount: Int,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "channel_rules", indices = [Index(value = ["merchantKey", "fundingKey"], unique = true)])
data class ChannelRuleEntity(
    @PrimaryKey val id: String,
    val merchantKey: String,
    val fundingKey: String,
    val channelRaw: String,
    val hitCount: Int,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

@Entity(tableName = "sample_records")
data class SampleRecordEntity(
    @PrimaryKey val recordId: String,
    val entityRaw: String,
    val createdAt: Long,
)
