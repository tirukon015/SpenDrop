import SwiftUI
import SwiftData

public struct AddPayBookContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allContacts: [PayBookContact]

    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var accountHolderName: String = ""
    @State private var accountNumber: String = ""
    @State private var phoneNumber: String = ""

    // Duplicate detection alert state
    @State private var showingDuplicateAlert: Bool = false
    @State private var existingContactName: String = ""

    public init() {
        if ProcessInfo.processInfo.arguments.contains("--demo-duplicate") {
            _name = State(initialValue: "Rahim (Second Account)")
            _bankName = State(initialValue: "Maybank")
            _accountHolderName = State(initialValue: "Abdul Rahim Bin Osman")
            _accountNumber = State(initialValue: "1234567890")
            _phoneNumber = State(initialValue: "012-345 6789")
            _showingDuplicateAlert = State(initialValue: true)
            _existingContactName = State(initialValue: "Rahim")
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBank: String { bankName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedHolder: String { accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAccount: String { accountNumber.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPhone: String { phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !trimmedName.isEmpty && !trimmedBank.isEmpty && !trimmedHolder.isEmpty && !trimmedAccount.isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name *", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    TextField("Bank Name *", text: $bankName)
                        .autocorrectionDisabled()

                    TextField("Account Holder Name *", text: $accountHolderName)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    TextField("Account Number *", text: $accountNumber)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()

                    TextField("Phone Number (Optional)", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("PAYEE DETAILS")
                } footer: {
                    Text("Fields marked with * are required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Payee")
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
            .alert("Duplicate Contact Found", isPresented: $showingDuplicateAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") {
                    commitSave()
                }
            } message: {
                Text("A contact with this account already exists as \(existingContactName).")
            }
        }
    }

    private func handleSaveAttempt() {
        guard isValid else { return }

        // Clean account number comparison (stripping spaces, dashes)
        let normalizedAccount = trimmedAccount.filter { $0.isNumber || $0.isLetter }.lowercased()
        let normalizedBank = trimmedBank.lowercased()

        if let match = allContacts.first(where: {
            let existingAcc = $0.accountNumber.filter { $0.isNumber || $0.isLetter }.lowercased()
            let existingBank = $0.bankName.lowercased()
            return existingBank == normalizedBank && existingAcc == normalizedAccount
        }) {
            existingContactName = match.name
            showingDuplicateAlert = true
            return
        }

        commitSave()
    }

    private func commitSave() {
        let newContact = PayBookContact(
            name: trimmedName,
            bankName: trimmedBank,
            accountHolderName: trimmedHolder,
            accountNumber: trimmedAccount,
            phoneNumber: trimmedPhone.isEmpty ? nil : trimmedPhone
        )
        modelContext.insert(newContact)
        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
