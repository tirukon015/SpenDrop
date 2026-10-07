package com.spendrop.app.ui.paybook

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.spendrop.app.ui.components.RowDivider
import com.spendrop.app.ui.theme.SD
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.spendrop.core.model.PaymentMethodType

/** Editable payment method values (shared by Add Person and the payment method form). */
data class MethodForm(
    val type: PaymentMethodType = PaymentMethodType.BANK_ACCOUNT,
    val provider: String = PaymentMethodType.commonProviders.first(),
    val customProvider: String = "",
    val identifier: String = "",
    val label: String = "",
    val notes: String = "",
) {
    val isOther: Boolean get() = provider.equals("Other", true)
    val isValid: Boolean get() = identifier.isNotBlank() && (!isOther || customProvider.isNotBlank())
    val normalizedIdentifier: String get() = identifier.filter { it.isLetterOrDigit() }.lowercase()
}

/** One payment method as inline form rows (type, provider, number, label, notes) for use inside an [SDCard]. */
@Composable
fun MethodFields(form: MethodForm, onChange: (MethodForm) -> Unit) {
    Column {
        FormPickerRow("Type", PaymentMethodType.entries, form.type, { it.raw }) { onChange(form.copy(type = it)) }
        RowDivider()
        FormPickerRow("Provider", PaymentMethodType.commonProviders, form.provider, { it }) { onChange(form.copy(provider = it)) }
        if (form.isOther) {
            RowDivider()
            FormFieldRow("Name", form.customProvider, "Bank or e-wallet name", tag = "customProvider") { onChange(form.copy(customProvider = it)) }
        }
        RowDivider()
        FormFieldRow(
            form.type.identifierFieldLabel.removeSuffix(" *").replace("Account Number", "Account No."), form.identifier, "Required", tag = "accountNumber",
            keyboard = if (form.type == PaymentMethodType.BANK_ACCOUNT) KeyboardType.Number else KeyboardType.Text,
        ) { onChange(form.copy(identifier = it)) }
        RowDivider()
        FormFieldRow("Label", form.label, "e.g. Personal, Business", tag = "methodLabel") { onChange(form.copy(label = it)) }
        RowDivider()
        FormFieldRow("Notes", form.notes, "Optional", singleLine = false, tag = "methodNotes") { onChange(form.copy(notes = it)) }
    }
}

/** Width of the label column of inline form rows. */
private val FormLabelWidth = 112.dp

/** An inline form row: label on the left, borderless text field on the right (iOS-style grouped form). */
@Composable
fun FormFieldRow(
    label: String, value: String, placeholder: String, modifier: Modifier = Modifier, singleLine: Boolean = true, tag: String? = null,
    keyboard: KeyboardType = KeyboardType.Text, capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    onValueChange: (String) -> Unit,
) {
    Row(modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = if (singleLine) Alignment.CenterVertically else Alignment.Top) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = SD.colors.label, maxLines = 2, modifier = Modifier.width(FormLabelWidth))
        BasicTextField(
            value = value, onValueChange = onValueChange, singleLine = singleLine, maxLines = if (singleLine) 1 else 4,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = SD.colors.label),
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, capitalization = capitalization),
            cursorBrush = SolidColor(SD.colors.blue),
            modifier = Modifier.weight(1f).semantics { contentDescription = label }.let { if (tag != null) it.testTag(tag) else it },
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty()) Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = SD.colors.tertiaryLabel)
                    inner()
                }
            },
        )
    }
}

/** An inline picker row: label on the left, current value + chevron on the right, menu on tap. */
@Composable
fun <T> FormPickerRow(label: String, options: List<T>, selected: T, text: (T) -> String, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { open = true }.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.width(FormLabelWidth))
            Text(text(selected), style = MaterialTheme.typography.bodyLarge, color = SD.colors.secondaryLabel, maxLines = 1,
                overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
            Icon(Icons.Filled.UnfoldMore, null, tint = SD.colors.tertiaryLabel, modifier = Modifier.padding(start = 4.dp).size(18.dp))
        }
        DropdownMenu(open, { open = false }, modifier = Modifier.heightIn(max = 360.dp)) {
            options.forEach { o -> DropdownMenuItem({ Text(text(o)) }, { onSelect(o); open = false }) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> Dropdown(label: String, options: List<T>, selected: T, text: (T) -> String, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(open, { open = it }, modifier.fillMaxWidth().padding(top = 8.dp)) {
        OutlinedTextField(
            text(selected), {}, readOnly = true, label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
            modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(open, { open = false }) {
            options.forEach { o -> DropdownMenuItem({ Text(text(o)) }, { onSelect(o); open = false }) }
        }
    }
}
