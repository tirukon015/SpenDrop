import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    @Query private var allProfiles: [PayBookProfile]

    @AppStorage("app_currency") private var selectedCurrency = "RM"
    @AppStorage("user_appearance") private var selectedAppearance = "system"
    @AppStorage(AskSpenDropSettings.floatingAssistantKey) private var floatingAssistant = true
    @AppStorage(AskSpenDropSettings.showMyNameKey) private var showMyName = true

    @State private var showingClearConfirmation = false
    @State private var showingSampleDataLoadedAlert = false
    @State private var showingLoadSampleConfirmation = false
    @State private var showingRemoveSampleConfirmation = false
    @State private var showingSampleRemovedAlert = false
    @State private var sampleRemovalMessage = ""

    /// Re-evaluated when sample records change.
    @Query private var sampleRecords: [SampleDataRecord]
    private var sampleDataLoaded: Bool {
        !sampleRecords.isEmpty || allExpenses.contains(where: \.isSampleData)
    }
    @State private var showingSelfTestSheet = false

    // Backup & Restore state
    @State private var localRestoreBackup: LocalRestoreBackup?
    @State private var showingRestoreSuccessAlert = false
    @State private var restoreSummaryMessage = ""
    @State private var screenshotStats: (count: Int, totalBytes: Int64) = (0, 0)
    @State private var showingOptimizeScreenshotsConfirmation = false
    @State private var showingOptimizeScreenshotsResult = false
    @State private var optimizeScreenshotsMessage = ""
    @State private var showingFileImporter = false
    @State private var importErrorMessage: String?
    @State private var showingImportError = false
    @State private var exportBackupURL: URL?
    @State private var showingExportShareSheet = false

    public init() {}

    private let currencyOptions = ["RM", "SGD", "USD", "EUR", "GBP"]
    private let appearanceOptions = [
        ("system", "System"),
        ("light", "Light"),
        ("dark", "Dark")
    ]

    public var body: some View {
        Form {
            // BACKUP & RESTORE
            Section(header: Text("Backup & Data Recovery")) {
                HStack {
                    Text("Stored Transactions")
                    Spacer()
                    Text("\(allExpenses.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("PayBook Profiles")
                    Spacer()
                    Text("\(allProfiles.count)")
                        .foregroundStyle(.secondary)
                }

                // Restore from the newest local auto-backup (explicit action only; never automatic)
                Button(action: {
                    prepareLocalRestore()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore from Local Backup")
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Merges your newest automatic backup on this iPhone. Nothing is deleted.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("settings.restoreLocal")

                // Export Backup JSON
                Button(action: {
                    exportBackup()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Backup (JSON)")
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Save or share complete backup file to Files, iCloud, or AirDrop")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Import Backup JSON
                Button(action: {
                    showingFileImporter = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Backup File (JSON)")
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Restore transactions and PayBook from a saved JSON file")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.green)
                    Text("Persistent Auto-Backup")
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            // PREFERENCES
            Section(header: Text("Preferences")) {
                Picker("Default Currency", selection: $selectedCurrency) {
                    ForEach(currencyOptions, id: \.self) { curr in
                        Text(curr).tag(curr)
                    }
                }

                Picker("Appearance", selection: $selectedAppearance) {
                    ForEach(appearanceOptions, id: \.0) { key, label in
                        Text(label).tag(key)
                    }
                }
            }

            // SPENDROP AI
            Section(header: Text("SpenDrop AI")) {
                Button {
                    AskSpenDropPresenter.shared.open()
                } label: {
                    Label {
                        Text("Ask SpenDrop")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image("SpenDropRobot")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
                .accessibilityIdentifier("settings.askSpenDrop")

                Toggle("Floating AI Assistant", isOn: $floatingAssistant)
                    .accessibilityIdentifier("settings.ai.floatingAssistant")
            }
            Section(footer: Text("Only changes what SpenDrop AI shows on screen. It doesn't affect your sign-in or your data.")) {
                Toggle("Show My Name", isOn: $showMyName)
                    .accessibilityIdentifier("settings.ai.showMyName")
            }

            // SCREENSHOT STORAGE
            Section(header: Text("Screenshot Storage"),
                    footer: Text("New screenshots are saved small (about 80–150 KB) and stay readable. Optimizing older ones keeps each original until its smaller copy is saved and checked.")) {
                HStack {
                    Text("Screenshots")
                    Spacer()
                    Text("\(screenshotStats.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total size")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: screenshotStats.totalBytes, countStyle: .file)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Average")
                    Spacer()
                    Text(screenshotStats.count == 0 ? "—" : ByteCountFormatter.string(fromByteCount: screenshotStats.totalBytes / Int64(screenshotStats.count), countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                Button(action: {
                    showingOptimizeScreenshotsConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .foregroundStyle(.blue)
                        Text("Optimize Existing Screenshots")
                            .foregroundStyle(.primary)
                    }
                }
                .disabled(screenshotStats.count == 0)
            }

            // SAMPLE DATA (optional demo; a new install starts empty)
            Section(header: Text("Sample Data"), footer: Text("Sample records are kept separate from your own and can be removed at any time without affecting your real data.")) {
                Button(action: {
                    showingLoadSampleConfirmation = true
                }) {
                    HStack {
                        Image(systemName: sampleDataLoaded ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                            .foregroundStyle(sampleDataLoaded ? .green : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sampleDataLoaded ? "Sample Data Loaded" : "Load Sample Data").foregroundStyle(.primary)
                            Text("Explore SpenDrop with example transactions").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(sampleDataLoaded)
                .accessibilityIdentifier("settings.loadSample")

                if sampleDataLoaded {
                    Button(role: .destructive, action: {
                        showingRemoveSampleConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "tray.and.arrow.up.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove Sample Data").foregroundStyle(.red)
                                Text("Remove example transactions and demo data").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.removeSample")
                }
            }

            // TESTING & DIAGNOSTICS
            Section(header: Text("Testing & Diagnostics")) {

                Button(action: {
                    showingSelfTestSheet = true
                }) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Run OCR & Parser Self-Test")
                            .foregroundStyle(.primary)
                    }
                }

                Button(role: .destructive, action: {
                    showingClearConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                        Text("Clear All Expenses")
                            .foregroundStyle(.red)
                    }
                }
            }

            // PRIVACY & SECURITY
            Section(header: Text("Privacy & Security")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text("100% Local-First")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text("SpenDrop never asks for your bank login, passwords, OTPs, or card PINs. All Vision OCR and transaction parsing runs entirely on your device with zero cloud tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // ABOUT
            Section(header: Text("About")) {
                HStack {
                    Text("App Name")
                    Spacer()
                    Text("SpenDrop")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Developer")
                        Spacer()
                        Text("Touhidul Islam Rukon")
                            .foregroundStyle(.secondary)
                    }
                    Text("SpenDrop is designed and built by Touhidul Islam Rukon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 2)

                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.4.0 (Shared Money & Cloud Backup)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Target Device")
                    Spacer()
                    Text("iPhone 17 Pro Max")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Storage Engine")
                    Spacer()
                    Text("Apple SwiftData (Local + Auto-Backup)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("OCR Engine")
                    Spacer()
                    Text("Apple Vision (On-Device)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingSelfTestSheet) {
            ParserSelfTestView()
        }
        .sheet(isPresented: $showingExportShareSheet) {
            if let url = exportBackupURL {
                ShareActivityView(activityItems: [url])
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .task {
            refreshScreenshotStats()
        }
        .alert("Optimize Existing Screenshots?", isPresented: $showingOptimizeScreenshotsConfirmation) {
            Button("Optimize") {
                let report = ScreenshotStorageMigrator.optimizeExisting(in: modelContext)
                refreshScreenshotStats()
                HapticFeedback.notification(.success)
                let saved = ByteCountFormatter.string(fromByteCount: max(0, report.bytesBefore - report.bytesAfter), countStyle: .file)
                optimizeScreenshotsMessage = "Optimized \(report.optimized) screenshots (saved \(saved)). \(report.alreadySmall) were already small."
                    + (report.keptOriginal > 0 ? " \(report.keptOriginal) could not be optimized and were kept as they are." : "")
                    + (report.missing > 0 ? " \(report.missing) screenshot files were already missing." : "")
                showingOptimizeScreenshotsResult = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Large screenshots are replaced by smaller, readable copies. Each original is deleted only after its copy is saved and verified; if anything fails, the original is kept. Transactions are not changed.")
        }
        .alert("Screenshots Optimized", isPresented: $showingOptimizeScreenshotsResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(optimizeScreenshotsMessage)
        }
        .alert("Load Sample Data?", isPresented: $showingLoadSampleConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Load Sample Data") {
                if SampleData.load(into: modelContext) {
                    HapticFeedback.notification(.success)
                    showingSampleDataLoadedAlert = true
                }
            }
        } message: {
            Text("This will add example expenses, people, splits, settlements, and other demonstration data so you can explore how SpenDrop works.")
        }
        .alert("Sample Data Loaded", isPresented: $showingSampleDataLoadedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Example people are marked \"(Sample)\". Use \"Remove Sample Data\" in Settings to take everything out again.")
        }
        .alert("Remove Sample Data?", isPresented: $showingRemoveSampleConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Sample Data", role: .destructive) {
                let result = SampleData.remove(from: modelContext)
                HapticFeedback.notification(.success)
                sampleRemovalMessage = "Removed \(result.expensesRemoved) expenses, \(result.peopleRemoved) people, \(result.movementsRemoved) money records and \(result.settlementsRemoved) settlements."
                    + (result.peopleKept > 0 ? " \(result.peopleKept) sample people were kept because your own records use them." : "")
                    + " Your real data was not affected."
                showingSampleRemovedAlert = true
            }
        } message: {
            Text("This will remove the example data previously added by SpenDrop. Your real transactions and data will not be affected.")
        }
        .alert("Sample Data Removed", isPresented: $showingSampleRemovedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sampleRemovalMessage)
        }
        .sheet(item: $localRestoreBackup) { backup in
            NavigationStack {
                RestoreRangeView(source: localRestoreSource(backup.payload))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { localRestoreBackup = nil }
                        }
                    }
            }
        }
        .alert("Data Restored Successfully", isPresented: $showingRestoreSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreSummaryMessage)
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "An error occurred while importing the backup file.")
        }
        .alert("Clear All Expenses?", isPresented: $showingClearConfirmation) {
            Button("Clear Everything", role: .destructive) {
                clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all \(allExpenses.count) transactions stored on this device.")
        }
    }

    // MARK: - Actions

    private func refreshScreenshotStats() {
        screenshotStats = ImageStorageService.shared.storageStats(relativePaths: allExpenses.compactMap(\.imageRelativePath))
    }

    private func prepareLocalRestore() {
        guard let backup = UserDataBackupService.latestLocalBackup() else {
            importErrorMessage = "No local backup was found on this iPhone. Use \"Import Backup File (JSON)\" to restore from a saved file."
            showingImportError = true
            return
        }
        localRestoreBackup = LocalRestoreBackup(payload: backup)
    }

    /// Same range → preview → confirm → merge flow as the cloud restore, reading the newest local backup.
    private func localRestoreSource(_ payload: UserDataBackupService.BackupPayload) -> RestoreRangeView.Source {
        RestoreRangeView.Source(
            title: "Local Backup",
            createdAt: payload.exportDate,
            detail: "Newest automatic backup on this iPhone",
            load: { payload },
            localIDs: { UserDataBackupService.LocalRecordIDs.fetch(from: modelContext) },
            restore: { plan in
                guard CloudBackupService.writeLocalSafetyBackup(from: modelContext) else {
                    throw NSError(domain: "SpenDropBackup", code: 4, userInfo: [NSLocalizedDescriptionKey:
                        "Couldn't save a safety copy of your current data, so nothing was restored."])
                }
                return try UserDataBackupService.applyRestorePlan(plan, into: modelContext)
            })
    }

    private func exportBackup() {
        if let url = UserDataBackupService.generateExportJSONFile(from: modelContext) {
            exportBackupURL = url
            HapticFeedback.notification(.success)
            showingExportShareSheet = true
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            do {
                let stats = try UserDataBackupService.importFromJSON(at: fileURL, into: modelContext)
                HapticFeedback.notification(.success)
                restoreSummaryMessage = stats.message
                showingRestoreSuccessAlert = true
            } catch {
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showingImportError = true
        }
    }

    private func clearAll() {
        HapticFeedback.notification(.warning)
        for expense in allExpenses {
            modelContext.delete(expense)
        }
        try? modelContext.save()
    }
}

// MARK: - UIKit Activity Share Sheet

struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct LocalRestoreBackup: Identifiable {
    let id = UUID()
    let payload: UserDataBackupService.BackupPayload
}
