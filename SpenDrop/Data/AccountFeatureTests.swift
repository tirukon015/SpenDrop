import Foundation
import SwiftData

/// Phase 3 checks: account activity, account resolving/relinking, funding options, Money In/Out/Transfer drafts
/// and account form validation. In-memory only. Launch argument: `--run-account-tests`.
@MainActor
public struct AccountFeatureTests {
    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        func check(_ name: String, _ passed: Bool, expected: String, actual: String) {
            results.append(TestCaseResult(testName: name, passed: passed, expected: expected, actual: actual, details: "Phase 3"))
        }
        func context() -> ModelContext {
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config])
            return ModelContext(container)
        }
        func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
            (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
        }

        // MARK: Recorded account activity
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank", type: .bank), tng = Account(name: "Touch 'n Go", type: .eWallet)
            let bijoy = PayBookProfile(name: "Bijoy")
            ctx.insert(maybank); ctx.insert(tng); ctx.insert(bijoy)

            let lunch = Expense(amount: 25, merchant: "McDonald's")
            let paidByOther = Expense(amount: 30, merchant: "Dinner")
            let foreign = Expense(amount: 10, currency: "USD", merchant: "Abroad")
            [lunch, paidByOther, foreign].forEach { ctx.insert($0); $0.account = maybank }
            paidByOther.setPayer(bijoy)

            let salary = MoneyMovement(kind: .income, amountMinor: 100000, account: maybank)
            let loan = MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: bijoy, account: maybank)
            let transfer = MoneyMovement(kind: .ownTransfer, amountMinor: 20000, account: maybank, counterAccount: tng)
            [salary, loan, transfer].forEach { ctx.insert($0) }
            try? ctx.save()

            let m = FinancialCalculator.accountActivity(for: maybank)
            let t = FinancialCalculator.accountActivity(for: tng)
            check("Account activity: Maybank in/out/net", m.inMinor == 100000 && m.outMinor == 37500 && m.netMinor == 62500,
                  expected: "in 100000, out 37500 (25 + 150 + 200), net 62500", actual: "in \(m.inMinor), out \(m.outMinor), net \(m.netMinor)")
            check("Account activity: transfer arrives in Touch 'n Go", t.inMinor == 20000 && t.outMinor == 0,
                  expected: "in 20000, out 0", actual: "in \(t.inMinor), out \(t.outMinor)")
        }

        // MARK: Resolving and relinking accounts
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank", type: .bank, sortIndex: 0)
            let wise = Account(name: "Wise", type: .other, isArchived: true, sortIndex: 1)
            ctx.insert(maybank); ctx.insert(wise)

            let same = AccountLinker.resolveAccount(named: " maybank ", in: ctx)
            let archived = AccountLinker.resolveAccount(named: "WISE", in: ctx)
            let created = AccountLinker.resolveAccount(named: "Bank Rakyat", in: ctx)
            let unknown = AccountLinker.resolveAccount(named: "Unknown", in: ctx)
            try? ctx.save()
            check("Resolve account: reuse by name (incl. archived), create new, ignore Unknown",
                  same === maybank && archived === wise && created?.name == "Bank Rakyat" && created?.type == .bank &&
                  created?.sortIndex == 2 && unknown == nil && count(Account.self, in: ctx) == 3,
                  expected: "Maybank reused, Wise reused, Bank Rakyat created (bank), Unknown nil, 3 accounts",
                  actual: "sameReused=\(same === maybank) archivedReused=\(archived === wise) created=\(created?.name ?? "nil")/\(created?.type.rawValue ?? "-") accounts=\(count(Account.self, in: ctx))")
        }
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank", type: .bank), cimb = Account(name: "CIMB", type: .bank)
            ctx.insert(maybank); ctx.insert(cimb)
            let expense = Expense(amount: 12, merchant: "Kedai", fundingAccount: "Maybank")
            ctx.insert(expense)
            expense.account = maybank

            AccountLinker.relink(expense, in: ctx)
            let unchanged = expense.account === maybank
            expense.fundingAccount = "CIMB"            // user edits the expense
            AccountLinker.relink(expense, in: ctx)
            let movedToCIMB = expense.account === cimb
            expense.fundingAccount = "GXBank"
            AccountLinker.relink(expense, in: ctx)
            let createdNew = expense.account?.name == "GXBank"
            expense.fundingAccount = "Unknown"
            AccountLinker.relink(expense, in: ctx)
            let cleared = expense.account == nil
            try? ctx.save()
            check("Editing an expense's funding account relinks it (no stale link)",
                  unchanged && movedToCIMB && createdNew && cleared && count(Account.self, in: ctx) == 3,
                  expected: "same -> Maybank, CIMB -> CIMB, GXBank -> new, Unknown -> none",
                  actual: "unchanged=\(unchanged) cimb=\(movedToCIMB) new=\(createdNew) cleared=\(cleared) accounts=\(count(Account.self, in: ctx))")
        }
        do {
            let ctx = context()
            let dup = Account(name: "maybank", sortIndex: 0), extra = Account(name: "Bank Rakyat", type: .bank, sortIndex: 1)
            let archived = Account(name: "Wise", isArchived: true, sortIndex: 2)
            [dup, extra, archived].forEach { ctx.insert($0) }
            let options = AccountLinker.fundingOptions(base: ["Maybank", "CIMB", "Wise", "Other"], accounts: [dup, extra, archived])
            check("Funding options: existing list + user accounts, no duplicates, Other last",
                  options == ["Maybank", "CIMB", "Wise", "Bank Rakyat", "Other"],
                  expected: "[Maybank, CIMB, Wise, Bank Rakyat, Other]", actual: "\(options)")
        }

        // MARK: Money In / Money Out / Transfer drafts
        do {
            var draft = MoneyMovementDraft(entryType: .moneyIn)
            let defaultKind = draft.kind
            let emptyIssues = draft.issues
            draft.amountText = "0"
            let zeroIssues = draft.issues
            draft.amountText = "12.50"
            let validIncome = draft.isValid && draft.amountMinor == 1250
            draft.setEntryType(.moneyOut)
            let outKind = draft.kind
            let loanIssues = draft.issues
            check("Draft validation: amount and person",
                  defaultKind == .income && emptyIssues == [.invalidAmount] && zeroIssues == [.invalidAmount] &&
                  validIncome && outKind == .loanGiven && loanIssues == [.missingPerson],
                  expected: "income default; empty/0 invalid; 12.50 valid; Money Out -> loan needs person",
                  actual: "default=\(defaultKind) empty=\(emptyIssues) zero=\(zeroIssues) valid=\(validIncome) out=\(outKind) loan=\(loanIssues)")

            let ctx = context()
            let maybank = Account(name: "Maybank"), tng = Account(name: "Touch 'n Go")
            ctx.insert(maybank); ctx.insert(tng)
            var transfer = MoneyMovementDraft(entryType: .transfer)
            transfer.amountText = "200"
            let missing = transfer.issues
            transfer.account = maybank
            transfer.counterAccount = maybank
            let same = transfer.issues
            transfer.counterAccount = tng
            check("Draft validation: transfer needs two different accounts",
                  transfer.kind == .ownTransfer && missing == [.missingFromAccount, .missingToAccount] && same == [.sameAccount] && transfer.isValid,
                  expected: "missing both, then same account, then valid", actual: "missing=\(missing) same=\(same) valid=\(transfer.isValid)")
        }
        do {
            let ctx = context()
            let maybank = Account(name: "Maybank"), tng = Account(name: "Touch 'n Go")
            let shadin = PayBookProfile(name: "Shadin")
            ctx.insert(maybank); ctx.insert(tng); ctx.insert(shadin)

            var loan = MoneyMovementDraft(entryType: .moneyOut)
            loan.amountText = "150"
            loan.person = shadin
            loan.account = maybank
            loan.note = "  for rent  "
            let savedLoan = loan.insertMovement(into: ctx)

            var income = MoneyMovementDraft(entryType: .moneyIn)
            income.amountText = "3000"
            income.person = shadin           // not needed for income: must not be stored
            let savedIncome = income.insertMovement(into: ctx)

            var transfer = MoneyMovementDraft(entryType: .transfer)
            transfer.amountText = "200"
            transfer.account = maybank
            transfer.counterAccount = tng
            let savedTransfer = transfer.insertMovement(into: ctx)

            var invalid = MoneyMovementDraft(entryType: .moneyOut)
            invalid.amountText = "5"
            let rejected = invalid.insertMovement(into: ctx)
            try? ctx.save()

            let passed = savedLoan?.kind == .loanGiven && savedLoan?.direction == .moneyOut && savedLoan?.amountMinor == 15000 &&
                savedLoan?.person === shadin && savedLoan?.personNameSnapshot == "Shadin" && savedLoan?.account === maybank &&
                savedLoan?.note == "for rent" && savedLoan?.sourceType == .manual &&
                savedIncome?.person == nil && savedIncome?.direction == .moneyIn &&
                savedTransfer?.counterAccount === tng && savedTransfer?.direction == .internal &&
                rejected == nil && count(MoneyMovement.self, in: ctx) == 3
            check("Draft save: loan, income and transfer stored correctly; invalid draft not saved", passed,
                  expected: "3 movements with correct kind/direction/person/accounts; invalid rejected",
                  actual: "loan=\(savedLoan?.kind.rawValue ?? "nil") person=\(savedLoan?.personNameSnapshot ?? "nil") incomePerson=\(savedIncome?.person?.name ?? "nil") transferTo=\(savedTransfer?.counterAccount?.name ?? "nil") count=\(count(MoneyMovement.self, in: ctx))")

            // Edit an existing record
            if let savedLoan {
                let originalId = savedLoan.id
                var edit = MoneyMovementDraft(movement: savedLoan)
                let loadedText = edit.amountText
                edit.amountText = "100"
                edit.kind = .repaymentMade
                let applied = edit.apply(to: savedLoan)
                try? ctx.save()
                check("Draft edit: loads the record and updates it in place",
                      loadedText == "150.00" && applied && savedLoan.id == originalId && savedLoan.amountMinor == 10000 &&
                      savedLoan.kind == .repaymentMade && savedLoan.directionRaw == "out" && count(MoneyMovement.self, in: ctx) == 3,
                      expected: "150.00 loaded; now 100 repayment made, same id, no new record",
                      actual: "loaded=\(loadedText) amount=\(savedLoan.amountMinor) kind=\(savedLoan.kind.rawValue) count=\(count(MoneyMovement.self, in: ctx))")
            }
        }

