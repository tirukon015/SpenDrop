package com.spendrop.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** SpenDrop palette (Common/Design/tokens.json — iOS system colours). */
@Immutable
data class SpenDropColors(
    val blue: Color, val green: Color, val indigo: Color, val orange: Color, val pink: Color, val purple: Color,
    val red: Color, val teal: Color, val yellow: Color, val mint: Color, val cyan: Color, val gray: Color, val primary: Color,
    val groupedBackground: Color, val card: Color, val tertiary: Color,
    val label: Color, val secondaryLabel: Color, val tertiaryLabel: Color, val separator: Color,
) {
    fun named(name: String): Color = when (name) {
        "blue" -> blue; "green" -> green; "indigo" -> indigo; "orange" -> orange; "pink" -> pink; "purple" -> purple
        "red" -> red; "teal" -> teal; "yellow" -> yellow; "mint" -> mint; "cyan" -> cyan; "primary" -> primary
        else -> gray
    }
}

val LightColors = SpenDropColors(
    blue = Color(0xFF007AFF), green = Color(0xFF34C759), indigo = Color(0xFF5856D6), orange = Color(0xFFFF9500),
    pink = Color(0xFFFF2D55), purple = Color(0xFFAF52DE), red = Color(0xFFFF3B30), teal = Color(0xFF30B0C7),
    yellow = Color(0xFFFFCC00), mint = Color(0xFF00C7BE), cyan = Color(0xFF32ADE6), gray = Color(0xFF8E8E93), primary = Color.Black,
    groupedBackground = Color(0xFFF2F2F7), card = Color.White, tertiary = Color(0xFFF2F2F7),
    label = Color.Black, secondaryLabel = Color(0x993C3C43), tertiaryLabel = Color(0x4D3C3C43), separator = Color(0x4A3C3C43),
)

val DarkColors = SpenDropColors(
    blue = Color(0xFF0A84FF), green = Color(0xFF30D158), indigo = Color(0xFF5E5CE6), orange = Color(0xFFFF9F0A),
    pink = Color(0xFFFF375F), purple = Color(0xFFBF5AF2), red = Color(0xFFFF453A), teal = Color(0xFF40C8E0),
    yellow = Color(0xFFFFD60A), mint = Color(0xFF63E6E2), cyan = Color(0xFF64D2FF), gray = Color(0xFF8E8E93), primary = Color.White,
    groupedBackground = Color.Black, card = Color(0xFF1C1C1E), tertiary = Color(0xFF2C2C2E),
    label = Color.White, secondaryLabel = Color(0x99EBEBF5), tertiaryLabel = Color(0x4DEBEBF5), separator = Color(0x99545458),
)

val LocalSpenDropColors = staticCompositionLocalOf { LightColors }

object Radius {
    val card = 16.dp
    val field = 14.dp
    val control = 12.dp
}

/** Appearance setting values (same as iOS `user_appearance`). */
enum class Appearance(val raw: String, val label: String) {
    SYSTEM("system", "System"), LIGHT("light", "Light"), DARK("dark", "Dark");
    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SYSTEM }
}

@Composable
fun SpenDropTheme(appearance: Appearance = Appearance.SYSTEM, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        Appearance.SYSTEM -> isSystemInDarkTheme()
        Appearance.LIGHT -> false
        Appearance.DARK -> true
    }
    val c = if (dark) DarkColors else LightColors
    val scheme = if (dark) darkColorScheme(
        primary = c.blue, onPrimary = Color.White, secondary = c.green, background = c.groupedBackground,
        surface = c.card, surfaceVariant = c.tertiary, onSurface = c.label, onBackground = c.label,
        onSurfaceVariant = c.secondaryLabel, error = c.red, outline = c.separator, surfaceContainer = c.card,
        surfaceContainerHigh = c.tertiary, surfaceContainerLow = c.card, surfaceContainerHighest = c.tertiary,
        primaryContainer = c.blue.copy(alpha = 0.25f), onPrimaryContainer = c.label,
        secondaryContainer = c.blue.copy(alpha = 0.22f), onSecondaryContainer = c.label,
    ) else lightColorScheme(
        primary = c.blue, onPrimary = Color.White, secondary = c.green, background = c.groupedBackground,
        surface = c.card, surfaceVariant = c.tertiary, onSurface = c.label, onBackground = c.label,
        onSurfaceVariant = c.secondaryLabel, error = c.red, outline = c.separator, surfaceContainer = c.card,
        surfaceContainerHigh = c.tertiary, surfaceContainerLow = c.card, surfaceContainerHighest = c.tertiary,
        primaryContainer = c.blue.copy(alpha = 0.14f), onPrimaryContainer = c.label,
        secondaryContainer = c.blue.copy(alpha = 0.14f), onSecondaryContainer = c.label,
    )
    val base = Typography()
    val type = base.copy(
        headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.Bold, fontSize = 32.sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    )
    CompositionLocalProvider(LocalSpenDropColors provides c) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}

object SD {
    val colors: SpenDropColors @Composable get() = LocalSpenDropColors.current
    val sectionHeader = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
    val amountLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
}
