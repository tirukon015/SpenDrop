package com.spendrop.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD

/** iOS-style section header: small, bold, upper case, secondary colour. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 18.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text.uppercase(), style = SD.sectionHeader, color = SD.colors.secondaryLabel, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

/** Grouped card (inset grouped list section). */
@Composable
fun SDCard(modifier: Modifier = Modifier, padding: Dp = 0.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(SD.colors.card).padding(padding),
        content = content,
    )
}

@Composable
fun SectionFooter(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
}

@Composable
fun RowDivider(start: Dp = 16.dp) = HorizontalDivider(Modifier.padding(start = start), color = SD.colors.separator.copy(alpha = 0.35f), thickness = 0.5.dp)

/** A tappable list row with optional icon, subtitle, value and chevron. Min height 48dp for touch targets. */
@Composable
fun ListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconTint: Color? = null,
    value: String? = null,
    valueColor: Color? = null,
    titleColor: Color? = null,
    chevron: Boolean = false,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = iconTint ?: SD.colors.blue, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = titleColor ?: SD.colors.label)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
        if (value != null) Text(value, style = MaterialTheme.typography.bodyLarge, color = valueColor ?: SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 8.dp))
        trailing?.invoke()
        if (chevron) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = SD.colors.tertiaryLabel)
    }
}

/** Round tinted icon badge (category / channel / account). */
@Composable
fun IconBadge(icon: ImageVector, tint: Color, size: Dp = 40.dp, contentDescription: String? = null) {
    Box(
        Modifier.size(size).clip(CircleShape).background(tint.copy(alpha = 0.15f)),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription, tint = tint, modifier = Modifier.size(size * 0.5f)) }
}

@Composable
fun InitialsAvatar(initials: String, size: Dp = 40.dp, tint: Color = SD.colors.blue) {
    Box(Modifier.size(size).clip(CircleShape).background(tint.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
        Text(initials, color = tint, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier, action: Pair<String, () -> Unit>? = null) {
    Column(
        modifier.fillMaxWidth().padding(32.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, null, tint = SD.colors.tertiaryLabel, modifier = Modifier.size(52.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = SD.colors.label, textAlign = TextAlign.Center)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = SD.colors.secondaryLabel, textAlign = TextAlign.Center)
        if (action != null) TextButton(onClick = action.second) { Text(action.first) }
    }
}

@Composable
fun ErrorBanner(message: String, modifier: Modifier = Modifier, onRetry: (() -> Unit)? = null) {
    Row(
        modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(Radius.control))
            .background(SD.colors.orange.copy(alpha = 0.14f)).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.ErrorOutline, null, tint = SD.colors.orange)
        Spacer(Modifier.width(10.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = SD.colors.label, modifier = Modifier.weight(1f))
        if (onRetry != null) TextButton(onClick = onRetry) { Text("Retry") }
    }
}

@Composable
fun LoadingState(message: String = "Loading…", modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        CircularProgressIndicator()
        Spacer(Modifier.size(12.dp))
        Text(message, color = SD.colors.secondaryLabel)
    }
}

/** Money text field: decimal keyboard, accepts "12", "12.5", "1,234.50". */
@Composable
fun AmountField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    isError: Boolean = false,
    supporting: String? = null,
    prefix: String = "RM",
) {
    OutlinedTextField(
        value = value,
        onValueChange = { new -> if (new.all { it.isDigit() || it == '.' || it == ',' } && new.count { it == '.' } <= 1) onValueChange(new) },
        label = { Text(label) },
        prefix = { Text("$prefix ") },
        singleLine = true,
        isError = isError,
        supportingText = supporting?.let { { Text(it) } },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = modifier.fillMaxWidth().semantics { contentDescription = label },
        shape = RoundedCornerShape(Radius.field),
    )
}
