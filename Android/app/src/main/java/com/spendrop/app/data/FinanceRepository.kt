package com.spendrop.app.data

import androidx.room.withTransaction
import com.spendrop.app.data.db.SpenDropDatabase
import com.spendrop.app.data.db.toEntity
import com.spendrop.app.data.db.toModel
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/** A set of record writes applied atomically. Deletes are expressed as records with `deletedAt` set. */
data class Changes(
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
    val removeSampleRecordIds: List<String> = emptyList(),
) {
    val isEmpty: Boolean
        get() = expenses.isEmpty() && shares.isEmpty() && accounts.isEmpty() && people.isEmpty() && paymentMethods.isEmpty() &&
            movements.isEmpty() && allocations.isEmpty() && classificationRules.isEmpty() && channelRules.isEmpty() &&
            sampleRecords.isEmpty() && removeSampleRecordIds.isEmpty()

    operator fun plus(o: Changes) = Changes(
        expenses + o.expenses, shares + o.shares, accounts + o.accounts, people + o.people, paymentMethods + o.paymentMethods,
        movements + o.movements, allocations + o.allocations, classificationRules + o.classificationRules,
        channelRules + o.channelRules, sampleRecords + o.sampleRecords, removeSampleRecordIds + o.removeSampleRecordIds,
    )
}

class FinanceRepository(private val db: SpenDropDatabase, scope: CoroutineScope) {
    private val dao = db.finance()

    /** Every live record, recomputed whenever anything changes. Calculations run on this immutable snapshot. */
    val snapshot: StateFlow<FinanceSnapshot?> = combine(
        listOf(
            dao.observeExpenses(), dao.observeShares(), dao.observeAccounts(), dao.observePeople(), dao.observePaymentMethods(),
            dao.observeMovements(), dao.observeAllocations(), dao.observeClassificationRules(), dao.observeChannelRules(),
            dao.observeSampleRecords(),
        ),
    ) { arr ->
        @Suppress("UNCHECKED_CAST")
        FinanceSnapshot(
            expenses = (arr[0] as List<com.spendrop.app.data.db.ExpenseEntity>).map { it.toModel() },
            shares = (arr[1] as List<com.spendrop.app.data.db.ExpenseShareEntity>).map { it.toModel() },
            accounts = (arr[2] as List<com.spendrop.app.data.db.AccountEntity>).map { it.toModel() },
            people = (arr[3] as List<com.spendrop.app.data.db.PersonEntity>).map { it.toModel() },
            paymentMethods = (arr[4] as List<com.spendrop.app.data.db.PaymentMethodEntity>).map { it.toModel() },
            movements = (arr[5] as List<com.spendrop.app.data.db.MovementEntity>).map { it.toModel() },
            allocations = (arr[6] as List<com.spendrop.app.data.db.AllocationEntity>).map { it.toModel() },
            classificationRules = (arr[7] as List<com.spendrop.app.data.db.ClassificationRuleEntity>).map { it.toModel() },
            channelRules = (arr[8] as List<com.spendrop.app.data.db.ChannelRuleEntity>).map { it.toModel() },
            sampleRecords = (arr[9] as List<com.spendrop.app.data.db.SampleRecordEntity>).map { it.toModel() },
        )
    }.stateIn(scope, SharingStarted.Eagerly, null)

    val people = snapshot.map { it?.people.orEmpty() }

    suspend fun apply(changes: Changes) {
        if (changes.isEmpty) return
        db.withTransaction {
            if (changes.accounts.isNotEmpty()) dao.upsertAccounts(changes.accounts.map { it.toEntity() })
            if (changes.people.isNotEmpty()) {
                // keep the local-only photo when a person record is updated
                val photos = changes.people.associate { it.id to dao.person(it.id)?.photoFile }
                dao.upsertPeople(changes.people.map { it.toEntity(photos[it.id]) })
            }
            if (changes.paymentMethods.isNotEmpty()) dao.upsertPaymentMethods(changes.paymentMethods.map { it.toEntity() })
            if (changes.expenses.isNotEmpty()) dao.upsertExpenses(changes.expenses.map { it.toEntity() })
            if (changes.shares.isNotEmpty()) dao.upsertShares(changes.shares.map { it.toEntity() })
            if (changes.movements.isNotEmpty()) dao.upsertMovements(changes.movements.map { it.toEntity() })
            if (changes.allocations.isNotEmpty()) dao.upsertAllocations(changes.allocations.map { it.toEntity() })
            if (changes.classificationRules.isNotEmpty()) dao.upsertClassificationRules(changes.classificationRules.map { it.toEntity() })
            if (changes.channelRules.isNotEmpty()) dao.upsertChannelRules(changes.channelRules.map { it.toEntity() })
            if (changes.sampleRecords.isNotEmpty()) dao.upsertSampleRecords(changes.sampleRecords.map { it.toEntity() })
            if (changes.removeSampleRecordIds.isNotEmpty()) dao.deleteSampleRecords(changes.removeSampleRecordIds)
        }
    }

