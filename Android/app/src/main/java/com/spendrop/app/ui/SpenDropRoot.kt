package com.spendrop.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.spendrop.app.AppContainer
import com.spendrop.app.cloud.EmailLinkResult
import com.spendrop.app.importing.Intake
import com.spendrop.app.ui.account.AccountNav
import com.spendrop.app.ui.account.AccountScreen
import com.spendrop.app.ui.account.CloudRestoreScreen
import com.spendrop.app.ui.account.EmailAuthForm
import com.spendrop.app.ui.account.EmailAuthMode
import com.spendrop.app.ui.account.NewPasswordForm
import com.spendrop.app.ui.account.RestoreRangeScreen
import com.spendrop.app.ui.accounts.AccountDetailScreen
import com.spendrop.app.ui.accounts.AccountsNav
import com.spendrop.app.ui.accounts.AccountsScreen
import com.spendrop.app.ui.accounts.UnlinkedMovementsScreen
import com.spendrop.app.ui.breakdown.BreakdownScreen
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.home.HomeNav
import com.spendrop.app.ui.home.HomeScreen
import com.spendrop.app.ui.importing.ImportFlowScreen
import com.spendrop.app.ui.importing.rememberImportPickers
import com.spendrop.app.ui.more.MoreScreen
import com.spendrop.app.ui.more.ParserSelfTestScreen
import com.spendrop.app.ui.more.SettingsScreen
import com.spendrop.app.ui.nav.*
import com.spendrop.app.ui.paybook.PaymentMethodEditScreen
import com.spendrop.app.ui.paybook.PayBookScreen
import com.spendrop.app.ui.paybook.PersonDetailScreen
import com.spendrop.app.ui.paybook.PersonEditScreen
import com.spendrop.app.ui.paybook.PersonNav
import com.spendrop.app.ui.transaction.EditorMode
import com.spendrop.app.ui.transaction.TransactionEditorScreen
import com.spendrop.app.ui.transactions.ExpenseDetailScreen
import com.spendrop.app.ui.transactions.TransactionsNav
import com.spendrop.app.ui.transactions.TransactionsScreen
import kotlin.reflect.KClass

private data class Tab(val route: Any, val cls: KClass<*>, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab(HomeRoute, HomeRoute::class, "Home", Icons.Filled.Home),
    Tab(TransactionsRoute, TransactionsRoute::class, "Transactions", Icons.AutoMirrored.Filled.ListAlt),
    Tab(PayBookRoute, PayBookRoute::class, "PayBook", Icons.Filled.Contacts),
    Tab(BreakdownRoute, BreakdownRoute::class, "Breakdown", Icons.Filled.BarChart),
    Tab(MoreRoute, MoreRoute::class, "More", Icons.Filled.MoreHoriz),
)

