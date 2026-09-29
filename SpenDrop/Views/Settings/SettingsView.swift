import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    @Query private var allProfiles: [PayBookProfile]

    @AppStorage("app_currency") private var selectedCurrency = "RM"
    @AppStorage("user_appearance") private var selectedAppearance = "system"

    @State private var showingClearConfirmation = false
    @State private var showingSampleDataLoadedAlert = false
    @State private var showingSelfTestSheet = false

    // Backup & Restore state
    @State private var showingRestoreConfirmation = false
    @State private var showingRestoreSuccessAlert = false
    @State private var restoreSummaryMessage = ""
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
            // USER ACCOUNT
            Section(header: Text("Account")) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)

                        Text("TR")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(UserDataBackupService.defaultAccountName)
                                .font(.headline)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }

                        Text(UserDataBackupService.defaultAccountEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

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

                // Restore Verified Screenshots & PayBook
                Button(action: {
                    showingRestoreConfirmation = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Screenshot Data & PayBook")
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Restores all receipts and bank accounts from submitted screenshots")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

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

            // TESTING & DIAGNOSTICS
            Section(header: Text("Testing & Diagnostics")) {
                Button(action: {
                    SampleData.seed(into: modelContext)
                    HapticFeedback.notification(.success)
                    showingSampleDataLoadedAlert = true
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .foregroundStyle(.blue)
                        Text("Load Sample Transactions")
                            .foregroundStyle(.primary)
                    }
                }

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
        .alert("Sample Data Loaded", isPresented: $showingSampleDataLoadedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sample Malaysian expenses have been added to your dashboard and history.")
        }
        .alert("Restore User Data?", isPresented: $showingRestoreConfirmation) {
            Button("Restore Everything", role: .none) {
                performRestore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all verified receipts, screenshot transactions, and PayBook accounts to your SpenDrop account.")
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

    private func performRestore() {
        let result = UserDataBackupService.restoreAccountData(into: modelContext, force: true)
        HapticFeedback.notification(.success)
        restoreSummaryMessage = "Restored \(result.expensesCount) transactions and \(result.profilesCount) PayBook profiles from your submitted screenshots."
        showingRestoreSuccessAlert = true
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
