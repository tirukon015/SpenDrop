package com.spendrop.app.ui.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.theme.SD

/** iOS segmented picker equivalent. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> Segmented(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        options.forEachIndexed { i, o ->
            SegmentedButton(
                selected = o == selected,
                onClick = { onSelect(o) },
                shape = SegmentedButtonDefaults.itemShape(i, options.size),
                icon = {},
                label = { Text(label(o), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
}

/** Horizontally scrolling chips (funding accounts, channels, filters). */
@Composable
fun <T> ChipRow(
    options: List<T>,
    isSelected: (T) -> Boolean,
    label: (T) -> String,
    onClick: (T) -> Unit,
    icon: ((T) -> ImageVector)? = null,
    selectedColor: (T) -> Color? = { null },
    modifier: Modifier = Modifier,
) {
    Row(modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { o ->
            val sel = isSelected(o)
            val c = selectedColor(o) ?: SD.colors.blue
            FilterChip(
                selected = sel,
                onClick = { onClick(o) },
                label = { Text(label(o)) },
                leadingIcon = icon?.let { f -> { Icon(f(o), null, Modifier.padding(0.dp)) } },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = c, selectedLabelColor = Color.White, selectedLeadingIconColor = Color.White,
                    containerColor = SD.colors.card,
                ),
            )
        }
    }
}
