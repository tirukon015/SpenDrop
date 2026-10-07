package com.spendrop.app.ui.transaction

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.spendrop.app.AppContainer
import com.spendrop.app.data.Changes
import com.spendrop.app.importing.ImageTools
import com.spendrop.app.ui.components.PhotoStore
import com.spendrop.core.Ids
import com.spendrop.core.Money
import com.spendrop.core.accounts.AccountLinker
import com.spendrop.core.classify.ChannelLearning
import com.spendrop.core.classify.TransactionClassifier
import com.spendrop.core.duplicates.DuplicateCheckResult
import com.spendrop.core.duplicates.DuplicateDetector
import com.spendrop.core.duplicates.MovementDuplicateDetector
import com.spendrop.core.duplicates.ReconcileCandidate
import com.spendrop.core.duplicates.TransactionReconciliationEngine
import com.spendrop.core.ledger.MoneyMovementDraft
import com.spendrop.core.ledger.TransactionEntryType
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyDirection
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.MoneyMovementKind
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.parser.CategorySuggestion
import com.spendrop.core.parser.ChannelSuggestion
import com.spendrop.core.parser.ParsedTransaction
import com.spendrop.core.split.SplitDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** iOS commonFundingAccounts (funding accounts = WHERE the money came from; never a payment channel). */
val COMMON_FUNDING_ACCOUNTS = listOf("Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other")

/** Everything the transaction form shows. Expense fields and the money-movement draft live side by side. */
data class EditorState(
    val loaded: Boolean = false,
    val editingExpenseId: String? = null,
    val editingMovementId: String? = null,
    val entryType: TransactionEntryType = TransactionEntryType.EXPENSE,
    val amountText: String = "",
    val currency: String = "RM",
    val merchant: String = "",
    val category: ExpenseCategory = ExpenseCategory.FOOD,
    val categoryTouched: Boolean = false,
    val fundingAccount: String = "Maybank",
    val channel: PaymentChannel = PaymentChannel.UNKNOWN,
    val fundingInstrument: String? = null,
    val paymentSource: PaymentSource = PaymentSource.UNKNOWN,
    val date: Long = System.currentTimeMillis(),
    val notes: String = "",
    val reference: String? = null,
    val split: SplitDraft? = null,
    val movement: MoneyMovementDraft = MoneyMovementDraft.new(TransactionEntryType.MONEY_IN, System.currentTimeMillis()),
    // Import review
    val parsed: ParsedTransaction? = null,
    val imageFile: File? = null,
    val sourceType: ExpenseSourceType = ExpenseSourceType.MANUAL,
    val categoryHint: CategorySuggestion? = null,
    val channelHint: ChannelSuggestion? = null,
    val duplicate: DuplicateCheckResult? = null,
    // Dialogs / result
    val askDuplicate: Boolean = false,
    val movementDuplicateMessage: String? = null,
    val error: String? = null,
    val saving: Boolean = false,
    val saved: Boolean = false,
    /** The record being edited no longer exists: the screen closes after the message. */
    val notFound: Boolean = false,
) {
    val amountMinor: Long get() = Money.parseMinor(amountText) ?: 0
    val isExpense: Boolean get() = entryType == TransactionEntryType.EXPENSE
    val splitProblem: String? get() = split?.problem(amountMinor)
    val isValid: Boolean
        get() = if (isExpense) amountMinor > 0 && (split?.isValid(amountMinor) ?: true)
        else movement.copy(amountText = amountText, date = date).isValid
    val isReview: Boolean get() = parsed != null
}

class EditorViewModel(private val container: AppContainer) : ViewModel() {
    private val repo = container.repository
    private val _state = MutableStateFlow(EditorState())
    val state: StateFlow<EditorState> = _state
    private val snapshot: FinanceSnapshot get() = repo.snapshot.value ?: FinanceSnapshot()

    fun update(f: (EditorState) -> EditorState) = _state.update(f)

    // ---------------------------------------------------------------------------------------- set-up

