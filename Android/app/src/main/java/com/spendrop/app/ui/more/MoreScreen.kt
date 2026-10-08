package com.spendrop.app.ui.more

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.ui.platform.testTag
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.theme.SD

/** Home for secondary features (iOS MoreView): Ask SpenDrop, Account, Accounts, Settings. */
@Composable
fun MoreScreen(openAccount: () -> Unit, openAccounts: () -> Unit, openSettings: () -> Unit, openAsk: () -> Unit = {}) {
    SDScreen(title = "More") { padding ->
        LazyColumn(contentPadding = padding) {
            item {
                SDCard { ListRow("Ask SpenDrop", subtitle = "Ask SpenDrop AI about your spending", icon = Icons.Filled.AutoAwesome, iconTint = SD.colors.purple, chevron = true, onClick = openAsk, modifier = Modifier.testTag("moreAskSpenDrop")) }
                Spacer(Modifier.height(16.dp))
                SDCard { ListRow("Account", subtitle = "Optional sign-in for cloud backup", icon = Icons.Filled.AccountCircle, chevron = true, onClick = openAccount) }
                Spacer(Modifier.height(16.dp))
                SDCard { ListRow("Bank Accounts", subtitle = "Banks, e-wallets and cash · money in and out", icon = Icons.Filled.AccountBalance, chevron = true, onClick = openAccounts) }
                Spacer(Modifier.height(16.dp))
                SDCard { ListRow("Settings", subtitle = "Backup & restore, preferences, diagnostics, about", icon = Icons.Filled.Settings, iconTint = SD.colors.gray, chevron = true, onClick = openSettings) }
            }
        }
    }
}
