package com.spendrop.app.cloud

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Public Supabase client values. Null when the build has no configuration (cloud features are then hidden). */
data class SupabaseConfig(val url: String, val publicKey: String) {
    companion object {
        const val CALLBACK_SCHEME = "spendrop"
        const val REDIRECT_URL = "spendrop://auth-callback"
        fun of(url: String, key: String): SupabaseConfig? =
            if (url.startsWith("https://") && key.isNotBlank()) SupabaseConfig(url.trimEnd('/'), key) else null
    }
}

/** User-facing cloud errors (same wording as iOS CloudError, with "this phone" instead of "this iPhone"). */
sealed class CloudError(message: String) : Exception(message) {
    object NotConfigured : CloudError("Cloud backup isn't set up in this version of SpenDrop.")
    object NotSignedIn : CloudError("Sign in to enable cloud backup.")
    object Offline : CloudError("You're offline. Your data is safe on this phone; cloud backup will run when you're back online.")
    object InvalidCredentials : CloudError("Incorrect email or password.")
    object EmailNotConfirmed : CloudError("Please confirm your email address first, then sign in.")
    object EmailAlreadyRegistered : CloudError("An account with this email already exists. Sign in instead.")
    class WeakPassword(msg: String) : CloudError(msg.ifEmpty { "Please choose a stronger password." })
    object SessionExpired : CloudError("Your session has expired. Please sign in again. Local data remains on this phone.")
    object Cancelled : CloudError("Sign-in was cancelled.")
    class UnsupportedBackup(version: Int) : CloudError("This backup was made by a newer version of SpenDrop (format $version). Update the app to restore it.")
    object InvalidResponse : CloudError("The server sent an unexpected response. Please try again.")
    class Server(val status: Int, msg: String) : CloudError(msg.ifEmpty { "Server error ($status). Please try again." })
    object SafetyBackupFailed : CloudError("Couldn't save a safety copy of your current data, so nothing was restored.")
    object RateLimited : CloudError("Too many attempts. Please wait a few minutes and try again.")
    object LinkExpired : CloudError("This link has expired or was already used. Please request a new one.")

    companion object {
        val json = Json { ignoreUnknownKeys = true; isLenient = true }

        /** Maps a Supabase error body to a user-facing error (iOS CloudJSON.error). */
        fun from(status: Int, body: String): CloudError {
            val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: JsonObject(emptyMap())
            fun s(k: String) = obj[k]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
            val code = s("error_code") ?: s("error") ?: s("code") ?: ""
            val message = s("msg") ?: s("error_description") ?: s("message") ?: ""
            val lower = "$code $message".lowercase()
            return when {
                "invalid_credentials" in lower || "invalid login credentials" in lower || (code == "invalid_grant" && "credentials" in lower) -> InvalidCredentials
                "email_not_confirmed" in lower || "email not confirmed" in lower -> EmailNotConfirmed
                "user_already_exists" in lower || "already registered" in lower || "email_exists" in lower -> EmailAlreadyRegistered
                "weak_password" in lower || "password should" in lower -> WeakPassword(message)
                status == 429 || "rate_limit" in lower || "rate limit" in lower -> RateLimited
                listOf("otp_expired", "flow_state_expired", "flow_state_not_found", "bad_code_verifier", "invalid flow state").any { it in lower } -> LinkExpired
                "refresh_token" in lower || "jwt expired" in lower || status == 401 -> SessionExpired
                else -> Server(status, message)
            }
        }
    }
}

/** Thin OkHttp wrapper: every call carries the public key; user calls carry the user's access token. */
class SupabaseHttp(val config: SupabaseConfig, client: OkHttpClient? = null) {
    val client: OkHttpClient = client ?: OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    fun url(path: String, query: Map<String, String> = emptyMap()): HttpUrl {
        val b = (config.url + path).toHttpUrl().newBuilder()
        query.forEach { (k, v) -> b.addQueryParameter(k, v) }
        return b.build()
    }

    suspend fun send(
        method: String,
        path: String,
        query: Map<String, String> = emptyMap(),
        token: String? = null,
        body: RequestBody? = null,
        headers: Map<String, String> = emptyMap(),
    ): ByteArray {
        val req = Request.Builder().url(url(path, query))
            .header("apikey", config.publicKey)
            .header("Authorization", "Bearer ${token ?: config.publicKey}")
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .method(method, body ?: if (method == "POST" || method == "PUT" || method == "PATCH") ByteArray(0).toRequestBody() else null)
            .build()
        val resp = try {
            client.newCall(req).await()
        } catch (e: IOException) {
            throw if (e is UnknownHostException || e is SocketTimeoutException || e is java.net.ConnectException) CloudError.Offline
            else CloudError.Offline
        }
        resp.use {
            val bytes = it.body.bytes()
            if (!it.isSuccessful) throw CloudError.from(it.code, bytes.decodeToString())
            return bytes
        }
    }

    suspend fun sendJson(method: String, path: String, json: String, query: Map<String, String> = emptyMap(), token: String? = null, headers: Map<String, String> = emptyMap()) =
        send(method, path, query, token, json.toRequestBody(JSON), headers + ("Content-Type" to "application/json"))

    companion object {
        val JSON = "application/json".toMediaType()
    }
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) { if (!cont.isCancelled) cont.resumeWithException(e) }
        override fun onResponse(call: Call, response: Response) { cont.resume(response) { _, _, _ -> response.close() } }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}
