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
            t.check("Channel detection never guesses (no text → Unknown; DuitNow QR text keeps its historical QR mapping)",
                    PaymentChannel.detect(from: "Thank you") == .unknown && PaymentChannel.detect(from: "DuitNow QR payment") == .qrPayment,
                    expected: "unknown, qrPayment", actual: "\(PaymentChannel.detect(from: "Thank you")), \(PaymentChannel.detect(from: "DuitNow QR payment"))")
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
            let byAmount = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date.addingTimeInterval(3600), reference: nil, kind: .income, in: ctx)
            let otherDirection = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date, reference: nil, kind: .otherOut, in: ctx)
            let later = MovementDuplicateDetector.findMatch(amountMinor: 5000, date: date.addingTimeInterval(2 * 86_400), reference: nil, kind: .otherIn, in: ctx)
            t.check("Movement duplicates: by reference, or same amount+direction within 24h; warns only",
                    byRef === existing && byAmount === existing && otherDirection == nil && later == nil,
                    expected: "ref match, amount match, none, none", actual: "\(byRef != nil) \(byAmount != nil) \(otherDirection != nil) \(later != nil)")

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
            t.check("Backup V3: rules exported and restored; same merchant merged (no duplicate), newer backup wins",
                    decoded?.version == 3 && decoded?.classificationRules?.count == 1 && summary?.rulesRestored == 1 &&
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
                let v2 = Schema(versionedSchema: SpenDropSchemaV2.self)
                if let container = try? ModelContainer(for: v2, configurations: [ModelConfiguration(schema: v2, url: storeURL)]) {
                    let ctx = ModelContext(container)
                    let account = Account(name: "Maybank", type: .bank); ctx.insert(account)
                    let person = PayBookProfile(name: "Bijoy"); ctx.insert(person)
                    let expense = Expense(amount: 30, merchant: "Dinner", fundingAccount: "Maybank"); ctx.insert(expense)
                    expense.account = account
                    var d = SplitDraft(); d.add(person); d.payer = person; d.apply(to: expense, in: ctx)
                    let movement = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: person, account: account); ctx.insert(movement)
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
