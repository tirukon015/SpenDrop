import Foundation
import SwiftData

// Mapping between the SwiftData models and the cloud rows — the same columns, value rules and caps as Android's
// CloudRows/Sanitize and the Web's backup import (ids lower-case UUID text, timestamps ISO-8601 with milliseconds,
// money in integer minor units). `user_id` and `server_updated_at` are server-owned and never sent.

enum SyncDates {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func parse(_ value: Any?) -> Date? { (value as? String).flatMap(CloudJSON.parseDate) }
    /// Same instant within the precision that survives a round trip (ms on the wire, µs in Postgres).
    static func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 0.002 }
    static func newer(_ a: Date, than b: Date) -> Bool { a.timeIntervalSince(b) >= 0.002 }
}

/// Result of turning a local record into a cloud row.
enum SyncRowResult {
    case row([String: Any])
    /// Never uploaded and that's expected (sample data, record gone): the op is dropped.
    case drop
    /// Can't be uploaded as it is (violates a cloud rule): the op is marked failed, local data kept.
    case invalid(String)
}

enum SyncRows {
    static let categories: Set<String> = ["Food", "Groceries", "Transport", "Shopping", "Bills", "Entertainment",
                                          "Education", "Health", "Travel", "Personal", "Subscription", "Other"]
    static let channels: Set<String> = ["APPLE_PAY", "QR_PAYMENT", "BANK_TRANSFER", "CARD", "CASH", "DUITNOW_QR", "TNG_QR",
                                        "ONLINE_BANKING", "E_WALLET", "OTHER", "UNKNOWN"]
    static let movementKinds: [String: String] = [
        "income": "in", "loanReceived": "in", "repaymentReceived": "in", "refund": "in", "otherIn": "in",
        "loanGiven": "out", "repaymentMade": "out", "otherOut": "out", "ownTransfer": "internal"]

    static func id(_ value: UUID) -> String { value.uuidString.lowercased() }
    static func uuid(_ value: Any?) -> UUID? { (value as? String).flatMap(UUID.init(uuidString:)) }
    static func opt(_ value: Any?) -> Any { value ?? NSNull() }
    static func cap(_ text: String, _ n: Int) -> String { text.count > n ? String(text.prefix(n)) : text }
    static func capOpt(_ text: String?, _ n: Int) -> Any { text.map { cap($0, n) as Any } ?? NSNull() }
    static func ref(_ value: UUID?, sample: Set<UUID>) -> Any {
        guard let value, !sample.contains(value) else { return NSNull() }
        return id(value)
    }
    static func string(_ row: [String: Any], _ key: String) -> String? { row[key] as? String }
    static func int(_ row: [String: Any], _ key: String) -> Int? {
        if let n = row[key] as? Int { return n }
        if let n = row[key] as? NSNumber { return n.intValue }
        if let s = row[key] as? String { return Int(s) }
        return nil
    }
    static func bool(_ row: [String: Any], _ key: String) -> Bool? { (row[key] as? Bool) ?? (row[key] as? NSNumber)?.boolValue }

    // MARK: Local → cloud

