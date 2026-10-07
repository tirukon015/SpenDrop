import Foundation
import SwiftData

/// Phase 7: payment channels, ClassificationRule, direction detection, scan→movement, Apple Pay automation,
/// trend/breakdown calculations, backup V3 and the V2 → V3 migration. `--run-phase7-tests`
@MainActor
public struct Phase7Tests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 7") { results.append($0) }

        // MARK: Payment channels
        do {
            let oldValues = [PaymentChannel.applePay, .qrPayment, .bankTransfer, .card, .cash, .other, .unknown].map(\.rawValue)
            let newValues = [PaymentChannel.duitNowQR, .onlineBanking, .eWallet].map(\.rawValue)
            let expense = Expense(amount: 1, merchant: "X")
            expense.paymentChannelRaw = "SOMETHING_NEW"
            t.check("Payment channels: old stored values unchanged, 3 new values, unknown raw falls back to Unknown",
                    oldValues == ["APPLE_PAY", "QR_PAYMENT", "BANK_TRANSFER", "CARD", "CASH", "OTHER", "UNKNOWN"] &&
                    newValues == ["DUITNOW_QR", "ONLINE_BANKING", "E_WALLET"] && expense.paymentChannel == .unknown,
                    expected: "unchanged + 3 new + Unknown", actual: "\(newValues) fallback=\(expense.paymentChannel)")
            t.check("Channel detection never guesses (no text → Unknown; 'DuitNow QR' → DuitNow QR; other QR wording → generic QR Payment)",
                    PaymentChannel.detect(from: "Thank you") == .unknown && PaymentChannel.detect(from: "DuitNow QR payment") == .duitNowQR &&
                    PaymentChannel.detect(from: "Scan & Pay") == .qrPayment,
                    expected: "unknown, duitNowQR, qrPayment",
                    actual: "\(PaymentChannel.detect(from: "Thank you")), \(PaymentChannel.detect(from: "DuitNow QR payment")), \(PaymentChannel.detect(from: "Scan & Pay"))")
        }

        // MARK: ClassificationRule
        do {
            let ctx = TestKit.context()
            let key = TransactionClassifier.merchantKey("  McDonald’s  ")
            let ignored = TransactionClassifier.merchantKey("Unknown")
            TransactionClassifier.learn(merchant: "McDonald's", category: .shopping, in: ctx)
            let once = TransactionClassifier.suggestCategory(merchant: "mcdonald's", deterministic: .food, in: ctx)
            TransactionClassifier.learn(merchant: "MCDONALD'S", category: .shopping, in: ctx)
            let twice = TransactionClassifier.suggestCategory(merchant: "McDonald's", deterministic: .food, in: ctx)
            TransactionClassifier.learn(merchant: "McDonald's", category: .food, in: ctx)      // correction
            let rule = TransactionClassifier.rule(for: "mcdonald's", in: ctx)
            try? ctx.save()
            t.check("Rules: key normalised; 1 confirmation not trusted; 2 trusted and beats parser; correction resets",
                    key == "mcdonald's" && ignored == nil && once.source == .deterministic && once.category == .food &&
                    twice.source == .learned && twice.category == .shopping && rule?.category == .food && rule?.hitCount == 1 &&
                    TestKit.count(ClassificationRule.self, in: ctx) == 1,
                    expected: "deterministic, then learned shopping, then food x1, one rule",
                    actual: "once=\(once.source)/\(once.category) twice=\(twice.source)/\(twice.category) rule=\(rule?.categoryRaw ?? "nil")x\(rule?.hitCount ?? 0)")
            let generic = TransactionClassifier.suggestCategory(merchant: "Shell Petrol", deterministic: nil, in: ctx)
            let unknown = TransactionClassifier.suggestCategory(merchant: "Zyx Qwv", deterministic: .other, in: ctx)
            t.check("Priority falls back to generic suggestion, then Unknown (Other)",
                    generic.source == .generic && generic.category == .transport && unknown.source == .unknown && unknown.category == .other,
                    expected: "generic transport, unknown other", actual: "\(generic.source)/\(generic.category), \(unknown.source)/\(unknown.category)")
        }

        // MARK: Direction detection
        do {
            let cases: [(String, MoneyMovementKind?)] = [
                ("DuitNow Transfer\nYou have received RM50.00 from BIJOY", .otherIn),
                ("Salary has been credited to your account RM3,000", .income),
                ("Refund processed RM30.00 Uniqlo", .refund),
                ("Reload successful\nTouch 'n Go eWallet RM200", .ownTransfer),
                ("Payment successful\nPaid to McDonald's RM18.50", nil),
                ("Received from Ali\nTransfer to Bob RM20", nil)
            ]
            let actual = cases.map { DirectionDetector.detect(text: $0.0).kind }
            t.check("Direction: received/salary/refund/top-up detected; payments and mixed wording stay unsuggested",
                    actual == cases.map(\.1), expected: "\(cases.map { $0.1?.rawValue ?? "nil" })", actual: "\(actual.map { $0?.rawValue ?? "nil" })")
            let text = "Maybank2u\nDuitNow Transfer\nYou have received\nRM 50.00\nfrom BIJOY DAS\n29 Sep 2026\nReference: MBB123"
            let ocr = OCRResult(fullText: text, lines: text.components(separatedBy: "\n").map { RecognizedTextLine(text: $0, confidence: 0.95) }, averageConfidence: 0.95)
            let parsed = TransactionParser.shared.parse(ocrResult: ocr)
            t.check("Parser: incoming screenshot keeps its amount and suggests Money In (for review)",
                    parsed.amount == 50 && parsed.suggestedMovementKind == .otherIn && parsed.directionReason != nil,
                    expected: "RM50, otherIn", actual: "RM\(parsed.amount ?? 0), \(parsed.suggestedMovementKind?.rawValue ?? "nil")")
        }

        // MARK: Movement duplicates and scan → movement drafts
        do {
            let ctx = TestKit.context()
            let date = Date()
            let existing = MoneyMovement(kind: .otherIn, amountMinor: 5000, date: date, transactionReference: "REF-9")
            ctx.insert(existing)
            try? ctx.save()
            let byRef = MovementDuplicateDetector.findMatch(amountMinor: 1, date: date.addingTimeInterval(9_999_999), reference: "REF-9", kind: .income, in: ctx)
            let byAmount = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date.addingTimeInterval(300), reference: nil, kind: .income, in: ctx)
            let hourLater = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date.addingTimeInterval(3600), reference: nil, kind: .income, in: ctx)
            let otherDirection = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date, reference: nil, kind: .otherOut, in: ctx)
            let later = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date.addingTimeInterval(2 * 86_400), reference: nil, kind: .otherIn, in: ctx)
            t.check("Movement duplicates: by reference, or same amount+direction within minutes (not an hour or a day apart); warns only",
                    byRef === existing && byAmount === existing && hourLater == nil && otherDirection == nil && later == nil,
                    expected: "ref match, 5-min match, none, none, none", actual: "\(byRef != nil) \(byAmount != nil) \(hourLater != nil) \(otherDirection != nil) \(later != nil)")

            let maybank = Account(name: "Maybank", type: .bank)
            ctx.insert(maybank)
            let incoming = MoneyMovementDraft.fromParsed(amount: 50, date: date, fundingAccount: "maybank", merchant: "BIJOY", reference: "MBB1",
                                                         channel: .bankTransfer, walletSource: nil, kind: .otherIn, source: .screenshot, in: ctx)
            let topUp = MoneyMovementDraft.fromParsed(amount: 200, date: date, fundingAccount: "Maybank", merchant: "Reload", reference: nil,
                                                      channel: .unknown, walletSource: .touchNGo, kind: .ownTransfer, source: .screenshot, in: ctx)
            let unknownAccount = MoneyMovementDraft.fromParsed(amount: 5, date: date, fundingAccount: "Unknown", merchant: "Unknown", reference: nil,
                                                               channel: .unknown, walletSource: nil, kind: .otherIn, source: .screenshot, in: ctx)
            let saved = incoming.insertMovement(into: ctx)
            try? ctx.save()
            t.check("Scan → Money In draft: account resolved (no duplicate), top-up gets TNG as destination, Unknown stays empty",
                    incoming.account === maybank && incoming.note == "BIJOY" && topUp.counterAccount?.name == "Touch 'n Go" &&
                    unknownAccount.account == nil && unknownAccount.note.isEmpty &&
                    saved?.sourceType == .screenshot && saved?.transactionReference == "MBB1" && saved?.paymentChannel == .bankTransfer &&
                    TestKit.fetch(Account.self, in: ctx).filter { $0.nameKey == "maybank" }.count == 1,
                    expected: "Maybank reused; TNG created; Unknown nil; provenance kept",
                    actual: "account=\(incoming.account?.name ?? "nil") to=\(topUp.counterAccount?.name ?? "nil") unknown=\(unknownAccount.account?.name ?? "nil") source=\(saved?.sourceType.rawValue ?? "nil")")
        }

        // MARK: Apple Pay automation
        do {
            let ctx = TestKit.context()
            TransactionClassifier.learn(merchant: "Starbucks", category: .food, in: ctx)
            TransactionClassifier.learn(merchant: "Starbucks", category: .food, in: ctx)
            let first = ApplePayAutomation.record(amount: 18.9, merchant: "Starbucks", card: "Maybank Visa Debit", in: ctx)
            let repeated = ApplePayAutomation.record(amount: 18.9, merchant: "starbucks", card: "Maybank Visa Debit", in: ctx)
            let invalid = ApplePayAutomation.record(amount: 0, merchant: "X", card: nil, in: ctx)
            let unknownCard = ApplePayAutomation.record(amount: 5, merchant: "Kiosk", card: "My Card", in: ctx)
            let expenses = TestKit.fetch(Expense.self, in: ctx)
            let starbucks = expenses.first { $0.merchant == "Starbucks" }
            let kiosk = expenses.first { $0.merchant == "Kiosk" }
            var savedID: UUID?
            if case .saved(let id) = first { savedID = id }
            t.check("Apple Pay automation: saved as Apple Pay expense (learned category, Maybank linked); repeat skipped; invalid rejected",
                    savedID == starbucks?.id && starbucks?.paymentChannel == .applePay && starbucks?.sourceType == .appleWallet &&
                    starbucks?.category == .food && starbucks?.account?.name == "Maybank" && starbucks?.amountMinor == 1890 &&
                    repeated == .duplicate && invalid != .duplicate && expenses.count == 2 &&
                    kiosk?.fundingAccount == "Unknown" && kiosk?.account == nil,
                    expected: "1 Starbucks + 1 Kiosk; duplicate skipped; unknown card unlinked",
                    actual: "expenses=\(expenses.count) repeat=\(repeated) account=\(starbucks?.account?.name ?? "nil") kiosk=\(kiosk?.fundingAccount ?? "nil")")
            _ = unknownCard
        }

        // MARK: Trends and breakdowns
        do {
            let ctx = TestKit.context()
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            cal.firstWeekday = 2
            let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!
            let e1 = Expense(amount: 10, merchant: "A", date: now)
            let e2 = Expense(amount: 20, merchant: "B", date: cal.date(byAdding: .month, value: -1, to: now)!)
            let old = Expense(amount: 99, merchant: "Old", date: cal.date(byAdding: .year, value: -2, to: now)!)
            [e1, e2, old].forEach { ctx.insert($0) }
            let income = MoneyMovement(kind: .income, amountMinor: 50000, date: now)
            let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, date: now)
            ctx.insert(income); ctx.insert(transfer)
            let monthly = PeriodGrouping.buckets(expenses: [e1, e2, old], movements: [income, transfer], granularity: .monthly, count: 3, now: now, calendar: cal)
            let weekly = PeriodGrouping.buckets(expenses: [e1], movements: [], granularity: .weekly, count: 4, now: now, calendar: cal)
            t.check("Trend buckets: monthly totals, old records outside range ignored, own transfer excluded",
                    monthly.count == 3 && monthly.map(\.spendingMinor) == [0, 2000, 1000] && monthly.last?.inMinor == 50000 &&
                    monthly.last?.outMinor == 1000 && weekly.count == 4 && weekly.last?.spendingMinor == 1000,
                    expected: "spending [0,2000,1000], in 50000, out 1000", actual: "\(monthly.map(\.spendingMinor)) in=\(monthly.last?.inMinor ?? -1) out=\(monthly.last?.outMinor ?? -1)")

            let bijoy = PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
            let dinner = Expense(amount: 30, merchant: "Dinner", date: Date())
            let lunch = Expense(amount: 12, merchant: "Dinner", date: Date())
            ctx.insert(dinner); ctx.insert(lunch)
            var d = SplitDraft(); d.add(bijoy); d.apply(to: dinner, in: ctx)
            let refund = MoneyMovement(kind: .refund, amountMinor: 500, date: Date(), linkedExpense: lunch)
            ctx.insert(refund)
            try? ctx.save()
            let engine = TransactionFilterEngine()
            engine.selectedDateFilter = .today
            engine.update(expenses: [dinner, lunch])
            engine.update(movements: [refund])
            let shared = engine.sharedSpendingSummary
            t.check("Breakdown: shared bills, my share, refunds and net spending; merchants grouped",
                    shared.sharedCount == 1 && shared.sharedTotalMinor == 3000 && shared.myShareMinor == 1500 &&
                    shared.refundsMinor == 500 && shared.netSpendingMinor == 4200 - 500 &&
                    engine.merchantBreakdown.first?.name == "Dinner" && engine.merchantBreakdown.first?.count == 2 &&
                    engine.movementKindBreakdown.first?.kind == .refund,
                    expected: "1 shared, bill 3000, mine 1500, refund 500, net 3700",
                    actual: "\(shared)")
        }

        // MARK: Backup V3 (rules) and V2 payloads
        do {
            let source = TestKit.context()
            TransactionClassifier.learn(merchant: "Grab", category: .transport, in: source)
            try? source.save()
            let payload = UserDataBackupService.makePayload(from: source)
            let data = try? UserDataBackupService.makeEncoder().encode(payload)
            let decoded = data.flatMap { try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
            let target = TestKit.context()
            TransactionClassifier.learn(merchant: "grab", category: .food, in: target, now: Date.distantPast)   // older local rule, same merchant
            try? target.save()
            let summary = decoded.map { UserDataBackupService.applyBackupPayload($0, into: target) }
            try? target.save()
            let rules = TestKit.fetch(ClassificationRule.self, in: target)
            t.check("Backup V3+: rules exported and restored; same merchant merged (no duplicate), newer backup wins",
                    decoded?.version == UserDataBackupService.BackupPayload.currentVersion && (decoded?.version ?? 0) >= 3 && decoded?.classificationRules?.count == 1 && summary?.rulesRestored == 1 &&
                    rules.count == 1 && rules.first?.category == .transport,
                    expected: "v3, 1 rule, transport", actual: "v\(decoded?.version ?? 0) rules=\(rules.count) cat=\(rules.first?.categoryRaw ?? "nil")")

            let v2 = UserDataBackupService.BackupPayload(version: 2, expenses: [], paybookProfiles: [])
            UserDataBackupService.applyBackupPayload(v2, into: target)
            t.check("A version-2 backup (no rules) leaves existing rules untouched", TestKit.count(ClassificationRule.self, in: target) == 1,
                    expected: "1 rule", actual: "\(TestKit.count(ClassificationRule.self, in: target))")
        }

        // MARK: Migration V2 → V3 on an on-disk store
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropV3Migration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("default.store")
            var ids: (expense: UUID, movement: UUID, account: UUID, person: UUID) = (UUID(), UUID(), UUID(), UUID())
            do {
                // Written with the frozen V2 model types (the shapes V2 shipped with).
                typealias V2 = SpenDropSchemaV2
                let v2 = Schema(versionedSchema: SpenDropSchemaV2.self)
                if let container = try? ModelContainer(for: v2, configurations: [ModelConfiguration(schema: v2, url: storeURL)]) {
                    let ctx = ModelContext(container)
                    let account = V2.Account(name: "Maybank", typeRaw: AccountType.bank.rawValue, currency: "RM", sortIndex: 0); ctx.insert(account)
                    let person = V2.PayBookProfile(name: "Bijoy"); ctx.insert(person)
                    let expense = V2.Expense(amount: 30, merchant: "Dinner", fundingAccount: "Maybank"); ctx.insert(expense)
                    expense.account = account
                    // Me + Bijoy equally, Bijoy paid (what SplitDraft stored in V2).
                    expense.splitMethodRaw = SplitMethod.equal.rawValue
                    expense.payer = person; expense.paidByMe = false; expense.payerNameSnapshot = person.name
                    for (index, p) in [nil, person].enumerated() {
                        let share = V2.ExpenseShare(isMe: p == nil, nameSnapshot: p?.name ?? "Me", amountMinor: 1500, sortIndex: index)
                        ctx.insert(share); share.expense = expense; share.person = p
                    }
                    let movement = V2.MoneyMovement(directionRaw: MoneyMovementKind.loanGiven.direction.rawValue, kindRaw: MoneyMovementKind.loanGiven.rawValue,
                                                    amountMinor: 15000); ctx.insert(movement)
                    movement.person = person; movement.personNameSnapshot = person.name; movement.account = account
                    try? ctx.save()
                    ids = (expense.id, movement.id, account.id, person.id)
                }
            }
            var actual = "open failed"
            var passed = false
            if let container = try? ExpenseDataContainer.openPersistentContainer(configuration: ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)) {
                let ctx = ModelContext(container)
                let expense = TestKit.fetch(Expense.self, in: ctx).first
                let movement = TestKit.fetch(MoneyMovement.self, in: ctx).first
                ctx.insert(ClassificationRule(merchantKey: "dinner", categoryRaw: "Food"))
                let ruleSaved = (try? ctx.save()) != nil
                passed = expense?.id == ids.expense && expense?.amount == 30 && expense?.shares.count == 2 && expense?.payer?.id == ids.person &&
                    expense?.account?.id == ids.account && expense?.fundingAccount == "Maybank" && expense?.spendingMinor == 1500 &&
                    movement?.id == ids.movement && movement?.person?.id == ids.person && movement?.account?.id == ids.account &&
                    ruleSaved && TestKit.count(ClassificationRule.self, in: ctx) == 1
                actual = "expense=\(expense?.id == ids.expense) shares=\(expense?.shares.count ?? -1) payer=\(expense?.payer?.name ?? "nil") movement=\(movement?.id == ids.movement) rules=\(TestKit.count(ClassificationRule.self, in: ctx))"
            }
            t.check("Migration V2 → V3: ids, amount, shares, payer, account links and movements kept; rules table ready",
                    passed, expected: "everything kept + rule saved", actual: actual)
        }

        return results
    }
}

