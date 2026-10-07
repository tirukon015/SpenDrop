package com.spendrop.app.ui.breakdown

import androidx.compose.foundation.Canvas
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.drawText
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.background
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

/** One x position. [values] are drawn side by side (e.g. Money In / Money Out) in [colors]. */
data class Bar(val label: String, val values: List<Long>, val colors: List<Color>, val description: String) {
    constructor(label: String, value: Long, color: Color, description: String) : this(label, listOf(value), listOf(color), description)
}

/** Round axis steps (1, 2, 2.5, 5 × 10ⁿ) so the gridlines land on readable amounts, like Swift Charts. */
private fun niceStep(maxMinor: Long, lines: Int = 4): Long {
    val raw = (maxMinor.toDouble() / lines).coerceAtLeast(1.0)
    val magnitude = Math.pow(10.0, Math.floor(Math.log10(raw)))
    val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).first { it * magnitude >= raw } * magnitude
    return step.toLong().coerceAtLeast(1L)
}

/** Axis label in whole ringgit: 0, 50, 1.2k. */
private fun axisLabel(minor: Long): String {
    val rm = minor / 100.0
    return when {
        rm >= 1000 -> (if (rm % 1000 == 0.0) "%.0fk" else "%.1fk").format(rm / 1000)
        rm % 1 == 0.0 -> "%.0f".format(rm)
        else -> "%.1f".format(rm)
    }
}

/**
 * Bar chart drawn like the iOS (Swift Charts) one: gradient bars with rounded corners and no background track,
 * light horizontal gridlines with amounts on a fixed left axis, labels underneath. When the bars don't fit (30 days)
 * the plot scrolls horizontally and starts at the latest day. Each bar's value is in its accessibility description.
 */
@Composable
fun BarChart(bars: List<Bar>, modifier: Modifier = Modifier, slotWidth: Dp = 32.dp, height: Dp = 180.dp, legend: List<Pair<String, Color>> = emptyList()) {
    val maxValue = bars.flatMap { it.values }.maxOrNull()?.coerceAtLeast(0L) ?: 0L
    val step = niceStep(maxOf(maxValue, 100L))
    val ticks = (0..((maxOf(maxValue, 1L) + step - 1) / step).toInt()).map { it * step }
    val top = ticks.last().toFloat().coerceAtLeast(1f)
    val grid = SD.colors.separator.copy(alpha = 0.5f)
    val labelColor = SD.colors.secondaryLabel
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = labelColor)
    val labelHeight = 18.dp
    val plotHeight = height - labelHeight
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth()) {
            // Fixed y axis (amounts)
            Canvas(Modifier.width(36.dp).height(height)) {
                val ph = plotHeight.toPx()
                ticks.forEach { t ->
                    val y = ph - ph * (t / top)
                    val layout = measurer.measure(axisLabel(t), labelStyle)
                    drawText(layout, topLeft = Offset(size.width - layout.size.width - 6.dp.toPx(), (y - layout.size.height / 2f).coerceIn(0f, ph - layout.size.height / 2f)))
                }
            }
            BoxWithConstraints(Modifier.weight(1f)) {
                val fits = maxWidth >= slotWidth * bars.size
                val slot = if (fits && bars.isNotEmpty()) maxWidth / bars.size else slotWidth
                val scroll = rememberScrollState()
                LaunchedEffect(bars.size, fits) { if (!fits) scroll.scrollTo(scroll.maxValue) }
                Box(Modifier.horizontalScroll(scroll, enabled = !fits)) {
                    val width = slot * bars.size
                    Canvas(Modifier.width(width).height(height)) {
                        val ph = plotHeight.toPx()
                        val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx()))
                        ticks.forEach { t ->
                            val y = ph - ph * (t / top)
                            drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f, pathEffect = if (t == 0L) null else dash)
                        }
                        val slotPx = slot.toPx()
                        bars.forEachIndexed { i, b ->
                            val groupWidth = slotPx * 0.62f
                            val each = groupWidth / b.values.size
                            val left = i * slotPx + (slotPx - groupWidth) / 2f
                            b.values.forEachIndexed { k, v ->
                                if (v <= 0) return@forEachIndexed
                                val h = ph * (v / top)
                                val color = b.colors.getOrElse(k) { b.colors.last() }
                                val x = left + k * each + (if (b.values.size > 1) each * 0.06f else 0f)
                                val w = if (b.values.size > 1) each * 0.88f else each
                                drawRoundRect(
                                    Brush.verticalGradient(listOf(lerp(color, Color.White, 0.28f), color), startY = ph - h, endY = ph),
                                    topLeft = Offset(x, ph - h), size = Size(w, h),
                                    cornerRadius = CornerRadius(minOf(5.dp.toPx(), w / 2f, h / 2f)),
                                )
                            }
                            val layout = measurer.measure(b.label, labelStyle, maxLines = 1, overflow = TextOverflow.Clip)
                            drawText(layout, topLeft = Offset(i * slotPx + (slotPx - layout.size.width) / 2f, ph + 3.dp.toPx()))
                        }
                    }
                    // One accessible element per bar
                    Row(Modifier.width(width).height(height)) {
                        bars.forEach { b -> Box(Modifier.width(slot).height(height).semantics { contentDescription = b.description }) }
                    }
                }
            }
        }
        if (legend.isNotEmpty()) Row(Modifier.padding(start = 36.dp, top = 6.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            legend.forEach { (name, color) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(color))
                    Text(name, style = MaterialTheme.typography.labelSmall, color = labelColor, modifier = Modifier.padding(start = 4.dp))
                }
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