    static func row(_ a: Account, updatedAt: Date) -> SyncRowResult {
        let name = cap(a.name.trimmingCharacters(in: .whitespacesAndNewlines), 80)
        return .row(["id": id(a.id), "name": name.isEmpty ? "Account" : name,
                     "type": ["bank", "eWallet", "cash", "other"].contains(a.typeRaw) ? a.typeRaw : "other",
                     "currency": a.currency.isEmpty ? "RM" : cap(a.currency, 8), "icon": opt(a.icon),
                     "is_archived": a.isArchived, "sort_index": a.sortIndex,
                     "created_at": SyncDates.string(a.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    static func row(_ p: PayBookProfile, updatedAt: Date) -> SyncRowResult {
        let name = cap(p.name.trimmingCharacters(in: .whitespacesAndNewlines), 80)
        return .row(["id": id(p.id), "name": name.isEmpty ? "Person" : name, "notes": capOpt(p.notes, 2000),
                     "is_frequent": p.isFrequent, "is_archived": p.isArchived,
                     "created_at": SyncDates.string(p.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    static func row(_ m: PayBookPaymentMethod, updatedAt: Date, sample: Set<UUID>) -> SyncRowResult {
        guard let person = m.profile else { return .invalid("Payment method has no person") }
        if sample.contains(person.id) { return .drop }
        return .row(["id": id(m.id), "person_id": id(person.id),
                     "payment_type": ["Bank Account", "E-Wallet", "Payment ID", "Other"].contains(m.paymentTypeRaw) ? m.paymentTypeRaw : "Other",
                     "provider": m.provider, "custom_provider_name": opt(m.customProviderName),
                     "account_identifier": cap(m.accountIdentifier, 120), "label": opt(m.label), "notes": opt(m.notes),
                     "created_at": SyncDates.string(m.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    /// Body of `save_expense_with_shares`: {p_expense, p_shares}. A split that doesn't add up is sent as a plain
    /// expense (the server would reject it), like the Web's backup import.
    static func rpcBody(_ e: Expense, updatedAt: Date, sample: Set<UUID>, receiptPath: String?) -> SyncRowResult {
        let amountMinor = Money.minorUnits(from: e.amount)
        guard amountMinor > 0 else { return .invalid("Amount must be more than zero to sync") }
        guard amountMinor <= 100_000_000_000 else { return .invalid("Amount is too large to sync") }
        let shares = e.shares.sorted { $0.sortIndex < $1.sortIndex }
        let validSplit = !shares.isEmpty && shares.reduce(0) { $0 + $1.amountMinor } == amountMinor && shares.allSatisfy { $0.amountMinor >= 0 }
        let payerId = e.payer.flatMap { sample.contains($0.id) ? nil : $0.id }
        let paidByMe = e.paidByMe || (payerId == nil && (e.payerNameSnapshot ?? "").isEmpty)
        let merchant = cap(e.merchant, 200)
        let funding = cap(e.fundingAccount, 80)
        var expense: [String: Any] = [
            "id": id(e.id), "amount_minor": amountMinor, "currency": e.currency.isEmpty ? "RM" : cap(e.currency, 8),
            "merchant": merchant.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : merchant,
            "category": categories.contains(e.categoryRaw) ? e.categoryRaw : "Other",
            "payment_channel": channels.contains(e.paymentChannelRaw) ? e.paymentChannelRaw : "UNKNOWN",
            "funding_account": funding.isEmpty ? "Unknown" : funding, "funding_instrument": opt(e.fundingInstrument),
            "account_id": ref(e.account?.id, sample: sample), "payment_source": e.paymentSourceRaw,
            "date": SyncDates.string(e.date), "notes": capOpt(e.notes, 4000), "transaction_reference": capOpt(e.transactionReference, 120),
            "source_type": e.sourceTypeRaw, "paid_by_me": paidByMe,
            "payer_id": paidByMe ? NSNull() : opt(payerId.map(id)),
            "payer_name_snapshot": paidByMe ? NSNull() : opt(e.payerNameSnapshot),
            "split_method": validSplit && ["equal", "parts", "amounts"].contains(e.splitMethodRaw ?? "") ? e.splitMethodRaw! : NSNull(),
            "receipt_path": opt(receiptPath), "is_sample_data": false,
            "created_at": SyncDates.string(e.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()]
        // Like Web/Android: the Hybrid Split rule is only sent when there is one (older servers never see the key).
        if validSplit, let rule = e.splitRule, !rule.isEmpty, rule.count <= 4000 { expense["split_rule"] = rule }
        let shareRows: [[String: Any]] = validSplit ? shares.map { s in
            ["id": id(s.id), "person_id": s.isMe ? NSNull() : ref(s.person?.id, sample: sample), "is_me": s.isMe,
             "name_snapshot": s.nameSnapshot, "amount_minor": s.amountMinor,
             "parts": s.parts.flatMap { (1...99).contains($0) ? $0 : nil } as Any? ?? NSNull(),
             "entered_minor": s.enteredMinor.flatMap { $0 >= 0 ? $0 : nil } as Any? ?? NSNull(),
             "sort_index": s.sortIndex, "created_at": SyncDates.string(e.createdAt)]
        } : []
        return .row(["p_expense": expense, "p_shares": shareRows])
    }

    static func row(_ m: MoneyMovement, updatedAt: Date, sample: Set<UUID>) -> SyncRowResult {
        guard let direction = movementKinds[m.kindRaw] else { return .invalid("Unknown money record type") }
        guard m.amountMinor > 0 else { return .invalid("Amount must be more than zero to sync") }
        return .row(["id": id(m.id), "kind": m.kindRaw, "direction": direction, "amount_minor": m.amountMinor,
                     "currency": m.currency.isEmpty ? "RM" : cap(m.currency, 8), "date": SyncDates.string(m.date),
                     "person_id": ref(m.person?.id, sample: sample), "person_name_snapshot": opt(m.personNameSnapshot),
                     "linked_expense_id": ref(m.linkedExpense.flatMap { $0.isSampleData ? nil : $0.id }, sample: sample),
                     "linked_expense_snapshot": opt(m.linkedExpenseSnapshot),
                     "account_id": ref(m.account?.id, sample: sample), "counter_account_id": ref(m.counterAccount?.id, sample: sample),
                     "note": capOpt(m.note, 4000), "transaction_reference": opt(m.transactionReference), "source_type": m.sourceTypeRaw,
                     "payment_channel": channels.contains(m.paymentChannelRaw) ? m.paymentChannelRaw : "UNKNOWN",
                     "created_at": SyncDates.string(m.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    static func row(_ a: SettlementAllocation, updatedAt: Date, sample: Set<UUID>) -> SyncRowResult {
        if sample.contains(a.personID) { return .drop }
        guard a.amountMinor > 0 else { return .invalid("Amount must be more than zero to sync") }
        return .row(["id": id(a.id), "group_id": id(a.groupID),
                     "kind": ["payment", "assign", "offset"].contains(a.kindRaw) ? a.kindRaw : "payment",
                     "payment_id": ref(a.paymentID, sample: sample), "expense_id": ref(a.expenseID, sample: sample),
                     "loan_id": ref(a.loanID, sample: sample), "person_id": id(a.personID), "direction": a.direction == -1 ? -1 : 1,
                     "amount_minor": a.amountMinor, "currency": a.currency.isEmpty ? "RM" : a.currency, "date": SyncDates.string(a.date),
                     "created_at": SyncDates.string(a.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    static func row(_ r: ClassificationRule, updatedAt: Date) -> SyncRowResult {
        .row(["id": id(r.id), "merchant_key": r.merchantKey,
              "category": r.categoryRaw.flatMap { categories.contains($0) ? $0 : nil } as Any? ?? NSNull(),
              "suggested_type": opt(r.suggestedTypeRaw), "account_id": opt(r.accountId.map(id)), "hit_count": max(0, r.hitCount),
              "created_at": SyncDates.string(r.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }

    static func row(_ r: ChannelRule, updatedAt: Date) -> SyncRowResult {
        .row(["id": id(r.id), "merchant_key": r.merchantKey, "funding_key": r.fundingKey, "channel": r.channelRaw,
              "hit_count": max(0, r.hitCount),
              "created_at": SyncDates.string(r.createdAt), "updated_at": SyncDates.string(updatedAt), "deleted_at": NSNull()])
    }
}

// MARK: - Fetch by id (chunks; never whole tables)

enum SyncFetch {
    static func expenses(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: Expense] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func shares(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: ExpenseShare] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<ExpenseShare>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func accounts(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: Account] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func people(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: PayBookProfile] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<PayBookProfile>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func methods(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: PayBookPaymentMethod] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<PayBookPaymentMethod>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func movements(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: MoneyMovement] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<MoneyMovement>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func allocations(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: SettlementAllocation] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<SettlementAllocation>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func classificationRules(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: ClassificationRule] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<ClassificationRule>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    static func channelRules(_ ids: [UUID], _ ctx: ModelContext) -> [UUID: ChannelRule] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<ChannelRule>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    /// Ids registered as demo data (small: only what "Load Sample Data" created).
    static func sampleIDs(_ ctx: ModelContext) -> Set<UUID> {
        Set(((try? ctx.fetch(FetchDescriptor<SampleDataRecord>())) ?? []).map(\.recordID))
    }
}

// MARK: - Cloud → local (fields the cloud doesn't have are kept from the local copy)

enum SyncApply {
    static func expense(_ r: [String: Any], into existing: Expense?, ctx: ModelContext) -> Expense? {
        guard let eid = SyncRows.uuid(r["id"]), let minor = SyncRows.int(r, "amount_minor"),
              let date = SyncDates.parse(r["date"]), let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let created = SyncDates.parse(r["created_at"]) ?? updated
        let e = existing ?? {
            let new = Expense(id: eid, amount: Money.majorAmount(fromMinor: minor), date: date, createdAt: created, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        e.amount = Money.majorAmount(fromMinor: minor)
        e.currency = SyncRows.string(r, "currency") ?? "RM"
        e.merchant = SyncRows.string(r, "merchant") ?? "Unknown"
        e.categoryRaw = SyncRows.string(r, "category") ?? "Other"
        e.paymentChannelRaw = SyncRows.string(r, "payment_channel") ?? "UNKNOWN"
        e.fundingAccount = SyncRows.string(r, "funding_account") ?? "Unknown"
        e.fundingInstrument = SyncRows.string(r, "funding_instrument")
        if let source = SyncRows.string(r, "payment_source") { e.paymentSourceRaw = source }
        e.date = date
        e.notes = SyncRows.string(r, "notes")
        e.transactionReference = SyncRows.string(r, "transaction_reference")
        e.sourceTypeRaw = SyncRows.string(r, "source_type") ?? "manual"
        e.account = SyncRows.uuid(r["account_id"]).flatMap { SyncFetch.accounts([$0], ctx)[$0] }
        e.paidByMe = SyncRows.bool(r, "paid_by_me") ?? true
        e.payer = e.paidByMe ? nil : SyncRows.uuid(r["payer_id"]).flatMap { SyncFetch.people([$0], ctx)[$0] }
        e.payerNameSnapshot = SyncRows.string(r, "payer_name_snapshot")
        e.splitMethodRaw = SyncRows.string(r, "split_method")
        // Missing key = a server without the Hybrid Split column: keep this device's rule.
        if r.keys.contains("split_rule") { e.splitRule = SyncRows.string(r, "split_rule") }
        e.isSampleData = SyncRows.bool(r, "is_sample_data") ?? false
        e.createdAt = created
        e.updatedAt = updated
        return e
    }

    static func share(_ r: [String: Any], into existing: ExpenseShare?, expense: Expense, ctx: ModelContext) -> ExpenseShare? {
        guard let sid = SyncRows.uuid(r["id"]), let minor = SyncRows.int(r, "amount_minor") else { return nil }
        let s = existing ?? {
            let new = ExpenseShare(id: sid, nameSnapshot: SyncRows.string(r, "name_snapshot") ?? "", amountMinor: minor)
            ctx.insert(new)
            return new
        }()
        if s.expense?.id != expense.id { s.expense = expense }
        s.isMe = SyncRows.bool(r, "is_me") ?? false
        s.person = s.isMe ? nil : SyncRows.uuid(r["person_id"]).flatMap { SyncFetch.people([$0], ctx)[$0] }
        s.nameSnapshot = SyncRows.string(r, "name_snapshot") ?? ""
        s.amountMinor = minor
        s.parts = SyncRows.int(r, "parts")
        s.enteredMinor = SyncRows.int(r, "entered_minor")
        s.sortIndex = SyncRows.int(r, "sort_index") ?? 0
        return s
    }

    static func account(_ r: [String: Any], into existing: Account?, ctx: ModelContext) -> Account? {
        guard let aid = SyncRows.uuid(r["id"]), let name = SyncRows.string(r, "name") else { return nil }
        let a = existing ?? {
            let new = Account(id: aid, name: name, createdAt: SyncDates.parse(r["created_at"]) ?? Date())
            ctx.insert(new)
            return new
        }()
        a.name = name
        a.typeRaw = SyncRows.string(r, "type") ?? "other"
        a.currency = SyncRows.string(r, "currency") ?? "RM"
        a.icon = SyncRows.string(r, "icon")
        a.isArchived = SyncRows.bool(r, "is_archived") ?? false
        a.sortIndex = SyncRows.int(r, "sort_index") ?? 0
        return a
    }

    static func person(_ r: [String: Any], into existing: PayBookProfile?, ctx: ModelContext) -> PayBookProfile? {
        guard let pid = SyncRows.uuid(r["id"]), let name = SyncRows.string(r, "name"),
              let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let p = existing ?? {
            let new = PayBookProfile(id: pid, name: name, createdAt: SyncDates.parse(r["created_at"]) ?? updated, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        p.name = name
        p.notes = SyncRows.string(r, "notes")
        p.isFrequent = SyncRows.bool(r, "is_frequent") ?? false
        p.isArchived = SyncRows.bool(r, "is_archived") ?? false
        p.updatedAt = updated
        return p
    }

    static func method(_ r: [String: Any], into existing: PayBookPaymentMethod?, ctx: ModelContext) -> PayBookPaymentMethod? {
        guard let mid = SyncRows.uuid(r["id"]), let personId = SyncRows.uuid(r["person_id"]),
              let person = SyncFetch.people([personId], ctx)[personId], let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let m = existing ?? {
            let new = PayBookPaymentMethod(id: mid, provider: SyncRows.string(r, "provider") ?? "", accountIdentifier: "",
                                           createdAt: SyncDates.parse(r["created_at"]) ?? updated, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        if m.profile?.id != person.id { m.profile = person }
        m.paymentTypeRaw = SyncRows.string(r, "payment_type") ?? "Other"
        m.provider = SyncRows.string(r, "provider") ?? ""
        m.customProviderName = SyncRows.string(r, "custom_provider_name")
        m.accountIdentifier = SyncRows.string(r, "account_identifier") ?? ""
        m.label = SyncRows.string(r, "label")
        m.notes = SyncRows.string(r, "notes")
        m.updatedAt = updated
        return m
    }

    static func movement(_ r: [String: Any], into existing: MoneyMovement?, ctx: ModelContext) -> MoneyMovement? {
        guard let mid = SyncRows.uuid(r["id"]), let kindRaw = SyncRows.string(r, "kind"), let kind = MoneyMovementKind(rawValue: kindRaw),
              let minor = SyncRows.int(r, "amount_minor"), let date = SyncDates.parse(r["date"]),
              let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let m = existing ?? {
            let new = MoneyMovement(id: mid, kind: kind, amountMinor: minor, date: date,
                                    createdAt: SyncDates.parse(r["created_at"]) ?? updated, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        m.kind = kind
        m.amountMinor = minor
        m.currency = SyncRows.string(r, "currency") ?? "RM"
        m.date = date
        m.person = SyncRows.uuid(r["person_id"]).flatMap { SyncFetch.people([$0], ctx)[$0] }
        m.personNameSnapshot = SyncRows.string(r, "person_name_snapshot")
        m.linkedExpense = SyncRows.uuid(r["linked_expense_id"]).flatMap { SyncFetch.expenses([$0], ctx)[$0] }
        m.linkedExpenseSnapshot = SyncRows.string(r, "linked_expense_snapshot")
        m.account = SyncRows.uuid(r["account_id"]).flatMap { SyncFetch.accounts([$0], ctx)[$0] }
        m.counterAccount = SyncRows.uuid(r["counter_account_id"]).flatMap { SyncFetch.accounts([$0], ctx)[$0] }
        m.note = SyncRows.string(r, "note")
        m.transactionReference = SyncRows.string(r, "transaction_reference")
        m.sourceTypeRaw = SyncRows.string(r, "source_type") ?? "manual"
        m.paymentChannelRaw = SyncRows.string(r, "payment_channel") ?? "UNKNOWN"
        m.updatedAt = updated
        return m
    }

    static func allocation(_ r: [String: Any], into existing: SettlementAllocation?, ctx: ModelContext) -> SettlementAllocation? {
        guard let aid = SyncRows.uuid(r["id"]), let personId = SyncRows.uuid(r["person_id"]),
              let minor = SyncRows.int(r, "amount_minor"), let date = SyncDates.parse(r["date"]) else { return nil }
        let kind = SettlementAllocation.Kind(rawValue: SyncRows.string(r, "kind") ?? "") ?? .payment
        let a = existing ?? {
            let new = SettlementAllocation(id: aid, groupID: SyncRows.uuid(r["group_id"]) ?? aid, kind: kind, paymentID: nil,
                                           expenseID: nil, loanID: nil, personID: personId, direction: 1, amountMinor: minor,
                                           currency: "RM", date: date, createdAt: SyncDates.parse(r["created_at"]) ?? date)
            ctx.insert(new)
            return new
        }()
        a.groupID = SyncRows.uuid(r["group_id"]) ?? aid
        a.kindRaw = kind.rawValue
        a.paymentID = SyncRows.uuid(r["payment_id"])
        a.expenseID = SyncRows.uuid(r["expense_id"])
        a.loanID = SyncRows.uuid(r["loan_id"])
        a.personID = personId
        a.direction = SyncRows.int(r, "direction") == -1 ? -1 : 1
        a.amountMinor = minor
        a.currency = SyncRows.string(r, "currency") ?? "RM"
        a.date = date
        return a
    }

    static func classificationRule(_ r: [String: Any], into existing: ClassificationRule?, ctx: ModelContext) -> ClassificationRule? {
        guard let rid = SyncRows.uuid(r["id"]), let key = SyncRows.string(r, "merchant_key"),
              let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let rule = existing ?? {
            let new = ClassificationRule(id: rid, merchantKey: key, createdAt: SyncDates.parse(r["created_at"]) ?? updated, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        rule.merchantKey = key
        rule.categoryRaw = SyncRows.string(r, "category")
        rule.suggestedTypeRaw = SyncRows.string(r, "suggested_type")
        rule.accountId = SyncRows.uuid(r["account_id"])
        rule.hitCount = SyncRows.int(r, "hit_count") ?? 1
        rule.updatedAt = updated
        return rule
    }

    static func channelRule(_ r: [String: Any], into existing: ChannelRule?, ctx: ModelContext) -> ChannelRule? {
        guard let rid = SyncRows.uuid(r["id"]), let key = SyncRows.string(r, "merchant_key"),
              let channel = SyncRows.string(r, "channel"), let updated = SyncDates.parse(r["updated_at"]) else { return nil }
        let rule = existing ?? {
            let new = ChannelRule(id: rid, merchantKey: key, fundingKey: SyncRows.string(r, "funding_key") ?? "", channelRaw: channel,
                                  createdAt: SyncDates.parse(r["created_at"]) ?? updated, updatedAt: updated)
            ctx.insert(new)
            return new
        }()
        rule.merchantKey = key
        rule.fundingKey = SyncRows.string(r, "funding_key") ?? ""
        rule.channelRaw = channel
        rule.hitCount = SyncRows.int(r, "hit_count") ?? 1
        rule.updatedAt = updated
        return rule
    }
}
