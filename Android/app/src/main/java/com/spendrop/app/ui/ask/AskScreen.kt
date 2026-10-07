package com.spendrop.app.ui.ask

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.spendrop.app.AppContainer
import com.spendrop.app.R
import com.spendrop.app.ai.AnswerBlock
import com.spendrop.app.ai.AskAnswer
import com.spendrop.app.ai.AskApi
import com.spendrop.app.ai.AskError
import com.spendrop.app.ai.AskEvidence
import com.spendrop.app.ai.TxnCard
import com.spendrop.app.cloud.AuthState
import com.spendrop.app.cloud.AuthUser
import com.spendrop.app.data.AiDefaults
import com.spendrop.app.ui.components.ErrorBanner
import com.spendrop.app.ui.components.Fmt
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.theme.Radius
import com.spendrop.app.ui.theme.SD

private val starterQuestions = listOf(
    "How much did I spend this week?",
    "What did I spend most on this month?",
    "Compare this month with last month",
)

/** "Ask SpenDrop": questions about the user's own spending, answered by the shared SpenDrop AI server. */
@Composable
fun AskScreen(container: AppContainer, onBack: () -> Unit, openSignIn: () -> Unit) {
    val vm: AskViewModel = viewModel(factory = AskViewModel.Factory(container))
    val state by vm.state.collectAsState()
    val auth by container.auth.state.collectAsState()
    val showName by container.preferences.aiShowName.collectAsState(AiDefaults.SHOW_NAME)
    val signedIn = auth as? AuthState.SignedIn
    // A new sign-in clears an "expired session" prompt.
    LaunchedEffect(signedIn?.user?.id) { if (signedIn != null) vm.clearSignIn() }
    val needsSignIn = signedIn == null || state.signInMessage != null

    SDScreen(
        title = "Ask SpenDrop",
        onBack = onBack,
        actions = {
            if (state.turns.isNotEmpty()) TextButton(onClick = vm::newChat, modifier = Modifier.testTag("askNewChat")) { Text("New chat") }
        },
        bottomBar = {
            if (!needsSignIn) Composer(enabled = !state.sending, onSend = vm::send)
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                auth is AuthState.NotConfigured -> Notice(AskError.NotAvailable.message!!, null, null)
                needsSignIn -> Notice(state.signInMessage ?: AskError.SIGN_IN_MESSAGE, "Sign In", openSignIn)
                else -> Conversation(state, greetingName(signedIn.user, showName), vm::send, vm::retry)
            }
        }
    }
}

/** First name, or the part of the email before "@"; null when the user turned "Show My Name" off. */
fun greetingName(user: AuthUser?, showName: Boolean): String? {
    if (!showName || user == null) return null
    user.name?.trim()?.split(Regex("\\s+"))?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { return it }
    return user.email?.substringBefore('@')?.takeIf { it.isNotBlank() }
}

