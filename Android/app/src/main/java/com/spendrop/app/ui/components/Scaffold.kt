package com.spendrop.app.ui.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.style.TextOverflow
import com.spendrop.app.ui.theme.SD

/**
 * Standard SpenDrop screen: grouped background, large title on top-level tabs (like iOS large titles), small title
 * with Back on pushed screens. [onBack] null = no back arrow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SDScreen(
    title: String,
    onBack: (() -> Unit)? = null,
    large: Boolean = onBack == null,
    actions: @Composable RowScope.() -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    snackbar: SnackbarHostState = remember { SnackbarHostState() },
    content: @Composable (PaddingValues) -> Unit,
) {
    val colors = TopAppBarDefaults.topAppBarColors(containerColor = SD.colors.groupedBackground, scrolledContainerColor = SD.colors.groupedBackground)
    val scroll = if (large) TopAppBarDefaults.exitUntilCollapsedScrollBehavior() else TopAppBarDefaults.pinnedScrollBehavior()
    val nav: @Composable () -> Unit = {
        if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
    }
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = SD.colors.groupedBackground,
        topBar = {
            if (large) LargeTopAppBar(title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) }, navigationIcon = nav, actions = actions, colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = SD.colors.groupedBackground, scrolledContainerColor = SD.colors.groupedBackground), scrollBehavior = scroll)
            else TopAppBar(title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) }, navigationIcon = nav, actions = actions, colors = colors, scrollBehavior = scroll)
        },
        floatingActionButton = floatingActionButton,
        bottomBar = bottomBar,
        snackbarHost = { SnackbarHost(snackbar) },
        content = content,
    )
}
