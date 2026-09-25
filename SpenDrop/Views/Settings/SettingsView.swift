import SwiftUI
import SwiftData

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]

    @AppStorage("app_currency") private var selectedCurrency = "RM"
    @AppStorage("user_appearance") private var selectedAppearance = "system"

    @State private var showingClearConfirmation = false
    @State private var showingSampleDataLoadedAlert = false
    @State private var showingSelfTestSheet = false

    public init() {}

    private let currencyOptions = ["RM", "SGD", "USD", "EUR", "GBP"]
    private let appearanceOptions = [
        ("system", "System"),
        ("light", "Light"),
        ("dark", "Dark")
    ]

    public var body: some View {
        NavigationStack {
            Form {
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

                // DATA & TESTING
                Section(header: Text("Data & Device Testing")) {
                    HStack {
                        Text("Total Stored Expenses")
                        Spacer()
                        Text("\(allExpenses.count)")
                            .foregroundStyle(.secondary)
                    }

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
                        Text("1.3.0 (Milestone 3 - Share Extension)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Target Device")
                        Spacer()
                        Text("iPhone 17 Pro Max / 16 Pro Max")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Storage Engine")
                        Spacer()
                        Text("Apple SwiftData (App Group)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("OCR Engine")
                        Spacer()
                        Text("Apple Vision (On-Device)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Share Extension")
                        Spacer()
                        Text("Enabled (App Group)")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSelfTestSheet) {
                ParserSelfTestView()
            }
            .alert("Sample Data Loaded", isPresented: $showingSampleDataLoadedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Sample Malaysian expenses have been added to your dashboard and history.")
            }
            .alert("Clear All Expenses?", isPresented: $showingClearConfirmation) {
                Button("Clear Everything", role: .destructive) {
                    clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(allExpenses.count) transactions stored on this device.")
            }
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
