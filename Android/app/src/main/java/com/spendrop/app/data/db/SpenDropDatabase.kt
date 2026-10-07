package com.spendrop.app.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        ExpenseEntity::class, ExpenseShareEntity::class, AccountEntity::class, PersonEntity::class, PaymentMethodEntity::class,
        MovementEntity::class, AllocationEntity::class, ClassificationRuleEntity::class, ChannelRuleEntity::class,
        SampleRecordEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
abstract class SpenDropDatabase : RoomDatabase() {
    abstract fun finance(): FinanceDao

    companion object {
        fun create(context: Context, inMemory: Boolean = false): SpenDropDatabase {
            val builder = if (inMemory) Room.inMemoryDatabaseBuilder(context, SpenDropDatabase::class.java)
            else Room.databaseBuilder(context, SpenDropDatabase::class.java, "spendrop.db")
            // Never fall back to destructive migration: user data is more important than a schema change.
            return builder.addMigrations(MIGRATION_1_2).build()
        }

        /** v2: the Hybrid Split rule on expenses. Additive; existing rows stay null (a normal split). */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE expenses ADD COLUMN splitRule TEXT")
            }
        }
    }
}
