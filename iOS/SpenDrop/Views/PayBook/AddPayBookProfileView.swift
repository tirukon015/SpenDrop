import SwiftUI
import SwiftData
import PhotosUI

public struct AddPayBookProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?

    // Optional initial payment method
    @State private var includePaymentMethod: Bool = false
    @State private var paymentType: PayBookPaymentType = .bankAccount
    @State private var provider: String = "Maybank"
    @State private var customProviderName: String = ""
    @State private var accountIdentifier: String = ""
    @State private var label: String = ""
    @State private var paymentNotes: String = ""

    public init(initialName: String = "", initialProvider: String = "", initialAccount: String = "") {
        _name = State(initialValue: initialName)
        if !initialProvider.isEmpty || !initialAccount.isEmpty {
            _includePaymentMethod = State(initialValue: true)
            if !initialProvider.isEmpty {
                if PayBookProviders.common.contains(initialProvider) {
                    _provider = State(initialValue: initialProvider)
                } else {
                    _provider = State(initialValue: "Other")
                    _customProviderName = State(initialValue: initialProvider)
                }
            }
            _accountIdentifier = State(initialValue: initialAccount)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAccount: String { accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isFormValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        if includePaymentMethod {
            guard !trimmedAccount.isEmpty else { return false }
            if provider == "Other" && customProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    public var body: some View {
        NavigationStack {
            Form {
                // PHOTO & BASIC INFO SECTION
                Section {
                    HStack(spacing: 16) {
                        // Avatar / Photo Picker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                if let photoData, let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(Color.blue)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        self.photoData = data
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Person Name *", text: $name)
                                .font(.headline)
                                .textContentType(.name)
                                .autocorrectionDisabled()

                            if photoData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    photoData = nil
                                    selectedPhotoItem = nil
                                }
                                .font(.caption)
                            } else {
                                Text("Tap icon to add photo (optional)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("PERSON PROFILE")
                } footer: {
                    Text("Each person can store multiple bank accounts and e-wallets.")
                }

                // OPTIONAL INITIAL PAYMENT METHOD
                Section {
                    Toggle("Add Payment Account Now", isOn: $includePaymentMethod)

                    if includePaymentMethod {
                        Picker("Type", selection: $paymentType) {
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
                            TextField("Custom Provider Name *", text: $customProviderName)
                                .autocorrectionDisabled()
                        }

                        TextField(paymentType.identifierFieldLabel + " *", text: $accountIdentifier)
                            .keyboardType(paymentType == .bankAccount ? .numbersAndPunctuation : .default)
                            .autocorrectionDisabled()

                        TextField("Label e.g. Personal, Business (optional)", text: $label)
                            .autocorrectionDisabled()

                        TextField("Payment notes (optional)", text: $paymentNotes)
                    }
                } header: {
                    Text("PAYMENT METHOD (OPTIONAL)")
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private func saveProfile() {
        guard isFormValid else { return }

        let newProfile = PayBookProfile(
            name: trimmedName,
            photoData: photoData,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        modelContext.insert(newProfile)

        if includePaymentMethod && !trimmedAccount.isEmpty {
            let method = PayBookPaymentMethod(
                paymentType: paymentType,
                provider: provider,
                customProviderName: provider == "Other" ? customProviderName : nil,
                accountIdentifier: trimmedAccount,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label,
                notes: paymentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : paymentNotes,
                profile: newProfile
            )
            modelContext.insert(method)
            newProfile.paymentMethods.append(method)
        }

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
