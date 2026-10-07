package com.spendrop.app.ui.nav

import kotlinx.serialization.Serializable

// Top-level tabs (same five as iOS: Home, Transactions, PayBook, Breakdown, More)
@Serializable object HomeRoute
@Serializable object TransactionsRoute
@Serializable object PayBookRoute
@Serializable object BreakdownRoute
@Serializable object MoreRoute

// Destinations
/** entryType: "expense" | "moneyIn" | "moneyOut" | "transfer"; quickCash pre-selects Cash. */
@Serializable data class AddTransactionRoute(val entryType: String = "expense", val quickCash: Boolean = false, val purpose: String? = null, val kind: String? = null, val personId: String? = null, val currency: String? = null, val amountMinor: Long? = null)
@Serializable data class EditExpenseRoute(val expenseId: String)
@Serializable data class ExpenseDetailRoute(val expenseId: String)
@Serializable data class MovementEditRoute(val movementId: String)
@Serializable data class PersonDetailRoute(val personId: String)
@Serializable data class PersonEditRoute(val personId: String? = null)
@Serializable data class PaymentMethodEditRoute(val personId: String, val methodId: String? = null)
@Serializable object AccountsRoute
@Serializable data class AccountDetailRoute(val accountId: String)
@Serializable object UnlinkedMovementsRoute
@Serializable object AccountRoute
@Serializable data class EmailAuthRoute(val mode: String)
@Serializable object NewPasswordRoute
@Serializable object SettingsRoute
@Serializable object CloudRestoreRoute
@Serializable data class RestoreRangeRoute(val source: String, val backupId: String? = null)
@Serializable object ParserSelfTestRoute
/** In-app import: the review flow for files the user picked (held by ImportCoordinator). */
@Serializable data class ImportRoute(val fromCamera: Boolean = false)
/** Bulk Screenshot Import: many screenshots → separate transactions in one review queue. */
@Serializable object BulkImportRoute
@Serializable object ReceiptCameraRoute
@Serializable object PermissionsRoute
/** SpenDrop AI chat ("Ask SpenDrop"), reached from More and from the floating robot. Not a tab. */
@Serializable object AskRoute
