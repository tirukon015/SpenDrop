package com.spendrop.app.ui.account

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.spendrop.app.cloud.AuthService
import com.spendrop.app.cloud.AuthValidation
import com.spendrop.app.cloud.SignUpResult
import com.spendrop.app.ui.components.SDCard
import com.spendrop.app.ui.components.SectionFooter
import com.spendrop.app.ui.theme.SD
import kotlinx.coroutines.launch

enum class EmailAuthMode(val title: String) { SIGN_IN("Sign In"), CREATE("Create Account"), FORGOT("Reset Password") }

/** Email sign-in / create account / forgot password (iOS EmailAuthView). */
@Composable
fun EmailAuthForm(auth: AuthService, initialMode: EmailAuthMode, onFinished: () -> Unit) {
    var mode by remember { mutableStateOf(initialMode) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var sentTo by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val problem = when (mode) {
        EmailAuthMode.SIGN_IN -> AuthValidation.problem(email, password, null)
        EmailAuthMode.CREATE -> AuthValidation.problem(email, password, confirm)
        EmailAuthMode.FORGOT -> AuthValidation.emailProblem(email)
    }

    Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 12.dp)) {
        val sent = sentTo
        if (sent != null) {
            SDCard(padding = 16.dp) {
                Text("Check your email", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(6.dp))
                Text(
                    if (mode == EmailAuthMode.CREATE) "We sent a confirmation link to $sent. Open it on this phone to finish creating your account, then you're signed in."
                    else "If an account exists for $sent, we sent a link to choose a new password. Open it on this phone.",
                    color = SD.colors.secondaryLabel,
                )
            }
            TextButton(onClick = { sentTo = null; mode = EmailAuthMode.SIGN_IN }, modifier = Modifier.padding(horizontal = 12.dp)) { Text("Back to Sign In") }
            return@Column
        }
        SDCard(padding = 16.dp) {
            OutlinedTextField(
                email, { email = it; error = null }, label = { Text("Email") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )
            if (mode != EmailAuthMode.FORGOT) {
                OutlinedTextField(
                    password, { password = it; error = null }, label = { Text("Password") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = if (mode == EmailAuthMode.CREATE) ImeAction.Next else ImeAction.Done),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            if (mode == EmailAuthMode.CREATE) {
                OutlinedTextField(
                    confirm, { confirm = it; error = null }, label = { Text("Confirm Password") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            error?.let { Text(it, color = SD.colors.red, modifier = Modifier.padding(top = 8.dp).semantics { contentDescription = "Error: $it" }) }
            if (error == null && problem != null && (email.isNotEmpty() || password.isNotEmpty())) {
                Text(problem, color = SD.colors.secondaryLabel, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
            }
        }
        when (mode) {
            EmailAuthMode.CREATE -> SectionFooter("${AuthValidation.PASSWORD_HINT} Your password is handled by the sign-in service and never stored by SpenDrop.")
            EmailAuthMode.FORGOT -> SectionFooter("We'll email you a link to choose a new password. Open it on this phone.")
            else -> Unit
        }
        Button(
            onClick = {
                busy = true; error = null
                scope.launch {
                    try {
                        when (mode) {
                            EmailAuthMode.SIGN_IN -> { auth.signIn(email, password); onFinished() }
                            EmailAuthMode.CREATE -> if (auth.signUp(email, password) == SignUpResult.SIGNED_IN) onFinished() else sentTo = email.trim()
                            EmailAuthMode.FORGOT -> { auth.requestPasswordReset(email); sentTo = email.trim() }
                        }
                    } catch (e: Exception) {
                        error = AuthService.friendlyMessage(e)
                    } finally { busy = false }
                }
            },
            enabled = problem == null && !busy,
            modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp),
        ) {
            if (busy) CircularProgressIndicator(Modifier.height(20.dp), strokeWidth = 2.dp) else Text(if (mode == EmailAuthMode.FORGOT) "Send Reset Link" else mode.title)
        }
        Column(Modifier.padding(horizontal = 8.dp)) {
            when (mode) {
                EmailAuthMode.SIGN_IN -> {
                    TextButton(onClick = { mode = EmailAuthMode.FORGOT; error = null }) { Text("Forgot Password?") }
                    TextButton(onClick = { mode = EmailAuthMode.CREATE; error = null }) { Text("Create Account") }
                }
                EmailAuthMode.CREATE -> TextButton(onClick = { mode = EmailAuthMode.SIGN_IN; error = null }) { Text("Already have an account? Sign In") }
                EmailAuthMode.FORGOT -> TextButton(onClick = { mode = EmailAuthMode.SIGN_IN; error = null }) { Text("Back to Sign In") }
            }
        }
    }
}

/** Shown after a password-reset link (iOS NewPasswordView). */
@Composable
fun NewPasswordForm(auth: AuthService, onDone: () -> Unit) {
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val problem = AuthValidation.newPasswordProblem(password, confirm)
    Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 12.dp)) {
        SDCard(padding = 16.dp) {
            Text(auth.currentUser?.email.orEmpty(), color = SD.colors.secondaryLabel)
            OutlinedTextField(password, { password = it }, label = { Text("New Password") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            OutlinedTextField(confirm, { confirm = it }, label = { Text("Confirm New Password") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            error?.let { Text(it, color = SD.colors.red, modifier = Modifier.padding(top = 8.dp)) }
            if (error == null && problem != null && password.isNotEmpty()) Text(problem, color = SD.colors.secondaryLabel, modifier = Modifier.padding(top = 8.dp))
        }
        SectionFooter(AuthValidation.PASSWORD_HINT)
        Button(
            onClick = {
                busy = true
                scope.launch {
                    try { auth.updatePassword(password); onDone() } catch (e: Exception) { error = AuthService.friendlyMessage(e) } finally { busy = false }
                }
            },
            enabled = problem == null && !busy, modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp),
        ) { Text("Save New Password") }
        TextButton(onClick = { scope.launch { auth.cancelPasswordRecovery(); onDone() } }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Cancel") }
    }
}
