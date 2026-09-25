import SwiftUI
import SwiftData

public struct EditPayBookContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allContacts: [PayBookContact]

    @Bindable public var contact: PayBookContact

    @State private var name: String
    @State private var bankName: String
    @State private var accountHolderName: String
    @State private var accountNumber: String
    @State private var phoneNumber: String

    // Duplicate detection alert state
    @State private var showingDuplicateAlert: Bool = false
    @State private var existingContactName: String = ""

    public init(contact: PayBookContact) {
        self.contact = contact
        _name = State(initialValue: contact.name)
        _bankName = State(initialValue: contact.bankName)
        _accountHolderName = State(initialValue: contact.accountHolderName)
        _accountNumber = State(initialValue: contact.accountNumber)
        _phoneNumber = State(initialValue: contact.phoneNumber ?? "")
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
                    Text("EDIT PAYEE DETAILS")
                } footer: {
                    Text("Fields marked with * are required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Payee")
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
                    commitUpdate()
                }
            } message: {
                Text("A contact with this account already exists as \(existingContactName).")
            }
        }
    }

    private func handleSaveAttempt() {
        guard isValid else { return }

        let normalizedAccount = trimmedAccount.filter { $0.isNumber || $0.isLetter }.lowercased()
        let normalizedBank = trimmedBank.lowercased()

        // Check duplicates among other contacts (excluding self)
        if let match = allContacts.first(where: {
            guard $0.id != contact.id else { return false }
            let existingAcc = $0.accountNumber.filter { $0.isNumber || $0.isLetter }.lowercased()
            let existingBank = $0.bankName.lowercased()
            return existingBank == normalizedBank && existingAcc == normalizedAccount
        }) {
            existingContactName = match.name
            showingDuplicateAlert = true
            return
        }

        commitUpdate()
    }

    private func commitUpdate() {
        contact.name = trimmedName
        contact.bankName = trimmedBank
        contact.accountHolderName = trimmedHolder
        contact.accountNumber = trimmedAccount
        contact.phoneNumber = trimmedPhone.isEmpty ? nil : trimmedPhone
        contact.updatedAt = Date()

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
