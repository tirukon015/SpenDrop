import SwiftUI
import SwiftData

@main
struct SpendDropApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--run-tests") {
            let results = TransactionParserTests.runAllTests()
            for r in results {
                let status = r.passed ? "PASS" : "FAIL"
                print("[TEST] [\(status)] \(r.testName): Expected: \(r.expected) | Actual: \(r.actual)")
            }
            let passedCount = results.filter { $0.passed }.count
            let totalCount = results.count
            print("[TEST_RUN_SUMMARY] \(passedCount)/\(totalCount) PASSED")
            fflush(stdout)
            exit(passedCount == totalCount ? 0 : 1)
        }

        // Idempotent initial seed of dummy data on first launch
        ExpenseDataContainer.seedInitialDataIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
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
                        print("\n[SpendDrop][DIAGNOSTIC_COMPLETE] All diagnostic tests finished")
                        fflush(stdout)
                    }

                    if ProcessInfo.processInfo.arguments.contains("--read-share-logs") {
                        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.spenddrop.shared") {
                            let logURL = containerURL.appendingPathComponent("share_extension_diagnostics.log")
                            if let content = try? String(contentsOf: logURL, encoding: .utf8) {
                                print("\n=== SHARE EXTENSION DIAGNOSTIC LOGS ===")
                                print(content)
                                print("=== END SHARE EXTENSION LOGS ===\n")
                            } else {
                                print("\n[SpendDropApp] No share_extension_diagnostics.log found yet in App Group container.")
                            }
                        }
                        fflush(stdout)
                    }
                }
        }
        .modelContainer(ExpenseDataContainer.shared)
    }
}
