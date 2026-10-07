package com.spendrop.app.cloud

import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AuthServiceTest {
    private lateinit var server: MockWebServer
    private lateinit var store: MemorySecureStore
    private var now = 1_000_000_000_000L

    private fun sessionJson(provider: String = "email", expiresIn: Int = 3600) = """
        {"access_token":"acc","refresh_token":"ref","expires_in":$expiresIn,
         "user":{"id":"11111111-2222-3333-4444-555555555555","email":"a@b.co","app_metadata":{"provider":"$provider"},"user_metadata":{"full_name":"Ann"}}}
    """.trimIndent()

    private fun service(): AuthService {
        val config = SupabaseConfig(server.url("/").toString().trimEnd('/').replace("http://", "https://"), "pk")
        // MockWebServer is http; build the client against its real URL.
        val http = SupabaseHttp(SupabaseConfig(server.url("/").toString().trimEnd('/'), config.publicKey))
        return AuthService(http, store) { now }
    }

    @Before fun setUp() { server = MockWebServer(); server.start(); store = MemorySecureStore() }
    @After fun tearDown() { server.close() }

    @Test fun signInStoresSessionAndSendsHeaders() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson()).build())
        val auth = service()
        auth.signIn(" a@b.co ", "Secret123")
        val req = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=password", req.target)
        assertEquals("pk", req.headers["apikey"])
        assertTrue(req.body!!.utf8().contains("\"email\":\"a@b.co\""))
        val state = auth.state.value as AuthState.SignedIn
        assertEquals("a@b.co", state.user.email)
        assertEquals("Ann", state.user.name)
        // Persisted: a new service instance restores the session.
        assertTrue(service().state.value is AuthState.SignedIn)
    }

    @Test fun wrongPasswordIsFriendly() = runTest {
        server.enqueue(MockResponse.Builder().code(400).body("""{"error_code":"invalid_credentials","msg":"Invalid login credentials"}""").build())
        val auth = service()
        val e = runCatching { auth.signIn("a@b.co", "x") }.exceptionOrNull()
        assertTrue(e is CloudError.InvalidCredentials)
        assertEquals("Incorrect email or password.", AuthService.friendlyMessage(e!!))
    }

    @Test fun signUpWithoutSessionNeedsConfirmationAndUsesPkce() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body("""{"id":"x","email":"a@b.co"}""").build())
        val auth = service()
        assertEquals(SignUpResult.CONFIRMATION_REQUIRED, auth.signUp("a@b.co", "Secret123"))
        val req = server.takeRequest()
        assertTrue(req.target!!.startsWith("/auth/v1/signup?redirect_to=spendrop"))
        assertTrue(req.body!!.utf8().contains("code_challenge_method"))
        assertTrue(auth.state.value is AuthState.SignedOut)
    }

    @Test fun confirmationLinkExchangesCode() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body("""{"id":"x"}""").build())
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson()).build())
        val auth = service()
        auth.signUp("a@b.co", "Secret123")
        server.takeRequest()
        val result = auth.handleCallbackParams(mapOf("code" to "abc"))
        assertEquals(EmailLinkResult.SignedIn, result)
        val req = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=pkce", req.target)
        assertTrue(req.body!!.utf8().contains("\"auth_code\":\"abc\""))
    }

    @Test fun linkWithoutPendingFlowAsksToSignIn() = runTest {
        assertEquals(EmailLinkResult.VerifiedSignInNeeded, service().handleCallbackParams(mapOf("code" to "abc")))
    }

    @Test fun expiredLinkMessage() = runTest {
        val r = service().handleCallbackParams(mapOf("error" to "access_denied", "error_code" to "otp_expired"))
        assertEquals(EmailLinkResult.Failed(CloudError.LinkExpired.message!!), r)
    }

    @Test fun recoveryLinkAwaitsNewPassword() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body("{}").build())
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson()).build())
        val auth = service()
        auth.requestPasswordReset("a@b.co")
        assertEquals(EmailLinkResult.PasswordRecovery, auth.handleCallbackParams(mapOf("code" to "c")))
        assertTrue(auth.awaitingNewPassword.value)
    }

    @Test fun googleCallbackUsesGoogleProvider() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson("google")).build())
        val auth = service()
        val url = auth.beginGoogleSignIn()
        assertTrue(url.contains("provider=google") && url.contains("code_challenge="))
        auth.handleCallbackParams(mapOf("code" to "g"))
        assertEquals("google", (auth.state.value as AuthState.SignedIn).user.provider)
    }

    @Test fun expiredTokenRefreshes_revokedSignsOut() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson(expiresIn = 30)).build())
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson()).build())
        server.enqueue(MockResponse.Builder().code(400).body("""{"error_code":"refresh_token_not_found"}""").build())
        val auth = service()
        auth.signIn("a@b.co", "Secret123")
        server.takeRequest()
        assertEquals("acc", auth.validAccessToken()) // refreshed (30 s left < 60 s)
        assertEquals("/auth/v1/token?grant_type=refresh_token", server.takeRequest().target)
        now += 7_200_000
        val e = runCatching { auth.validAccessToken() }.exceptionOrNull()
        assertTrue(e is CloudError.SessionExpired)
        assertTrue(auth.state.value is AuthState.SignedOut)
    }

    @Test fun offlineKeepsSession() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(sessionJson(expiresIn = 10)).build())
        val auth = service()
        auth.signIn("a@b.co", "Secret123")
        server.close()
        val e = runCatching { auth.validAccessToken() }.exceptionOrNull()
        assertTrue(e is CloudError.Offline)
        assertTrue(auth.state.value is AuthState.SignedIn)
    }

    @Test fun validation() {
        assertEquals("Enter a valid email address.", AuthValidation.emailProblem("a@b"))
        assertNull(AuthValidation.emailProblem("a@b.co"))
        assertEquals("Password must be at least 8 characters.", AuthValidation.passwordRuleProblem("Ab1"))
        assertEquals("Use an uppercase letter, a lowercase letter and a number.", AuthValidation.passwordRuleProblem("abcdefgh1"))
        assertEquals("Passwords don't match.", AuthValidation.problem("a@b.co", "Secret123", "Secret124"))
        assertNull(AuthValidation.problem("a@b.co", "x", null))
    }

    @Test fun pkceChallengeMatchesRfc7636Example() {
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", Pkce.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    }
}
