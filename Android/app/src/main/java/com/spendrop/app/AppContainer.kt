package com.spendrop.app

import android.content.Context
import com.spendrop.app.cloud.AuthService
import com.spendrop.app.cloud.KeystoreSecureStore
import com.spendrop.app.cloud.SupabaseConfig
import com.spendrop.app.cloud.SupabaseHttp
import com.spendrop.app.data.FinanceRepository
import com.spendrop.app.data.Preferences
import com.spendrop.app.data.db.SpenDropDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Application-wide singletons (simple manual dependency injection). */
class AppContainer(
    val context: Context,
    private val inMemory: Boolean = false,
    private val secureStore: com.spendrop.app.cloud.SecureStore? = null,
) {
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val database: SpenDropDatabase by lazy { SpenDropDatabase.create(context, inMemory) }
    val repository: FinanceRepository by lazy { FinanceRepository(database, appScope) }
    val preferences: Preferences by lazy { Preferences(context) }
    val supabaseConfig: SupabaseConfig? = SupabaseConfig.of(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_KEY)
    val http: SupabaseHttp? by lazy { supabaseConfig?.let { SupabaseHttp(it) } }
    val auth: AuthService by lazy { AuthService(http, secureStore ?: KeystoreSecureStore(context)) }
    val links = LinkEvents()
    /** SpenDrop AI ("Ask SpenDrop"): the shared server, authorised with this account's Supabase session. */
    val askApi: com.spendrop.app.ai.AskApi by lazy { com.spendrop.app.ai.AskApi(BuildConfig.SPENDROP_API_URL, { auth.validAccessToken() }) }
    val sync: com.spendrop.app.cloud.SyncService by lazy { com.spendrop.app.cloud.SyncService(http, auth, repository, preferences) }
    val localBackup: com.spendrop.app.data.LocalBackup by lazy { com.spendrop.app.data.LocalBackup(context, repository) { auth.currentUser?.email ?: com.spendrop.core.backup.BackupCodec.DEFAULT_ACCOUNT_NAME } }
    /** The backup chosen for restore (cloud or file), handed to the restore-range screen. */
    val restoreSource = kotlinx.coroutines.flow.MutableStateFlow<com.spendrop.app.ui.account.RestoreSource?>(null)
    val cloudBackup: com.spendrop.app.cloud.CloudBackupService by lazy { com.spendrop.app.cloud.CloudBackupService(context, http, auth, repository, preferences) }
    val pendingImports = com.spendrop.app.importing.PendingImports()
    /** One filter state for Transactions and Breakdown (iOS TransactionFilterEngine.shared). */
    val filters = kotlinx.coroutines.flow.MutableStateFlow(com.spendrop.core.insights.TransactionFilters())
}
