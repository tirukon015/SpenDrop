import CoreData
import Foundation
import SwiftData

/// Test-only model used to create a store that SpenDrop's schema cannot open (simulates a failed migration).
/// It is not part of the app schema.
@Model
final class DataSafetyProbeRecord {
    var label: String
    init(label: String) { self.label = label }
}

/// Test-only model whose `Expense.amount` type cannot be migrated to SpenDrop's `Expense` (simulates a failed migration).
enum IncompatibleProbe {
    @Model
    final class Expense {
        var amount: String
        init(amount: String) { self.amount = amount }
    }
}

/// Phase 0 data-safety checks. Every test runs in its own temporary directory or in-memory store and never
/// touches the user's database or backup files. Run with the `--run-data-safety-tests` launch argument.
@MainActor
public struct DataSafetyTests {
    public static func runAllTests() -> [TestCaseResult] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpenDropDataSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var results: [TestCaseResult] = []
        func record(_ name: String, _ passed: Bool, expected: String, actual: String, details: String = "") {
            results.append(TestCaseResult(testName: name, passed: passed, expected: expected, actual: actual, details: details))
        }
        func freshDir(_ name: String) -> URL {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        var defaultsSuites: [String] = []
        defer { defaultsSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) } }
        func freshDefaults() -> UserDefaults {
            let suite = "SpenDropDataSafetyTests.\(UUID().uuidString)"
            defaultsSuites.append(suite)
            return UserDefaults(suiteName: suite)!
        }
        func inMemoryContext() -> ModelContext? {
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: ExpenseDataContainer.currentSchema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }
        func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
        }

        // 1. A store created by the pre-versioning app opens with the versioned schema and keeps every record.
        do {
            let storeURL = freshDir("legacy").appendingPathComponent("default.store")
            let expenseId = UUID()
            var created = false
            do {
                // The frozen V1 models reproduce the pre-versioning app's model exactly (see test 1b).
                let legacySchema = Schema([SpenDropSchemaV1.Expense.self, SpenDropSchemaV1.PayBookProfile.self,
                                           SpenDropSchemaV1.PayBookPaymentMethod.self, SpenDropSchemaV1.PayBookContact.self])
                let legacyConfig = ModelConfiguration(schema: legacySchema, url: storeURL)
                if let legacy = try? ModelContainer(for: legacySchema, configurations: [legacyConfig]) {
                    let ctx = ModelContext(legacy)
                    let expense = SpenDropSchemaV1.Expense(id: expenseId, amount: 30, merchant: "Lunch", fundingAccount: "Maybank")
                    expense.notes = "keep me"
                    expense.imageRelativePath = "receipts/a.jpg"
                    let profile = SpenDropSchemaV1.PayBookProfile(name: "Bijoy")
                    ctx.insert(expense)
                    ctx.insert(profile)
                    let method = SpenDropSchemaV1.PayBookPaymentMethod(provider: "Maybank", accountIdentifier: "123", profile: profile)
                    ctx.insert(method)
                    profile.paymentMethods.append(method)
                    created = (try? ctx.save()) != nil
                }
            }
            var actual = "legacy store not created"
            var passed = false
            if created {
                let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
                if let container = try? ExpenseDataContainer.openPersistentContainer(configuration: config) {
                    let ctx = ModelContext(container)
                    let expenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
                    let e = expenses.first { $0.id == expenseId }
                    let methods = count(PayBookPaymentMethod.self, in: ctx)
                    passed = expenses.count == 1 && e?.notes == "keep me" && e?.imageRelativePath == "receipts/a.jpg" &&
                             count(PayBookProfile.self, in: ctx) == 1 && methods == 1 && e?.account?.name == "Maybank"
                    actual = "expenses=\(expenses.count) notes=\(e?.notes ?? "nil") profiles=\(count(PayBookProfile.self, in: ctx)) methods=\(methods) account=\(e?.account?.name ?? "nil")"
                } else {
                    actual = "versioned open threw"
                }
            }
            record("Versioned schema opens existing unversioned store", passed,
                   expected: "1 expense (fields intact, linked to account Maybank), 1 profile, 1 method", actual: actual,
                   details: "Simulates upgrading a device database created before explicit versioning")
        }

        // 1b. The frozen V1 models must describe exactly the model the app shipped before versioning.
        //     Fingerprint recorded from the shipped build's store (Phase 0/1) on 2026-09-29.
        do {
            let shipped = "Expense{amount:Double,categoryRaw:String,confidence:Optional<Double>,createdAt:Date,currency:String,date:Date,externalTransactionId:Optional<String>,fundingAccount:String,fundingInstrument:Optional<String>,id:UUID,imageRelativePath:Optional<String>,isSampleData:Bool,matchingConfidence:Optional<Double>,matchingStatusRaw:String,merchant:String,notes:Optional<String>,ocrText:Optional<String>,paymentChannelRaw:String,paymentMethodRaw:Optional<String>,paymentSourceRaw:String,sourceTypeRaw:String,transactionReference:Optional<String>,underlyingBankRaw:Optional<String>,updatedAt:Date|};PayBookContact{accountHolderName:String,accountNumber:String,bankName:String,createdAt:Date,id:UUID,name:String,phoneNumber:Optional<String>,updatedAt:Date|};PayBookPaymentMethod{accountIdentifier:String,createdAt:Date,customProviderName:Optional<String>,id:UUID,label:Optional<String>,notes:Optional<String>,paymentTypeRaw:String,provider:String,updatedAt:Date|profile->PayBookProfile};PayBookProfile{createdAt:Date,id:UUID,name:String,notes:Optional<String>,photoData:Optional<Data>,updatedAt:Date|paymentMethods->PayBookPaymentMethod}"
            let frozen = ExpenseDataContainer.schemaFingerprint(Schema(versionedSchema: SpenDropSchemaV1.self))
            record("Frozen V1 schema matches the shipped model", frozen == shipped,
                   expected: "identical fingerprint", actual: frozen == shipped ? "identical" : "DIFFERENT: \(frozen)",
                   details: "If this fails, existing databases would not be recognised")
        }

        // 1c. V2 lists the live model types; they must still describe exactly the V2 model shipped in Phase 2/3.
        //     Recorded from the running Phase 6 build on 2026-09-29 (before V3 was added).
        do {
            let shipped = "Account{createdAt:Date,currency:String,icon:Optional<String>,id:UUID,isArchived:Bool,name:String,sortIndex:Int,typeRaw:String|expenses->Expense,incomingTransfers->MoneyMovement,movements->MoneyMovement};Expense{amount:Double,categoryRaw:String,confidence:Optional<Double>,createdAt:Date,currency:String,date:Date,externalTransactionId:Optional<String>,fundingAccount:String,fundingInstrument:Optional<String>,id:UUID,imageRelativePath:Optional<String>,isSampleData:Bool,matchingConfidence:Optional<Double>,matchingStatusRaw:String,merchant:String,notes:Optional<String>,ocrText:Optional<String>,paidByMe:Bool,payerNameSnapshot:Optional<String>,paymentChannelRaw:String,paymentMethodRaw:Optional<String>,paymentSourceRaw:String,sourceTypeRaw:String,splitMethodRaw:Optional<String>,transactionReference:Optional<String>,underlyingBankRaw:Optional<String>,updatedAt:Date|account->Account,linkedMovements->MoneyMovement,payer->PayBookProfile,shares->ExpenseShare};ExpenseShare{amountMinor:Int,enteredMinor:Optional<Int>,id:UUID,isMe:Bool,nameSnapshot:String,parts:Optional<Int>,sortIndex:Int|expense->Expense,person->PayBookProfile};MoneyMovement{amountMinor:Int,createdAt:Date,currency:String,date:Date,directionRaw:String,id:UUID,kindRaw:String,linkedExpenseSnapshot:Optional<String>,note:Optional<String>,paymentChannelRaw:String,personNameSnapshot:Optional<String>,sourceTypeRaw:String,transactionReference:Optional<String>,updatedAt:Date|account->Account,counterAccount->Account,linkedExpense->Expense,person->PayBookProfile};PayBookContact{accountHolderName:String,accountNumber:String,bankName:String,createdAt:Date,id:UUID,name:String,phoneNumber:Optional<String>,updatedAt:Date|};PayBookPaymentMethod{accountIdentifier:String,createdAt:Date,customProviderName:Optional<String>,id:UUID,label:Optional<String>,notes:Optional<String>,paymentTypeRaw:String,provider:String,updatedAt:Date|profile->PayBookProfile};PayBookProfile{createdAt:Date,id:UUID,isArchived:Bool,isFrequent:Bool,name:String,notes:Optional<String>,photoData:Optional<Data>,updatedAt:Date|movements->MoneyMovement,paidExpenses->Expense,paymentMethods->PayBookPaymentMethod,shares->ExpenseShare}"
            let now = ExpenseDataContainer.schemaFingerprint(Schema(versionedSchema: SpenDropSchemaV2.self))
            record("V2 schema still matches the shipped V2 model", now == shipped,
                   expected: "identical fingerprint", actual: now == shipped ? "identical" : "DIFFERENT: \(now)",
                   details: "If this fails, a live model changed without freezing V2 first")
        }

        // 1d. V2–V5 were frozen when V6 changed Expense. The frozen V5 model must have exactly the Core Data version
        //     hashes of the shipped V5 model, or existing stores would be "an unknown model version" (safe mode).
        //     Hashes recorded from the shipped V5 model (live types before V6) on 2026-10-07.
        do {
            let shipped: [String: String] = [
                "Account": "7GwxZCuhAx+YfzfemfITSOLutdiluOZqznE5HnTiLN0=",
                "ChannelRule": "fO6rKEykYrpeEJK4VFrG2RorA4+F9pHofBOoarV9DSE=",
                "ClassificationRule": "p94qvMxNtPEDaATigd0hEypBNJ5zEgSVazI61eP8CtM=",
                "Expense": "7DGIAhlSrwxLW0H1pd2ZCbXqiNJn2/w/+bnMWbeNweI=",
                "ExpenseShare": "jz14UjeZc9QxnQHZ6cJVZ50cVqWfjZTf7saddWXGioU=",
                "MoneyMovement": "6UXYCYdCFaBHtw0DsxiEAQBkHoJpa2FdhmsQk0pDB+E=",
                "PayBookContact": "UlvDublLdTPtKdgQsCvELE/sVa0z+6mWSTprgf3E0tc=",
                "PayBookPaymentMethod": "39Gk48926ZUIdlM1BIj8kh9wSlBkg7mT+TXQ8IBo04Q=",
                "PayBookProfile": "A/mRAj1+kOXSd7rlNB9ARmMLirJYTLXHO+WqUYHWnio=",
                "SampleDataRecord": "KP1UttJYMA7wEbnqGAlGmLac+Uxog7N0b1dFPPJmjJU=",
                "SettlementAllocation": "sxGHVj+cwH8lJYMdsIItAxWevI7taCkne15jn0ZTSQI="
            ]
            let frozen = NSManagedObjectModel.makeManagedObjectModel(for: SpenDropSchemaV5.models)?
                .entityVersionHashesByName.mapValues { $0.base64EncodedString() } ?? [:]
            let current = NSManagedObjectModel.makeManagedObjectModel(for: SpenDropSchemaV6.models)?
                .entityVersionHashesByName.mapValues { $0.base64EncodedString() } ?? [:]
            let changed = current.keys.filter { current[$0] != shipped[$0] }.sorted()
            record("Frozen V5 model has the shipped V5 version hashes", frozen == shipped && changed == ["Expense"],
                   expected: "identical hashes; V6 changes only Expense",
                   actual: frozen == shipped ? "identical; V6 changed \(changed)" : "DIFFERENT: \(frozen.keys.filter { frozen[$0] != shipped[$0] }.sorted())",
                   details: "If this fails, devices with a V2–V5 database would open in safe mode")
        }

        // 1e. V6 = V5 + one optional Expense field, nothing else.
        do {
            let v5 = ExpenseDataContainer.schemaFingerprint(Schema(versionedSchema: SpenDropSchemaV5.self))
            let expected = v5.replacingOccurrences(of: "splitMethodRaw:Optional<String>,transactionReference",
                                                   with: "splitMethodRaw:Optional<String>,splitRule:Optional<String>,transactionReference")
            let now = ExpenseDataContainer.schemaFingerprint(ExpenseDataContainer.currentSchema)
            record("V6 only adds optional splitRule to Expense", now == expected && expected != v5,
                   expected: "V5 + Expense.splitRule:Optional<String>",
                   actual: now == expected ? "as expected" : "DIFFERENT: \(now)")
        }

        // 1f. A V5 database (shipped model) with a split expense upgrades to V6 with every share intact and the new
        //     splitRule nil; a Hybrid Split can then be saved and read back.
        do {
            let storeURL = freshDir("v5-upgrade").appendingPathComponent("default.store")
            let expenseId = UUID()
            var created = false
            do {
                let v5Schema = Schema(versionedSchema: SpenDropSchemaV5.self)
                if let v5 = try? ModelContainer(for: v5Schema, configurations: [ModelConfiguration(schema: v5Schema, url: storeURL)]) {
                    let ctx = ModelContext(v5)
                    let expense = SpenDropSchemaV2.Expense(id: expenseId, amount: 30, merchant: "Dinner")
                    expense.splitMethodRaw = "parts"
                    let bijoy = SpenDropSchemaV2.PayBookProfile(name: "Bijoy")
                    ctx.insert(expense)
                    ctx.insert(bijoy)
                    let mine = SpenDropSchemaV2.ExpenseShare(isMe: true, nameSnapshot: "Me", amountMinor: 1000, parts: 1, sortIndex: 0)
                    let his = SpenDropSchemaV2.ExpenseShare(isMe: false, nameSnapshot: "Bijoy", amountMinor: 2000, parts: 2, sortIndex: 1)
                    ctx.insert(mine)
                    ctx.insert(his)
                    mine.expense = expense
                    his.expense = expense
                    his.person = bijoy
                    created = (try? ctx.save()) != nil
                }
            }
            var passed = false
            var actual = "V5 store not created"
            if created {
                let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
                let result = ExpenseDataContainer.openStoreSafely(storeURL: storeURL, configuration: config, defaults: freshDefaults())
                var persistent = false
                if case .persistent = result.status { persistent = true }
                let ctx = ModelContext(result.container)
                let e = ((try? ctx.fetch(FetchDescriptor<Expense>())) ?? []).first { $0.id == expenseId }
                let shares = (e?.shares ?? []).sorted { $0.sortIndex < $1.sortIndex }
                let intact = shares.map(\.amountMinor) == [1000, 2000] && shares.map(\.parts) == [1, 2] && shares.last?.person?.name == "Bijoy" &&
                             e?.splitMethod == .parts && e?.splitRule == nil
                let reloaded = e.flatMap { SplitDraft(expense: $0) }
                var hybridSaved = false
                if let e, var draft = reloaded {
                    draft.setHybrid(true)
                    let row = draft.addIndividual()
                    draft.setIndividualPerson(draft.participants[1].id, for: row)
                    draft.setIndividualAmountText("5", for: row)
                    hybridSaved = draft.apply(to: e, in: ctx) && (try? ctx.save()) != nil
                }
                let after = (e?.shares ?? []).sorted { $0.sortIndex < $1.sortIndex }
                let back = e.flatMap { SplitDraft(expense: $0) }
                passed = persistent && intact && reloaded?.method == .parts && reloaded?.usesHybrid == false && hybridSaved &&
                         after.map(\.amountMinor) == [1250, 1750] && e?.splitRule != nil && back?.usesHybrid == true
                actual = "persistent=\(persistent) intact=\(intact) shares=\(shares.map(\.amountMinor)) hybridSaved=\(hybridSaved) after=\(after.map(\.amountMinor)) rule=\(e?.splitRule ?? "nil")"
            }
            record("V5 database upgrades to V6 with split shares intact", passed,
                   expected: "opens normally; shares 10/20, parts 1/2, Bijoy linked, splitRule nil; Hybrid Split saves 12.50/17.50 and reloads",
                   actual: actual, details: "Lightweight V5 -> V6 migration of a real on-disk store")
        }

        // 2. SwiftData silently migrates a store with a different model and drops entities it does not know.
        //    The pre-upgrade copy taken before opening must still contain that data.
        do {
            let dir = freshDir("dropped-entity")
            let storeURL = dir.appendingPathComponent("default.store")
            let probeSchema = Schema([DataSafetyProbeRecord.self])
            do {
                if let probe = try? ModelContainer(for: probeSchema, configurations: [ModelConfiguration(schema: probeSchema, url: storeURL)]) {
                    let ctx = ModelContext(probe)
                    ctx.insert(DataSafetyProbeRecord(label: "precious"))
                    try? ctx.save()
                }
            }
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
            _ = ExpenseDataContainer.openStoreSafely(storeURL: storeURL, configuration: config, defaults: freshDefaults())

            let safetyDir = ExpenseDataContainer.safetyDirectory(forStoreAt: storeURL)
            let snapshotName = ((try? FileManager.default.contentsOfDirectory(atPath: safetyDir.path)) ?? []).first { $0.hasPrefix("pre-upgrade-") }
            var copyLabel = "no copy"
            if let snapshotName {
                let copyURL = safetyDir.appendingPathComponent(snapshotName).appendingPathComponent("default.store")
                if let copy = try? ModelContainer(for: probeSchema, configurations: [ModelConfiguration(schema: probeSchema, url: copyURL)]) {
                    copyLabel = (try? ModelContext(copy).fetch(FetchDescriptor<DataSafetyProbeRecord>()).first?.label) ?? "missing"
                }
            }
            record("Pre-upgrade copy keeps data an automatic migration drops", copyLabel == "precious",
                   expected: "record readable from pre-upgrade copy", actual: "copy=\(copyLabel)",
                   details: "SwiftData's inferred migration removes unknown entities without an error")
        }

        // 2b. A store whose Expense model cannot be migrated automatically is left untouched and the app enters safe mode.
        do {
            let storeURL = freshDir("incompatible").appendingPathComponent("default.store")
            let oldSchema = Schema([IncompatibleProbe.Expense.self])
            do {
                if let old = try? ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: storeURL)]) {
                    let ctx = ModelContext(old)
                    ctx.insert(IncompatibleProbe.Expense(amount: "thirty"))
                    try? ctx.save()
                }
            }
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
            let result = ExpenseDataContainer.openStoreSafely(storeURL: storeURL, configuration: config, defaults: freshDefaults())
            var isSafeMode = false
            if case .safeMode = result.status { isSafeMode = true }
            let isInMemory = result.container.configurations.allSatisfy { $0.isStoredInMemoryOnly }

            var amount = "unreadable"
            if let old = try? ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: storeURL)]) {
                amount = (try? ModelContext(old).fetch(FetchDescriptor<IncompatibleProbe.Expense>()).first?.amount) ?? "missing"
            }
            record("Failed migration leaves database untouched (safe mode)", isSafeMode && isInMemory && amount == "thirty",
                   expected: "safe mode, in-memory container, original data readable",
                   actual: "safeMode=\(isSafeMode) inMemory=\(isInMemory) data=\(amount)",
                   details: "Previously the store files were deleted on failure")
        }

        // 3. A corrupt (non-database) file is not deleted either.
        do {
            let storeURL = freshDir("corrupt").appendingPathComponent("default.store")
            let garbage = Data("not a sqlite database".utf8)
            try? garbage.write(to: storeURL)
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
            let result = ExpenseDataContainer.openStoreSafely(storeURL: storeURL, configuration: config, defaults: freshDefaults())
            var isSafeMode = false
            if case .safeMode = result.status { isSafeMode = true }
            let stillThere = (try? Data(contentsOf: storeURL)) == garbage
            record("Corrupt database file is preserved", isSafeMode && stillThere,
                   expected: "safe mode and file bytes unchanged", actual: "safeMode=\(isSafeMode) preserved=\(stillThere)")
        }

        // 4. Successful open records the schema fingerprint; a pre-upgrade copy is taken only when the schema changes.
        do {
            let dir = freshDir("snapshot")
            let storeURL = dir.appendingPathComponent("default.store")
            let defaults = freshDefaults()
            let config = ModelConfiguration(schema: ExpenseDataContainer.currentSchema, url: storeURL)
            var firstOpenOK = false
            do {
                let first = ExpenseDataContainer.openStoreSafely(storeURL: storeURL, configuration: config, defaults: defaults)
                if case .persistent = first.status { firstOpenOK = true }
                let ctx = ModelContext(first.container)
                ctx.insert(Expense(amount: 12.5, merchant: "Mamak"))
                try? ctx.save()
            }
            let fingerprint = ExpenseDataContainer.schemaFingerprint(ExpenseDataContainer.currentSchema)
            let sameSchema = ExpenseDataContainer.snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: fingerprint, defaults: defaults)
            let changed = ExpenseDataContainer.snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: fingerprint + "-v2", defaults: defaults)
            let copyExists = changed.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("default.store").path) } ?? false

            // Pruning keeps only the newest 3 pre-upgrade copies.
            for i in 0..<4 {
                ExpenseDataContainer.snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: "other-\(i)", defaults: defaults,
                                                                   now: Date().addingTimeInterval(Double(i + 1)))
            }
            let safetyDir = ExpenseDataContainer.safetyDirectory(forStoreAt: storeURL)
            let snapshotCount = ((try? FileManager.default.contentsOfDirectory(atPath: safetyDir.path)) ?? []).filter { $0.hasPrefix("pre-upgrade-") }.count

            let passed = firstOpenOK && sameSchema == nil && copyExists && snapshotCount == 3
            record("Pre-upgrade copy taken only on schema change", passed,
                   expected: "open OK, no copy for same schema, copy for changed schema, max 3 kept",
                   actual: "open=\(firstOpenOK) sameSchemaCopy=\(sameSchema != nil) changedCopy=\(copyExists) kept=\(snapshotCount)")
        }

        // 5. First launch with this safety code (no fingerprint recorded yet) takes a pre-upgrade copy.
        do {
            let storeURL = freshDir("firstlaunch").appendingPathComponent("default.store")
            try? Data("existing".utf8).write(to: storeURL)
            let copy = ExpenseDataContainer.snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: "v1", defaults: freshDefaults())
            let copied = copy.flatMap { try? Data(contentsOf: $0.appendingPathComponent("default.store")) } == Data("existing".utf8)
            record("First launch after update takes a pre-upgrade copy", copied,
                   expected: "copy of existing store", actual: "copied=\(copied)")
        }

        // 5b. A pre-upgrade copy is taken even when UserDefaults wrongly says the schema is current
        //     (the store file's own metadata is checked too).
        do {
            let storeURL = freshDir("stale-defaults").appendingPathComponent("default.store")
            do {
                let v1 = Schema(versionedSchema: SpenDropSchemaV1.self)
                if let old = try? ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: storeURL)]) {
                    let ctx = ModelContext(old)
                    ctx.insert(SpenDropSchemaV1.Expense(amount: 1, merchant: "Old"))
                    try? ctx.save()
                }
            }
            let defaults = freshDefaults()
            let current = ExpenseDataContainer.schemaFingerprint(ExpenseDataContainer.currentSchema)
            defaults.set(current, forKey: "SpenDrop.lastOpenedSchemaFingerprint")
            let matchesBefore = ExpenseDataContainer.storeMatchesCurrentModel(storeURL: storeURL)
            let copy = ExpenseDataContainer.snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: current, defaults: defaults)
            record("Pre-upgrade copy taken when settings are out of sync with the store", !matchesBefore && copy != nil,
                   expected: "old store detected, copy taken", actual: "storeMatchesCurrent=\(matchesBefore) copied=\(copy != nil)")
        }

        // 6. Schema fingerprint is stable and detects model changes.
        do {
            let a = ExpenseDataContainer.schemaFingerprint(ExpenseDataContainer.currentSchema)
            let b = ExpenseDataContainer.schemaFingerprint(ExpenseDataContainer.currentSchema)
            let c = ExpenseDataContainer.schemaFingerprint(Schema([Expense.self]))
            let mentionsFields = a.contains("amount") && a.contains("paymentMethods")
            record("Schema fingerprint is stable and change-sensitive", a == b && a != c && mentionsFields,
                   expected: "same twice, differs for different schema", actual: "stable=\(a == b) differs=\(a != c) detailed=\(mentionsFields)")
        }

        // 7. Backup writer keeps history and a copy before the backup shrinks.
        do {
            let dir = freshDir("backupwriter")
            let url = dir.appendingPathComponent("SpenDrop_AutoBackup.json")
            let enc = UserDataBackupService.makeEncoder()
            func payload(_ n: Int) -> Data {
                let dtos = (0..<n).map { i in
                    UserDataBackupService.ExpenseDTO(amount: Double(i + 1), merchant: "M\(i)", categoryRaw: "Food",
                                                     paymentSourceRaw: "Cash", date: Date())
                }
                return (try? enc.encode(UserDataBackupService.BackupPayload(expenses: dtos, paybookProfiles: []))) ?? Data()
            }
            try? UserDataBackupService.writeBackupData(payload(3), to: url)
            // Pretend the existing file was written yesterday, so today's write archives it.
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: url.path)
            try? UserDataBackupService.writeBackupData(payload(1), to: url)

            let history = dir.appendingPathComponent("SpenDropBackupHistory")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []
            let shrinkName = names.first { $0.contains("before-shrink") }
            let dailyName = names.first { !$0.contains("before-shrink") }
            let dec = UserDataBackupService.makeDecoder()
            let shrinkCount = shrinkName.flatMap { try? dec.decode(UserDataBackupService.BackupPayload.self, from: Data(contentsOf: history.appendingPathComponent($0))) }?.expenses.count
            let mainCount = (try? dec.decode(UserDataBackupService.BackupPayload.self, from: Data(contentsOf: url)))?.expenses.count
            let passed = shrinkCount == 3 && mainCount == 1 && dailyName != nil
            record("Auto-backup keeps previous copy before shrinking", passed,
                   expected: "main=1, before-shrink copy=3, daily history copy",
                   actual: "main=\(mainCount ?? -1) shrinkCopy=\(shrinkCount ?? -1) daily=\(dailyName ?? "none")")
        }

        // 8. Auto-backup never writes from an in-memory (safe mode / preview / test) store.
        do {
            if let ctx = inMemoryContext() {
                ctx.insert(Expense(amount: 5, merchant: "Test"))
                try? ctx.save()
                let wrote = UserDataBackupService.saveAutoBackup(from: ctx)
                record("Auto-backup skipped for in-memory store", !wrote, expected: "not written", actual: wrote ? "written" : "not written")
            } else {
                record("Auto-backup skipped for in-memory store", false, expected: "not written", actual: "could not create context")
            }
        }

        // 9. A saved change posts ModelContext.didSave, which triggers the automatic backup.
        do {
            var received = false
            let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in received = true }
            if let ctx = inMemoryContext() {
                ctx.insert(Expense(amount: 9, merchant: "Save signal"))
                try? ctx.save()
            }
            NotificationCenter.default.removeObserver(observer)
            record("Saving posts the didSave signal used for auto-backup", received, expected: "received", actual: received ? "received" : "not received")
        }

        // 10. Backup files written before Phase 0 (without new optional fields) still decode and restore.
        do {
            let v1JSON = """
            {"accountName":"Test","appName":"SpenDrop","exportDate":"2026-09-01T10:00:00Z","version":1,
             "expenses":[{"id":"11111111-1111-1111-1111-111111111111","amount":18.5,"currency":"RM","merchant":"McDonald's",
               "categoryRaw":"Food","paymentSourceRaw":"Touch 'n Go","date":"2026-09-01T09:00:00Z","sourceTypeRaw":"screenshot",
               "isSampleData":false,"createdAt":"2026-09-01T09:05:00Z","paymentChannelRaw":"QR_PAYMENT","fundingAccount":"Touch 'n Go",
               "matchingStatusRaw":"UNMATCHED"}],
             "paybookProfiles":[{"id":"22222222-2222-2222-2222-222222222222","name":"Bijoy",
               "paymentMethods":[{"id":"33333333-3333-3333-3333-333333333333","paymentTypeRaw":"Bank Account","provider":"Maybank","accountIdentifier":"123"}]}]}
            """
            let payload = try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: Data(v1JSON.utf8))
            var actual = "decode failed"
            var passed = false
            if let payload, let ctx = inMemoryContext() {
                let summary = UserDataBackupService.applyBackupPayload(payload, into: ctx)
                let e = (try? ctx.fetch(FetchDescriptor<Expense>()))?.first
                let expectedCreated = ISO8601DateFormatter().date(from: "2026-09-01T09:05:00Z")
                passed = summary.expensesAdded == 1 && summary.profilesAdded == 1 && summary.methodsAdded == 1 &&
                         e?.id.uuidString == "11111111-1111-1111-1111-111111111111" && e?.createdAt == expectedCreated &&
                         e?.paymentChannel == .qrPayment
                actual = "added=\(summary.expensesAdded)/\(summary.profilesAdded)/\(summary.methodsAdded) createdAtKept=\(e?.createdAt == expectedCreated)"
            }
            record("Version 1 backup file still restores", passed, expected: "1 expense, 1 person, 1 method; id and createdAt kept", actual: actual)
        }

        // 11. Backup round trip keeps fields that the old backup format dropped.
        do {
            var passed = false
            var actual = "no context"
            if let source = inMemoryContext(), let target = inMemoryContext() {
                let original = Expense(amount: 42.9, merchant: "MYDIN", imageRelativePath: "receipts/mydin.jpg", confidence: 0.91,
                                       externalTransactionId: "EXT-1", matchingConfidence: 0.7)
                source.insert(original)
                try? source.save()
                let payload = UserDataBackupService.BackupPayload(expenses: [UserDataBackupService.ExpenseDTO(from: original)], paybookProfiles: [])
                if let data = try? UserDataBackupService.makeEncoder().encode(payload),
                   let decoded = try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: data) {
                    UserDataBackupService.applyBackupPayload(decoded, into: target)
                    let e = (try? target.fetch(FetchDescriptor<Expense>()))?.first
                    passed = e?.id == original.id && e?.imageRelativePath == "receipts/mydin.jpg" && e?.confidence == 0.91 &&
                             e?.externalTransactionId == "EXT-1" && e?.matchingConfidence == 0.7
                    actual = "id=\(e?.id == original.id) image=\(e?.imageRelativePath ?? "nil") ext=\(e?.externalTransactionId ?? "nil")"
                }
            }
            record("Backup round trip keeps receipt path and match data", passed, expected: "all fields preserved", actual: actual)
        }

        // 12. Import identity: same id updates, new id is imported even if it looks like a duplicate.
        do {
            var passed = false
            var actual = "no context"
            if let ctx = inMemoryContext() {
                let day = Date()
                let existing = Expense(amount: 10, merchant: "Mamak", date: day, transactionReference: "REF-1", updatedAt: day.addingTimeInterval(-3600))
                ctx.insert(existing)
                try? ctx.save()

                let changed = UserDataBackupService.ExpenseDTO(id: existing.id, amount: 12, merchant: "Mamak", categoryRaw: existing.categoryRaw,
                                                               paymentSourceRaw: existing.paymentSourceRaw, date: day, transactionReference: "REF-1",
                                                               createdAt: existing.createdAt)
                let lookalike = UserDataBackupService.ExpenseDTO(id: UUID(), amount: 10, merchant: "Mamak", categoryRaw: "Food",
                                                                 paymentSourceRaw: "Cash", date: day, transactionReference: "REF-1")
                let summary = UserDataBackupService.applyBackupPayload(
                    UserDataBackupService.BackupPayload(expenses: [changed, lookalike], paybookProfiles: []), into: ctx)
                let total = count(Expense.self, in: ctx)
                passed = summary.expensesUpdated == 1 && summary.expensesAdded == 1 && summary.possibleDuplicateExpenses == 1 &&
                         total == 2 && existing.amount == 12
                actual = "updated=\(summary.expensesUpdated) added=\(summary.expensesAdded) flagged=\(summary.possibleDuplicateExpenses) total=\(total) amount=\(existing.amount)"
            }
            record("Import matches by id and never skips new records", passed,
                   expected: "updated=1 added=1 flagged=1 total=2 amount=12", actual: actual)
        }

        // 13. A newer record on the device is not overwritten by an older backup.
        do {
            var passed = false
            var actual = "no context"
            if let ctx = inMemoryContext() {
                let now = Date()
                let local = Expense(amount: 20, merchant: "Grab", updatedAt: now)
                ctx.insert(local)
                try? ctx.save()
                var old = UserDataBackupService.ExpenseDTO(id: local.id, amount: 15, merchant: "Grab", categoryRaw: "Transport",
                                                           paymentSourceRaw: "Cash", date: local.date, createdAt: local.createdAt)
                old.updatedAt = now.addingTimeInterval(-86_400)
                let summary = UserDataBackupService.applyBackupPayload(
                    UserDataBackupService.BackupPayload(expenses: [old], paybookProfiles: []), into: ctx)
                passed = summary.expensesKeptNewer == 1 && local.amount == 20
                actual = "keptNewer=\(summary.expensesKeptNewer) amount=\(local.amount)"
            }
            record("Newer device record is kept over older backup", passed, expected: "keptNewer=1 amount=20", actual: actual)
        }

        // 14. People are never merged by name; same id updates the person and their payment methods.
        do {
            var passed = false
            var actual = "no context"
            if let ctx = inMemoryContext() {
                let bijoy = PayBookProfile(name: "Bijoy", updatedAt: Date().addingTimeInterval(-3600))
                ctx.insert(bijoy)
                let method = PayBookPaymentMethod(provider: "Maybank", accountIdentifier: "111", label: "Old", updatedAt: Date().addingTimeInterval(-3600), profile: bijoy)
                ctx.insert(method)
                bijoy.paymentMethods.append(method)
                try? ctx.save()

                let otherBijoy = UserDataBackupService.PayBookProfileDTO(id: UUID(), name: "Bijoy", paymentMethods: [])
                let sameBijoy = UserDataBackupService.PayBookProfileDTO(
                    id: bijoy.id, name: "Bijoy K",
                    paymentMethods: [UserDataBackupService.PayBookMethodDTO(id: method.id, paymentTypeRaw: "Bank Account", provider: "Maybank",
                                                                            accountIdentifier: "111", label: "Main")])
                let summary = UserDataBackupService.applyBackupPayload(
                    UserDataBackupService.BackupPayload(expenses: [], paybookProfiles: [otherBijoy, sameBijoy]), into: ctx)
                let profiles = count(PayBookProfile.self, in: ctx)
                let methods = count(PayBookPaymentMethod.self, in: ctx)
                passed = profiles == 2 && summary.profilesAdded == 1 && summary.profilesUpdated == 1 && summary.profilesSharingName == 1 &&
                         bijoy.name == "Bijoy K" && methods == 1 && method.label == "Main"
                actual = "profiles=\(profiles) added=\(summary.profilesAdded) updated=\(summary.profilesUpdated) sameName=\(summary.profilesSharingName) name=\(bijoy.name) methods=\(methods) label=\(method.label ?? "nil")"
            }
            record("People are matched by id, never merged by name", passed,
                   expected: "2 people, 1 added, 1 updated, 1 flagged same name, method updated not duplicated", actual: actual)
        }

        return results
    }
}