    /**
     * Saves an expense and REPLACES its split: shares not in [shares] are tombstoned (same contract as the
     * cloud RPC save_expense_with_shares). Pass an empty list for a non-shared expense.
     */
    suspend fun saveExpense(expense: Expense, shares: List<ExpenseShare>, extra: Changes = Changes()) {
        require(shares.isEmpty() || shares.sumOf { it.amountMinor } == expense.amountMinor) {
            "Split shares must add up to the expense amount."
        }
        db.withTransaction {
            apply(extra)
            dao.upsertExpenses(listOf(expense.toEntity()))
            if (shares.isEmpty()) dao.tombstoneAllShares(expense.id, expense.updatedAt)
            else {
                dao.tombstoneSharesExcept(expense.id, shares.map { it.id }, expense.updatedAt)
                dao.upsertShares(shares.map { it.copy(expenseId = expense.id, deletedAt = null).toEntity() })
            }
        }
    }

    suspend fun deleteExpense(expense: Expense, now: Long = System.currentTimeMillis()) {
        db.withTransaction {
            dao.upsertExpenses(listOf(expense.copy(deletedAt = now, updatedAt = now).toEntity()))
            dao.tombstoneAllShares(expense.id, now)
        }
    }

    suspend fun expenseShares(expenseId: String): List<ExpenseShare> = dao.sharesOf(expenseId).map { it.toModel() }

    suspend fun personPhoto(personId: String): String? = dao.person(personId)?.photoFile

    suspend fun setPersonPhoto(personId: String, file: String?) {
        val p = dao.person(personId) ?: return
        dao.upsertPeople(listOf(p.copy(photoFile = file)))
    }

    /** Full contents including tombstones (backup export / merges). */
    suspend fun fullSnapshot(includeDeleted: Boolean): FinanceSnapshot {
        fun <T> List<T>.live(deleted: (T) -> Long?) = if (includeDeleted) this else filter { deleted(it) == null }
        return FinanceSnapshot(
            expenses = dao.allExpenses().map { it.toModel() }.live { it.deletedAt },
            shares = dao.allShares().map { it.toModel() }.live { it.deletedAt },
            accounts = dao.allAccounts().map { it.toModel() }.live { it.deletedAt },
            people = dao.allPeople().map { it.toModel() }.live { it.deletedAt },
            paymentMethods = dao.allPaymentMethods().map { it.toModel() }.live { it.deletedAt },
            movements = dao.allMovements().map { it.toModel() }.live { it.deletedAt },
            allocations = dao.allAllocations().map { it.toModel() }.live { it.deletedAt },
            classificationRules = dao.allClassificationRules().map { it.toModel() }.live { it.deletedAt },
            channelRules = dao.allChannelRules().map { it.toModel() }.live { it.deletedAt },
            sampleRecords = dao.allSampleRecords().map { it.toModel() },
        )
    }

    suspend fun eraseAll() = dao.eraseAll()

    /** Writes pulled cloud records. Rules whose key already exists locally under another id are replaced. */
    suspend fun applyPulled(changes: Changes, replacedClassificationRuleIds: List<String>, replacedChannelRuleIds: List<String>) {
        db.withTransaction {
            if (replacedClassificationRuleIds.isNotEmpty()) dao.deleteClassificationRules(replacedClassificationRuleIds)
            if (replacedChannelRuleIds.isNotEmpty()) dao.deleteChannelRules(replacedChannelRuleIds)
            apply(changes)
        }
    }
}
