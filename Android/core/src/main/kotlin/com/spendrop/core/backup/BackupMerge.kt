package com.spendrop.core.backup

import com.spendrop.core.Ids
import com.spendrop.core.Money
import com.spendrop.core.model.Account
import com.spendrop.core.model.AccountType
import com.spendrop.core.model.ChannelRule
import com.spendrop.core.model.ClassificationRule
import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.ExpenseShare
import com.spendrop.core.model.ExpenseSourceType
import com.spendrop.core.model.FinanceSnapshot
import com.spendrop.core.model.MoneyMovement
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentMethodType
import com.spendrop.core.model.PaymentSource
import com.spendrop.core.model.Person
import com.spendrop.core.model.PersonPaymentMethod
import com.spendrop.core.model.SampleRecord
import com.spendrop.core.model.SettlementAllocation
import com.spendrop.core.model.SettlementKind
import java.time.Instant
import java.time.ZoneId

/** iOS `ImportSummary`: what applying a backup did. Records are matched by `id` only. */
data class ImportSummary(
    var expensesAdded: Int = 0,
    var expensesUpdated: Int = 0,
    var expensesKeptNewer: Int = 0,
    var possibleDuplicateExpenses: Int = 0,
    var profilesAdded: Int = 0,
    var profilesUpdated: Int = 0,
    var profilesKeptNewer: Int = 0,
    var profilesSharingName: Int = 0,
    var methodsAdded: Int = 0,
    var methodsUpdated: Int = 0,
    var accountsAdded: Int = 0,
    var accountsMatchedByName: Int = 0,
    var sharesRestored: Int = 0,
    var movementsAdded: Int = 0,
    var movementsUpdated: Int = 0,
    var movementsKeptNewer: Int = 0,
    var rulesRestored: Int = 0,
    var settlementsRestored: Int = 0,
    /** Relationship ids pointing to records missing from both the backup and this device (link left empty). */
    var missingReferences: Int = 0,
) {
    val message: String
        get() {
            val lines = mutableListOf(
                "Expenses: $expensesAdded added, $expensesUpdated updated.",
                "PayBook people: $profilesAdded added, $profilesUpdated updated.",
            )
            if (movementsAdded + movementsUpdated > 0) lines += "Money movements: $movementsAdded added, $movementsUpdated updated."
            if (accountsAdded > 0) lines += "Accounts: $accountsAdded added."
            val keptNewer = expensesKeptNewer + profilesKeptNewer + movementsKeptNewer
            if (keptNewer > 0) lines += "$keptNewer records on this device were newer and were kept."
            if (possibleDuplicateExpenses > 0) lines += "$possibleDuplicateExpenses imported expenses look similar to existing ones. They were imported, not skipped. Please review them."
            if (profilesSharingName > 0) lines += "$profilesSharingName imported people share a name with an existing person. They were kept separate."
            if (missingReferences > 0) lines += "$missingReferences links pointed to records that no longer exist and were left empty."
            return lines.joinToString("\n")
        }
}

/**
 * Result of a pure merge.
 * @property merged the complete local data after the merge (every local record kept, tombstones included).
 * @property changes only the records that were added or changed: upsert exactly these.
 * @property removedShareIds split shares the backup no longer lists for an expense it updated (iOS deletes them;
 *   in [merged]/[changes] they are tombstoned with `deletedAt = now`).
 */
data class BackupMergeResult(
    val merged: FinanceSnapshot,
    val changes: FinanceSnapshot,
    val removedShareIds: List<String>,
    val summary: ImportSummary,
)

/**
 * Port of iOS `UserDataBackupService.applyBackupPayload` (manual JSON import and cloud restore) as a pure function.
 *
 * - existing id: updated from the backup unless the device copy's `updatedAt` is newer (then counted as "kept newer");
 * - new id: imported even if it looks like an existing record (same reference, or same merchant + amount + day of
 *   month: reported as a possible duplicate, never skipped);
 * - people are never merged by name; accounts are matched by id, then by normalised name (one "Maybank");
 * - classification rules by id then merchant key, channel rules by id then merchant|funding key (newer wins);
 * - version-2 fields (account/payer/split) are applied only from version >= 2 files, so a v1 file never clears them;
 * - for an expense it updates, the backup's share list is the truth (missing shares are removed);
 * - nothing else on the device is ever removed.
 *
 * Android-only rules (iOS has no tombstones): a record tombstoned on this device counts as absent; if the backup
 * contains it, it comes back (deletedAt cleared, updatedAt = [now] so the restore wins over the tombstone in sync).
 * Accounts and shares have no `updatedAt` in the backup; when the backup changes one, its updatedAt becomes [now].
 *
 * @param zone time zone for the duplicate signature's "day of month" (iOS `Calendar.current`).
 */
