import SwiftUI
import SwiftData

@main
struct SpenDropApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSafeModeAlert = false
    @State private var safeModeFollowUpMessage: String?

    init() {
        print("[SPENDROP_BOOT] SpenDropApp.init started")
        fflush(stdout)

        // The daily cloud backup's background task must be registered before launch finishes.
        SystemBackupTaskScheduler.register()

        NSSetUncaughtExceptionHandler { exception in
            print("[SPENDROP_CRASH] Uncaught Exception: \(exception)")
            print("[SPENDROP_CRASH] Reason: \(exception.reason ?? "none")")
            print("[SPENDROP_CRASH] Stack: \(exception.callStackSymbols)")
            fflush(stdout)
        }

        signal(SIGABRT) { sig in
            print("[SPENDROP_CRASH] Signal SIGABRT: \(sig)")
            fflush(stdout)
            exit(1)
        }

        // In-app test suites (each runs on in-memory stores or temporary folders only), e.g. --run-all-tests
        if let exitCode = AllTestSuites.runFromLaunchArguments(ProcessInfo.processInfo.arguments) {
            exit(exitCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                // Email confirmation and password-reset links (spendrop://auth-callback).
                .modifier(AuthLinkHandling())
                .task {
                    showingSafeModeAlert = !ExpenseDataContainer.isPersistentStoreHealthy
                    UserDataBackupService.startAutomaticBackups(for: ExpenseDataContainer.shared)
                    // Optional cloud backup (only when configured and signed in; never blocks local use).
                    CloudBackupService.shared.startAutomaticBackups()
                    Task { await AuthService.shared.refreshSessionIfNeeded() }

                    // Safe, non-blocking initial data setup on scene presentation
                    ExpenseDataContainer.migrateLegacyContactsIfNeeded(into: ExpenseDataContainer.shared.mainContext)
                    ExpenseDataContainer.handlePayBookLaunchArguments(context: ExpenseDataContainer.shared.mainContext)

                    // Link expenses saved since the last launch (manual, scan, Share Extension) to their Account.
                    if ExpenseDataContainer.isPersistentStoreHealthy {
                        let context = ExpenseDataContainer.shared.mainContext
                        let linked = AccountLinker.linkUnlinkedExpenses(in: context)
                        if linked.expensesLinked > 0 { try? context.save() }
                    }

                    if ProcessInfo.processInfo.arguments.contains("--restore-user-data") {
                        UserDataBackupService.restoreAccountData(into: ExpenseDataContainer.shared.mainContext, force: true)
                    }

                    if ProcessInfo.processInfo.arguments.contains("--run-image-diagnostics") {
                        let reports = await ImagePipelineDiagnostics.runAllTests()
                        for report in reports {
                            print("\n--- REPORT FOR \(report.formatName) ---")
                            print("Data Load:        \(report.dataLoad.passed ? "PASS" : "FAIL") (\(report.dataLoad.detail))")
                            print("UIImage Decode:   \(report.uiImageDecode.passed ? "PASS" : "FAIL") (\(report.uiImageDecode.detail))")
                            print("CGImage Decode:   \(report.cgImageDecode.passed ? "PASS" : "FAIL") (\(report.cgImageDecode.detail))")
                            print("Downsampling:     \(report.downsampling.passed ? "PASS" : "FAIL") (\(report.downsampling.detail))")
                            print("Temp Storage:     \(report.tempStorage.passed ? "PASS" : "FAIL") (\(report.tempStorage.detail))")
                            print("App Group Store:  \(report.appGroupStorage.passed ? "PASS" : "FAIL") (\(report.appGroupStorage.detail))")
                            print("Vision OCR:       \(report.visionOCR.passed ? "PASS" : "FAIL") (\(report.visionOCR.detail))")
                            print("Parser:           \(report.parser.passed ? "PASS" : "FAIL") (\(report.parser.detail))")
                        }
                        print("\n[SpenDrop][DIAGNOSTIC_COMPLETE] All diagnostic tests finished")
                        fflush(stdout)
                    }

                    if ProcessInfo.processInfo.arguments.contains("--read-share-logs") {
                        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ExpenseDataContainer.appGroupIdentifier) {
                            let logURL = containerURL.appendingPathComponent("share_extension_diagnostics.log")
                            if let content = try? String(contentsOf: logURL, encoding: .utf8) {
                                print("\n=== SHARE EXTENSION DIAGNOSTIC LOGS ===")
                                print(content)
                                print("=== END SHARE EXTENSION LOGS ===\n")
                            } else {
                                print("\n[SpenDropApp] No share_extension_diagnostics.log found yet in App Group container.")
                            }
                        }
                        fflush(stdout)
                    }
                }
                .alert("SpenDrop Couldn't Open Your Data", isPresented: $showingSafeModeAlert) {
                    Button("Keep Data As Is", role: .cancel) {}
                    Button("Move Aside & Use Backup") {
                        do {
                            let folder = try ExpenseDataContainer.moveUnopenableStoreAside()
                            safeModeFollowUpMessage = "Your old database was moved (not deleted) to \(folder.lastPathComponent). Close SpenDrop completely and open it again to restore from your latest backup."
                        } catch {
                            safeModeFollowUpMessage = "Nothing was changed. \(error.localizedDescription)"
                        }
                    }
                } message: {
                    Text("Nothing has been deleted. Your database was left untouched on this device. SpenDrop is running in safe mode, so changes you make now will not be saved.")
                }
                .alert("Safe Mode", isPresented: Binding(
                    get: { safeModeFollowUpMessage != nil },
                    set: { if !$0 { safeModeFollowUpMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(safeModeFollowUpMessage ?? "")
                }
        }
        .modelContainer(ExpenseDataContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            let context = ExpenseDataContainer.shared.mainContext
            switch newPhase {
            case .background:
                // Flush pending autosave changes, then back up immediately before the app is suspended.
                if context.hasChanges { try? context.save() }
                UserDataBackupService.saveAutoBackup(from: context)
                // Never starts a cloud backup (backup is opt-in). If one the user or the daily schedule started
                // is still running, give it time to finish instead of being cut off.
                if CloudBackupService.shared.isBackupRunning {
                    let task = UIApplication.shared.beginBackgroundTask(withName: "SpenDropCloudBackup")
                    Task { @MainActor in
                        while CloudBackupService.shared.isBackupRunning { try? await Task.sleep(for: .milliseconds(500)) }
                        UIApplication.shared.endBackgroundTask(task)
                    }
                }
            case .active:
                // Picks up anything the Share Extension saved while the app was not running.
                UserDataBackupService.scheduleAutoBackup(from: context)
                // iOS doesn't guarantee when background work runs: catch up on today's daily cloud backup if it
                // is on, its time has passed and it hasn't succeeded yet today (does nothing otherwise).
                Task { await CloudBackupService.shared.runAutomaticBackupIfDue() }
            default:
                break
            }
        }
    }
}
