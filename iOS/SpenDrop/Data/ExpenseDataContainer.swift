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
        Schema(versionedSchema: SpenDropSchemaV6.self)
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
            let result = openStoreSafely(storeURL: groupConfig.url, configuration: groupConfig, defaults: safetyDefaults)
            storeStatus = result.status
            return result.container
        }

        // 2. No App Group available on this device: standard sandbox store
        print("[ExpenseDataContainer] App Group unavailable. Using standard sandbox store...")
        let standardConfig = ModelConfiguration(schema: schema)
        let result = openStoreSafely(storeURL: standardConfig.url, configuration: standardConfig, defaults: safetyDefaults)
        storeStatus = result.status
        return result.container
    }

    /// Opens the on-disk store without ever deleting it.
    /// - Takes a pre-upgrade copy of the store files when the schema changed since the last successful open.
    /// - On failure the store files are left exactly where they are and an in-memory container is returned
    ///   in safe mode, so the app can still launch without touching the user's data.
    static func openStoreSafely(storeURL: URL, configuration: ModelConfiguration, defaults: UserDefaults) -> (container: ModelContainer, status: StoreStatus) {
        let fingerprint = schemaFingerprint(currentSchema)
        snapshotStoreIfSchemaChanged(storeURL: storeURL, fingerprint: fingerprint, defaults: defaults)

        do {
            let container = try openPersistentContainer(configuration: configuration)
            defaults.set(fingerprint, forKey: schemaFingerprintKey)
            print("[ExpenseDataContainer] Opened store at \(storeURL.path)")
            return (container, .persistent(storeURL: storeURL))
        } catch {
            print("[ExpenseDataContainer] CRITICAL: Could not open store at \(storeURL.path): \(error). The store was left untouched. Starting in safe mode.")
            let reason = String(describing: error)
            return (makeInMemoryContainer(), .safeMode(reason: reason, storeURL: storeURL))
        }
    }

    static func openPersistentContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: currentSchema, migrationPlan: SpenDropMigrationPlan.self, configurations: [configuration])
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let inMemoryConfig = ModelConfiguration(schema: currentSchema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: currentSchema, configurations: [inMemoryConfig])
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }

    // MARK: - Pre-Upgrade Snapshots

    /// Stable description of every entity, attribute and relationship in the schema.
    /// Any model change produces a different fingerprint, which triggers a pre-upgrade snapshot.
    static func schemaFingerprint(_ schema: Schema) -> String {
        schema.entities
            .sorted { $0.name < $1.name }
            .map { entity in
                let attributes = entity.attributes.map { "\($0.name):\(String(describing: $0.valueType))" }.sorted()
                let relationships = entity.relationships.map { "\($0.name)->\($0.destination)" }.sorted()
                return "\(entity.name){\(attributes.joined(separator: ","))|\(relationships.joined(separator: ","))}"
            }
            .joined(separator: ";")
    }

    static func safetyDirectory(forStoreAt storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("SpenDropSafety", isDirectory: true)
    }

    /// Copies the store files into `SpenDropSafety/pre-upgrade-<timestamp>/` when the schema differs from the
    /// one that last opened this store (including the first launch with this safety code). Returns the copy's folder.
    @discardableResult
    static func snapshotStoreIfSchemaChanged(storeURL: URL, fingerprint: String, defaults: UserDefaults, now: Date = Date()) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }
        // Copy when the recorded fingerprint differs OR the store file itself does not match the current model.
        // The second check does not depend on UserDefaults, which can be out of sync with the store
        // (e.g. after a store file was restored from a copy).
        let fingerprintChanged = defaults.string(forKey: schemaFingerprintKey) != fingerprint
        guard fingerprintChanged || !storeMatchesCurrentModel(storeURL: storeURL) else { return nil }

        let safetyDir = safetyDirectory(forStoreAt: storeURL)
        let snapshotDir = safetyDir.appendingPathComponent("pre-upgrade-\(timestampString(now))", isDirectory: true)
        do {
            try copyStoreFiles(from: storeURL, into: snapshotDir)
            print("[ExpenseDataContainer] Saved pre-upgrade copy of the store to \(snapshotDir.path)")
        } catch {
            print("[ExpenseDataContainer] WARNING: Could not save pre-upgrade copy of the store: \(error)")
            return nil
        }
        pruneDirectories(in: safetyDir, prefix: "pre-upgrade-", keep: maxPreUpgradeSnapshots)
        return snapshotDir
    }

    /// Reads the store's own metadata and checks it against the current model without opening the store.
    /// Returns false when the store would need a migration (or its metadata cannot be read).
    static func storeMatchesCurrentModel(storeURL: URL) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL),
              let model = NSManagedObjectModel.makeManagedObjectModel(for: SpenDropSchemaV6.models) else {
            return false
        }
        return model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }

    /// Moves the store files that failed to open into `SpenDropSafety/failed-open-<timestamp>/`.
    /// Only called when the user explicitly chooses to restore from backup. The files are kept, never deleted.
    @discardableResult
    public static func moveUnopenableStoreAside() throws -> URL {
        guard case .safeMode(_, let storeURL?) = storeStatus else {
            throw NSError(domain: "SpenDropStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "The database is not in safe mode."])
        }
        let destination = safetyDirectory(forStoreAt: storeURL)
            .appendingPathComponent("failed-open-\(timestampString(Date()))", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for suffix in storeFileSuffixes {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.moveItem(at: src, to: destination.appendingPathComponent(src.lastPathComponent))
            }
        }
        // Also move SwiftData's external-storage folder so the next launch starts clean.
        let supportDir = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".\(storeURL.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        if fm.fileExists(atPath: supportDir.path) {
            try fm.moveItem(at: supportDir, to: destination.appendingPathComponent(supportDir.lastPathComponent))
        }
        print("[ExpenseDataContainer] Moved unopenable store to \(destination.path)")
        return destination
    }

    private static func copyStoreFiles(from storeURL: URL, into directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in storeFileSuffixes {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: directory.appendingPathComponent(src.lastPathComponent))
            }
        }
    }

    private static func pruneDirectories(in parent: URL, prefix: String, keep: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: parent.path) else { return }
        let matching = items.filter { $0.hasPrefix(prefix) }.sorted()   // timestamps sort chronologically
        for name in matching.dropLast(keep) {
            try? fm.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    static func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    public static let shared: ModelContainer = createContainer()

    public static let previewContainer: ModelContainer = {
        let configuration = ModelConfiguration(schema: currentSchema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: currentSchema, configurations: [configuration])
            UserDataBackupService.restoreAccountData(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

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
