package com.spendrop.app.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences as DsPreferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore("spendrop_settings")

/** Small user preferences (iOS @AppStorage equivalents). Financial records never live here. */
class Preferences(private val context: Context) {
    object Keys {
        val appearance = stringPreferencesKey("user_appearance")
        val currency = stringPreferencesKey("app_currency")
        val breakdownMode = stringPreferencesKey("breakdown_mode")
        val deviceId = stringPreferencesKey("device_id")
        val cloudBackupUser = stringPreferencesKey("cloud_backup_enabled_user")
        val dailyBackupEnabled = booleanPreferencesKey("daily_backup_enabled")
        val dailyBackupMinutes = intPreferencesKey("daily_backup_minutes")
        val retentionDays = intPreferencesKey("backup_retention_days")
        val lastBackupHash = stringPreferencesKey("last_backup_hash")
        val lastBackupAt = stringPreferencesKey("last_backup_at")
        val lastAutoBackupDay = stringPreferencesKey("last_auto_backup_day")
        val lastBackupMessage = stringPreferencesKey("last_backup_message")
        val ownerUserId = stringPreferencesKey("local_data_owner")
        val syncUser = stringPreferencesKey("cloud_sync_enabled_user")
        val syncPushWatermark = stringPreferencesKey("cloud_sync_push_watermark")
        val syncLastAt = stringPreferencesKey("cloud_sync_last_at")
        val syncLastMessage = stringPreferencesKey("cloud_sync_last_message")
        fun syncCursor(table: String) = stringPreferencesKey("cloud_sync_cursor_$table")
        /** SpenDrop AI: the floating robot on the main tabs (default ON). */
        val aiFloatingAssistant = booleanPreferencesKey("ai_floating_assistant")
        /** SpenDrop AI: greet with the user's name on the Ask screen (default ON). Display only. */
        val aiShowName = booleanPreferencesKey("ai_show_name")
    }

    val data: Flow<DsPreferences> = context.dataStore.data

    fun string(key: DsPreferences.Key<String>, default: String): Flow<String> = data.map { it[key] ?: default }
    fun <T> flow(key: DsPreferences.Key<T>): Flow<T?> = data.map { it[key] }
    suspend fun <T> get(key: DsPreferences.Key<T>): T? = data.first()[key]
    suspend fun <T> set(key: DsPreferences.Key<T>, value: T?) {
        context.dataStore.edit { if (value == null) it.remove(key) else it[key] = value }
    }

    fun bool(key: DsPreferences.Key<Boolean>, default: Boolean): Flow<Boolean> = data.map { it[key] ?: default }

    /** SpenDrop AI display settings. They change only what the AI shows on screen, never sign-in or data. */
    val aiFloatingAssistant: Flow<Boolean> get() = bool(Keys.aiFloatingAssistant, AiDefaults.FLOATING_ASSISTANT)
    val aiShowName: Flow<Boolean> get() = bool(Keys.aiShowName, AiDefaults.SHOW_NAME)

    /** Stable random id for this installation (cloud backup folder `<user>/<device id>/`). */
    suspend fun deviceId(): String = get(Keys.deviceId) ?: java.util.UUID.randomUUID().toString().uppercase().also { set(Keys.deviceId, it) }
}

/** Defaults for the SpenDrop AI settings (both ON, like iOS and the Web). */
object AiDefaults {
    const val FLOATING_ASSISTANT = true
    const val SHOW_NAME = true
}
