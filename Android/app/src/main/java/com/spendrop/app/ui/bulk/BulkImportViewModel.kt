package com.spendrop.app.ui.bulk

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.spendrop.app.container
import com.spendrop.app.importing.ImportProcessor
import com.spendrop.app.importing.Intake
import com.spendrop.app.importing.IntakeItem
import com.spendrop.app.ui.transaction.EditorState
import com.spendrop.app.ui.transaction.EditorViewModel
import com.spendrop.core.Ids
import com.spendrop.core.bulk.BulkReview
import com.spendrop.core.duplicates.DuplicateCheckResult
import com.spendrop.core.duplicates.MovementDuplicateDetector
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.parser.ParsedTransaction
import com.spendrop.core.parser.ParsingConfidence
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** One selected screenshot and how far it got. */
data class Shot(val index: Int, val item: IntakeItem, val state: ShotState)

enum class ShotState { WAITING, PROCESSING, DONE, UNABLE }

/** One detected transaction: a NORMAL editor draft (the same view model as Add / Review) plus its queue state. */
data class Draft(
    val id: String,
    val shotIndex: Int,
    val vm: EditorViewModel,
    val removed: Boolean = false,
    val choice: BulkReview.DuplicateChoice? = null,
    val expanded: Boolean = false,
    /** Already saved by this import (kept in the list, never checked or saved again). */
    val saved: Boolean = false,
)

enum class BulkPhase { LOADING, PROCESSING, REVIEW, SAVING, DONE }

data class BulkUi(
    val phase: BulkPhase = BulkPhase.LOADING,
    val shots: List<Shot> = emptyList(),
    val drafts: List<Draft> = emptyList(),
    /** Shots the user dismissed from the "Unable to detect" list. */
    val dismissedShots: Set<Int> = emptySet(),
    val saved: Int = 0,
    val failed: Int = 0,
    val saveProgress: Int = 0,
)

/** A draft as the review queue sees it right now. */
data class DraftView(val draft: Draft, val state: EditorState, val duplicate: DuplicateCheckResult, val facts: BulkReview.DraftFacts) {
    val status: BulkReview.Status get() = BulkReview.status(facts)
    val willSave: Boolean get() = !draft.saved && BulkReview.willSave(facts)
}

