package com.spendrop.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.finance.ExpenseMath
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind

/** One expense (iOS ExpenseRowView): category badge, merchant, category • funding • channel, amount, date. */
@Composable
fun ExpenseRow(expense: Expense, shares: List<ExpenseShare>, payerName: String?, onClick: () -> Unit) {
    val shared = shares.isNotEmpty()
    val my = ExpenseMath.myShareMinor(expense, shares)
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val cat = expense.category
        Box(Modifier.size(42.dp).clip(RoundedCornerShape(12.dp)).background(cat.color.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
            Icon(cat.icon, cat.displayName, tint = cat.color, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(expense.merchant, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (expense.isReconciled) Icon(Icons.Filled.Verified, "Reconciled", tint = SD.colors.green, modifier = Modifier.padding(start = 4.dp).size(14.dp))
                if (shared) {
                    Icon(Icons.Filled.Group, "Shared", tint = SD.colors.blue, modifier = Modifier.padding(start = 6.dp).size(14.dp))
                    Text("${shares.size}", style = MaterialTheme.typography.labelSmall, color = SD.colors.blue)
                }
            }
            Text(
                "${cat.displayName} • ${expense.displayFundingAndChannel}",
                style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            expense.notes?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = SD.colors.tertiaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(start = 8.dp)) {
            Text(Fmt.money(if (expense.paidByMe) expense.amountMinor else my, expense.currency), fontWeight = FontWeight.SemiBold)
            if (shared) {
                Text(
                    if (expense.paidByMe) "You ${Fmt.money(my, expense.currency)}" else "Paid by ${payerName ?: expense.payerNameSnapshot ?: "someone"}",
                    style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel,
                )
            }
            Text(Fmt.date(expense.date), style = MaterialTheme.typography.labelSmall, color = SD.colors.secondaryLabel)
        }
    }
}

/** One money movement (iOS MovementRow). [timelineStyle]: transfers shown as "Not spending". */
@Composable
fun MovementRow(
    movement: MoneyMovement,
    accountName: (String?) -> String?,
    personName: String?,
    incoming: Boolean = movement.direction == MoneyDirection.IN,
    timelineStyle: Boolean = false,
    onClick: () -> Unit,
) {
    val transfer = movement.kind == MoneyMovementKind.OWN_TRANSFER
    val neutral = timelineStyle && transfer
    val date = Fmt.date(movement.date)
    val title = when {
        transfer -> "${accountName(movement.accountId) ?: "?"} → ${accountName(movement.counterAccountId) ?: "?"}"
        (personName ?: movement.personNameSnapshot) != null -> (if (movement.direction == MoneyDirection.IN) "From " else "To ") + (personName ?: movement.personNameSnapshot)
        else -> movement.note ?: movement.kind.displayName
    }
    val subtitle = when {
        transfer -> if (timelineStyle) "Transfer · Not spending · $date" else "${movement.kind.displayName} · $date"
        timelineStyle && accountName(movement.accountId) != null -> "${movement.kind.displayName} · ${accountName(movement.accountId)} · $date"
        else -> "${movement.kind.displayName} · $date"
    }
    val tint = when { transfer -> SD.colors.gray; incoming -> SD.colors.green; else -> SD.colors.orange }
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(
            if (transfer) Icons.Filled.SwapHoriz else if (incoming) Icons.AutoMirrored.Filled.CallReceived else Icons.AutoMirrored.Filled.CallMade,
            tint, size = 42.dp, contentDescription = movement.kind.displayName,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = SD.colors.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(
            (if (neutral) "" else if (incoming) "+" else "-") + Fmt.money(movement.amountMinor, movement.currency),
            fontWeight = FontWeight.SemiBold,
            color = if (neutral) SD.colors.secondaryLabel else if (incoming) SD.colors.green else SD.colors.label,
            modifier = Modifier.padding(start = 8.dp),
        )
    }
}
