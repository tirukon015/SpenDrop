package com.spendrop.app.ai

import com.spendrop.app.cloud.CloudError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.UnknownHostException

/** The Ask SpenDrop client against a mock of the shared server (`POST /api/ai/chat`). */
class AskApiTest {
    private lateinit var server: MockWebServer

    @Before fun setUp() { server = MockWebServer(); server.start() }
    @After fun tearDown() { server.close() }

    private fun api(token: suspend () -> String = { "tok-123" }, client: OkHttpClient = OkHttpClient()) =
        AskApi(server.url("/").toString(), token, client)

    private val answerJson = """
        {"conversationId":"7d9c1b2e-3f4a-4b5c-8d6e-0f1a2b3c4d5e","answer":{
          "status":"answered","text":"You spent RM 45.50 on Food this week.","confidence":"HIGH",
          "blocks":[
            {"type":"metric","label":"Food · This week","valueMinor":4550,"currency":"MYR","caption":"3 transactions"},
            {"type":"sparkline","points":[1,2,3]},
            {"type":"comparison","currency":"MYR","a":{"label":"This week","valueMinor":4550,"count":3},"b":{"label":"Last week","valueMinor":0,"count":0},"diffMinor":4550,"pct":null},
            {"type":"breakdown","title":"By merchant","currency":"MYR","kind":"merchant","items":[{"key":"kfc","label":"KFC","valueMinor":3000,"count":2,"diffMinor":-150}]},
            {"type":"transactions","title":"Food","items":[{"id":"a1","merchant":"KFC","amountMinor":3000,"spendMinor":1500,"currency":"MYR","date":"2026-10-06T04:00:00Z","localDate":"2026-10-06","localTime":"12:00","category":"Food","fundingAccount":"Maybank","paymentChannel":"DUITNOW_QR","hasReceipt":true,"isShared":true,"source":"screenshot"}],"more":2},
            {"type":"findings","title":"Worth a look","items":[{"title":"Two KFC visits","detail":"Both on Monday"}]}
          ],
          "evidence":[{"tool":"sum_spending","transactionCount":3,"period":"This week","filters":"Food","generatedAt":"2026-10-08T00:00:00Z"}],
          "followUps":["Compare with last week"],"understoodAs":"Food spending this week","insight":"More than usual","suggestion":null,
          "focus":null,"meta":{"requestId":"r1","intent":"SPENDING_TOTAL","route":"deterministic","provider":"none","tools":[{"name":"sum_spending","ok":true,"ms":3}],"totalMs":12}}}
    """.trimIndent()

    @Test fun decodesAnswer_ignoringUnknownBlockTypes_andNullPct() {
        val r = AskJson.decodeFromString(AskChatResponse.serializer(), answerJson)
        assertEquals("7d9c1b2e-3f4a-4b5c-8d6e-0f1a2b3c4d5e", r.conversationId)
        val a = r.answer
        assertEquals("answered", a.status)
        // 6 blocks sent, the unknown "sparkline" is dropped without failing the answer.
        assertEquals(listOf(AnswerBlock.Metric::class, AnswerBlock.Comparison::class, AnswerBlock.Breakdown::class, AnswerBlock.Transactions::class, AnswerBlock.Findings::class), a.blocks.map { it::class })
        assertNull((a.blocks[1] as AnswerBlock.Comparison).pct)
        assertEquals(4550L, (a.blocks[0] as AnswerBlock.Metric).valueMinor)
        val t = (a.blocks[3] as AnswerBlock.Transactions)
        assertEquals(1500L, t.items.single().spendMinor)
        assertEquals(2, t.more)
        assertEquals(-150L, (a.blocks[2] as AnswerBlock.Breakdown).items.single().diffMinor)
        assertEquals(3, a.evidence.single().transactionCount)
        assertEquals("Food spending this week", a.understoodAs)
        assertNull(a.suggestion)
        assertNull(a.focus)
        assertEquals(12L, a.meta?.totalMs)
    }

