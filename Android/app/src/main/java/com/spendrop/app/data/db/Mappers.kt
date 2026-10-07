package com.spendrop.app.data.db

import com.spendrop.core.model.Account
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SampleRecord
import com.spendrop.core.model.SettlementAllocation

fun ExpenseEntity.toModel() = Expense(
    id, amountMinor, currency, merchant, categoryRaw, fundingAccount, accountId, paymentChannelRaw, fundingInstrument,
    paymentSourceRaw, underlyingBankRaw, paymentMethodRaw, date, notes, transactionReference, externalTransactionId,
    matchingStatusRaw, matchingConfidence, sourceTypeRaw, ocrText, confidence, imageRelativePath, receiptPath, isSampleData,
    paidByMe, payerId, payerNameSnapshot, splitMethodRaw, createdAt, updatedAt, deletedAt, splitRule,
)

fun Expense.toEntity() = ExpenseEntity(
    id, amountMinor, currency, merchant, categoryRaw, fundingAccount, accountId, paymentChannelRaw, fundingInstrument,
    paymentSourceRaw, underlyingBankRaw, paymentMethodRaw, date, notes, transactionReference, externalTransactionId,
    matchingStatusRaw, matchingConfidence, sourceTypeRaw, ocrText, confidence, imageRelativePath, receiptPath, isSampleData,
    paidByMe, payerId, payerNameSnapshot, splitMethodRaw, createdAt, updatedAt, deletedAt, splitRule,
)

fun ExpenseShareEntity.toModel() = ExpenseShare(id, expenseId, personId, isMe, nameSnapshot, amountMinor, parts, enteredMinor, sortIndex, createdAt, updatedAt, deletedAt)
fun ExpenseShare.toEntity() = ExpenseShareEntity(id, expenseId, personId, isMe, nameSnapshot, amountMinor, parts, enteredMinor, sortIndex, createdAt, updatedAt, deletedAt)

fun AccountEntity.toModel() = Account(id, name, typeRaw, currency, icon, isArchived, sortIndex, createdAt, updatedAt, deletedAt)
fun Account.toEntity() = AccountEntity(id, name, typeRaw, currency, icon, isArchived, sortIndex, createdAt, updatedAt, deletedAt)

fun PersonEntity.toModel() = Person(id, name, notes, isFrequent, isArchived, createdAt, updatedAt, deletedAt)
fun Person.toEntity(photoFile: String? = null) = PersonEntity(id, name, notes, isFrequent, isArchived, photoFile, createdAt, updatedAt, deletedAt)

fun PaymentMethodEntity.toModel() = PersonPaymentMethod(id, personId, paymentTypeRaw, provider, customProviderName, accountIdentifier, label, notes, createdAt, updatedAt, deletedAt)
fun PersonPaymentMethod.toEntity() = PaymentMethodEntity(id, personId, paymentTypeRaw, provider, customProviderName, accountIdentifier, label, notes, createdAt, updatedAt, deletedAt)

fun MovementEntity.toModel() = MoneyMovement(
    id, kindRaw, directionRaw, amountMinor, currency, date, personId, personNameSnapshot, linkedExpenseId, linkedExpenseSnapshot,
    accountId, counterAccountId, note, transactionReference, sourceTypeRaw, paymentChannelRaw, createdAt, updatedAt, deletedAt,
)
fun MoneyMovement.toEntity() = MovementEntity(
    id, kindRaw, directionRaw, amountMinor, currency, date, personId, personNameSnapshot, linkedExpenseId, linkedExpenseSnapshot,
    accountId, counterAccountId, note, transactionReference, sourceTypeRaw, paymentChannelRaw, createdAt, updatedAt, deletedAt,
)

fun AllocationEntity.toModel() = SettlementAllocation(id, groupId, kindRaw, paymentId, expenseId, loanId, personId, direction, amountMinor, currency, date, createdAt, updatedAt, deletedAt)
fun SettlementAllocation.toEntity() = AllocationEntity(id, groupId, kindRaw, paymentId, expenseId, loanId, personId, direction, amountMinor, currency, date, createdAt, updatedAt, deletedAt)

fun ClassificationRuleEntity.toModel() = ClassificationRule(id, merchantKey, categoryRaw, suggestedTypeRaw, accountId, hitCount, createdAt, updatedAt, deletedAt)
fun ClassificationRule.toEntity() = ClassificationRuleEntity(id, merchantKey, categoryRaw, suggestedTypeRaw, accountId, hitCount, createdAt, updatedAt, deletedAt)

fun ChannelRuleEntity.toModel() = ChannelRule(id, merchantKey, fundingKey, channelRaw, hitCount, createdAt, updatedAt, deletedAt)
fun ChannelRule.toEntity() = ChannelRuleEntity(id, merchantKey, fundingKey, channelRaw, hitCount, createdAt, updatedAt, deletedAt)

fun SampleRecordEntity.toModel() = SampleRecord(recordId, entityRaw, createdAt)
fun SampleRecord.toEntity() = SampleRecordEntity(recordId, entityRaw, createdAt)