/** App shell: five tabs (same as iOS) and every destination. */
@Composable
fun SpenDropRoot(container: AppContainer) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val dest = entry?.destination
    val onTab = tabs.any { t -> dest?.hasRoute(t.cls) == true }
    val pickers = rememberImportPickers { uris -> container.pendingImports.set(uris); nav.navigate(ImportRoute) }
    val link by container.links.latest.collectAsState()
    val awaitingPassword by container.auth.awaitingNewPassword.collectAsState()

    Scaffold(bottomBar = {
        if (onTab) NavigationBar {
            tabs.forEach { t ->
                NavigationBarItem(
                    selected = dest?.hasRoute(t.cls) == true,
                    onClick = {
                        nav.navigate(t.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true; restoreState = true
                        }
                    },
                    icon = { Icon(t.icon, null) }, label = { Text(t.label) },
                )
            }
        }
    }) { outer ->
        NavHost(nav, startDestination = HomeRoute, modifier = Modifier.padding(bottom = outer.calculateBottomPadding()).consumeWindowInsets(outer)) {
            val openExpense: (String) -> Unit = { nav.navigate(ExpenseDetailRoute(it)) }
            val openMovement: (String) -> Unit = { nav.navigate(MovementEditRoute(it)) }
            composable<HomeRoute> {
                HomeScreen(container, pickers, HomeNav(add = { nav.navigate(AddTransactionRoute()) }, quickCash = { nav.navigate(AddTransactionRoute(quickCash = true)) }, openExpense = openExpense))
            }
            composable<TransactionsRoute> { TransactionsScreen(container, TransactionsNav({ nav.navigate(AddTransactionRoute()) }, openExpense, openMovement)) }
            composable<PayBookRoute> { PayBookScreen(container, { nav.navigate(PersonDetailRoute(it)) }, { nav.navigate(PersonEditRoute()) }) }
            composable<BreakdownRoute> { BreakdownScreen(container) }
            composable<MoreRoute> { MoreScreen({ nav.navigate(AccountRoute) }, { nav.navigate(AccountsRoute) }, { nav.navigate(SettingsRoute) }) }

            composable<AddTransactionRoute> { e ->
                val r = e.toRoute<AddTransactionRoute>()
                TransactionEditorScreen(container, EditorMode.New(r.entryType, r.quickCash, r.purpose, r.kind, r.personId, r.currency, r.amountMinor),
                    onClose = { nav.popBackStack() }, onScanInstead = { nav.popBackStack(); pickers.photos() })
            }
            composable<EditExpenseRoute> { e -> TransactionEditorScreen(container, EditorMode.EditExpense(e.toRoute<EditExpenseRoute>().expenseId), onClose = { nav.popBackStack() }) }
            composable<MovementEditRoute> { e -> TransactionEditorScreen(container, EditorMode.EditMovement(e.toRoute<MovementEditRoute>().movementId), onClose = { nav.popBackStack() }) }
            composable<ExpenseDetailRoute> { e -> ExpenseDetailScreen(container, e.toRoute<ExpenseDetailRoute>().expenseId, { nav.popBackStack() }, { nav.navigate(EditExpenseRoute(it)) }) }

            composable<PersonDetailRoute> { e ->
                PersonDetailScreen(container, e.toRoute<PersonDetailRoute>().personId, PersonNav(
                    back = { nav.popBackStack() }, edit = { nav.navigate(PersonEditRoute(it)) },
                    editMethod = { p, m -> nav.navigate(PaymentMethodEditRoute(p, m)) }, openExpense = openExpense, openMovement = openMovement,
                    newMovement = { kind, pid, cur, amt -> nav.navigate(AddTransactionRoute(kind = kind.raw, personId = pid, currency = cur, amountMinor = amt)) },
                ))
            }
            composable<PersonEditRoute> { e ->
                val r = e.toRoute<PersonEditRoute>()
                PersonEditScreen(container, r.personId) { saved ->
                    nav.popBackStack()
                    if (r.personId == null && saved != null) nav.navigate(PersonDetailRoute(saved))
                }
            }
            composable<PaymentMethodEditRoute> { e -> val r = e.toRoute<PaymentMethodEditRoute>(); PaymentMethodEditScreen(container, r.personId, r.methodId) { nav.popBackStack() } }

            val accountsNav = AccountsNav({ nav.popBackStack() }, { nav.navigate(AccountDetailRoute(it)) }, { nav.navigate(UnlinkedMovementsRoute) }, openExpense, openMovement)
            composable<AccountsRoute> { AccountsScreen(container, accountsNav) }
            composable<AccountDetailRoute> { e -> AccountDetailScreen(container, e.toRoute<AccountDetailRoute>().accountId, accountsNav) }
            composable<UnlinkedMovementsRoute> { UnlinkedMovementsScreen(container, accountsNav) }

            composable<AccountRoute> { AccountScreen(container, AccountNav({ nav.popBackStack() }, { nav.navigate(EmailAuthRoute(it.name)) }, { nav.navigate(CloudRestoreRoute) })) }
            composable<EmailAuthRoute> { e ->
                val mode = EmailAuthMode.valueOf(e.toRoute<EmailAuthRoute>().mode)
                SDScreen(title = mode.title, onBack = { nav.popBackStack() }) { p ->
                    androidx.compose.foundation.layout.Box(Modifier.padding(p)) { EmailAuthForm(container.auth, mode) { nav.popBackStack() } }
                }
            }
            composable<NewPasswordRoute> {
                SDScreen(title = "Set New Password", onBack = { nav.popBackStack() }) { p ->
                    androidx.compose.foundation.layout.Box(Modifier.padding(p)) { NewPasswordForm(container.auth) { nav.popBackStack() } }
                }
            }
            composable<CloudRestoreRoute> { CloudRestoreScreen(container, { nav.popBackStack() }) { nav.navigate(RestoreRangeRoute("cloud")) } }
            composable<RestoreRangeRoute> { RestoreRangeScreen(container, { nav.popBackStack() }) { nav.popBackStack() } }
            composable<SettingsRoute> { SettingsScreen(container, { nav.popBackStack() }, { nav.navigate(RestoreRangeRoute("file")) }, { nav.navigate(ParserSelfTestRoute) }) }
            composable<ParserSelfTestRoute> { ParserSelfTestScreen { nav.popBackStack() } }
            composable<ImportRoute> {
                ImportFlowScreen(container, load = { Intake.fromUris(container.context, container.pendingImports.take()) }, fromShare = false) { nav.popBackStack() }
            }
        }
    }

    androidx.compose.runtime.LaunchedEffect(awaitingPassword) {
        if (awaitingPassword && nav.currentDestination?.hasRoute(NewPasswordRoute::class) != true) nav.navigate(NewPasswordRoute) { launchSingleTop = true }
    }
    link?.let { r ->
        val (title, msg) = when (r) {
            EmailLinkResult.SignedIn -> "Signed In" to "Your SpenDrop account is ready. Cloud backup can be turned on in More → Account."
            EmailLinkResult.VerifiedSignInNeeded -> "Email Verified" to "Your email is verified. Sign in with your email and password."
            EmailLinkResult.PasswordRecovery -> "Choose a New Password" to "Enter a new password for your account."
            is EmailLinkResult.Failed -> "Link Couldn't Be Used" to r.message
        }
        MessageDialog(title, msg) { container.links.consume() }
    }
}
