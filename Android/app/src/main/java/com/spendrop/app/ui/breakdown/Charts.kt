package com.spendrop.app.ui.breakdown

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.theme.SD

data class Bar(val label: String, val value: Long, val color: Color, val description: String)

/**
 * Vertical bars with labels underneath. Scrolls horizontally when there are many bars (30 days). Each bar's value
 * is in its accessibility description, so the chart is readable with TalkBack.
 */
@Composable
fun BarChart(bars: List<Bar>, modifier: Modifier = Modifier, barWidth: Int = 28, height: Int = 140, signed: Boolean = false) {
    val max = bars.maxOfOrNull { kotlin.math.abs(it.value) }?.takeIf { it > 0 } ?: 1L
    val track = SD.colors.tertiary
    Row(
        modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.Bottom,
    ) {
        bars.forEach { b ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(barWidth.dp + 10.dp).semantics(mergeDescendants = true) { contentDescription = b.description }) {
                Canvas(Modifier.width(barWidth.dp).height(height.dp)) {
                    drawRoundRect(track, size = size, cornerRadius = CornerRadius(6f, 6f))
                    val frac = kotlin.math.abs(b.value).toFloat() / max
                    val h = size.height * frac
                    if (h > 0f) drawRoundRect(if (signed && b.value < 0) Color(0xFFFF9500) else b.color, topLeft = Offset(0f, size.height - h), size = Size(size.width, h), cornerRadius = CornerRadius(6f, 6f))
                }
                Text(b.label, style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Clip)
            }
        }
    }
}

data class Slice(val value: Long, val color: Color)

/** Donut chart (category breakdown). The legend beside it carries the numbers. */
@Composable
fun Donut(slices: List<Slice>, description: String, modifier: Modifier = Modifier.size(140.dp)) {
    val total = slices.sumOf { it.value }.takeIf { it > 0 } ?: 1L
    val empty = SD.colors.tertiary
    Box(modifier.semantics { contentDescription = description }) {
        Canvas(Modifier.fillMaxWidth().fillMaxHeight()) {
            val stroke = size.minDimension * 0.18f
            val inset = stroke / 2
            val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
            if (slices.isEmpty()) drawArc(empty, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            var start = -90f
            slices.forEach { sl ->
                val sweep = 360f * sl.value / total
                drawArc(sl.color, start, (sweep - 1.5f).coerceAtLeast(0.5f), false, Offset(inset, inset), arcSize, style = Stroke(stroke))
                start += sweep
            }
        }
    }
}
