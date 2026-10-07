package com.spendrop.app.ui.ask

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.spendrop.app.AppContainer
import com.spendrop.app.ai.AskAnswer
import com.spendrop.app.ai.AskApi
import com.spendrop.app.ai.AskChatResponse
import com.spendrop.app.ai.AskError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One question and what came back for it. */
data class AskTurn(
    val id: Long,
    val question: String,
    val answer: AskAnswer? = null,
    val error: String? = null,
    val loading: Boolean = false,
)

data class AskUiState(
    val turns: List<AskTurn> = emptyList(),
    /** Server-side conversation; sent with every follow-up so "and last month?" keeps its context. */
    val conversationId: String? = null,
    /** Set when the server or the session says the user must sign in again (401 / expired session). */
    val signInMessage: String? = null,
) {
    val sending: Boolean get() = turns.any { it.loading }
}

/**
 * Holds the Ask SpenDrop conversation for as long as the screen is on the back stack. The conversation lives on the
 * server; this only keeps what is shown. Nothing here touches local records.
 */
class AskViewModel(private val ask: suspend (message: String, conversationId: String?) -> AskChatResponse) : ViewModel() {
    private val _state = MutableStateFlow(AskUiState())
    val state: StateFlow<AskUiState> = _state
    private var nextId = 1L
    private var job: Job? = null

    fun send(text: String) {
        val q = text.trim().take(AskApi.MAX_MESSAGE)
        if (q.isEmpty() || _state.value.sending) return
        val turn = AskTurn(nextId++, q, loading = true)
        _state.update { it.copy(turns = it.turns + turn, signInMessage = null) }
        run(turn.id, q)
    }

    /** Asks the same question again for a turn that failed. */
    fun retry(turnId: Long) {
        val turn = _state.value.turns.firstOrNull { it.id == turnId } ?: return
        if (_state.value.sending || turn.answer != null) return
        replace(turnId) { it.copy(error = null, loading = true) }
        _state.update { it.copy(signInMessage = null) }
        run(turnId, turn.question)
    }

    /** Starts over: a new server conversation on the next question. */
    fun newChat() {
        job?.cancel()
        _state.value = AskUiState()
    }

    /** After the user signs in again, failed turns can be retried. */
    fun clearSignIn() = _state.update { it.copy(signInMessage = null) }

    private fun run(turnId: Long, question: String) {
        val conversation = _state.value.conversationId
        job = viewModelScope.launch {
            try {
                val r = ask(question, conversation)
                replace(turnId) { it.copy(answer = r.answer, loading = false, error = null) }
                _state.update { it.copy(conversationId = r.conversationId) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: AskError.SignInRequired) {
                replace(turnId) { it.copy(loading = false, error = e.message) }
                _state.update { it.copy(signInMessage = e.message) }
            } catch (e: AskError) {
                replace(turnId) { it.copy(loading = false, error = e.message ?: AskError.GENERIC_MESSAGE) }
            } catch (_: Exception) {
                replace(turnId) { it.copy(loading = false, error = AskError.GENERIC_MESSAGE) }
            }
        }
    }

    private fun replace(id: Long, f: (AskTurn) -> AskTurn) =
        _state.update { s -> s.copy(turns = s.turns.map { if (it.id == id) f(it) else it }) }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            AskViewModel { message, conversationId -> container.askApi.chat(message, conversationId) } as T
    }
}