object BackupMerge {
    fun apply(payload: BackupPayload, local: FinanceSnapshot, now: Long, zone: ZoneId = ZoneId.systemDefault()): BackupMergeResult {
        val s = ImportSummary()
        val isV2 = payload.version >= 2
        fun key(id: String) = Ids.normalize(id)

        // 1. Accounts
        val accounts = LinkedHashMap<String, Account>().apply { local.accounts.forEach { put(key(it.id), it) } }
        val accountRemap = HashMap<String, String>()
        val accountsByName = HashMap<String, Account>()
        for (a in local.accounts) if (a.deletedAt == null) {
            accountRemap[key(a.id)] = a.id
            BackupKeys.accountKey(a.name)?.let { accountsByName.putIfAbsent(it, a) }
        }
        for (dto in payload.accounts.orEmpty()) {
            val k = key(dto.id)
            val existing = accounts[k]
            val nameKey = BackupKeys.accountKey(dto.name)
            if (existing != null && existing.deletedAt == null) {
                val changed = existing.copy(name = dto.name, typeRaw = dto.typeRaw, currency = dto.currency, icon = dto.icon,
                    isArchived = dto.isArchived, sortIndex = dto.sortIndex)
                accounts[k] = if (changed != existing) changed.copy(updatedAt = now) else existing
                accountRemap[k] = existing.id
            } else if (nameKey != null && accountsByName[nameKey] != null) {
                accountRemap[k] = accountsByName.getValue(nameKey).id
                s.accountsMatchedByName++
            } else {
                val created = Account(
                    id = dto.id, name = dto.name, typeRaw = AccountType.fromRaw(dto.typeRaw).raw, currency = dto.currency,
                    icon = dto.icon, isArchived = dto.isArchived, sortIndex = dto.sortIndex, createdAt = dto.createdAt,
                    updatedAt = if (existing != null) now else dto.createdAt,
                )
                accounts[k] = created
                accountRemap[k] = created.id
                nameKey?.let { accountsByName[it] = created }
                s.accountsAdded++
            }
        }
        fun account(id: String?): String? {
            if (id == null) return null
            return accountRemap[key(id)] ?: run { s.missingReferences++; null }
        }

        // 2. People and their payment methods
        val people = LinkedHashMap<String, Person>().apply { local.people.forEach { put(key(it.id), it) } }
        val existingNames = local.people.filter { it.deletedAt == null }.map { it.name.lowercase() }.toSet()
        val methods = LinkedHashMap<String, PersonPaymentMethod>().apply { local.paymentMethods.forEach { put(key(it.id), it) } }
        for (dto in payload.paybookProfiles) {
            val k = key(dto.id)
            val found = people[k]?.takeIf { it.deletedAt == null }
            val profId: String
            if (found != null) {
                profId = found.id
                if (dto.updatedAt != null && found.updatedAt > dto.updatedAt) {
                    s.profilesKeptNewer++
                } else {
                    people[k] = found.copy(
                        name = dto.name, notes = dto.notes, isFrequent = dto.isFrequent ?: found.isFrequent,
                        isArchived = dto.isArchived ?: found.isArchived, updatedAt = dto.updatedAt ?: found.updatedAt,
                    )
                    s.profilesUpdated++
                }
            } else {
                if (dto.name.lowercase() in existingNames) s.profilesSharingName++
                val tomb = people[k]
                people[k] = Person(
                    id = dto.id, name = dto.name, notes = dto.notes, isFrequent = dto.isFrequent ?: false,
                    isArchived = dto.isArchived ?: false, createdAt = dto.createdAt ?: now,
                    updatedAt = if (tomb != null) now else dto.updatedAt ?: now,
                )
                profId = dto.id
                s.profilesAdded++
            }
            for (m in dto.paymentMethods) {
                val mk = key(m.id)
                val typeRaw = PaymentMethodType.entries.firstOrNull { it.raw == m.paymentTypeRaw }?.raw ?: PaymentMethodType.BANK_ACCOUNT.raw
                val method = methods[mk]?.takeIf { it.deletedAt == null }
                if (method != null) {
                    if (m.updatedAt != null && method.updatedAt > m.updatedAt) continue
                    methods[mk] = method.copy(
                        paymentTypeRaw = typeRaw, provider = m.provider, customProviderName = m.customProviderName,
                        accountIdentifier = m.accountIdentifier, label = m.label, notes = m.notes,
                        updatedAt = m.updatedAt ?: method.updatedAt, personId = profId,
                    )
                    s.methodsUpdated++
                } else {
                    val tomb = methods[mk]
                    methods[mk] = PersonPaymentMethod(
                        id = m.id, personId = profId, paymentTypeRaw = typeRaw, provider = m.provider,
                        customProviderName = m.customProviderName, accountIdentifier = m.accountIdentifier, label = m.label,
                        notes = m.notes, createdAt = m.createdAt ?: now, updatedAt = if (tomb != null) now else m.updatedAt ?: now,
                    )
                    s.methodsAdded++
                }
            }
        }
        fun person(id: String?): String? {
            if (id == null) return null
            val p = people[key(id)]
            if (p != null && p.deletedAt == null) return p.id
            s.missingReferences++
            return null
        }

        // 3. Expenses, with account, payer and split
        val expenses = LinkedHashMap<String, Expense>().apply { local.expenses.forEach { put(key(it.id), it) } }
        val liveLocal = local.expenses.filter { it.deletedAt == null }
        val existingRefs = liveLocal.mapNotNull { it.transactionReference?.takeIf { r -> r.isNotEmpty() } }.toSet()
        val existingSignatures = liveLocal.map { signature(it.merchant, Money.major(it.amountMinor), it.date, zone) }.toSet()
        val shares = LinkedHashMap<String, ExpenseShare>().apply { local.shares.forEach { put(key(it.id), it) } }
        val removedShares = mutableListOf<String>()

        for (dto in payload.expenses) {
            val k = key(dto.id)
            val existing = expenses[k]?.takeIf { it.deletedAt == null }
            var expense: Expense
            if (existing != null) {
                if (dto.updatedAt != null && existing.updatedAt > dto.updatedAt) {
                    s.expensesKeptNewer++
                    continue
                }
                expense = applyDto(dto, existing)
                s.expensesUpdated++
            } else {
                val sameRef = dto.transactionReference?.let { it.isNotEmpty() && it in existingRefs } ?: false
                if (sameRef || signature(dto.merchant, dto.amount, dto.date, zone) in existingSignatures) s.possibleDuplicateExpenses++
                expense = makeExpense(dto)
                if (expenses[k] != null) expense = expense.copy(updatedAt = now)
                s.expensesAdded++
            }

            if (isV2) {
                expense = expense.copy(
                    accountId = account(dto.accountId), paidByMe = dto.paidByMe ?: true, payerId = person(dto.payerId),
                    payerNameSnapshot = dto.payerNameSnapshot, splitMethodRaw = dto.splitMethodRaw,
                )
                val backupShares = dto.shares.orEmpty()
                val keep = backupShares.map { key(it.id) }.toSet()
                for ((sk, stale) in shares.entries.toList()) {
                    if (stale.deletedAt == null && key(stale.expenseId) == k && sk !in keep) {
                        shares[sk] = stale.copy(deletedAt = now, updatedAt = now)
                        removedShares += stale.id
                    }
                }
                for (sd in backupShares) {
                    val sk = key(sd.id)
                    val old = shares[sk]
                    val base = old ?: ExpenseShare(id = sd.id, expenseId = expense.id, nameSnapshot = sd.nameSnapshot,
                        amountMinor = sd.amountMinor, createdAt = now, updatedAt = now)
                    val updated = base.copy(
                        expenseId = expense.id, personId = if (sd.isMe) null else person(sd.personId), isMe = sd.isMe,
                        nameSnapshot = sd.nameSnapshot, amountMinor = sd.amountMinor, parts = sd.parts,
                        enteredMinor = sd.enteredMinor, sortIndex = sd.sortIndex, deletedAt = null,
                    )
                    shares[sk] = if (old != null && updated != old) updated.copy(updatedAt = now) else updated
                    s.sharesRestored++
                }
            }
            expenses[k] = expense
        }

        // 4. Money movements
        val movements = LinkedHashMap<String, MoneyMovement>().apply { local.movements.forEach { put(key(it.id), it) } }
        for (dto in payload.moneyMovements.orEmpty()) {
            val k = key(dto.id)
            val found = movements[k]?.takeIf { it.deletedAt == null }
            if (found != null) {
                if (found.updatedAt > dto.updatedAt) { s.movementsKeptNewer++; continue }
                s.movementsUpdated++
            } else {
                s.movementsAdded++
            }
            val linked = dto.linkedExpenseId?.let { id ->
                expenses[key(id)]?.takeIf { it.deletedAt == null }?.id ?: run { s.missingReferences++; null }
            }
            movements[k] = MoneyMovement(
                id = found?.id ?: dto.id, kindRaw = dto.kindRaw, directionRaw = dto.directionRaw, amountMinor = dto.amountMinor,
                currency = dto.currency, date = dto.date, personId = person(dto.personId), personNameSnapshot = dto.personNameSnapshot,
                linkedExpenseId = linked, linkedExpenseSnapshot = dto.linkedExpenseSnapshot, accountId = account(dto.accountId),
                counterAccountId = account(dto.counterAccountId), note = dto.note, transactionReference = dto.transactionReference,
                sourceTypeRaw = dto.sourceTypeRaw, paymentChannelRaw = dto.paymentChannelRaw, createdAt = dto.createdAt,
                updatedAt = if (found == null && movements[k] != null) now else dto.updatedAt,
            )
        }

        // 5. Classification rules: by id, then by merchant key. Newer (or equal) wins.
        val rules = LinkedHashMap<String, ClassificationRule>().apply { local.classificationRules.forEach { put(key(it.id), it) } }
        val rulesByKey = HashMap<String, String>()
        local.classificationRules.filter { it.deletedAt == null }.forEach { rulesByKey.putIfAbsent(it.merchantKey, key(it.id)) }
        for (dto in payload.classificationRules.orEmpty()) {
            val foundKey = rules[key(dto.id)]?.takeIf { it.deletedAt == null }?.let { key(dto.id) } ?: rulesByKey[dto.merchantKey]
            val rule = foundKey?.let { rules[it] }
            if (rule != null) {
                if (dto.updatedAt < rule.updatedAt) continue
                rules[foundKey] = rule.copy(categoryRaw = dto.categoryRaw, suggestedTypeRaw = dto.suggestedTypeRaw,
                    accountId = dto.accountId, hitCount = dto.hitCount, updatedAt = dto.updatedAt)
            } else {
                val tomb = rules[key(dto.id)]
                rules[key(dto.id)] = ClassificationRule(
                    id = dto.id, merchantKey = dto.merchantKey, categoryRaw = dto.categoryRaw, suggestedTypeRaw = dto.suggestedTypeRaw,
                    accountId = dto.accountId, hitCount = dto.hitCount, createdAt = dto.createdAt,
                    updatedAt = if (tomb != null) maxOf(now, dto.updatedAt) else dto.updatedAt,
                )
                rulesByKey[dto.merchantKey] = key(dto.id)
            }
            s.rulesRestored++
        }

        // 6. Channel rules: by id, then by merchant + funding key. Newer (or equal) wins.
        val channelRules = LinkedHashMap<String, ChannelRule>().apply { local.channelRules.forEach { put(key(it.id), it) } }
        val channelByKey = HashMap<String, String>()
        local.channelRules.filter { it.deletedAt == null }.forEach { channelByKey.putIfAbsent(it.merchantKey + "|" + it.fundingKey, key(it.id)) }
        for (dto in payload.channelRules.orEmpty()) {
            val pair = dto.merchantKey + "|" + dto.fundingKey
            val foundKey = channelRules[key(dto.id)]?.takeIf { it.deletedAt == null }?.let { key(dto.id) } ?: channelByKey[pair]
            val rule = foundKey?.let { channelRules[it] }
            if (rule != null) {
                if (dto.updatedAt < rule.updatedAt) continue
                channelRules[foundKey] = rule.copy(channelRaw = dto.channelRaw, hitCount = dto.hitCount, updatedAt = dto.updatedAt)
            } else {
                val tomb = channelRules[key(dto.id)]
                channelRules[key(dto.id)] = ChannelRule(
                    id = dto.id, merchantKey = dto.merchantKey, fundingKey = dto.fundingKey, channelRaw = dto.channelRaw,
                    hitCount = dto.hitCount, createdAt = dto.createdAt,
                    updatedAt = if (tomb != null) maxOf(now, dto.updatedAt) else dto.updatedAt,
                )
                channelByKey[pair] = key(dto.id)
            }
        }

        // 7. Settlements and the sample-data register (version 4): matched by id, only added.
        val allocations = LinkedHashMap<String, SettlementAllocation>().apply { local.allocations.forEach { put(key(it.id), it) } }
        for (a in payload.settlementAllocations.orEmpty()) {
            val k = key(a.id)
            val old = allocations[k]
            if (old != null && old.deletedAt == null) continue
            allocations[k] = SettlementAllocation(
                id = a.id, groupId = a.groupID, kindRaw = SettlementKind.fromRaw(a.kindRaw).raw, paymentId = a.paymentID,
                expenseId = a.expenseID, loanId = a.loanID, personId = a.personID, direction = a.direction,
                amountMinor = a.amountMinor, currency = a.currency, date = a.date, createdAt = a.createdAt,
                updatedAt = if (old != null) now else a.createdAt,
            )
            s.settlementsRestored++
        }
        val sample = LinkedHashMap<String, SampleRecord>().apply { local.sampleRecords.forEach { put(key(it.recordId), it) } }
        for (r in payload.sampleRecords.orEmpty()) {
            if (key(r.recordID) in sample || r.entityRaw !in SAMPLE_ENTITIES) continue
            sample[key(r.recordID)] = SampleRecord(recordId = r.recordID, entityRaw = r.entityRaw, createdAt = r.createdAt)
        }

        val merged = FinanceSnapshot(
            expenses = expenses.values.toList(), shares = shares.values.toList(), accounts = accounts.values.toList(),
            people = people.values.toList(), paymentMethods = methods.values.toList(), movements = movements.values.toList(),
            allocations = allocations.values.toList(), classificationRules = rules.values.toList(),
            channelRules = channelRules.values.toList(), sampleRecords = sample.values.toList(),
        )
        fun <T> changed(after: Collection<T>, before: List<T>, id: (T) -> String): List<T> {
            val old = before.associateBy { key(id(it)) }
            return after.filter { old[key(id(it))] != it }
        }
        val changes = FinanceSnapshot(
            expenses = changed(merged.expenses, local.expenses) { it.id },
            shares = changed(merged.shares, local.shares) { it.id },
            accounts = changed(merged.accounts, local.accounts) { it.id },
            people = changed(merged.people, local.people) { it.id },
            paymentMethods = changed(merged.paymentMethods, local.paymentMethods) { it.id },
            movements = changed(merged.movements, local.movements) { it.id },
            allocations = changed(merged.allocations, local.allocations) { it.id },
            classificationRules = changed(merged.classificationRules, local.classificationRules) { it.id },
            channelRules = changed(merged.channelRules, local.channelRules) { it.id },
            sampleRecords = changed(merged.sampleRecords, local.sampleRecords) { it.recordId },
        )
        return BackupMergeResult(merged, changes, removedShares, s)
    }

