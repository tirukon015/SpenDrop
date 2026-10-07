package com.spendrop.app.ui.paybook

import androidx.compose.foundation.layout.Column
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

@Composable
fun MethodFields(form: MethodForm, onChange: (MethodForm) -> Unit) {
    Column {
        Dropdown("Payment Type", PaymentMethodType.entries, form.type, { it.raw }) { onChange(form.copy(type = it)) }
        Dropdown("Provider", PaymentMethodType.commonProviders, form.provider, { it }) { onChange(form.copy(provider = it)) }
        if (form.isOther) OutlinedTextField(form.customProvider, { onChange(form.copy(customProvider = it)) }, label = { Text("Custom Provider / Bank Name *") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        OutlinedTextField(form.identifier, { onChange(form.copy(identifier = it)) }, label = { Text(form.type.identifierFieldLabel + " *") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        OutlinedTextField(form.label, { onChange(form.copy(label = it)) }, label = { Text("Label e.g. Personal, Business (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        OutlinedTextField(form.notes, { onChange(form.copy(notes = it)) }, label = { Text("Notes (optional)") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
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
