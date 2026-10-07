package com.spendrop.app.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.spendrop.app.ui.theme.SD
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

/** Date + time of a transaction in the device's time zone (iOS DatePicker with date and time). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeField(millis: Long, onChange: (Long) -> Unit, label: String, showTime: Boolean = true, modifier: Modifier = Modifier) {
    val zone = ZoneId.systemDefault()
    val local = Instant.ofEpochMilli(millis).atZone(zone)
    var pickDate by remember { mutableStateOf(false) }
    var pickTime by remember { mutableStateOf(false) }
    // Label above the date/time buttons so neither is squeezed on narrow phones.
    androidx.compose.foundation.layout.Column(modifier.fillMaxWidth()) {
        Text(label, color = SD.colors.secondaryLabel, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium)
        Row(verticalAlignment = Alignment.CenterVertically) {
            AssistChip(onClick = { pickDate = true }, label = { Text(Fmt.date(millis), maxLines = 1) }, leadingIcon = { Icon(Icons.Filled.CalendarMonth, null) })
            if (showTime) AssistChip(onClick = { pickTime = true }, label = { Text(Fmt.time(millis), maxLines = 1) }, leadingIcon = { Icon(Icons.Filled.Schedule, null) }, modifier = Modifier.padding(start = 8.dp))
        }
    }
    if (pickDate) {
        // The Material date picker works in UTC days: convert the local calendar day both ways.
        val state = rememberDatePickerState(initialSelectedDateMillis = local.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickDate = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { utc ->
                        val day = Instant.ofEpochMilli(utc).atZone(ZoneOffset.UTC).toLocalDate()
                        onChange(day.atTime(local.toLocalTime()).atZone(zone).toInstant().toEpochMilli())
                    }
                    pickDate = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { pickDate = false }) { Text("Cancel") } },
        ) { DatePicker(state) }
    }
    if (pickTime) {
        val state = rememberTimePickerState(local.hour, local.minute)
        AlertDialog(
            onDismissRequest = { pickTime = false },
            confirmButton = {
                TextButton(onClick = {
                    onChange(local.toLocalDate().atTime(LocalTime.of(state.hour, state.minute)).atZone(zone).toInstant().toEpochMilli())
                    pickTime = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { pickTime = false }) { Text("Cancel") } },
            text = { TimePicker(state) },
        )
    }
}

/** A calendar day (no time), as epoch millis of local midnight. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayField(day: LocalDate, onChange: (LocalDate) -> Unit, label: String) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        AssistChip(onClick = { open = true }, label = { Text(Fmt.date(day.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli())) })
    }
    if (open) {
        val state = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { open = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                    open = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
        ) { DatePicker(state) }
    }
}
