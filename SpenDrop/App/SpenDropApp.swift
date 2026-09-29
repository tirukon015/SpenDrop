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
                .task {
                    showingSafeModeAlert = !ExpenseDataContainer.isPersistentStoreHealthy
                    UserDataBackupService.startAutomaticBackups(for: ExpenseDataContainer.shared)
                    // Optional cloud backup (only when configured and signed in; never blocks local use).
                    CloudBackupService.shared.startAutomaticBackups()

                    // Safe, non-blocking initial data setup on scene presentation
                    ExpenseDataContainer.migrateLegacyContactsIfNeeded(into: ExpenseDataContainer.shared.mainContext)
                    ExpenseDataContainer.seedInitialDataIfNeeded()
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
        }
        .modelContainer(ExpenseDataContainer.shared)
    }
}