    fun startNew(entryType: String, quickCash: Boolean, purpose: String?, kind: String?, personId: String?, currency: String?, amountMinor: Long?) {
        if (_state.value.loaded) return
        val type = TransactionEntryType.entries.firstOrNull { it.raw == entryType } ?: TransactionEntryType.EXPENSE
        val now = System.currentTimeMillis()
        val person = personId?.let { id -> snapshot.people.firstOrNull { it.id == id } }
        var movement = MoneyMovementDraft.new(if (type == TransactionEntryType.EXPENSE) TransactionEntryType.MONEY_IN else type, now)
        kind?.let { k -> MoneyMovementKind.entries.firstOrNull { it.raw == k } }?.let { k ->
            movement = movement.setEntryType(TransactionEntryType.of(k)).copy(kind = k, person = person, currency = currency ?: "RM")
        }
        val split = when (purpose) {
            "paidFor" -> SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR, method = com.spendrop.core.model.SplitMethod.AMOUNTS)
            else -> null
        }
        _state.value = EditorState(
            loaded = true,
            entryType = if (kind != null) TransactionEntryType.of(MoneyMovementKind.fromRaw(kind)) else type,
            fundingAccount = if (quickCash) "Cash" else "Maybank",
            channel = if (quickCash) PaymentChannel.CASH else PaymentChannel.UNKNOWN,
            paymentSource = if (quickCash) PaymentSource.CASH else PaymentSource.UNKNOWN,
            amountText = amountMinor?.let { Money.plain(it) } ?: "",
            currency = currency ?: "RM",
            movement = movement,
            split = split,
            date = now,
        )
    }

    fun startEditExpense(id: String) {
        if (_state.value.loaded) return
        viewModelScope.launch {
            val s = snapshot
            val e = s.expenses.firstOrNull { it.id == id } ?: return@launch _state.update { it.copy(notFound = true, error = "This transaction no longer exists.") }
            val shares = s.sharesOf(id)
            _state.value = EditorState(
                loaded = true, editingExpenseId = id, amountText = Money.plain(e.amountMinor), currency = e.currency,
                merchant = if (e.merchant == "Unknown") "" else e.merchant, category = e.category, categoryTouched = true,
                fundingAccount = e.effectiveFundingAccount, channel = e.paymentChannel, fundingInstrument = e.fundingInstrument,
                paymentSource = PaymentSource.fromRaw(e.paymentSourceRaw), date = e.date, notes = e.notes.orEmpty(),
                reference = e.transactionReference, split = SplitDraft.fromExpense(e, shares, s.people), sourceType = e.sourceType,
            )
        }
    }

    fun startEditMovement(id: String) {
        if (_state.value.loaded) return
        val s = snapshot
        val m = s.movements.firstOrNull { it.id == id } ?: return _state.update { it.copy(notFound = true, error = "This record no longer exists.") }
        val person = m.personId?.let { pid -> s.people.firstOrNull { it.id == pid } }
        val draft = MoneyMovementDraft.fromMovement(m, person)
        _state.value = EditorState(
            loaded = true, editingMovementId = id, entryType = draft.entryType, amountText = Money.plain(m.amountMinor),
            currency = m.currency, date = m.date, movement = draft, reference = m.transactionReference,
        )
    }

    /** Review of an imported screenshot / PDF / shared text (iOS ShareExtensionViewModel.applyParsedTransaction + applySuggestions). */
    private var reviewStarted = false

    fun startReview(parsed: ParsedTransaction, imageFile: File?, sourceType: ExpenseSourceType) {
        if (_state.value.loaded || reviewStarted) return
        reviewStarted = true
        // Wait for the database: a share can arrive before the first read on a cold start, and duplicate checks and
        // learned rules must see the real data.
        viewModelScope.launch { review(repo.snapshot.filterNotNull().first(), parsed, imageFile, sourceType) }
    }

    private fun review(s: FinanceSnapshot, parsed: ParsedTransaction, imageFile: File?, sourceType: ExpenseSourceType) {
        val evidence = CategorySuggestion(
            parsed.category ?: ExpenseCategory.OTHER,
            if (parsed.category == null) 0.0 else parsed.categoryConfidence,
            parsed.categoryReason ?: "No category evidence in this receipt",
        )
        val catSuggestion = TransactionClassifier.suggestion(parsed.merchant, evidence, s.classificationRules).suggestion
        val funding = parsed.displayFundingAccount
        val learned = ChannelLearning.suggestion(parsed.merchant, funding, parsed.paymentChannel, s.channelRules)
        val channelHint = learned ?: ChannelSuggestion(parsed.paymentChannel, parsed.channelConfidence, parsed.channelReason.orEmpty())
        val type = when (parsed.suggestedMovementKind?.direction) {
            MoneyDirection.IN -> TransactionEntryType.MONEY_IN
            MoneyDirection.OUT -> TransactionEntryType.MONEY_OUT
            else -> TransactionEntryType.EXPENSE // own transfers need two accounts: recorded as Transfer by hand
        }
        val now = System.currentTimeMillis()
        val date = parsed.date ?: now
        var movement = MoneyMovementDraft.new(if (type == TransactionEntryType.EXPENSE) TransactionEntryType.MONEY_IN else type, now)
        parsed.suggestedMovementKind?.takeIf { it.direction != MoneyDirection.INTERNAL }?.let { movement = movement.copy(kind = it) }
        val st = EditorState(
            loaded = true, entryType = type, amountText = parsed.amountMinor?.let { Money.plain(it) } ?: "", currency = parsed.currency,
            merchant = parsed.merchant.orEmpty(), category = catSuggestion.category, categoryTouched = true,
            fundingAccount = funding, channel = learned?.channel ?: parsed.paymentChannel, fundingInstrument = parsed.fundingInstrument,
            paymentSource = parsed.paymentSource ?: PaymentSource.UNKNOWN, date = date, notes = parsed.suggestedRemark.orEmpty(),
            reference = parsed.transactionReference, movement = movement, parsed = parsed, imageFile = imageFile, sourceType = sourceType,
            categoryHint = catSuggestion, channelHint = channelHint,
        )
        _state.value = st.copy(duplicate = duplicateCheck(st))
    }

    private fun duplicateCheck(st: EditorState): DuplicateCheckResult =
        DuplicateDetector.checkDuplicate(st.amountMinor, st.merchant, st.date, st.reference, snapshot.expenses, st.channel, st.fundingAccount)

    // ---------------------------------------------------------------------------------------- edits

    fun setAmount(text: String) = _state.update { st ->
        val next = st.copy(amountText = text)
        if (st.isReview) next.copy(duplicate = duplicateCheck(next)) else next
    }

    fun setMerchant(text: String) = _state.update { st ->
        // Learned category for a known merchant, unless the user picked one (iOS AddExpenseView)
        var next = st.copy(merchant = text)
        if (!st.categoryTouched && st.isExpense) {
            TransactionClassifier.rule(text, snapshot.classificationRules)?.let { rule ->
                if (rule.hitCount >= TransactionClassifier.TRUSTED_HIT_COUNT) ExpenseCategory.fromRawOrNull(rule.categoryRaw)?.let { next = next.copy(category = it) }
            }
        }
        next
    }

    fun setEntryType(type: TransactionEntryType) = _state.update { st ->
        st.copy(entryType = type, movement = if (type == TransactionEntryType.EXPENSE) st.movement else st.movement.setEntryType(type))
    }

    fun setSplitEnabled(on: Boolean) = _state.update {
        if (!on) it.copy(split = null)
        else it.copy(split = SplitDraft.lastTimeSuggestion(it.merchant, snapshot, it.editingExpenseId) ?: SplitDraft())
    }

    fun setPaidForSomeone() = _state.update {
        it.copy(split = SplitDraft(purpose = SplitDraft.Purpose.PAID_FOR, method = com.spendrop.core.model.SplitMethod.AMOUNTS))
    }

    fun dismissDialogs() = _state.update { it.copy(askDuplicate = false, movementDuplicateMessage = null, error = null) }

    // ---------------------------------------------------------------------------------------- save

    /** Save button: imports are checked for duplicates first (manual entries never are). */
    fun onSave(context: Context) {
        val st = _state.value
        if (!st.isValid || st.saving) return
        if (!st.isExpense) {
            if (st.isReview) {
                val m = st.movement.copy(amountText = st.amountText, date = st.date)
                val match = MovementDuplicateDetector.findMatch(st.amountMinor, st.date, st.reference, m.kind, snapshot.movements, st.editingMovementId)
                if (match != null) {
                    _state.update { it.copy(movementDuplicateMessage = "A ${match.kind.displayName.lowercase()} of the same amount on ${com.spendrop.app.ui.components.Fmt.date(match.date)} is already recorded.") }
                    return
                }
            }
            saveMovement(); return
        }
        if (st.isReview && st.duplicate?.isDuplicate == true) {
            _state.update { it.copy(askDuplicate = true) }
            return
        }
        saveExpense(context, mergeInto = null)
    }

    /**
     * Bulk Import: saves this draft through exactly the same path as the Save button (no dialogs; the duplicate choice
     * was made on the review card). [mergeInto] = "Merge with Existing". Returns true when the record was saved.
     */
    suspend fun commit(context: Context, mergeInto: Expense?): Boolean {
        val job = if (_state.value.isExpense) saveExpense(context, mergeInto) else saveMovement()
        job?.join()
        return _state.value.saved
    }

    fun saveMovement(): kotlinx.coroutines.Job? {
        val st = _state.value
        if (st.saving) return null
        _state.update { it.copy(saving = true, movementDuplicateMessage = null) }
        return viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                var draft = st.movement.copy(amountText = st.amountText, date = st.date, transactionReference = st.reference ?: st.movement.transactionReference)
                val extraAccounts = ArrayList<com.spendrop.core.model.Account>()
                if (st.isReview) {
                    // Account from the funding account text (Unknown stays unlinked; no duplicate accounts).
                    val res = AccountLinker.resolveAccount(st.fundingAccount, snapshot.accounts, st.currency, now)
                    res?.let { r -> if (r.isNew) extraAccounts += r.account; draft = draft.copy(accountId = r.account.id) }
                    val noteParts = listOf(st.merchant.trim(), st.notes.trim()).filter { it.isNotEmpty() }
                    draft = draft.copy(note = noteParts.joinToString(" · "), paymentChannel = st.channel)
                }
                val existing = st.editingMovementId?.let { id -> snapshot.movements.firstOrNull { it.id == id } }
                val movement: MoneyMovement? = if (existing != null) draft.applyTo(existing, now)
                else draft.newMovement(now, sourceType = if (st.isReview) st.sourceType else null)
                if (movement == null) {
                    _state.update { it.copy(saving = false, error = draft.issues.firstOrNull()?.message ?: "Check the details and try again.") }
                    return@launch
                }
                repo.apply(Changes(accounts = extraAccounts, movements = listOf(movement)))
                _state.update { it.copy(saving = false, saved = true) }
            } catch (e: Exception) {
                _state.update { it.copy(saving = false, error = "Couldn't save: ${e.message ?: "unknown error"}") }
            }
        }
    }

    fun saveExpense(context: Context, mergeInto: Expense?): kotlinx.coroutines.Job? {
        val st = _state.value
        if (st.saving) return null
        _state.update { it.copy(saving = true, askDuplicate = false) }
        return viewModelScope.launch {
            try {
                val s = snapshot
                val now = System.currentTimeMillis()
                val imageName = st.imageFile?.let { f -> withContext(Dispatchers.IO) { storeReceipt(context, f) } }
                val merchantTrim = st.merchant.trim()
                val finalMerchant = merchantTrim.ifEmpty { if (!st.isReview && st.category == ExpenseCategory.FOOD) "Food / Dining" else "Unknown" }
                // The legacy payment source follows the funding account the user chose (channel-like sources such as Apple Pay stay).
                val fromFunding = PaymentSource.entries.firstOrNull { it.raw.equals(st.fundingAccount.trim(), true) }
                var source = st.paymentSource
                if (source == PaymentSource.UNKNOWN || (!source.isChannelLike && fromFunding != source)) source = fromFunding ?: PaymentSource.UNKNOWN

                if (mergeInto != null) {
                    val merged = TransactionReconciliationEngine.reconcile(
                        mergeInto,
                        ReconcileCandidate(st.amountMinor, finalMerchant, st.date, st.category, st.fundingAccount, st.channel, st.reference,
                            st.notes.ifBlank { null }, imageName, null, st.fundingInstrument),
                        now,
                    )
                    val relinked = AccountLinker.relink(merged, s.accounts, now)
                    val extra = Changes(accounts = listOfNotNull(relinked.newAccount))
                    val shares = s.sharesOf(merged.id)
                    val splitSave = st.split?.takeIf { relinked.expense.amountMinor == st.amountMinor }?.apply(relinked.expense, shares, now)
                    if (splitSave != null) repo.saveExpense(splitSave.expense, splitSave.newShares, extra)
                    else repo.saveExpense(relinked.expense, shares, extra)
                } else {
                    val existing = st.editingExpenseId?.let { id -> s.expenses.firstOrNull { it.id == id } }
                    val base = existing ?: Expense(id = Ids.new(), amountMinor = st.amountMinor, date = st.date, createdAt = now, updatedAt = now)
                    var expense = base.copy(
                        amountMinor = st.amountMinor, currency = st.currency, merchant = finalMerchant, categoryRaw = st.category.raw,
                        fundingAccount = st.fundingAccount.trim().ifEmpty { "Unknown" }, paymentChannelRaw = st.channel.raw,
                        fundingInstrument = st.fundingInstrument, paymentSourceRaw = source.raw,
                        paymentMethodRaw = if (source.raw == base.paymentSourceRaw) base.paymentMethodRaw ?: source.defaultPaymentMethod else source.defaultPaymentMethod,
                        date = st.date, notes = st.notes.trim().ifEmpty { null }, transactionReference = st.reference,
                        sourceTypeRaw = if (existing != null) base.sourceTypeRaw else st.sourceType.raw,
                        imageRelativePath = imageName ?: base.imageRelativePath,
                        confidence = if (st.isReview) 1.0 else base.confidence, updatedAt = now,
                    )
                    val relink = AccountLinker.relink(expense, s.accounts, now)
                    expense = relink.expense
                    val currentShares = s.sharesOf(expense.id)
                    val split = st.split
                    val (finalExpense, shares) = when {
                        split != null -> split.apply(expense, currentShares, now)?.let { it.expense to it.newShares }
                            ?: run { _state.update { it.copy(saving = false, error = split.problem(st.amountMinor) ?: "The split doesn't add up.") }; return@launch }
                        currentShares.isNotEmpty() -> SplitDraft.removeSplit(expense, currentShares, now).let { it.expense to emptyList() }
                        else -> expense to emptyList()
                    }
                    val rules = listOfNotNull(
                        TransactionClassifier.learn(merchantTrim, st.category, s.classificationRules, accountId = finalExpense.accountId, now = now),
                    )
                    val channelRules = listOfNotNull(ChannelLearning.learn(merchantTrim, st.fundingAccount, st.channel, s.channelRules, now))
                    repo.saveExpense(finalExpense, shares, Changes(accounts = listOfNotNull(relink.newAccount), classificationRules = rules, channelRules = channelRules))
                }
                _state.update { it.copy(saving = false, saved = true) }
            } catch (e: Exception) {
                _state.update { it.copy(saving = false, error = "Couldn't save: ${e.message ?: "unknown error"}") }
            }
        }
    }

    /** Keeps an optimised copy of the screenshot in app-private storage (iOS keeps screenshots locally too). */
    private fun storeReceipt(context: Context, source: File): String? = runCatching {
        val bmp = ImageTools.decodeOriented(source, 1800) ?: return null
        val name = "${Ids.new()}.jpg"
        ImageTools.writeReceiptJpeg(bmp, File(PhotoStore.receiptsDir(context), name))
        bmp.recycle()
        name
    }.getOrNull()

    class Factory(private val container: AppContainer) : androidx.lifecycle.ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = EditorViewModel(container) as T
    }
}
