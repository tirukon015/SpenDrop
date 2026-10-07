package com.spendrop.app.cloud

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spendrop.app.data.Changes
import com.spendrop.app.data.FinanceRepository
import com.spendrop.app.data.Preferences
import com.spendrop.app.data.db.SpenDropDatabase
import com.spendrop.core.model.Account
import com.spendrop.core.model.Expense
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.util.Collections

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class SyncServiceTest {
    private lateinit var server: MockWebServer
    private val requests = Collections.synchronizedList(mutableListOf<Pair<String, String>>())
    private val webExpense = """[{"id":"aaaaaaaa-0000-0000-0000-000000000001","user_id":"u1","amount_minor":2590,"currency":"RM","merchant":"Starbucks",
        "category":"Food","payment_channel":"APPLE_PAY","funding_account":"Maybank","funding_instrument":null,"account_id":null,"payment_source":null,
        "date":"2026-10-06T10:00:00.000Z","notes":"from web","transaction_reference":null,"source_type":"manual","paid_by_me":true,"payer_id":null,
        "payer_name_snapshot":null,"split_method":null,"receipt_path":null,"is_sample_data":false,"created_at":"2026-10-06T10:00:00.000Z",
        "updated_at":"2026-10-06T10:00:00.000Z","deleted_at":null,"server_updated_at":"2026-10-06T10:00:01.123456+00:00"}]"""

    @Before fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val target = request.target
                requests += "${request.method} $target" to (request.body?.utf8() ?: "")
                return when {
                    target.startsWith("/auth/v1/token") -> MockResponse.Builder().code(200).body(
                        """{"access_token":"tok","refresh_token":"r","expires_in":3600,"user":{"id":"u1","email":"a@b.co"}}""").build()
                    request.method == "GET" && target.startsWith("/rest/v1/expenses") && !target.contains("server_updated_at=gt") -> MockResponse.Builder().code(200).body(webExpense).build()
                    request.method == "GET" -> MockResponse.Builder().code(200).body("[]").build()
                    else -> MockResponse.Builder().code(201).body("").build()
                }
            }
        }
        server.start()
    }

    @After fun tearDown() = server.close()

    @Test fun firstSyncPullsWebDataAndPushesPhoneData() = runBlocking {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val repo = FinanceRepository(SpenDropDatabase.create(ctx, inMemory = true), scope)
        val prefs = Preferences(ctx)
        val http = SupabaseHttp(SupabaseConfig(server.url("/").toString().trimEnd('/'), "pk"))
        val auth = AuthService(http, MemorySecureStore())
        auth.signIn("a@b.co", "Secret123")
        val t = 1_790_000_000_000L
        repo.apply(Changes(accounts = listOf(Account("acc-1", "Maybank", "bank", createdAt = t, updatedAt = t))))
        repo.saveExpense(Expense("bbbbbbbb-0000-0000-0000-000000000002", 1850, merchant = "McDonald's", accountId = "acc-1", fundingAccount = "Maybank",
            paymentChannelRaw = "DUITNOW_QR", date = t, createdAt = t, updatedAt = t), emptyList())

        val sync = SyncService(http, auth, repo, prefs)
        assertTrue(sync.enable())
        val report = sync.syncNow()
        assertTrue(report.message, report.succeeded)

        // Pulled: the Web expense is now on the phone (cursor saved), with funding and channel kept apart.
        val local = repo.fullSnapshot(false)
        val fromWeb = local.expenses.first { it.id == "aaaaaaaa-0000-0000-0000-000000000001" }
        assertEquals(2590L, fromWeb.amountMinor)
        assertEquals("Maybank", fromWeb.fundingAccount)
        assertEquals("APPLE_PAY", fromWeb.paymentChannelRaw)
        assertEquals("2026-10-06T10:00:01.123456+00:00", prefs.get(Preferences.Keys.syncCursor("expenses")))

        // Pushed: account upsert on id, then the phone expense through the RPC; the pulled one is not echoed back.
        val posts = requests.filter { it.first.startsWith("POST /rest") }
        val accountPost = posts.first { it.first.startsWith("POST /rest/v1/accounts?on_conflict=id") }
        assertTrue(accountPost.second.contains("\"name\":\"Maybank\""))
        assertFalse(accountPost.second.contains("user_id"))
        val rpc = posts.filter { it.first == "POST /rest/v1/rpc/save_expense_with_shares" }
        assertEquals(1, rpc.size)
        assertTrue(rpc[0].second.contains("\"p_expense\"") && rpc[0].second.contains("\"amount_minor\":1850") && rpc[0].second.contains("\"payment_channel\":\"DUITNOW_QR\""))
        assertTrue(posts.indexOf(accountPost) < posts.indexOf(rpc[0])) // foreign keys: account before expense

        // Second sync: nothing changed, nothing pushed; pull uses the cursor.
        requests.clear()
        sync.syncNow()
        assertTrue(requests.none { it.first.startsWith("POST /rest") })
        assertTrue(requests.any { it.first.contains("/rest/v1/expenses?") && it.first.contains("server_updated_at=gt.2026-10-06T10%3A00%3A01.123456%2B00%3A00") })
    }

    @Test fun refusesToMixAccounts() = runBlocking {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        val prefs = Preferences(ctx)
        prefs.set(Preferences.Keys.ownerUserId, "someone-else")
        val http = SupabaseHttp(SupabaseConfig(server.url("/").toString().trimEnd('/'), "pk"))
        val auth = AuthService(http, MemorySecureStore())
        auth.signIn("a@b.co", "Secret123")
        val repo = FinanceRepository(SpenDropDatabase.create(ctx, inMemory = true), CoroutineScope(Dispatchers.Default))
        assertFalse(SyncService(http, auth, repo, prefs).enable())
        prefs.set(Preferences.Keys.ownerUserId, null)
    }
}
