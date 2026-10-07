package com.spendrop.app.ui.paybook

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.Icon
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import com.spendrop.app.ui.components.RowDivider
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.ui.components.ListRow
import com.spendrop.app.ui.components.MessageDialog
import com.spendrop.app.ui.components.PersonAvatar
import com.spendrop.app.ui.components.PhotoStore
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SDScreen
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.components.SectionHeader
import com.spendrop.app.ui.theme.SD
import com.spendrop.core.Ids
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Add Person (with an optional first payment account) or edit a person's name, notes and photo. */
@Composable
fun PersonEditScreen(container: AppContainer, personId: String?, onDone: (savedId: String?) -> Unit) {
    val snapshot by container.repository.snapshot.collectAsState()
    val existing = snapshot?.people?.firstOrNull { it.id == personId }
    var name by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }
    var loaded by rememberSaveable { mutableStateOf(personId == null) }
    var withMethod by rememberSaveable { mutableStateOf(false) }
    var method by remember { mutableStateOf(MethodForm()) }
    var photo by remember { mutableStateOf<Uri?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val id = remember { personId ?: Ids.new() }
    LaunchedEffect(existing) {
        if (!loaded && existing != null) { name = existing.name; notes = existing.notes.orEmpty(); loaded = true }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { photo = it }
    val valid = name.isNotBlank() && (!withMethod || method.isValid)

    SDScreen(title = if (personId == null) "Add Person" else "Edit Person", onBack = { onDone(null) }, actions = {
        TextButton(enabled = valid && !saving, onClick = {
            saving = true
            scope.launch {
                val now = System.currentTimeMillis()
                val person = (existing ?: Person(id = id, name = "", createdAt = now, updatedAt = now))
                    .copy(name = name.trim(), notes = notes.trim().ifEmpty { null }, updatedAt = now)
                val methods = if (withMethod && personId == null) listOf(
                    PersonPaymentMethod(Ids.new(), id, method.type.raw, method.provider.trim(), method.customProvider.trim().ifEmpty { null },
                        method.identifier.trim(), method.label.trim().ifEmpty { null }, method.notes.trim().ifEmpty { null }, now, now),
                ) else emptyList()
                container.repository.apply(Changes(people = listOf(person), paymentMethods = methods))
                photo?.let { uri ->
                    val file = withContext(Dispatchers.IO) { PhotoStore.savePersonPhoto(context, id, uri) }
                    if (file != null) container.repository.setPersonPhoto(id, file) else error = "The photo couldn't be read. The person was saved without it."
                }
                if (error == null) onDone(id)
            }
        }) { Text("Save", fontWeight = FontWeight.SemiBold) }
    }) { padding ->
        Column(Modifier.padding(padding).imePadding().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            // Photo: live initials (or the chosen photo) with a camera badge; tap to choose.
            val pickPhoto = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
            Column(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.clickable(role = Role.Button, onClickLabel = "Choose photo", onClick = pickPhoto)) {
                    val initials = Person(id, name.trim(), createdAt = 0, updatedAt = 0).initials
                    if (name.isBlank() && photo == null && existing == null) {
                        Box(Modifier.size(96.dp).clip(CircleShape).background(SD.colors.blue.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Person, null, tint = SD.colors.blue, modifier = Modifier.size(48.dp))
                        }
                    } else PersonAvatar(container, id, initials, 96.dp, overrideUri = photo)
                    Box(
                        Modifier.align(Alignment.BottomEnd).size(32.dp).clip(CircleShape).background(SD.colors.groupedBackground).padding(3.dp)
                            .clip(CircleShape).background(SD.colors.blue),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.PhotoCamera, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
                }
                TextButton(onClick = pickPhoto) { Text(if (photo != null) "Change Photo" else "Add Photo", fontWeight = FontWeight.Medium) }
            }

            SectionHeader("Person")
            SDCard {
                FormFieldRow("Name", name, "Required", tag = "personName", capitalization = KeyboardCapitalization.Words) { name = it }
                RowDivider()
                FormFieldRow("Notes", notes, "Optional", singleLine = false, tag = "personNotes") { notes = it }
            }
            SectionFooter("Each person can store several bank accounts and e-wallets.")

            if (personId == null) {
                SectionHeader("Payment account")
                SDCard {
                    ListRow("Add Payment Account Now", trailing = { Switch(withMethod, { withMethod = it }) })
                    if (withMethod) { RowDivider(); MethodFields(method) { method = it } }
                }
                SectionFooter(if (withMethod) "Saved with this person so you can copy it when you pay them." else "Optional. You can add accounts later from their page.")
            }
        }
    }
    error?.let { MessageDialog("Photo not saved", it) { error = null; onDone(id) } }
}

/** Add or edit one payment method of a person. */
@Composable
fun PaymentMethodEditScreen(container: AppContainer, personId: String, methodId: String?, onDone: () -> Unit) {
    val snapshot by container.repository.snapshot.collectAsState()
    val s = snapshot
    val person = s?.people?.firstOrNull { it.id == personId }
    val existing = s?.paymentMethods?.firstOrNull { it.id == methodId }
    var form by remember { mutableStateOf(MethodForm()) }
    var loaded by remember { mutableStateOf(methodId == null) }
    var duplicate by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(existing) {
        if (!loaded && existing != null) {
            form = MethodForm(existing.paymentType, existing.provider, existing.customProviderName.orEmpty(), existing.accountIdentifier, existing.label.orEmpty(), existing.notes.orEmpty())
            loaded = true
        }
    }
    SDScreen(title = if (methodId == null) "Add Payment Method" else "Edit Payment Method", onBack = onDone, actions = {
        TextButton(enabled = form.isValid && person != null, onClick = {
            val others = s?.paymentMethods.orEmpty().filter { it.personId == personId && it.id != methodId }
            if (others.any { it.normalizedIdentifier == form.normalizedIdentifier && it.displayProvider.equals(if (form.isOther) form.customProvider.trim() else form.provider, true) }) {
                duplicate = true
                return@TextButton
            }
            scope.launch {
                val now = System.currentTimeMillis()
                val m = (existing ?: PersonPaymentMethod(Ids.new(), personId, provider = "", accountIdentifier = "", createdAt = now, updatedAt = now)).copy(
                    paymentTypeRaw = form.type.raw, provider = form.provider.trim(), customProviderName = if (form.isOther) form.customProvider.trim() else null,
                    accountIdentifier = form.identifier.trim(), label = form.label.trim().ifEmpty { null }, notes = form.notes.trim().ifEmpty { null }, updatedAt = now,
                )
                container.repository.apply(Changes(paymentMethods = listOf(m), people = listOfNotNull(person?.copy(updatedAt = now))))
                onDone()
            }
        }) { Text("Save", fontWeight = FontWeight.SemiBold) }
    }) { padding ->
        Column(Modifier.padding(padding).imePadding().verticalScroll(rememberScrollState())) {
            SectionHeader(if (person != null) "Account details for ${person.name}" else "Payment method details")
            SDCard { MethodFields(form) { form = it } }
            SectionFooter("Labels help distinguish multiple accounts from the same bank (e.g. Personal vs Business).")
        }
    }
    if (duplicate) MessageDialog("Already saved", "This exact payment account is already saved under ${person?.name ?: "this person"}.") { duplicate = false }
}