/// Transaction intelligence: evidence-first category and payment channel, confidence and reasons, learned
/// corrections (category per merchant; channel per merchant AND funding account), safe merchant normalization,
/// and backup of the learned channel rules. Isolated in-memory stores only. `--run-classifier-tests`
@MainActor
public enum ClassifierTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Classifier") { results.append($0) }
        let parser = TransactionParser.shared
        func parse(_ lines: [String], confidence: Float = 1) -> ParsedTransaction {
            parser.parse(ocrResult: PDFReceiptImporter.ocrResult(from: lines, confidence: confidence))
        }
        func evidence(_ p: ParsedTransaction) -> CategorySuggestion {
            CategorySuggestion(category: p.category ?? .other, confidence: p.category == nil ? 0 : p.categoryConfidence, reason: p.categoryReason ?? "")
        }

        // 1. Evaluation set (25 synthetic receipts). Before this change: category 21/25 (4 confidently wrong),
        //    channel 14/25 (9 wrong non-Unknown), funding 24/25, merchant 23/25.
        let empty = TestKit.context()
        let score = ClassifierEvaluation.score { lines in
            let p = parse(lines)
            let (category, _) = TransactionClassifier.suggestion(merchant: p.merchant, parsed: evidence(p), in: empty)
            return .init(merchant: p.merchant, category: category.category, categoryConfident: !category.needsReview,
                         channel: p.paymentChannel, funding: p.displayFundingAccount)
        }
        t.check("Evaluation set: every category, channel, funding account and merchant correct; no confidently wrong category; no wrong channel guessed",
                score.category == score.total && score.channel == score.total && score.funding == score.total && score.merchant == score.total &&
                score.confidentWrongCategory == 0 && score.wrongChannelNotUnknown == 0,
                expected: "25/25 on all, 0 confident-wrong, 0 wrong channels", actual: "\(score) \(score.misses)")

        // 2. Merchant normalization: variants match, look-alike names don't
        let normalized = ClassifierEvaluation.normalization.filter { MerchantDetector.knownMerchant(for: $0.raw)?.name != $0.expected }
        t.check("Merchant normalization: MCD/McD/MCDONALDS → McDonald's, 7ELEVEN → 7-Eleven, LOTUSS → Lotus's; MCDERMOTT, SHELLY, DIGITAL, ATMOS, AMAZARA, TMART are not matched",
                normalized.isEmpty, expected: "18/18", actual: "wrong: \(normalized.map(\.raw))")

        // 3. Category: evidence only
        let tngUnknown = parse(ClassifierEvaluation.tng("Payment", "AH SENG ENTERPRISE"))
        let grab = CategoryDetector.suggest(merchant: "GRAB", receiptText: "GRAB\nPayment")
        let grabFood = CategoryDetector.suggest(merchant: "GRAB", receiptText: "GRAB\nFood delivery order")
        let smart = CategoryDetector.suggest(merchant: "SMART BUSINESS PROVIDER", receiptText: "SMART BUSINESS PROVIDER")
        let mcd = CategoryDetector.suggest(merchant: "MCD BANGSAR", receiptText: "MCD BANGSAR")
        let warung = CategoryDetector.suggest(merchant: "WARUNG MAK LONG", receiptText: "WARUNG MAK LONG")
        let receiptOnly = CategoryDetector.suggest(merchant: "AH SENG", receiptText: "AH SENG\nNasi lemak ayam")
        t.check("Category: Touch 'n Go is never category evidence (unknown merchant → Other, needs review); known merchant → confident; name words → likely; receipt words only → suggestion",
                (tngUnknown.category ?? .other) == .other && evidence(tngUnknown).needsReview &&
                mcd.category == .food && !mcd.needsReview && warung.category == .food && !warung.needsReview &&
                receiptOnly.category == .food && receiptOnly.needsReview,
                expected: "Other?/Food/Food/Food?", actual: "\(tngUnknown.category?.rawValue ?? "nil") \(mcd) \(warung) \(receiptOnly)")
        t.check("Category: plain 'Grab' is ambiguous (needs review) unless the receipt says what it was; 'SMART BUSINESS' is not Groceries ('mart') or Transport ('bus')",
                grab.needsReview && grabFood.category == .food && grabFood.needsReview && smart.category == .other && smart.needsReview,
                expected: "Grab?/Food?/Other", actual: "\(grab) \(grabFood) \(smart)")

        // 4. Payment channel: evidence only; the funding account never decides it
        let tngPay = parse(ClassifierEvaluation.tng("Payment", "MCDONALD'S BANGSAR"))
        let tngQR = parse(ClassifierEvaluation.tng("Touch 'n Go QR", "WARUNG MAK LONG"))
        let tngDuit = parse(ClassifierEvaluation.tng("DuitNow QR", "NASI KANDAR PELITA"))
        let tngOnline = parse(ClassifierEvaluation.tng("Online Payment", "SHOPEE MALAYSIA"))
        let bankNone = parse(["Maybank", "Successful", "RM 42.50", "Recipient", "KEDAI MAKAN SELERA", "Reference ID", "MB12345678"])
        t.check("Channel: Touch 'n Go without channel wording → Unknown (never Online or DuitNow QR); 'Touch 'n Go QR' → TNG QR; 'DuitNow QR' → DuitNow QR; 'Online Payment' → Online",
                tngPay.paymentChannel == .unknown && tngPay.displayFundingAccount == "Touch 'n Go" &&
                tngQR.paymentChannel == .tngQR && tngDuit.paymentChannel == .duitNowQR && tngOnline.paymentChannel == .other,
                expected: "unknown, TNG_QR, DUITNOW_QR, OTHER", actual: "\(tngPay.paymentChannel) \(tngQR.paymentChannel) \(tngDuit.paymentChannel) \(tngOnline.paymentChannel)")
        t.check("Channel: a bank receipt without channel wording → Unknown with a reason (the bank is the funding account, not evidence of a transfer)",
                bankNone.paymentChannel == .unknown && bankNone.displayFundingAccount == "Maybank" && (bankNone.channelReason?.isEmpty == false),
                expected: "unknown + reason, Maybank", actual: "\(bankNone.paymentChannel) \(bankNone.channelReason ?? "nil") \(bankNone.displayFundingAccount)")

        // 5. Conflicts: the strongest evidence wins; funding and channel stay separate
        let applePay = parse(["Apple Pay", "STARBUCKS PAVILION", "RM 18.50", "Maybank Visa Debit", "Status: Approved"])
        let card = parse(["Maybank", "Card Purchase", "Maybank Visa Debit", "RM 32.90", "Merchant", "UNIQLO MID VALLEY", "Approval Code 123456"])
        let qrOverTransfer = PaymentChannel.suggest(evidenceText: "DuitNow QR\nfund transfer")
        t.check("Conflicts: Apple Pay with a Maybank card → Apple Pay / Maybank; card purchase on a bank receipt → Card (not Bank Transfer); DuitNow QR beats transfer wording",
                applePay.paymentChannel == .applePay && applePay.displayFundingAccount == "Maybank" &&
                card.paymentChannel == .card && card.displayFundingAccount == "Maybank" && qrOverTransfer.channel == .duitNowQR,
                expected: "APPLE_PAY/Maybank, CARD/Maybank, DUITNOW_QR",
                actual: "\(applePay.paymentChannel)/\(applePay.displayFundingAccount) \(card.paymentChannel)/\(card.displayFundingAccount) \(qrOverTransfer.channel)")

        // 6. Low-confidence OCR lines are not channel evidence
        let blurry = parser.parse(ocrResult: OCRResult(fullText: "Maybank\nSuccessful\nRM 9.00\nDuitNow QR\nRecipient\nAH SENG",
                                                       lines: [RecognizedTextLine(text: "Maybank", confidence: 0.95), RecognizedTextLine(text: "Successful", confidence: 0.95),
                                                               RecognizedTextLine(text: "RM 9.00", confidence: 0.95), RecognizedTextLine(text: "DuitNow QR", confidence: 0.3),
                                                               RecognizedTextLine(text: "Recipient", confidence: 0.95), RecognizedTextLine(text: "AH SENG", confidence: 0.95)],
                                                       averageConfidence: 0.85))
        let clear = parse(["Maybank", "Successful", "RM 9.00", "DuitNow QR", "Recipient", "AH SENG"], confidence: 0.95)
        t.check("A channel word read with low OCR confidence is ignored (Unknown); read clearly it counts",
                blurry.paymentChannel == .unknown && clear.paymentChannel == .duitNowQR,
                expected: "unknown, DUITNOW_QR", actual: "\(blurry.paymentChannel) \(clear.paymentChannel)")

        // 7. Learned categories: corrections teach; old transactions are never rewritten
        let ctx = TestKit.context()
        let old = Expense(amount: 12, merchant: "AH SENG ENTERPRISE", category: .other, date: Date(), fundingAccount: "Touch 'n Go")
        let oldMcd = Expense(amount: 9, merchant: "MCD BANGSAR", category: .food, date: Date(), fundingAccount: "Maybank")
        ctx.insert(old); ctx.insert(oldMcd); try? ctx.save()
        TransactionClassifier.learn(merchant: "AH SENG ENTERPRISE", category: .food, in: ctx)
        let once = TransactionClassifier.suggestion(merchant: "AH SENG ENTERPRISE", parsed: evidence(tngUnknown), in: ctx)
        TransactionClassifier.learn(merchant: "McDonald's", category: .shopping, in: ctx)
        let mcdOnce = TransactionClassifier.suggestion(merchant: "MCD BANGSAR", parsed: mcd, in: ctx)
        TransactionClassifier.learn(merchant: "MCDONALDS", category: .shopping, in: ctx)
        let mcdTwice = TransactionClassifier.suggestion(merchant: "MCD BANGSAR", parsed: mcd, in: ctx)
        try? ctx.save()
        t.check("Learned category: one correction applies to a merchant with no evidence of its own; it overrides a known merchant only after two confirmations (shared across MCD / McDonald's / MCDONALDS)",
                once.0.category == .food && once.1 == .learned && mcdOnce.0.category == .food && mcdOnce.1 != .learned &&
                mcdTwice.0.category == .shopping && mcdTwice.1 == .learned && !mcdTwice.0.needsReview,
                expected: "Food(learned), Food(evidence), Shopping(learned)", actual: "\(once) \(mcdOnce) \(mcdTwice)")
        t.check("Learning never rewrites saved transactions: the earlier expenses keep their categories",
                old.category == .other && oldMcd.category == .food && TestKit.count(Expense.self, in: ctx) == 2,
                expected: "Other, Food, 2 expenses", actual: "\(old.category) \(oldMcd.category) \(TestKit.count(Expense.self, in: ctx))")

        // 8. Learned channels: per merchant AND funding account, only when the receipt is silent
        ChannelLearning.learn(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", channel: .duitNowQR, in: ctx)
        let channelOnce = ChannelLearning.suggestion(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", detected: .unknown, in: ctx)
        ChannelLearning.learn(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", channel: .duitNowQR, in: ctx)
        let channelTwice = ChannelLearning.suggestion(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", detected: .unknown, in: ctx)
        let otherFunding = ChannelLearning.suggestion(merchant: "AH SENG ENTERPRISE", funding: "Maybank", detected: .unknown, in: ctx)
        let otherMerchant = ChannelLearning.suggestion(merchant: "JAYA GROCER", funding: "Touch 'n Go", detected: .unknown, in: ctx)
        let receiptSaysCard = ChannelLearning.suggestion(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", detected: .card, in: ctx)
        t.check("Learned channel: suggested only after two same choices, only for that merchant + funding account (no global 'Touch 'n Go = DuitNow QR'), never over receipt evidence",
                channelOnce == nil && channelTwice?.channel == .duitNowQR && otherFunding == nil && otherMerchant == nil && receiptSaysCard == nil,
                expected: "nil, DUITNOW_QR, nil, nil, nil",
                actual: "\(String(describing: channelOnce?.channel)) \(String(describing: channelTwice?.channel)) \(String(describing: otherFunding)) \(String(describing: otherMerchant)) \(String(describing: receiptSaysCard))")
        let unknownLearned = ChannelLearning.learn(merchant: "KEDAI X", funding: "Maybank", channel: .unknown, in: ctx)
        ChannelLearning.learn(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", channel: .tngQR, in: ctx)
        let corrected = ChannelLearning.rule(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", in: ctx)
        let afterCorrection = ChannelLearning.suggestion(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", detected: .unknown, in: ctx)
        t.check("Unknown is never learned; a different choice replaces the rule and restarts its count (no suggestion until confirmed again)",
                unknownLearned == nil && corrected?.channel == .tngQR && corrected?.hitCount == 1 && afterCorrection == nil &&
                TestKit.count(ChannelRule.self, in: ctx) == 1,
                expected: "nil, TNG_QR x1, nil, 1 rule", actual: "\(String(describing: unknownLearned)) \(String(describing: corrected?.channelRaw)) \(String(describing: corrected?.hitCount)) \(TestKit.count(ChannelRule.self, in: ctx))")

        // 9. Backups carry learned channels; restore merges them without duplicates
        try? ctx.save()
        let payload = UserDataBackupService.makePayload(from: ctx)
        let decoded = (try? JSONEncoder().encode(payload)).flatMap { try? JSONDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
        let fresh = TestKit.context()
        if let decoded { _ = UserDataBackupService.applyBackupPayload(decoded, into: fresh); _ = UserDataBackupService.applyBackupPayload(decoded, into: fresh) }
        try? fresh.save()
        let restored = ChannelLearning.rule(merchant: "AH SENG ENTERPRISE", funding: "Touch 'n Go", in: fresh)
        t.check("Backup includes learned channel rules; restoring twice gives one rule with the same channel and count",
                decoded?.channelRules?.count == 1 && restored?.channel == .tngQR && restored?.hitCount == 1 && TestKit.count(ChannelRule.self, in: fresh) == 1,
                expected: "1 rule, TNG_QR x1", actual: "\(String(describing: decoded?.channelRules?.count)) \(String(describing: restored?.channelRaw)) \(TestKit.count(ChannelRule.self, in: fresh))")
        var olderFile = payload; olderFile.channelRules = nil
        let olderDecoded = (try? JSONEncoder().encode(olderFile)).flatMap { try? JSONDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
        t.check("A backup made before channel learning (no channelRules field) still decodes and restores",
                olderDecoded != nil && olderDecoded?.channelRules == nil && olderDecoded?.expenses.count == 2,
                expected: "decodes, 2 expenses", actual: "\(String(describing: olderDecoded?.expenses.count))")

        // 10. Migration V4 → V5 on an on-disk store: only the new ChannelRule table is added; nothing is rewritten
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropV5Migration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("default.store")
            var before: [String: Int] = [:]
            var snapshot: [UUID: String] = [:]
            do {
                // Expected balances: the same records built with the live types in memory.
                do {
                    let c = TestKit.context()
                    let bijoy = PayBookProfile(name: "Bijoy"); c.insert(bijoy)
                    let qr = Expense(amount: 15, merchant: "TEALIVE KLCC", category: .food, paymentChannel: .qrPayment, fundingAccount: "Maybank"); c.insert(qr)
                    var d = SplitDraft(); d.add(bijoy); d.apply(to: qr, in: c)
                    c.insert(MoneyMovement(kind: .loanGiven, amountMinor: 5000, person: bijoy))
                    try? c.save()
                    before = ["Bijoy": PersonLedger.balances(for: bijoy)["RM"] ?? 0]
                }
                // The V4 store is written with the frozen V2 model types (the shapes V4 shipped with).
                typealias V2 = SpenDropSchemaV2
                let v4 = Schema(versionedSchema: SpenDropSchemaV4.self)
                if let container = try? ModelContainer(for: v4, configurations: [ModelConfiguration(schema: v4, url: storeURL)]) {
                    let c = ModelContext(container)
                    let bijoy = V2.PayBookProfile(name: "Bijoy"); c.insert(bijoy)
                    // Saved with the old classifier's guesses: these must survive exactly as they are.
                    func expense(_ amount: Double, _ merchant: String, _ category: ExpenseCategory, _ channel: PaymentChannel) -> V2.Expense {
                        let e = V2.Expense(amount: amount, merchant: merchant, fundingAccount: "Maybank"); c.insert(e)
                        e.categoryRaw = category.rawValue; e.paymentChannelRaw = channel.rawValue
                        return e
                    }
                    let qr = expense(15, "TEALIVE KLCC", .food, .qrPayment)
                    _ = expense(42.5, "KEDAI MAKAN", .other, .bankTransfer)
                    qr.splitMethodRaw = SplitMethod.equal.rawValue
                    for (index, p) in [nil, bijoy].enumerated() {
                        let share = V2.ExpenseShare(isMe: p == nil, nameSnapshot: p?.name ?? "Me", amountMinor: 750, sortIndex: index)
                        c.insert(share); share.expense = qr; share.person = p
                    }
                    let loan = V2.MoneyMovement(directionRaw: MoneyMovementKind.loanGiven.direction.rawValue, kindRaw: MoneyMovementKind.loanGiven.rawValue,
                                                amountMinor: 5000); c.insert(loan)
                    loan.person = bijoy; loan.personNameSnapshot = bijoy.name
                    TransactionClassifier.learn(merchant: "KEDAI MAKAN", category: .food, in: c)
                    try? c.save()
                    snapshot = Dictionary(uniqueKeysWithValues: ((try? c.fetch(FetchDescriptor<V2.Expense>())) ?? []).map { ($0.id, "\($0.categoryRaw)|\($0.paymentChannelRaw)|\($0.amount)|\($0.fundingAccount)") })
                }
            }
            var actual = "open failed"
            var passed = false
            if let container = try? ExpenseDataContainer.openPersistentContainer(configuration: ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)) {
                let c = ModelContext(container)
                let people = Dictionary(TestKit.fetch(PayBookProfile.self, in: c).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                let after = people.mapValues { PersonLedger.balances(for: $0)["RM"] ?? 0 }
                let now = Dictionary(uniqueKeysWithValues: TestKit.fetch(Expense.self, in: c).map { ($0.id, "\($0.categoryRaw)|\($0.paymentChannelRaw)|\($0.amount)|\($0.fundingAccount)") })
                ChannelLearning.learn(merchant: "KEDAI MAKAN", funding: "Maybank", channel: .duitNowQR, in: c)
                try? c.save()
                passed = !snapshot.isEmpty && now == snapshot && after == before && TestKit.count(MoneyMovement.self, in: c) == 1 &&
                    TestKit.count(ClassificationRule.self, in: c) == 1 && TestKit.count(ChannelRule.self, in: c) == 1
                actual = "expenses same=\(now == snapshot) before=\(before) after=\(after) rules=\(TestKit.count(ClassificationRule.self, in: c)) channelRules=\(TestKit.count(ChannelRule.self, in: c))"
            }
            t.check("Migration V4 → V5 on disk: every expense keeps its category, channel, amount and funding account (old QR/Bank Transfer guesses not rewritten); balances, movements and learned categories kept; the new channel-rule table works",
                    passed, expected: "identical, 1 rule, 1 channel rule", actual: actual)
        }
        return results
    }
}
