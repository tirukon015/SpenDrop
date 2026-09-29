import CoreData
import Foundation
import SwiftData

// Schema versions and the migration plan live in SchemaVersions.swift.

@MainActor
public final class ExpenseDataContainer {
    public static let appGroupIdentifier = "group.com.spendrop.shared"
    private static let legacyAppGroupIdentifier = "group.com.spenddrop.shared"

    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard let legacyURL = fm.containerURL(forSecurityApplicationGroupIdentifier: legacyAppGroupIdentifier),
              let newURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        let legacyAppSupport = legacyURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        let newAppSupport = newURL.appendingPathComponent("Library/Application Support", isDirectory: true)

        let legacyStore = legacyAppSupport.appendingPathComponent("default.store")
        let newStore = newAppSupport.appendingPathComponent("default.store")

        guard fm.fileExists(atPath: legacyStore.path) && !fm.fileExists(atPath: newStore.path) else {
            return
        }

        try? fm.createDirectory(at: newAppSupport, withIntermediateDirectories: true)
        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        for file in storeFiles {
            let src = legacyAppSupport.appendingPathComponent(file)
            let dst = newAppSupport.appendingPathComponent(file)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: - Store Status

    /// Whether SpenDrop is running on the user's real database or in safe mode.
    public enum StoreStatus: Equatable {
        /// The on-disk database opened normally.
        case persistent(storeURL: URL)
        /// The on-disk database could not be opened. It was left untouched on disk and the app
        /// is running on a temporary in-memory store; nothing written now is saved.
        case safeMode(reason: String, storeURL: URL?)
    }

    public private(set) static var storeStatus: StoreStatus = .safeMode(reason: "Not opened yet", storeURL: nil)

    /// True only when changes are being written to the user's on-disk database.
    public static var isPersistentStoreHealthy: Bool {
        if case .persistent = storeStatus { return true }
        return false
    }

    /// True when the on-disk database exists but could not be opened (the app is in safe mode).
    public static var didFailToOpenStore: Bool {
        if case .safeMode(_, .some) = storeStatus { return true }
        return false
    }

    public static var currentSchema: Schema {
        Schema(versionedSchema: SpenDropSchemaV3.self)
    }

    private static let schemaFingerprintKey = "SpenDrop.lastOpenedSchemaFingerprint"
    private static let storeFileSuffixes = ["", "-shm", "-wal"]
    private static let maxPreUpgradeSnapshots = 3

    private static var safetyDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    // MARK: - Container Creation

    /// UI tests launch the app with `--ui-testing`: a fresh temporary database each launch, no seeding, no
    /// backup files written. The user's database and backups are never touched in this mode.
    public static let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    private static func createContainer() -> ModelContainer {
        let fm = FileManager.default
        let schema = currentSchema

        if isUITesting {
            let dir = fm.temporaryDirectory.appendingPathComponent("SpenDropUITestStore", isDirectory: true)
            try? fm.removeItem(at: dir)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("default.store"))
            if let container = try? openPersistentContainer(configuration: config) {
                storeStatus = .persistent(storeURL: config.url)
                return container
            }
        }

        // 1. App Group store (shared with the Share Extension)
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let appSupport = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

            migrateLegacyStoreIfNeeded()

            let groupConfig = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupIdentifier))
            do {
                let container = try ModelContainer(for: schema, configurations: [groupConfig])
                print("[ExpenseDataContainer] Successfully initialized App Group container.")
                return container
            } catch {
                print("[ExpenseDataContainer] Failed to initialize App Group container: \(error). Attempting recovery...")
                // If the app group store is corrupted, clean up and retry
                let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
                for f in storeFiles {
                    try? fm.removeItem(at: appSupport.appendingPathComponent(f))
                }

                if let recoveredContainer = try? ModelContainer(for: schema, configurations: [groupConfig]) {
                    print("[ExpenseDataContainer] Recovered App Group container after clearing corrupt store.")
                    return recoveredContainer
                }
            }
        }

        // 2. Fall back to standard sandbox store in Application Support
        print("[ExpenseDataContainer] Falling back to standard sandbox store...")
        let standardConfig = ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [standardConfig])
            print("[ExpenseDataContainer] Successfully initialized standard sandbox container.")
            return container
        } catch {
            print("[ExpenseDataContainer] Standard container failed: \(error). Attempting sandbox store recovery...")
            if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
                for f in storeFiles {
                    try? fm.removeItem(at: appSupportURL.appendingPathComponent(f))
                }
            }
            if let recovered = try? ModelContainer(for: schema, configurations: [standardConfig]) {
                print("[ExpenseDataContainer] Recovered standard container after clearing corrupt store.")
                return recovered
            }
        }

        // 3. In-memory fallback: guarantees the app NEVER crashes with a black screen on launch
        print("[ExpenseDataContainer] CRITICAL: Persisted stores failed. Initializing in-memory container.")
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let inMemoryContainer = try? ModelContainer(for: schema, configurations: [inMemoryConfig]) {
            return inMemoryContainer
        }

        // 4. Absolute fallback
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }

    public static let shared: ModelContainer = createContainer()

    public static let previewContainer: ModelContainer = {
        let schema = Schema([Expense.self, PayBookProfile.self, PayBookPaymentMethod.self, PayBookContact.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            UserDataBackupService.restoreAccountData(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

    public static func seedInitialDataIfNeeded() {
        let context = ExpenseDataContainer.shared.mainContext

        // 1. Ensure Paybook profiles exist
        var profileDescriptor = FetchDescriptor<PayBookProfile>()
        profileDescriptor.fetchLimit = 1
        let profileCount = (try? context.fetchCount(profileDescriptor)) ?? 0

        // 2. Ensure Expenses exist
        var descriptor = FetchDescriptor<Expense>()
        descriptor.fetchLimit = 1
        let expenseCount = (try? context.fetchCount(descriptor)) ?? 0

        if expenseCount == 0 || profileCount == 0 {
            print("[ExpenseDataContainer] Database needs rehydration (expenses: \(expenseCount), profiles: \(profileCount)). Restoring user account & screenshot data...")
            UserDataBackupService.restoreFromAutoBackupIfNeeded(into: context)
        }
    }

    /// Migrates any legacy PayBookContact records to PayBookProfile + PayBookPaymentMethod
    public static func migrateLegacyContactsIfNeeded(into context: ModelContext) {
        let desc = FetchDescriptor<PayBookContact>()
        guard let legacyContacts = try? context.fetch(desc), !legacyContacts.isEmpty else { return }

        let existingProfiles = (try? context.fetch(FetchDescriptor<PayBookProfile>())) ?? []
        var profilesByName: [String: PayBookProfile] = [:]
        for prof in existingProfiles {
            profilesByName[prof.name.lowercased()] = prof
        }

        for contact in legacyContacts {
            let trimmedName = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                context.delete(contact)
                continue
            }

            // Find existing profile with the same name or create a new one
            let profile: PayBookProfile
            if let found = profilesByName[trimmedName.lowercased()] {
                profile = found
            } else {
                let newProf = PayBookProfile(name: trimmedName)
                context.insert(newProf)
                profilesByName[trimmedName.lowercased()] = newProf
                profile = newProf
            }

            let method = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: contact.bankName,
                accountIdentifier: contact.accountNumber,
                notes: contact.phoneNumber,
                profile: profile
            )
            context.insert(method)
            profile.paymentMethods.append(method)

            context.delete(contact)
        }

        try? context.save()
    }

    public static func handlePayBookLaunchArguments(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--clear-paybook") {
            let desc = FetchDescriptor<PayBookProfile>()
            if let items = try? context.fetch(desc) {
                for item in items { context.delete(item) }
                try? context.save()
            }
        }
        if args.contains("--seed-paybook") {
            let desc = FetchDescriptor<PayBookProfile>()
            let count = (try? context.fetchCount(desc)) ?? 0
            if count == 0 {
                seedSamplePayBookContacts(into: context)
            }
        }
    }

    public static func seedSamplePayBookContacts(into context: ModelContext) {
        let rahim = PayBookProfile(
            name: "Rahim",
            notes: "Frequent contractor & utility transfers"
        )
        context.insert(rahim)

        let rahimMaybank = PayBookPaymentMethod(
            paymentType: .bankAccount,
            provider: "Maybank",
            accountIdentifier: "1234567890",
            label: "Personal",
            notes: "Abdul Rahim Bin Osman",
            profile: rahim
        )
        let rahimCimb = PayBookPaymentMethod(
            paymentType: .bankAccount,
            provider: "CIMB Bank",
            accountIdentifier: "9876543210",
            label: "Business",
            profile: rahim
        )
        let rahimTng = PayBookPaymentMethod(
            paymentType: .eWallet,
            provider: "Touch 'n Go",
            accountIdentifier: "0123456789",
            profile: rahim
        )
        rahim.paymentMethods.append(contentsOf: [rahimMaybank, rahimCimb, rahimTng])

        let karim = PayBookProfile(
            name: "Karim",
            notes: "Family transfer"
        )
        context.insert(karim)

        let karimMaybank = PayBookPaymentMethod(
            paymentType: .bankAccount,
            provider: "Maybank",
            accountIdentifier: "999999999",
            label: "Main Account",
            profile: karim
        )
        let karimAffin = PayBookPaymentMethod(
            paymentType: .bankAccount,
            provider: "Affin Bank",
            accountIdentifier: "555566667777",
            profile: karim
        )
        karim.paymentMethods.append(contentsOf: [karimMaybank, karimAffin])

        let siti = PayBookProfile(
            name: "Siti Nurhaliza",
            notes: "Siti Nurhaliza Binti Tarudin"
        )
        context.insert(siti)

        let sitiRhb = PayBookPaymentMethod(
            paymentType: .bankAccount,
            provider: "RHB Bank",
            accountIdentifier: "21415600192837",
            profile: siti
        )
        let sitiDuitNow = PayBookPaymentMethod(
            paymentType: .paymentId,
            provider: "DuitNow",
            accountIdentifier: "siti@email.com",
            profile: siti
        )
        siti.paymentMethods.append(contentsOf: [sitiRhb, sitiDuitNow])

        try? context.save()
    }
}
