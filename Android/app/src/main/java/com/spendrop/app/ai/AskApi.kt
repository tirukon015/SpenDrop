package com.spendrop.app.ai

import com.spendrop.app.cloud.CloudError
import com.spendrop.app.cloud.await
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

/** Why a question couldn't be answered, in words for people. */
sealed class AskError(message: String) : Exception(message) {
    /** No session, or the server refused the token (401): show the sign-in prompt. */
    class SignInRequired(message: String = SIGN_IN_MESSAGE) : AskError(message)
    object Offline : AskError(OFFLINE_MESSAGE)
    object NotAvailable : AskError("SpenDrop AI isn't set up in this version of SpenDrop.")
    /** Any other refusal; [message] is the server's own text when it sent one. */
    class Server(val status: Int, val code: String?, message: String) : AskError(message)

    companion object {
        const val SIGN_IN_MESSAGE = "Sign in to SpenDrop Cloud to use SpenDrop AI"
        const val SESSION_EXPIRED_MESSAGE = "Your session has expired. Sign in again to use SpenDrop AI."
        const val OFFLINE_MESSAGE = "You're offline. SpenDrop AI needs an internet connection — your transactions are still available offline."
        const val GENERIC_MESSAGE = "SpenDrop AI couldn't answer right now. Please try again."
    }
}

/**
 * Client for the shared SpenDrop AI endpoint (`POST /api/ai/chat`, the same server the Web app uses).
 * The request carries only the question, the conversation id and the time zone; the user is identified by the
 * Supabase access token alone (never a user id). [accessToken] is [com.spendrop.app.cloud.AuthService.validAccessToken],
 * which refreshes an expiring session.
 */
class AskApi(
    baseUrl: String,
    private val accessToken: suspend () -> String,
    private val client: OkHttpClient = defaultClient(),
) {
    val endpoint: String = baseUrl.trimEnd('/') + "/api/ai/chat"

    /** Builds the request body: exactly `message`, plus `conversationId` / `timeZone` when known. */
    fun requestBody(message: String, conversationId: String?, timeZone: String?): String = buildJsonObject {
        put("message", message)
        if (!conversationId.isNullOrBlank()) put("conversationId", conversationId)
        if (!timeZone.isNullOrBlank()) put("timeZone", timeZone)
    }.toString()

    suspend fun chat(message: String, conversationId: String?, timeZone: String? = java.time.ZoneId.systemDefault().id): AskChatResponse {
        val text = message.trim().take(MAX_MESSAGE)
        require(text.isNotEmpty()) { "Empty question" }
        val token = try {
            accessToken()
        } catch (e: CancellationException) {
            throw e
        } catch (e: CloudError) {
            throw when (e) {
                is CloudError.NotSignedIn -> AskError.SignInRequired()
                is CloudError.SessionExpired -> AskError.SignInRequired(AskError.SESSION_EXPIRED_MESSAGE)
                is CloudError.Offline -> AskError.Offline
                is CloudError.NotConfigured -> AskError.NotAvailable
                else -> AskError.Server(0, null, e.message ?: AskError.GENERIC_MESSAGE)
            }
        }
        val request = Request.Builder().url(endpoint)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .post(requestBody(text, conversationId, timeZone).toRequestBody(JSON))
            .build()
        val response = try {
            client.newCall(request).await()
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            throw if (e is UnknownHostException || e is ConnectException || e is SocketTimeoutException) AskError.Offline
            else AskError.Server(0, null, AskError.GENERIC_MESSAGE)
        }
        response.use { r ->
            val body = r.body.string()
            if (!r.isSuccessful) throw errorFor(r.code, body)
            return runCatching { AskJson.decodeFromString(AskChatResponse.serializer(), body) }
                .getOrElse { throw AskError.Server(r.code, "invalid_response", AskError.GENERIC_MESSAGE) }
        }
    }

    companion object {
        const val MAX_MESSAGE = 1000
        private val JSON = "application/json".toMediaType()

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        /** `{"error":{"code","message"}}` → [AskError]. 401 always means "sign in again". */
        fun errorFor(status: Int, body: String): AskError {
            val err = runCatching { AskJson.parseToJsonElement(body).jsonObject["error"]?.jsonObject }.getOrNull()
            val code = err?.get("code")?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
            val message = err?.get("message")?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }?.takeIf { it.isNotBlank() }
            return when (status) {
                401 -> AskError.SignInRequired(AskError.SESSION_EXPIRED_MESSAGE)
                else -> AskError.Server(status, code, message ?: when (status) {
                    429 -> "You've asked a lot of questions in a short time. Please wait a moment and try again."
                    503 -> "SpenDrop AI is busy right now. Please try again in a moment."
                    else -> AskError.GENERIC_MESSAGE
                })
            }
        }
    }
}
