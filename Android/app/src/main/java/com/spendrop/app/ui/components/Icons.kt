package com.spendrop.app.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Contactless
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Wallet
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.PaymentChannel

val ExpenseCategory.icon: ImageVector
    get() = when (this) {
        ExpenseCategory.FOOD -> Icons.Filled.Restaurant
        ExpenseCategory.GROCERIES -> Icons.Filled.ShoppingCart
        ExpenseCategory.TRANSPORT -> Icons.Filled.DirectionsCar
        ExpenseCategory.SHOPPING -> Icons.Filled.ShoppingBag
        ExpenseCategory.BILLS -> Icons.Filled.Bolt
        ExpenseCategory.ENTERTAINMENT -> Icons.Filled.Tv
        ExpenseCategory.EDUCATION -> Icons.AutoMirrored.Filled.MenuBook
        ExpenseCategory.HEALTH -> Icons.Filled.Favorite
        ExpenseCategory.TRAVEL -> Icons.Filled.Flight
        ExpenseCategory.PERSONAL -> Icons.Filled.Person
        ExpenseCategory.SUBSCRIPTION -> Icons.Filled.Autorenew
        ExpenseCategory.OTHER -> Icons.Filled.MoreHoriz
    }

/** Category tint names from Common/Constants/categories.json. */
val ExpenseCategory.tintName: String
    get() = when (this) {
        ExpenseCategory.FOOD -> "orange"; ExpenseCategory.GROCERIES -> "green"; ExpenseCategory.TRANSPORT -> "blue"
        ExpenseCategory.SHOPPING -> "pink"; ExpenseCategory.BILLS -> "red"; ExpenseCategory.ENTERTAINMENT -> "purple"
        ExpenseCategory.EDUCATION -> "indigo"; ExpenseCategory.HEALTH -> "mint"; ExpenseCategory.TRAVEL -> "teal"
        ExpenseCategory.PERSONAL -> "cyan"; ExpenseCategory.SUBSCRIPTION -> "yellow"; ExpenseCategory.OTHER -> "gray"
    }

val ExpenseCategory.color: Color @Composable get() = SD.colors.named(tintName)

val PaymentChannel.icon: ImageVector
    get() = when (this) {
        PaymentChannel.APPLE_PAY -> Icons.Filled.Contactless
        PaymentChannel.QR_PAYMENT, PaymentChannel.TNG_QR -> Icons.Filled.QrCode
        PaymentChannel.DUITNOW_QR -> Icons.Filled.QrCodeScanner
        PaymentChannel.BANK_TRANSFER -> Icons.Filled.SwapHoriz
        PaymentChannel.ONLINE_BANKING -> Icons.Filled.Language
        PaymentChannel.CARD -> Icons.Filled.CreditCard
        PaymentChannel.E_WALLET -> Icons.Filled.PhoneAndroid
        PaymentChannel.CASH -> Icons.Filled.Payments
        PaymentChannel.OTHER -> Icons.Filled.MoreHoriz
        PaymentChannel.UNKNOWN -> Icons.AutoMirrored.Filled.HelpOutline
    }

val PaymentChannel.tintName: String
    get() = when (this) {
        PaymentChannel.APPLE_PAY -> "primary"; PaymentChannel.QR_PAYMENT -> "indigo"; PaymentChannel.DUITNOW_QR -> "pink"
        PaymentChannel.TNG_QR -> "blue"; PaymentChannel.BANK_TRANSFER -> "teal"; PaymentChannel.ONLINE_BANKING -> "cyan"
        PaymentChannel.CARD -> "purple"; PaymentChannel.E_WALLET -> "blue"; PaymentChannel.CASH -> "green"
        PaymentChannel.OTHER -> "orange"; PaymentChannel.UNKNOWN -> "gray"
    }

val PaymentChannel.color: Color @Composable get() = SD.colors.named(tintName)

val AccountType.icon: ImageVector
    get() = when (this) {
        AccountType.BANK -> Icons.Filled.AccountBalance
        AccountType.E_WALLET -> Icons.Filled.AccountBalanceWallet
        AccountType.CASH -> Icons.Filled.Payments
        AccountType.OTHER -> Icons.Filled.Wallet
    }