/**
 * Bulk Screenshot Import (Common/BusinessRules/bulk-import.md). Screenshots are read two at a time (OCR is heavy on
 * low-end phones); every detected transaction becomes its own editor draft; nothing is saved until "Add N".
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BulkImportViewModel(app: Application) : AndroidViewModel(app) {
    private val container = app.container
    private val processor = ImportProcessor(app)
    private val _ui = MutableStateFlow(BulkUi())
    val ui: StateFlow<BulkUi> = _ui
    private var started = false

    /** Every draft's live editor state, re-evaluated against saved records and the earlier drafts. */
    val views: StateFlow<List<DraftView>> = _ui.flatMapLatest { u ->
        if (u.drafts.isEmpty()) flowOf(emptyList())
        else combine(combine(u.drafts.map { it.vm.state }) { it.toList() }, container.repository.snapshot) { states, snap ->
            evaluate(u.drafts, states, snap ?: FinanceSnapshot())
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private var source = ExpenseSourceType.SCREENSHOT

    fun start(load: suspend () -> List<IntakeItem>, source: ExpenseSourceType = ExpenseSourceType.SCREENSHOT) {
        if (started) return
        started = true
        this.source = source
        viewModelScope.launch {
            val items = load().take(MAX)
            _ui.value = BulkUi(BulkPhase.PROCESSING, items.mapIndexed { i, it -> Shot(i, it, if (it is IntakeItem.Unreadable) ShotState.UNABLE else ShotState.WAITING) })
            val permits = Semaphore(2)
            val results = items.mapIndexed { i, item ->
                async {
                    if (item is IntakeItem.Unreadable) return@async emptyList<ParsedTransaction>()
                    permits.withPermit {
                        setShot(i, ShotState.PROCESSING)
                        val found = runCatching { processor.detectAll(item) }.getOrDefault(emptyList())
                        setShot(i, if (found.isEmpty()) ShotState.UNABLE else ShotState.DONE)
                        found
                    }
                }
            }.awaitAll()
            // Drafts keep the order of the screenshots (and of rows inside a screenshot).
            val drafts = results.flatMapIndexed { i, parsedList -> parsedList.map { newDraft(i, it) } }
            _ui.update { it.copy(phase = BulkPhase.REVIEW, drafts = drafts) }
        }
    }

    private fun setShot(i: Int, s: ShotState) = _ui.update { u -> u.copy(shots = u.shots.map { if (it.index == i) it.copy(state = s) else it }) }

    private fun newDraft(shotIndex: Int, parsed: ParsedTransaction): Draft {
        val vm = EditorViewModel(container)
        val image = (_ui.value.shots.getOrNull(shotIndex)?.item as? IntakeItem.Image)?.file
        vm.startReview(parsed, image, source)
        return Draft(Ids.new(), shotIndex, vm)
    }

    /** "Enter Manually" for a screenshot nothing was detected in: an empty normal draft with that screenshot. */
    fun enterManually(shotIndex: Int) = _ui.update { u ->
        val d = newDraft(shotIndex, ParsedTransaction(confidence = ParsingConfidence.LOW)).copy(expanded = true)
        val at = u.drafts.indexOfLast { it.shotIndex <= shotIndex } + 1
        u.copy(drafts = u.drafts.toMutableList().apply { add(at, d) }, dismissedShots = u.dismissedShots + shotIndex)
    }

    fun clearFailed() = _ui.update { it.copy(failed = 0) }
    fun dismissShot(shotIndex: Int) = _ui.update { it.copy(dismissedShots = it.dismissedShots + shotIndex) }
    fun toggle(id: String) = updateDraft(id) { it.copy(expanded = !it.expanded) }
    fun remove(id: String) = updateDraft(id) { it.copy(removed = true, expanded = false) }
    fun restore(id: String) = updateDraft(id) { it.copy(removed = false) }
    fun choose(id: String, c: BulkReview.DuplicateChoice) = updateDraft(id) { it.copy(choice = c) }
    private fun updateDraft(id: String, f: (Draft) -> Draft) = _ui.update { u -> u.copy(drafts = u.drafts.map { if (it.id == id) f(it) else it }) }

    /** Saves the included drafts one by one through the normal editor save path. Each becomes its own record. */
    fun saveAll(context: Context, onDone: () -> Unit) {
        if (_ui.value.phase == BulkPhase.SAVING) return
        val toSave = views.value.filter { it.willSave }
        _ui.update { it.copy(phase = BulkPhase.SAVING, saveProgress = 0, failed = 0) }
        viewModelScope.launch {
            var saved = 0; var failed = 0
            val repo = container.repository
            toSave.forEachIndexed { i, v ->
                val merge = if (v.draft.choice == BulkReview.DuplicateChoice.MERGE) v.duplicate.matchedExpense else null
                val before = repo.snapshot.value
                if (v.draft.vm.commit(context, merge)) {
                    saved++
                    updateDraft(v.draft.id) { it.copy(saved = true, expanded = false) }
                    // Each save goes through the normal path, which reads the current snapshot (accounts, learned rules).
                    // Wait for this save to reach it so the next one doesn't create the same account or rule again.
                    withTimeoutOrNull(5_000) { repo.snapshot.first { it !== before } }
                } else failed++
                _ui.update { it.copy(saveProgress = i + 1) }
            }
            // Anything that couldn't be saved stays in the queue (the saved ones are marked) so it can be fixed and retried.
            _ui.update { it.copy(phase = if (failed == 0) BulkPhase.DONE else BulkPhase.REVIEW, saved = it.saved + saved, failed = failed) }
            if (failed == 0) onDone()
        }
    }

    override fun onCleared() {
        _ui.value.shots.forEach { Intake.discard(it.item) }
    }

    companion object {
        const val MAX = 30

        /** Status inputs for every draft (pure; also used by tests). */
        fun evaluate(drafts: List<Draft>, states: List<EditorState>, snapshot: FinanceSnapshot): List<DraftView> {
            val earlier = ArrayList<Expense>()
            return drafts.mapIndexed { i, d ->
                val st = states[i]
                val dup = when {
                    d.removed || d.saved || !st.loaded -> DuplicateCheckResult.NONE
                    st.isExpense -> BulkReview.duplicate(st.amountMinor, st.merchant, st.date, st.reference, snapshot.expenses, earlier, st.channel, st.fundingAccount)
                    else -> MovementDuplicateDetector.findMatch(st.amountMinor, st.date, st.reference, st.movement.kind, snapshot.movements)
                        ?.let { DuplicateCheckResult(true, null, "A ${it.kind.displayName.lowercase()} of the same amount is already recorded.") } ?: DuplicateCheckResult.NONE
                }
                if (!d.removed && !d.saved && st.loaded && st.isExpense) earlier += Expense(
                    id = d.id, amountMinor = st.amountMinor, merchant = st.merchant.ifBlank { "Unknown" }, date = st.date,
                    transactionReference = st.reference, paymentChannelRaw = st.channel.raw, fundingAccount = st.fundingAccount,
                    createdAt = st.date, updatedAt = st.date,
                )
                val p = st.parsed
                DraftView(d, st, dup, BulkReview.DraftFacts(
                    valid = st.loaded && st.isValid,
                    merchantFound = st.merchant.isNotBlank() || !st.isExpense,
                    confidence = p?.confidence ?: ParsingConfidence.LOW,
                    failedOrBalanceOnly = p?.isFailedTransaction == true || p?.isBalanceOrLimitOnly == true,
                    duplicate = dup, choice = d.choice, removed = d.removed,
                ))
            }
        }
    }
}
