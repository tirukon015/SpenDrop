package com.spendrop.app.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        ExpenseEntity::class, ExpenseShareEntity::class, AccountEntity::class, PersonEntity::class, PaymentMethodEntity::class,
        MovementEntity::class, AllocationEntity::class, ClassificationRuleEntity::class, ChannelRuleEntity::class,
        SampleRecordEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class SpenDropDatabase : RoomDatabase() {
    abstract fun finance(): FinanceDao

    companion object {
        fun create(context: Context, inMemory: Boolean = false): SpenDropDatabase {
            val builder = if (inMemory) Room.inMemoryDatabaseBuilder(context, SpenDropDatabase::class.java)
            else Room.databaseBuilder(context, SpenDropDatabase::class.java, "spendrop.db")
            // Never fall back to destructive migration: user data is more important than a schema change.
            return builder.build()
        }
    }
}