@Composable
private fun Notice(message: String, action: String?, onAction: (() -> Unit)?) {
    Column(
        Modifier.fillMaxSize().padding(32.dp).testTag("askSignIn"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Robot(96)
        Spacer(Modifier.height(16.dp))
        Text(message, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, color = SD.colors.label)
        Spacer(Modifier.height(8.dp))
        Text("Your transactions stay on this phone and keep working without an account.", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, textAlign = TextAlign.Center)
        if (action != null && onAction != null) {
            Spacer(Modifier.height(20.dp))
            Button(onClick = onAction) { Text(action) }
        }
    }
}

@Composable
private fun Robot(sizeDp: Int) {
    Image(painterResource(R.drawable.spendrop_robot), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(sizeDp.dp))
}

@Composable
private fun Conversation(state: AskUiState, name: String?, send: (String) -> Unit, retry: (Long) -> Unit) {
    val list = rememberLazyListState()
    LaunchedEffect(state.turns.size, state.turns.lastOrNull()?.loading) {
        if (state.turns.isNotEmpty()) list.animateScrollToItem(state.turns.size)
    }
    LazyColumn(state = list, modifier = Modifier.fillMaxSize().testTag("askConversation"), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 16.dp)) {
        item { Greeting(name, if (state.turns.isEmpty()) send else null) }
        items(state.turns, key = { it.id }) { turn ->
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
                UserBubble(turn.question)
                Spacer(Modifier.height(8.dp))
                when {
                    turn.loading -> Thinking()
                    turn.answer != null -> AnswerCard(turn.answer, onFollowUp = if (!state.sending) send else null)
                    turn.error != null -> ErrorBanner(turn.error, Modifier.padding(horizontal = 0.dp), onRetry = if (state.signInMessage == null) ({ retry(turn.id) }) else null)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Greeting(name: String?, starter: ((String) -> Unit)?) {
    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Robot(80)
        Spacer(Modifier.height(8.dp))
        Text(if (name != null) "Hi $name!" else "Hi there!", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("askGreeting"))
        Text("Ask about your spending in your own words.", color = SD.colors.secondaryLabel, textAlign = TextAlign.Center)
        if (starter != null) {
            Spacer(Modifier.height(12.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
                starterQuestions.forEach { q -> SuggestionChip(onClick = { starter(q) }, label = { Text(q) }) }
            }
        }
    }
}

@Composable
private fun UserBubble(text: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Text(
            text, color = Color.White,
            modifier = Modifier.widthIn(max = 320.dp).clip(RoundedCornerShape(18.dp, 18.dp, 4.dp, 18.dp)).background(SD.colors.blue).padding(horizontal = 14.dp, vertical = 10.dp),
        )
    }
}

@Composable
private fun Thinking() {
    Row(Modifier.padding(8.dp).semantics(mergeDescendants = true) { contentDescription = "SpenDrop AI is thinking" }, verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(10.dp))
        Text("Thinking…", color = SD.colors.secondaryLabel)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AnswerCard(a: AskAnswer, onFollowUp: ((String) -> Unit)?) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(SD.colors.card).padding(14.dp).testTag("askAnswer"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        a.preface?.takeIf { it.isNotBlank() }?.let { Text(it, color = SD.colors.secondaryLabel) }
        if (a.text.isNotBlank()) Text(a.text, style = MaterialTheme.typography.bodyLarge, color = if (a.status == "error" || a.status == "refused") SD.colors.secondaryLabel else SD.colors.label)
        a.understoodAs?.takeIf { it.isNotBlank() }?.let {
            Text("I read this as “$it”", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
        a.blocks.forEach { Block(it) }
        a.insight?.takeIf { it.isNotBlank() }?.let { Callout(Icons.Filled.AutoAwesome, "Insight", it, SD.colors.purple) }
        a.suggestion?.takeIf { it.isNotBlank() }?.let { Callout(Icons.Filled.Lightbulb, "Suggestion", it, SD.colors.orange) }
        a.evidence.firstOrNull()?.let { EvidenceFooter(it) }
        if (a.followUps.isNotEmpty() && onFollowUp != null) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                a.followUps.take(4).forEach { q -> SuggestionChip(onClick = { onFollowUp(q) }, label = { Text(q) }) }
            }
        }
    }
}

@Composable
private fun Callout(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, text: String, tint: Color) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control)).background(tint.copy(alpha = 0.12f)).padding(10.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Column {
            Text(title, style = MaterialTheme.typography.labelMedium, color = tint, fontWeight = FontWeight.SemiBold)
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** "Based on 12 transactions · This week" — how the answer was calculated. */
fun evidenceLine(e: AskEvidence): String = listOf(
    "Based on ${e.transactionCount} transaction${if (e.transactionCount == 1) "" else "s"}",
    e.period, e.filters,
).map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" · ")

@Composable
private fun EvidenceFooter(e: AskEvidence) {
    HorizontalDivider(color = SD.colors.separator.copy(alpha = 0.35f), thickness = 0.5.dp)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.Info, null, tint = SD.colors.tertiaryLabel, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text(evidenceLine(e), style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
    }
}

/** Server currencies are ISO codes; SpenDrop shows ringgit as "RM" everywhere. Amounts are never recalculated here. */
fun askMoney(minor: Long, currency: String): String = Fmt.money(minor, if (currency.equals("MYR", ignoreCase = true)) "RM" else currency)
private fun askSigned(minor: Long, currency: String): String = (if (minor > 0) "+" else "") + askMoney(minor, currency)

@Composable
private fun Block(b: AnswerBlock) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control)).background(SD.colors.groupedBackground).padding(10.dp)) {
        when (b) {
            is AnswerBlock.Metric -> {
                Text(b.label, style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel)
                Text(askMoney(b.valueMinor, b.currency), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                b.caption?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel) }
            }
            is AnswerBlock.Comparison -> {
                Row(Modifier.fillMaxWidth()) {
                    listOf(b.a, b.b).forEach { side ->
                        Column(Modifier.weight(1f)) {
                            Text(side.label, style = MaterialTheme.typography.labelMedium, color = SD.colors.secondaryLabel, maxLines = 2)
                            Text(askMoney(side.valueMinor, b.currency), fontWeight = FontWeight.SemiBold)
                            Text("${side.count} transaction${if (side.count == 1) "" else "s"}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))
                val pct = b.pct?.let { " (" + (if (it > 0) "+" else "") + "%.0f%%".format(it) + ")" }.orEmpty()
                Text("Difference ${askSigned(b.diffMinor, b.currency)}$pct", style = MaterialTheme.typography.bodyMedium,
                    color = if (b.diffMinor > 0) SD.colors.orange else SD.colors.green)
            }
            is AnswerBlock.Breakdown -> {
                Text(b.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                b.items.take(8).forEach { item ->
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(item.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${item.count} transaction${if (item.count == 1) "" else "s"}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(askMoney(item.valueMinor, b.currency), fontWeight = FontWeight.SemiBold)
                            item.diffMinor?.let { Text(askSigned(it, b.currency), style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel) }
                        }
                    }
                }
                if (b.items.size > 8) Text("+${b.items.size - 8} more", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 4.dp))
            }
            is AnswerBlock.Transactions -> {
                Text(b.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                b.items.forEach { TxnRow(it) }
                b.more?.takeIf { it > 0 }?.let { Text("+$it more", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 4.dp)) }
            }
            is AnswerBlock.Findings -> {
                Text(b.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                b.items.forEach { f ->
                    Column(Modifier.padding(top = 6.dp)) {
                        Text(f.title, fontWeight = FontWeight.Medium)
                        if (f.detail.isNotBlank()) Text(f.detail, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
                    }
                }
            }
        }
    }
}

@Composable
private fun TxnRow(t: TxnCard) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(t.merchant.ifBlank { "Transaction" }, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
            val details = listOf("${t.localDate} ${t.localTime}".trim(), t.category, t.fundingAccount).filter { it.isNotBlank() }.joinToString(" · ")
            Text(details, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(askMoney(t.amountMinor, t.currency), fontWeight = FontWeight.SemiBold)
            if (t.spendMinor != t.amountMinor) Text("Your share ${askMoney(t.spendMinor, t.currency)}", style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel)
        }
    }
}

@Composable
private fun Composer(enabled: Boolean, onSend: (String) -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    val canSend = enabled && text.isNotBlank()
    val submit = { if (canSend) { onSend(text); text = "" } }
    Row(
        Modifier.fillMaxWidth().background(SD.colors.card).imePadding().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = text, onValueChange = { text = it.take(AskApi.MAX_MESSAGE) },
            placeholder = { Text("Ask about your spending…") },
            modifier = Modifier.weight(1f).testTag("askInput"), maxLines = 4,
            shape = RoundedCornerShape(20.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { submit() }),
        )
        Spacer(Modifier.width(8.dp))
        FilledIconButton(onClick = submit, enabled = canSend, modifier = Modifier.size(48.dp).testTag("askSend")) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
        }
    }
}