    /** iOS `SampleDataRecord.Entity` raw values. */
    val SAMPLE_ENTITIES = setOf("expense", "person", "paymentMethod", "account", "movement", "allocation", "rule")

    /** iOS `expenseSignature`: "\(merchant.lowercased())_\(amount)_\(day of month)" (amount as Swift prints a Double). */
    fun signature(merchant: String, amount: Double, date: Long, zone: ZoneId): String =
        "${merchant.lowercase()}_${amount}_${Instant.ofEpochMilli(date).atZone(zone).dayOfMonth}"

    private val channelLikeSources = setOf(
        PaymentSource.APPLE_PAY, PaymentSource.QR_PAYMENT, PaymentSource.BANK_TRANSFER, PaymentSource.PHYSICAL_CARD, PaymentSource.UNKNOWN,
    )

    /** iOS `makeExpense(from:)` followed by the `Expense.init` normalisation (defaults, funding and channel derivation). */
    fun makeExpense(dto: ExpenseDto): Expense {
        val category = ExpenseCategory.fromRawOrNull(dto.categoryRaw) ?: ExpenseCategory.PERSONAL
        val src = PaymentSource.fromRawOrNull(dto.paymentSourceRaw) ?: PaymentSource.TOUCH_N_GO
        val bank = dto.underlyingBankRaw?.let { PaymentSource.fromRawOrNull(it) }
        val sourceType = ExpenseSourceType.entries.firstOrNull { it.raw == dto.sourceTypeRaw } ?: ExpenseSourceType.SCREENSHOT
        val channelIn = dto.paymentChannelRaw?.let { PaymentChannel.fromRawOrNull(it) } ?: PaymentChannel.UNKNOWN
        val fundingIn = dto.fundingAccount ?: bank?.raw ?: (if (src !in channelLikeSources) src.raw else "Unknown")
        val method = dto.paymentMethodRaw ?: src.defaultPaymentMethod

        // Expense.init: funding account derivation
        val funding = when {
            fundingIn.isNotBlank() -> fundingIn
            bank != null && bank != PaymentSource.UNKNOWN -> bank.raw
            src !in channelLikeSources && src != PaymentSource.OTHER -> src.raw
            else -> "Unknown"
        }
        // Expense.init: payment channel derivation (never guesses beyond these rules)
        val channel = when {
            channelIn != PaymentChannel.UNKNOWN -> channelIn
            src == PaymentSource.APPLE_PAY -> PaymentChannel.APPLE_PAY
            src == PaymentSource.QR_PAYMENT || dto.paymentMethodRaw == "duitnow_qr" -> PaymentChannel.QR_PAYMENT
            src == PaymentSource.BANK_TRANSFER || dto.paymentMethodRaw == "bank_transfer" -> PaymentChannel.BANK_TRANSFER
            src == PaymentSource.PHYSICAL_CARD || dto.paymentMethodRaw == "card" -> PaymentChannel.CARD
            src == PaymentSource.CASH || dto.paymentMethodRaw == "cash" -> PaymentChannel.CASH
            else -> PaymentChannel.UNKNOWN
        }
        return Expense(
            id = dto.id,
            amountMinor = Money.minorUnits(dto.amount),
            currency = dto.currency,
            merchant = if (dto.merchant.isBlank()) "Unknown" else dto.merchant,
            categoryRaw = category.raw,
            fundingAccount = funding,
            paymentChannelRaw = channel.raw,
            fundingInstrument = dto.fundingInstrument,
            paymentSourceRaw = src.raw,
            underlyingBankRaw = bank?.raw,
            paymentMethodRaw = method,
            date = dto.date,
            notes = dto.notes?.takeUnless { it.isBlank() },
            transactionReference = dto.transactionReference,
            externalTransactionId = dto.externalTransactionId,
            matchingStatusRaw = dto.matchingStatusRaw ?: "UNMATCHED",
            matchingConfidence = dto.matchingConfidence,
            sourceTypeRaw = sourceType.raw,
            ocrText = dto.ocrText,
            confidence = dto.confidence,
            imageRelativePath = dto.imageRelativePath,
            isSampleData = dto.isSampleData,
            createdAt = dto.createdAt,
            updatedAt = dto.updatedAt ?: dto.createdAt,
        )
    }

