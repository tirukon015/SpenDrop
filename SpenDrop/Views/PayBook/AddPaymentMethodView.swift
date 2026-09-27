import SwiftUI
import SwiftData

public struct AddPaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var profile: PayBookProfile

    @State private var paymentType: PayBookPaymentType = .bankAccount
    @State private var provider: String = "Maybank"
    @State private var customProviderName: String = ""
    @State private var accountIdentifier: String = ""
    @State private var label: String = ""
    @State private var notes: String = ""

    // Duplicate detection alert state
    @State private var showingDuplicateAlert: Bool = false

    private let quickLabels = ["Personal", "Business", "Savings", "Current", "Main", "Family"]

    public init(profile: PayBookProfile, initialProvider: String = "", initialAccount: String = "") {
        self.profile = profile
        if !initialProvider.isEmpty {
            if PayBookProviders.common.contains(initialProvider) {
                _provider = State(initialValue: initialProvider)
            } else {
                _provider = State(initialValue: "Other")
                _customProviderName = State(initialValue: initialProvider)
            }
        }
        if !initialAccount.isEmpty {
            _accountIdentifier = State(initialValue: initialAccount)
        }
    }

    private var trimmedProvider: String {
        if provider == "Other" {
            return customProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return provider.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAccount: String { accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        if trimmedAccount.isEmpty { return false }
        if provider == "Other" && trimmedProvider.isEmpty { return false }
        return true
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Payment Type", selection: $paymentType) {
                        ForEach(PayBookPaymentType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }

                    Picker("Provider", selection: $provider) {
                        ForEach(PayBookProviders.common, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }

                    if provider == "Other" {
                        TextField("Custom Provider / Bank Name *", text: $customProviderName)
                            .autocorrectionDisabled()
                    }

                    TextField(paymentType.identifierFieldLabel + " *", text: $accountIdentifier)
                        .keyboardType(paymentType == .bankAccount ? .numbersAndPunctuation : .default)
                        .autocorrectionDisabled()
                } header: {
                    Text("ACCOUNT DETAILS FOR \(profile.name.uppercased())")
                } footer: {
                    Text("Enter the account number, phone number, or payment handle.")
                }

                Section {
                    TextField("Label (optional)", text: $label)
                        .autocorrectionDisabled()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickLabels, id: \.self) { chip in
                                Button(action: {
                                    HapticFeedback.selection()
                                    label = chip
                                }) {
                                    Text(chip)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(label == chip ? Color.blue : Color(uiColor: .tertiarySystemGroupedBackground))
                                        .foregroundStyle(label == chip ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...3)
                } header: {
                    Text("IDENTIFIER LABEL & NOTES")
                } footer: {
                    Text("Labels help distinguish multiple accounts from the same bank (e.g. Personal vs Business).")
                }
            }
            .navigationTitle("Add Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSaveAttempt()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .alert("Account Already Saved", isPresented: $showingDuplicateAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") {
                    commitSave()
                }
            } message: {
                Text("This exact payment account is already saved under \(profile.name).")
            }
        }
    }

    private func handleSaveAttempt() {
        guard isValid else { return }

        let normalizedAcc = trimmedAccount.filter { $0.isNumber || $0.isLetter }.lowercased()
        let normalizedProv = trimmedProvider.lowercased()

        // Check if THIS person already has the identical provider & account number
        let isDuplicate = profile.paymentMethods.contains { method in
            let existingProv = method.displayProvider.lowercased()
            let existingAcc = method.normalizedIdentifier
            return existingProv == normalizedProv && existingAcc == normalizedAcc
        }

        if isDuplicate {
            showingDuplicateAlert = true
            return
        }

        commitSave()
    }

    private func commitSave() {
        let newMethod = PayBookPaymentMethod(
            paymentType: paymentType,
            provider: provider,
            customProviderName: provider == "Other" ? trimmedProvider : nil,
            accountIdentifier: trimmedAccount,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            profile: profile
        )
        modelContext.insert(newMethod)
        profile.paymentMethods.append(newMethod)
        profile.updatedAt = Date()

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
