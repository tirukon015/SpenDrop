package com.spendrop.app.ui.ask

import com.spendrop.app.ai.AskAnswer
import com.spendrop.app.ai.AskChatResponse
import com.spendrop.app.ai.AskError
import com.spendrop.app.ai.AskEvidence
import com.spendrop.app.cloud.AuthUser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AskViewModelTest {
    @Before fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())
    @After fun tearDown() = Dispatchers.resetMain()

    @Test fun followUpsCarryTheConversationId_andNewChatStartsOver() {
        val sent = mutableListOf<Pair<String, String?>>()
        val vm = AskViewModel { m, c -> sent += m to c; AskChatResponse("conv-1", AskAnswer(text = "ok")) }
        vm.send("How much this week?")
        vm.send("And last week?")
        assertEquals(listOf("How much this week?" to null, "And last week?" to "conv-1"), sent)
        assertEquals(2, vm.state.value.turns.count { it.answer != null })
        vm.newChat()
        assertEquals(0, vm.state.value.turns.size)
        vm.send("Hi")
        assertEquals("Hi" to null, sent.last())
    }

    @Test fun offlineErrorCanBeRetried() {
        var fail = true
        val vm = AskViewModel { _, _ -> if (fail) throw AskError.Offline else AskChatResponse("c", AskAnswer(text = "ok")) }
        vm.send("Hi")
        val t = vm.state.value.turns.single()
        assertEquals(AskError.OFFLINE_MESSAGE, t.error)
        fail = false
        vm.retry(t.id)
        assertEquals("ok", vm.state.value.turns.single().answer?.text)
        assertNull(vm.state.value.turns.single().error)
    }

    @Test fun unauthorizedShowsSignIn() {
        val vm = AskViewModel { _, _ -> throw AskError.SignInRequired(AskError.SESSION_EXPIRED_MESSAGE) }
        vm.send("Hi")
        assertEquals(AskError.SESSION_EXPIRED_MESSAGE, vm.state.value.signInMessage)
        vm.clearSignIn()
        assertNull(vm.state.value.signInMessage)
    }

    @Test fun greetingRespectsShowMyName() {
        assertEquals("Ann", greetingName(AuthUser("id", "a@b.co", "Ann Lee"), showName = true))
        assertEquals("rukon", greetingName(AuthUser("id", "rukon@example.com", null), showName = true))
        assertNull(greetingName(AuthUser("id", "a@b.co", "Ann Lee"), showName = false))
    }

    @Test fun evidenceLineAndMoney() {
        assertEquals("Based on 3 transactions · This week · Food", evidenceLine(AskEvidence("t", 3, "This week", "Food", "")))
        assertEquals("Based on 1 transaction", evidenceLine(AskEvidence("t", 1, "", " ", "")))
        assertEquals("RM 1,234.50", askMoney(123450, "MYR"))
    }
}