    /** iOS `apply(_:to:)`: fields added after format 1 are only applied when present, so old files never clear them. */
    fun applyDto(dto: ExpenseDto, e: Expense): Expense = e.copy(
        amountMinor = Money.minorUnits(dto.amount),
        currency = dto.currency,
        merchant = dto.merchant,
        categoryRaw = dto.categoryRaw,
        paymentSourceRaw = dto.paymentSourceRaw,
        underlyingBankRaw = dto.underlyingBankRaw,
        paymentMethodRaw = dto.paymentMethodRaw,
        date = dto.date,
        notes = dto.notes,
        transactionReference = dto.transactionReference,
        sourceTypeRaw = dto.sourceTypeRaw,
        ocrText = dto.ocrText,
        isSampleData = dto.isSampleData,
        createdAt = dto.createdAt,
        paymentChannelRaw = dto.paymentChannelRaw ?: e.paymentChannelRaw,
        fundingAccount = dto.fundingAccount ?: e.fundingAccount,
        fundingInstrument = dto.fundingInstrument,
        matchingStatusRaw = dto.matchingStatusRaw ?: e.matchingStatusRaw,
        imageRelativePath = dto.imageRelativePath ?: e.imageRelativePath,
        confidence = dto.confidence ?: e.confidence,
        externalTransactionId = dto.externalTransactionId ?: e.externalTransactionId,
        matchingConfidence = dto.matchingConfidence ?: e.matchingConfidence,
        updatedAt = dto.updatedAt ?: e.updatedAt,
    )
}
