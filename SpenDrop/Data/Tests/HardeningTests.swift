import Foundation
import SwiftData

/// Phase 8: cross-cutting edge cases, the full V1 → V3 migration chain and a full local backup round trip.
/// `--run-hardening-tests`
@MainActor
public struct HardeningTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Phase 8") { results.append($0) }

        // MARK: Migration chain V1 → V2 → V3 on disk
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpenDropChain-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("default.store")
            var ids: [UUID] = []
            do {
                let v1 = Schema(versionedSchema: SpenDropSchemaV1.self)
                if let c = try? ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: storeURL)]) {
                    let ctx = ModelContext(c)
                    for (i, funding) in ["Maybank", "Touch 'n Go", "Unknown"].enumerated() {
                        let e = SpenDropSchemaV1.Expense(amount: Double(i + 1) * 12.5, merchant: "M\(i)", fundingAccount: funding)
                        ctx.insert(e); ids.append(e.id)
                    }
                    let p = SpenDropSchemaV1.PayBookProfile(name: "Rahim"); ctx.insert(p)
                    try? ctx.save()
                }
            }
            var actual = "open failed"
            var passed = false
            if let c = try? ExpenseDataContainer.openPersistentContainer(configuration: ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)) {
                let ctx = ModelContext(c)
                let expenses = TestKit.fetch(Expense.self, in: ctx)
                let byID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
                ctx.insert(ClassificationRule(merchantKey: "m0", categoryRaw: "Food"))
                passed = Set(expenses.map(\.id)) == Set(ids) && byID[ids[0]]?.account?.name == "Maybank" &&
                    byID[ids[1]]?.account?.type == .eWallet && byID[ids[2]]?.account == nil && byID[ids[1]]?.amount == 25 &&
                    TestKit.count(PayBookProfile.self, in: ctx) == 1 && (try? ctx.save()) != nil && TestKit.count(ClassificationRule.self, in: ctx) == 1
                actual = "expenses=\(expenses.count) accounts=\(TestKit.fetch(Account.self, in: ctx).map(\.name).sorted()) rules=\(TestKit.count(ClassificationRule.self, in: ctx))"
            }
            t.check("Migration chain V1 → V2 → V3: ids/amounts kept, accounts linked, Unknown unlinked, rules table ready",
                    passed, expected: "all kept", actual: actual)
        }

        // MARK: Full local backup round trip: export → wipe → import
        do {
            let original = TestKit.context()
            let maybank = Account(name: "Maybank", type: .bank), tng = Account(name: "Touch 'n Go", type: .eWallet), wise = Account(name: "Wise", isArchived: true)
            [maybank, tng, wise].forEach { original.insert($0) }
            let bijoy = PayBookProfile(name: "Bijoy"), shadin = PayBookProfile(name: "Shadin")
            original.insert(bijoy); original.insert(shadin)
            bijoy.isFrequent = true
            let dinner = Expense(amount: 30, merchant: "Dinner", fundingAccount: "Maybank"); original.insert(dinner); dinner.account = maybank
            var split = SplitDraft(); split.method = .parts; split.add(bijoy); split.setParts(2, for: split.participants[1].id); split.apply(to: dinner, in: original)
            let usd = Expense(amount: 10, currency: "USD", merchant: "Abroad"); original.insert(usd)
            let purchase = Expense(amount: 100, merchant: "Uniqlo"); original.insert(purchase)
            let movements = [
                MoneyMovement(kind: .refund, amountMinor: 3000, linkedExpense: purchase, account: maybank),
                MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: shadin, account: maybank),
                MoneyMovement(kind: .ownTransfer, amountMinor: 20000, account: maybank, counterAccount: tng),
                MoneyMovement(kind: .income, amountMinor: 300000, account: maybank, note: "Salary")
            ]
            movements.forEach { original.insert($0) }
            TransactionClassifier.learn(merchant: "Dinner", category: .food, in: original)
            try? original.save()

            var passed = false
            var actual = "export failed"
            if let url = UserDataBackupService.generateExportJSONFile(from: original) {
                let wiped = TestKit.context()
                let summary = try? UserDataBackupService.importFromJSON(at: url, into: wiped)
                let again = try? UserDataBackupService.importFromJSON(at: url, into: wiped)       // duplicate import
                try? FileManager.default.removeItem(at: url)
                let e = TestKit.fetch(Expense.self, in: wiped), m = TestKit.fetch(MoneyMovement.self, in: wiped)
                let rDinner = e.first { $0.id == dinner.id }
                let rRefund = m.first { $0.kind == .refund }
                let rLoan = m.first { $0.kind == .loanGiven }
                let rTransfer = m.first { $0.kind == .ownTransfer }
                let rShadin = TestKit.fetch(PayBookProfile.self, in: wiped).first { $0.id == shadin.id }
                let rBijoy = TestKit.fetch(PayBookProfile.self, in: wiped).first { $0.id == bijoy.id }
                let sameTimes = abs((rDinner?.createdAt ?? .distantPast).timeIntervalSince(dinner.createdAt)) < 1 &&
                                abs((rLoan?.updatedAt ?? .distantPast).timeIntervalSince(movements[1].updatedAt)) < 1
                let totalsRM = FinancialCalculator.summary(expenses: e, movements: m) == FinancialCalculator.summary(expenses: [dinner, usd, purchase], movements: movements)
                let totalsUSD = FinancialCalculator.summary(expenses: e, movements: m, currency: "USD").spendingMinor == 1000
                passed = summary?.expensesAdded == 3 && again?.expensesAdded == 0 && again?.movementsAdded == 0 &&
                    e.count == 3 && m.count == 4 && TestKit.count(ExpenseShare.self, in: wiped) == 2 && TestKit.count(Account.self, in: wiped) == 3 &&
                    TestKit.count(ClassificationRule.self, in: wiped) == 1 &&
                    rDinner?.account?.id == maybank.id && rDinner?.splitMethod == .parts && rDinner?.myShareMinor == 1000 &&
                    rDinner?.shares.first { !$0.isMe }?.person?.id == bijoy.id && rDinner?.shares.first { !$0.isMe }?.parts == 2 &&
                    rRefund?.linkedExpense?.id == purchase.id && rRefund?.linkedExpenseSnapshot?.hasPrefix("Uniqlo") == true &&
                    rLoan?.person?.id == shadin.id && rLoan?.personNameSnapshot == "Shadin" &&
                    rTransfer?.account?.id == maybank.id && rTransfer?.counterAccount?.id == tng.id &&
                    TestKit.fetch(Account.self, in: wiped).first { $0.id == wise.id }?.isArchived == true && rBijoy?.isFrequent == true &&
                    rShadin.map { PersonLedger.balances(for: $0)["RM"] } == 15000 && sameTimes && totalsRM && totalsUSD
                actual = "added=\(summary?.expensesAdded ?? -1) again=\(again?.expensesAdded ?? -1) e=\(e.count) m=\(m.count) totals=\(totalsRM)/\(totalsUSD) times=\(sameTimes)"
            }
            t.check("Local backup round trip (export → wipe → import, twice): every record, link, snapshot, timestamp and total",
                    passed, expected: "identical, second import adds nothing", actual: actual)
        }

        // MARK: Transfers both ways
        do {
            let ctx = TestKit.context()
            let maybank = Account(name: "Maybank", type: .bank), tng = Account(name: "Touch 'n Go", type: .eWallet)
            ctx.insert(maybank); ctx.insert(tng)
            let there = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, account: maybank, counterAccount: tng)
            let back = MoneyMovement(kind: .ownTransfer, amountMinor: 5000, account: tng, counterAccount: maybank)
            ctx.insert(there); ctx.insert(back)
            try? ctx.save()
            let m = FinancialCalculator.accountActivity(for: maybank), n = FinancialCalculator.accountActivity(for: tng)
            let global = FinancialCalculator.summary(expenses: [], movements: [there, back])
            var same = MoneyMovementDraft(entryType: .transfer); same.amountText = "1"; same.account = tng; same.counterAccount = tng
            t.check("Transfers Maybank → TNG and TNG → Maybank: per-account in/out, global cash flow and spending zero; same account rejected",
                    m.outMinor == 20000 && m.inMinor == 5000 && n.inMinor == 20000 && n.outMinor == 5000 && global == FinancialCalculator.Summary() &&
                    same.issues == [.sameAccount],
                    expected: "Maybank -200/+50, TNG +200/-50, global 0", actual: "maybank \(m) tng \(n) global \(global)")
        }

        // MARK: Accounts: rename, archive, unarchive keep history
        do {
            let ctx = TestKit.context()
            let bank = Account(name: "Maybank", type: .bank)
            ctx.insert(bank)
            let e = Expense(amount: 8, merchant: "Kopi", fundingAccount: "Maybank"); ctx.insert(e); e.account = bank
            try? ctx.save()
            bank.name = "Maybank Savings"
            bank.isArchived = true
            let hiddenFromPickers = !AccountLinker.fundingOptions(base: ["Other"], accounts: [bank]).contains("Maybank Savings")
            let historyKept = bank.expenses.count == 1 && e.fundingAccount == "Maybank" && e.account === bank
            bank.isArchived = false
            let visibleAgain = AccountLinker.fundingOptions(base: ["Other"], accounts: [bank]).contains("Maybank Savings")
            t.check("Account rename/archive/unarchive: history and original text kept; archived hidden from pickers",
                    hiddenFromPickers && historyKept && visibleAgain, expected: "hidden, kept, visible",
                    actual: "hidden=\(hiddenFromPickers) kept=\(historyKept) visible=\(visibleAgain)")
        }

