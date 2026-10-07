package com.spendrop.app.cloud

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.MessageDigest
import java.security.SecureRandom

@Serializable
data class AuthUser(val id: String, val email: String? = null, val name: String? = null, val provider: String = "email") {
    val providerDisplayName: String get() = if (provider == "google") "Google" else "Email"
}

@Serializable
data class AuthSession(val accessToken: String, val refreshToken: String, val expiresAtMillis: Long, val user: AuthUser)

sealed interface AuthState {
    object NotConfigured : AuthState
    data class SignedOut(val message: String? = null) : AuthState
    data class SignedIn(val user: AuthUser) : AuthState
}

sealed interface EmailLinkResult {
    object SignedIn : EmailLinkResult
    object VerifiedSignInNeeded : EmailLinkResult
    object PasswordRecovery : EmailLinkResult
    data class Failed(val message: String) : EmailLinkResult
}

enum class SignUpResult { SIGNED_IN, CONFIRMATION_REQUIRED }

data class Pkce(val verifier: String, val challenge: String) {
    companion object {
        fun make(): Pkce {
            val bytes = ByteArray(48).also { SecureRandom().nextBytes(it) }
            val verifier = b64url(bytes)
            return Pkce(verifier, challenge(verifier))
        }
        fun challenge(verifier: String): String = b64url(MessageDigest.getInstance("SHA-256").digest(verifier.encodeToByteArray()))
        fun b64url(bytes: ByteArray): String = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}

/**
 * SpenDrop account sign-in with Supabase Auth's HTTP API — the same endpoints and flows as iOS AuthService:
 * email/password, sign-up with PKCE confirmation link, password reset link, Google OAuth (PKCE) via the browser,
 * session refresh, sign-out, account deletion. Local-first: signing in or out never touches local records.
 */
class AuthService(
    private val http: SupabaseHttp?,
    private val store: SecureStore,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private var session: AuthSession? = store.read(SESSION_KEY)?.let { runCatching { json.decodeFromString<AuthSession>(it) }.getOrNull() }

    private val _state = MutableStateFlow(
        when {
            http == null -> AuthState.NotConfigured
            session != null -> AuthState.SignedIn(session!!.user)
            else -> AuthState.SignedOut()
        },
    )
    val state: StateFlow<AuthState> = _state

    private val _awaitingNewPassword = MutableStateFlow(false)
    val awaitingNewPassword: StateFlow<Boolean> = _awaitingNewPassword

    val currentUser: AuthUser? get() = (state.value as? AuthState.SignedIn)?.user
    val isConfigured: Boolean get() = http != null

    @Serializable
    private data class PendingFlow(val verifier: String, val kind: String, val createdAt: Long)

    private fun requireHttp() = http ?: throw CloudError.NotConfigured

    // Email / password ---------------------------------------------------------------------------------------

    suspend fun signUp(email: String, password: String): SignUpResult {
        val pkce = Pkce.make()
        savePending(PendingFlow(pkce.verifier, "signup", now()))
        val body = buildJsonObject {
            put("email", email.trim()); put("password", password)
            put("code_challenge", pkce.challenge); put("code_challenge_method", "s256")
        }
        val data = requireHttp().sendJson("POST", "/auth/v1/signup", body.toString(), mapOf("redirect_to" to SupabaseConfig.REDIRECT_URL))
        val s = runCatching { parseSession(data.decodeToString(), "email") }.getOrNull()
        if (s != null) {
            clearPending(); save(s)
            return SignUpResult.SIGNED_IN
        }
        return SignUpResult.CONFIRMATION_REQUIRED
    }

    suspend fun signIn(email: String, password: String) {
        val body = buildJsonObject { put("email", email.trim()); put("password", password) }
        val data = requireHttp().sendJson("POST", "/auth/v1/token", body.toString(), mapOf("grant_type" to "password"))
        save(parseSession(data.decodeToString(), "email"))
    }

    /** Same answer whether or not the address has an account (never reveals who is registered). */
    suspend fun requestPasswordReset(email: String) {
        val pkce = Pkce.make()
        savePending(PendingFlow(pkce.verifier, "recovery", now()))
        val body = buildJsonObject { put("email", email.trim()); put("code_challenge", pkce.challenge); put("code_challenge_method", "s256") }
        requireHttp().sendJson("POST", "/auth/v1/recover", body.toString(), mapOf("redirect_to" to SupabaseConfig.REDIRECT_URL))
    }

    suspend fun updatePassword(newPassword: String) {
        val token = validAccessToken()
        requireHttp().sendJson("PUT", "/auth/v1/user", buildJsonObject { put("password", newPassword) }.toString(), token = token)
        _awaitingNewPassword.value = false
        signOut("Password updated. Sign in with your new password.")
    }

    suspend fun cancelPasswordRecovery() {
        _awaitingNewPassword.value = false
        signOut()
    }

    // Google -------------------------------------------------------------------------------------------------

    /** Returns the browser URL to open. The callback arrives at spendrop://auth-callback and is finished by [handleAuthCallback]. */
    fun beginGoogleSignIn(): String {
        val h = requireHttp()
        val pkce = Pkce.make()
        savePending(PendingFlow(pkce.verifier, "google", now()))
        return h.url(
            "/auth/v1/authorize",
            mapOf(
                "provider" to "google", "redirect_to" to SupabaseConfig.REDIRECT_URL,
                "code_challenge" to pkce.challenge, "code_challenge_method" to "s256",
            ),
        ).toString()
    }

    // Callback links (email confirmation, password reset, Google) ------------------------------------------------

    fun isAuthCallback(uri: Uri?): Boolean = uri?.scheme == SupabaseConfig.CALLBACK_SCHEME && uri.host == "auth-callback"

    suspend fun handleAuthCallback(uri: Uri): EmailLinkResult? {
        if (!isAuthCallback(uri) || http == null) return null
        val items = HashMap<String, String>()
        uri.queryParameterNames.forEach { items[it] = uri.getQueryParameter(it) ?: "" }
        uri.fragment?.let { frag -> Uri.parse("x://x/?$frag").let { f -> f.queryParameterNames.forEach { items[it] = f.getQueryParameter(it) ?: "" } } }
        return handleCallbackParams(items)
    }

    suspend fun handleCallbackParams(items: Map<String, String>): EmailLinkResult {
        val err = items["error_code"] ?: items["error"]
        if (err != null) {
            val desc = items["error_description"].orEmpty()
            val expired = "otp_expired" in err || "expired" in desc.lowercase()
            return EmailLinkResult.Failed(if (expired) CloudError.LinkExpired.message!! else desc.replace('+', ' ').ifEmpty { "This link couldn't be used. Please request a new one." })
        }
        val pending = loadPending()
        return try {
            val code = items["code"]
            if (!code.isNullOrEmpty()) {
                if (pending == null) return EmailLinkResult.VerifiedSignInNeeded
                val body = buildJsonObject { put("auth_code", code); put("code_verifier", pending.verifier) }
                val data = requireHttp().sendJson("POST", "/auth/v1/token", body.toString(), mapOf("grant_type" to "pkce"))
                save(parseSession(data.decodeToString(), if (pending.kind == "google") "google" else "email"))
                clearPending()
                if (pending.kind == "recovery") {
                    _awaitingNewPassword.value = true
                    return EmailLinkResult.PasswordRecovery
                }
                return EmailLinkResult.SignedIn
            }
            val access = items["access_token"]; val refresh = items["refresh_token"]
            if (access != null && refresh != null) {
                val userData = requireHttp().send("GET", "/auth/v1/user", token = access).decodeToString()
                val sessionJson = buildJsonObject {
                    put("access_token", access); put("refresh_token", refresh)
                    put("expires_in", items["expires_in"]?.toDoubleOrNull() ?: 3600.0)
                    put("user", json.parseToJsonElement(userData))
                }
                save(parseSession(sessionJson.toString(), "email"))
                clearPending()
                if (items["type"] == "recovery") {
                    _awaitingNewPassword.value = true
                    return EmailLinkResult.PasswordRecovery
                }
                return EmailLinkResult.SignedIn
            }
            EmailLinkResult.VerifiedSignInNeeded
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: CloudError.Offline) {
            EmailLinkResult.Failed("You're offline. Connect to the internet and open the link again.")
        } catch (e: CloudError) {
            if (e is CloudError.LinkExpired && pending?.kind == "signup") {
                EmailLinkResult.Failed("This link has expired or belongs to an older request. If your email is already verified, sign in; otherwise create the account again to get a new link.")
            } else EmailLinkResult.Failed(e.message ?: "This link couldn't be used. Please request a new one.")
        } catch (_: Exception) {
            EmailLinkResult.Failed("This link couldn't be used. Please request a new one.")
        }
    }

    // Session ------------------------------------------------------------------------------------------------

    /** A valid access token, refreshed within a minute of expiry. Offline keeps the session; a revoked one signs out. */
    suspend fun validAccessToken(): String {
        val h = requireHttp()
        val s = session ?: throw CloudError.NotSignedIn
        if (s.expiresAtMillis - now() > 60_000) return s.accessToken
        try {
            val body = buildJsonObject { put("refresh_token", s.refreshToken) }
            val data = h.sendJson("POST", "/auth/v1/token", body.toString(), mapOf("grant_type" to "refresh_token"))
            val fresh = parseSession(data.decodeToString(), s.user.provider)
            save(fresh)
            return fresh.accessToken
        } catch (e: CloudError.Offline) {
            throw e
        } catch (e: CloudError) {
            // Only a refused refresh token ends the cloud session; rate limits and server errors are retried later.
            val revoked = e is CloudError.SessionExpired || e is CloudError.InvalidCredentials || e is CloudError.LinkExpired ||
                (e is CloudError.Server && e.status in 400..499 && e.status != 429)
            if (!revoked) throw e
            clearSession(CloudError.SessionExpired.message)
            throw CloudError.SessionExpired
        }
    }

    suspend fun refreshSessionIfNeeded() {
        if (session != null) runCatching { validAccessToken() }
    }

    suspend fun signOut(message: String = "Signed out. Local data remains on this phone.") {
        session?.accessToken?.let { token -> runCatching { http?.send("POST", "/auth/v1/logout", token = token) } }
        _awaitingNewPassword.value = false
        clearSession(message)
    }

    /** Deletes cloud backups first ([deleteCloudData]), then the account via RPC delete_my_account. Local data stays. */
    suspend fun deleteAccount(deleteCloudData: suspend () -> Unit) {
        val token = validAccessToken()
        deleteCloudData()
        requireHttp().sendJson("POST", "/rest/v1/rpc/delete_my_account", "{}", token = token)
        clearSession("Your cloud account was deleted. Local data remains on this phone.")
    }

    // Internals ----------------------------------------------------------------------------------------------

    private fun save(s: AuthSession) {
        session = s
        store.write(SESSION_KEY, json.encodeToString(s))
        _state.value = AuthState.SignedIn(s.user)
    }

    private fun clearSession(message: String?) {
        session = null
        store.delete(SESSION_KEY)
        _state.value = if (http == null) AuthState.NotConfigured else AuthState.SignedOut(message)
    }

    private fun savePending(p: PendingFlow) = store.write(PENDING_KEY, json.encodeToString(p))
    private fun loadPending(): PendingFlow? = store.read(PENDING_KEY)?.let { runCatching { json.decodeFromString<PendingFlow>(it) }.getOrNull() }
    private fun clearPending() = store.delete(PENDING_KEY)

    fun parseSession(body: String, provider: String?): AuthSession {
        val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: throw CloudError.InvalidResponse
        fun JsonObject.str(k: String) = this[k]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
        val access = obj.str("access_token") ?: throw CloudError.InvalidResponse
        val refresh = obj.str("refresh_token") ?: throw CloudError.InvalidResponse
        val user = obj["user"]?.let { runCatching { it.jsonObject }.getOrNull() } ?: throw CloudError.InvalidResponse
        val id = user.str("id") ?: throw CloudError.InvalidResponse
        val expiresAt = obj["expires_at"]?.jsonPrimitive?.doubleOrNull?.let { (it * 1000).toLong() }
            ?: (now() + ((obj["expires_in"]?.jsonPrimitive?.doubleOrNull ?: 3600.0) * 1000).toLong())
        val appMeta = user["app_metadata"]?.let { runCatching { it.jsonObject }.getOrNull() }
        val userMeta = user["user_metadata"]?.let { runCatching { it.jsonObject }.getOrNull() }
        val p = provider ?: if (appMeta?.str("provider") == "google") "google" else "email"
        return AuthSession(access, refresh, expiresAt, AuthUser(id, user.str("email"), userMeta?.str("full_name") ?: userMeta?.str("name"), p))
    }

    companion object {
        private const val SESSION_KEY = "session"
        private const val PENDING_KEY = "pendingEmailFlow"

        /** Messages for people, not developers (iOS AuthService.friendlyMessage). */
        fun friendlyMessage(e: Throwable): String = when (e) {
            is CloudError.Offline -> "You're offline. Connect to the internet and try again."
            is CloudError.InvalidCredentials -> "Incorrect email or password."
            is CloudError.EmailNotConfirmed -> "Please verify your email first. Open the link we sent you, then sign in."
            is CloudError.EmailAlreadyRegistered -> "An account with this email already exists. Sign in instead, or reset your password."
            is CloudError.WeakPassword -> "Choose a stronger password. ${AuthValidation.PASSWORD_HINT}"
            is CloudError.RateLimited, is CloudError.LinkExpired, is CloudError.NotConfigured -> e.message!!
            is CloudError.SessionExpired -> "Your session has expired. Please sign in again."
            else -> "Something went wrong. Please try again."
        }
    }
}

/** Form checks shown before any network call (iOS AuthValidation). */
object AuthValidation {
    const val PASSWORD_HINT = "At least 8 characters, with an uppercase letter, a lowercase letter and a number."

    fun problem(email: String, password: String, confirm: String?): String? {
        emailProblem(email)?.let { return it }
        if (password.isEmpty()) return "Enter your password."
        if (confirm == null) return null
        passwordRuleProblem(password)?.let { return it }
        return if (confirm == password) null else "Passwords don't match."
    }

    fun passwordRuleProblem(p: String): String? {
        if (p.length < 8) return "Password must be at least 8 characters."
        if (!(p.any { it.isLowerCase() } && p.any { it.isUpperCase() } && p.any { it.isDigit() })) return "Use an uppercase letter, a lowercase letter and a number."
        return null
    }

    fun emailProblem(email: String): String? {
        val t = email.trim()
        val parts = t.split("@")
        val ok = parts.size == 2 && parts[0].isNotEmpty() && parts[1].contains(".") && !parts[1].startsWith(".") && !parts[1].endsWith(".") && !t.contains(" ")
        return if (ok) null else "Enter a valid email address."
    }

    fun newPasswordProblem(p: String, confirm: String): String? = passwordRuleProblem(p) ?: if (confirm == p) null else "Passwords don't match."
}
