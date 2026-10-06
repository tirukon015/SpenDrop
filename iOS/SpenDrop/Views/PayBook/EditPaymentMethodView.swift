import SwiftUI
import SwiftData

public struct EditPaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var method: PayBookPaymentMethod

    @State private var paymentType: PayBookPaymentType
    @State private var provider: String
    @State private var customProviderName: String
    @State private var accountIdentifier: String
    @State private var label: String
    @State private var notes: String

    @State private var showingDeleteAlert: Bool = false

    private let quickLabels = ["Personal", "Business", "Savings", "Current", "Main", "Family"]

    public init(method: PayBookPaymentMethod) {
        self.method = method
        _paymentType = State(initialValue: method.paymentType)
        if PayBookProviders.common.contains(method.provider) {
            _provider = State(initialValue: method.provider)
            _customProviderName = State(initialValue: "")
        } else {
            _provider = State(initialValue: "Other")
            _customProviderName = State(initialValue: method.displayProvider)
        }
        _accountIdentifier = State(initialValue: method.accountIdentifier)
        _label = State(initialValue: method.label ?? "")
        _notes = State(initialValue: method.notes ?? "")
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
                    Text("PAYMENT METHOD DETAILS")
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
                    Text("LABEL & NOTES")
                }

                Section {
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Label("Delete Payment Method", systemImage: "trash")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commitUpdate()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .alert("Delete this payment method?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteMethod()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \(method.displayProvider) (\(method.maskedIdentifier)) from this profile.")
            }
        }
    }

    private func commitUpdate() {
        guard isValid else { return }

        method.paymentType = paymentType
        method.provider = provider
        method.customProviderName = provider == "Other" ? trimmedProvider : nil
        method.accountIdentifier = trimmedAccount
        method.label = trimmedLabel.isEmpty ? nil : trimmedLabel
        method.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        method.updatedAt = Date()
        method.profile?.updatedAt = Date()

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }

    private func deleteMethod() {
        HapticFeedback.notification(.warning)
        if let profile = method.profile {
            profile.paymentMethods.removeAll(where: { $0.id == method.id })
            profile.updatedAt = Date()
        }
        modelContext.delete(method)
        try? modelContext.save()
        dismiss()
    }
}
