package com.spendrop.app.ui.transaction

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.components.InitialsAvatar
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Ids
import com.spendrop.core.model.Person

/** Choose a PayBook person, or add a new one by name (iOS PayBookPickerSheet .selectPerson). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonPickerSheet(people: List<Person>, exclude: Set<String>, onDismiss: () -> Unit, onPick: (Person, isNew: Boolean) -> Unit) {
    var query by remember { mutableStateOf("") }
    val term = query.trim().lowercase()
    val list = people.filter { !it.isArchived && it.id !in exclude && (term.isEmpty() || it.name.lowercase().contains(term)) }
        .sortedWith(compareByDescending<Person> { it.isFrequent }.thenBy { it.name.lowercase() })
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = SD.colors.groupedBackground) {
        Column(Modifier.navigationBarsPadding()) {
            Text("Choose Person", style = androidx.compose.material3.MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 16.dp))
            OutlinedTextField(query, { query = it }, placeholder = { Text("Search or type a new name") }, leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true, modifier = Modifier.fillMaxWidth().padding(16.dp))
            LazyColumn {
                if (term.isNotEmpty() && people.none { it.name.trim().equals(query.trim(), true) }) item {
                    ListRow("Add \"${query.trim()}\" to PayBook", icon = Icons.Filled.PersonAdd, onClick = {
                        val now = System.currentTimeMillis()
                        onPick(Person(Ids.new(), query.trim(), createdAt = now, updatedAt = now), true)
                    })
                }
                items(list, key = { it.id }) { p ->
                    Row { ListRow(p.name, subtitle = if (p.isFrequent) "Frequent" else null, onClick = { onPick(p, false) }, trailing = null, icon = null) }
                }
                if (list.isEmpty() && term.isEmpty()) item {
                    Text("No people in PayBook yet. Type a name to add someone.", color = SD.colors.secondaryLabel, modifier = Modifier.padding(16.dp))
                }
            }
        }
    }
}
