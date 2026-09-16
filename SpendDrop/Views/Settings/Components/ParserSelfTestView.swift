import SwiftUI

public struct ParserSelfTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var testResults: [TestCaseResult] = []
    @State private var isRunning = false

    public init() {}

    private var allPassed: Bool {
        !testResults.isEmpty && testResults.allSatisfy { $0.passed }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: allPassed ? "checkmark.seal.fill" : "gearshape.arrow.triangle.2.circlepath")
                                .font(.title)
                                .foregroundStyle(allPassed ? .green : .blue)

                            VStack(alignment: .leading) {
                                Text(allPassed ? "All Tests Passed (\(testResults.count)/\(testResults.count))" : "Parser & Duplicate Verification")
                                    .font(.headline)
                                Text("Automated validation of Malaysian payment screenshots, false positives, balances, multi-amounts, and duplicate detection.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Test Results")) {
                    if testResults.isEmpty {
                        Text("No test run yet. Tap 'Run Tests' below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(testResults) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.passed ? .green : .red)
                                    Text(result.testName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }

                                Text(result.details)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                HStack(alignment: .top) {
                                    Text("Actual:")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                    Text(result.actual)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("OCR & Parser Tests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: runTests) {
                        Label("Run Tests", systemImage: "play.fill")
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                runTests()
            }
        }
    }

    private func runTests() {
        isRunning = true
        HapticFeedback.impact(.light)
        testResults = TransactionParserTests.runAllTests()
        isRunning = false
        if allPassed {
            HapticFeedback.notification(.success)
        }
    }
}