    @Test fun decodesMinimalAnswer() {
        val r = AskJson.decodeFromString(AskChatResponse.serializer(), """{"conversationId":"c","answer":{"status":"no_data","text":"No transactions yet.","blocks":[{"type":"chart"}],"evidence":[],"followUps":[],"focus":null,"meta":{"requestId":"x"}}}""")
        assertEquals("no_data", r.answer.status)
        assertTrue(r.answer.blocks.isEmpty())
    }

    @Test fun sendsOnlyMessageConversationAndTimeZone_withBearerToken() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(answerJson).build())
        val r = api().chat("  How much on food this week?  ", "7d9c1b2e-3f4a-4b5c-8d6e-0f1a2b3c4d5e", "Asia/Kuala_Lumpur")
        assertEquals(1, r.answer.evidence.size)
        val req = server.takeRequest()
        assertEquals("POST", req.method)
        assertEquals("/api/ai/chat", req.target)
        assertEquals("Bearer tok-123", req.headers["Authorization"])
        assertTrue(req.headers["Content-Type"]!!.startsWith("application/json"))
        val body = AskJson.parseToJsonElement(req.body!!.utf8()).jsonObject
        assertEquals(setOf("message", "conversationId", "timeZone"), body.keys)
        assertEquals("How much on food this week?", body["message"]!!.jsonPrimitive.content)
        assertEquals("Asia/Kuala_Lumpur", body["timeZone"]!!.jsonPrimitive.content)
    }

    @Test fun firstQuestionHasNoConversationId() = runTest {
        server.enqueue(MockResponse.Builder().code(200).body(answerJson).build())
        api().chat("Hi", null, "UTC")
        val body = AskJson.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject
        assertEquals(setOf("message", "timeZone"), body.keys)
    }

    @Test fun unauthorizedMeansSignIn() = runTest {
        server.enqueue(MockResponse.Builder().code(401).body("""{"error":{"code":"unauthorized","message":"Sign in to use SpenDrop AI."}}""").build())
        val e = runCatching { api().chat("Hi", null) }.exceptionOrNull()
        assertTrue(e is AskError.SignInRequired)
    }

    @Test fun serverErrorShowsServerMessage() = runTest {
        server.enqueue(MockResponse.Builder().code(429).body("""{"error":{"code":"rate_limited","message":"Too many questions. Try again in a minute."}}""").build())
        val e = runCatching { api().chat("Hi", null) }.exceptionOrNull() as AskError.Server
        assertEquals(429, e.status)
        assertEquals("rate_limited", e.code)
        assertEquals("Too many questions. Try again in a minute.", e.message)
    }

    @Test fun noSessionMeansSignIn_withoutCallingTheServer() = runTest {
        val e = runCatching { api(token = { throw CloudError.NotSignedIn }).chat("Hi", null) }.exceptionOrNull()
        assertTrue(e is AskError.SignInRequired)
        assertEquals(AskError.SIGN_IN_MESSAGE, e!!.message)
        assertEquals(0, server.requestCount)
    }

    @Test fun offlineIsFriendly() = runTest {
        val offline = OkHttpClient.Builder().addInterceptor { throw UnknownHostException("spendrop.vercel.app") }.build()
        val e = runCatching { api(client = offline).chat("Hi", null) }.exceptionOrNull()
        assertTrue(e is AskError.Offline)
        assertEquals("You're offline. SpenDrop AI needs an internet connection — your transactions are still available offline.", e!!.message)
        // Refresh failing offline is the same message.
        val e2 = runCatching { api(token = { throw CloudError.Offline }).chat("Hi", null) }.exceptionOrNull()
        assertTrue(e2 is AskError.Offline)
    }

    @Test fun connectionRefusedIsOffline() = runTest {
        val url = server.url("/").toString()
        server.close()
        val e = runCatching { AskApi(url, { "t" }).chat("Hi", null) }.exceptionOrNull()
        assertTrue("got $e", e is AskError.Offline)
    }
}
