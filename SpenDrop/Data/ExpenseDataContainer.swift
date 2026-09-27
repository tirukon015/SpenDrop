import Foundation
import SwiftData

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

    private static func createContainer() -> ModelContainer {
        let fm = FileManager.default
        let schema = Schema([
            Expense.self,
            PayBookProfile.self,
            PayBookPaymentMethod.self,
            PayBookContact.self
        ])

        // 1. Check if App Group is actually accessible on this device
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
            SampleData.seed(into: container.mainContext)
            seedSamplePayBookContacts(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

    public static func seedInitialDataIfNeeded() {
        let context = ExpenseDataContainer.shared.mainContext
        let defaults = UserDefaults.standard

        // Seed Paybook if empty
        var profileDescriptor = FetchDescriptor<PayBookProfile>()
        profileDescriptor.fetchLimit = 1
        let profileCount = (try? context.fetchCount(profileDescriptor)) ?? 0
        if profileCount == 0 {
            seedSamplePayBookContacts(into: context)
        }

        // Seed Expenses if empty
        let seededKey = "has_seeded_initial_sample_data_v1"
        if !defaults.bool(forKey: seededKey) {
            var descriptor = FetchDescriptor<Expense>()
            descriptor.fetchLimit = 1
            let count = (try? context.fetchCount(descriptor)) ?? 0
            if count == 0 {
                SampleData.seed(into: context)
            }
            defaults.set(true, forKey: seededKey)
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
