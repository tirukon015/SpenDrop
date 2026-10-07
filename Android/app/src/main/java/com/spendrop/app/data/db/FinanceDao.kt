package com.spendrop.app.data.db

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface FinanceDao {
    // Live (non-deleted) observation. Tombstones are kept for backups/sync but never shown.
    @Query("SELECT * FROM expenses WHERE deletedAt IS NULL ORDER BY date DESC") fun observeExpenses(): Flow<List<ExpenseEntity>>
    @Query("SELECT * FROM expense_shares WHERE deletedAt IS NULL") fun observeShares(): Flow<List<ExpenseShareEntity>>
    @Query("SELECT * FROM accounts WHERE deletedAt IS NULL ORDER BY sortIndex, name") fun observeAccounts(): Flow<List<AccountEntity>>
    @Query("SELECT * FROM people WHERE deletedAt IS NULL ORDER BY name COLLATE NOCASE") fun observePeople(): Flow<List<PersonEntity>>
    @Query("SELECT * FROM person_payment_methods WHERE deletedAt IS NULL") fun observePaymentMethods(): Flow<List<PaymentMethodEntity>>
    @Query("SELECT * FROM money_movements WHERE deletedAt IS NULL ORDER BY date DESC") fun observeMovements(): Flow<List<MovementEntity>>
    @Query("SELECT * FROM settlement_allocations WHERE deletedAt IS NULL") fun observeAllocations(): Flow<List<AllocationEntity>>
    @Query("SELECT * FROM classification_rules WHERE deletedAt IS NULL") fun observeClassificationRules(): Flow<List<ClassificationRuleEntity>>
    @Query("SELECT * FROM channel_rules WHERE deletedAt IS NULL") fun observeChannelRules(): Flow<List<ChannelRuleEntity>>
    @Query("SELECT * FROM sample_records") fun observeSampleRecords(): Flow<List<SampleRecordEntity>>

    // Everything including tombstones (backups, merges, sync).
    @Query("SELECT * FROM expenses") suspend fun allExpenses(): List<ExpenseEntity>
    @Query("SELECT * FROM expense_shares") suspend fun allShares(): List<ExpenseShareEntity>
    @Query("SELECT * FROM accounts") suspend fun allAccounts(): List<AccountEntity>
    @Query("SELECT * FROM people") suspend fun allPeople(): List<PersonEntity>
    @Query("SELECT * FROM person_payment_methods") suspend fun allPaymentMethods(): List<PaymentMethodEntity>
    @Query("SELECT * FROM money_movements") suspend fun allMovements(): List<MovementEntity>
    @Query("SELECT * FROM settlement_allocations") suspend fun allAllocations(): List<AllocationEntity>
    @Query("SELECT * FROM classification_rules") suspend fun allClassificationRules(): List<ClassificationRuleEntity>
    @Query("SELECT * FROM channel_rules") suspend fun allChannelRules(): List<ChannelRuleEntity>
    @Query("SELECT * FROM sample_records") suspend fun allSampleRecords(): List<SampleRecordEntity>

    @Query("SELECT * FROM expenses WHERE id = :id") suspend fun expense(id: String): ExpenseEntity?
    @Query("SELECT * FROM expense_shares WHERE expenseId = :expenseId AND deletedAt IS NULL ORDER BY sortIndex") suspend fun sharesOf(expenseId: String): List<ExpenseShareEntity>
    @Query("SELECT * FROM people WHERE id = :id") suspend fun person(id: String): PersonEntity?
    @Query("SELECT COUNT(*) FROM expenses WHERE deletedAt IS NULL") suspend fun liveExpenseCount(): Int

    @Upsert suspend fun upsertExpenses(items: List<ExpenseEntity>)
    @Upsert suspend fun upsertShares(items: List<ExpenseShareEntity>)
    @Upsert suspend fun upsertAccounts(items: List<AccountEntity>)
    @Upsert suspend fun upsertPeople(items: List<PersonEntity>)
    @Upsert suspend fun upsertPaymentMethods(items: List<PaymentMethodEntity>)
    @Upsert suspend fun upsertMovements(items: List<MovementEntity>)
    @Upsert suspend fun upsertAllocations(items: List<AllocationEntity>)
    @Upsert suspend fun upsertClassificationRules(items: List<ClassificationRuleEntity>)
    @Upsert suspend fun upsertChannelRules(items: List<ChannelRuleEntity>)
    @Upsert suspend fun upsertSampleRecords(items: List<SampleRecordEntity>)

    @Query("UPDATE expense_shares SET deletedAt = :now, updatedAt = :now WHERE expenseId = :expenseId AND deletedAt IS NULL AND id NOT IN (:keepIds)")
    suspend fun tombstoneSharesExcept(expenseId: String, keepIds: List<String>, now: Long)

    @Query("UPDATE expense_shares SET deletedAt = :now, updatedAt = :now WHERE expenseId = :expenseId AND deletedAt IS NULL")
    suspend fun tombstoneAllShares(expenseId: String, now: Long)

    @Query("DELETE FROM sample_records WHERE recordId IN (:ids)") suspend fun deleteSampleRecords(ids: List<String>)

    // Sync: a learned rule is unique per merchant key (and funding key). When the cloud already has a rule for the
    // same key under another id, the local copy is replaced by the cloud one.
    @Query("DELETE FROM classification_rules WHERE id IN (:ids)") suspend fun deleteClassificationRules(ids: List<String>)
    @Query("DELETE FROM channel_rules WHERE id IN (:ids)") suspend fun deleteChannelRules(ids: List<String>)

    /** Signing out of a different account / "Erase local data": wipes this device's copy only. */
    @Transaction
    suspend fun eraseAll() {
        eraseExpenses(); eraseShares(); eraseAccounts(); erasePeople(); eraseMethods(); eraseMovements(); eraseAllocations()
        eraseCRules(); eraseChRules(); eraseSamples()
    }
    @Query("DELETE FROM expenses") suspend fun eraseExpenses()
    @Query("DELETE FROM expense_shares") suspend fun eraseShares()
    @Query("DELETE FROM accounts") suspend fun eraseAccounts()
    @Query("DELETE FROM people") suspend fun erasePeople()
    @Query("DELETE FROM person_payment_methods") suspend fun eraseMethods()
    @Query("DELETE FROM money_movements") suspend fun eraseMovements()
    @Query("DELETE FROM settlement_allocations") suspend fun eraseAllocations()
    @Query("DELETE FROM classification_rules") suspend fun eraseCRules()
    @Query("DELETE FROM channel_rules") suspend fun eraseChRules()
    @Query("DELETE FROM sample_records") suspend fun eraseSamples()
}
