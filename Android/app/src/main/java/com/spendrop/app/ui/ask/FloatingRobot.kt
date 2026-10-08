package com.spendrop.app.ui.ask

import android.provider.Settings
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.spendrop.app.R

/** True when the user turned animations off (Developer options / Accessibility "Remove animations"). */
fun systemAnimationsOff(context: android.content.Context): Boolean =
    runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)

/**
 * The SpenDrop AI robot that floats over the main tabs. The image is never cropped (Fit, transparent background);
 * it hides itself while the keyboard is open and only bobs (3 dp, ~3.5 s) when system animations are on.
 * Placement (above the bottom bar, clear of a screen's FAB) is decided by the caller.
 */
@Composable
fun FloatingRobot(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    if (WindowInsets.ime.getBottom(density) > 0) return
    val context = LocalContext.current
    val animate = remember { !systemAnimationsOff(context) }
    val size = if (LocalConfiguration.current.screenWidthDp >= 600) 76.dp else 64.dp
    // Read only in the layout phase (offset lambda), so the bobbing never recomposes the screen.
    val lift = if (animate) {
        rememberInfiniteTransition(label = "robotFloat")
            .animateFloat(0f, 1f, infiniteRepeatable(tween(1750, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "robotFloatY")
    } else null
    val liftPx = with(density) { 3.dp.toPx() }
    Box(
        modifier
            .size(size) // ≥ 48 dp touch target
            .offset { IntOffset(0, -((lift?.value ?: 0f) * liftPx).toInt()) }
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "Ask SpenDrop AI" }
            .testTag("floatingRobot"),
        contentAlignment = Alignment.Center,
    ) {
        Image(painterResource(R.drawable.spendrop_robot), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(size))
    }
}
