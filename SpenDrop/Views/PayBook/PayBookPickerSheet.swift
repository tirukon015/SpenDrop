import SwiftUI
import SwiftData

public enum PayBookPickerMode {
    /// Select an existing recipient & account to populate payment form
    case selectForPayment
    /// Save current payment details to an existing person or new profile
    case saveRecipient(name: String, provider: String, account: String)
    /// Pick a person (no payment method needed), or add a new one by name
    case selectPerson
}

public struct PayBookPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name, order: .forward) private var allProfiles: [PayBookProfile]

    public let mode: PayBookPickerMode
    public var onSelect: ((PayBookProfile, PayBookPaymentMethod) -> Void)?
    public var onSaved: (() -> Void)?
    public var onSelectPerson: ((PayBookProfile) -> Void)?

    @State private var searchText: String = ""
    @State private var selectedProfileForAccounts: PayBookProfile?
    @State private var showingCreateNewSheet: Bool = false
    @State private var showingNewPersonAlert: Bool = false
    @State private var newPersonName: String = ""

    public init(
        mode: PayBookPickerMode = .selectForPayment,
        onSelect: ((PayBookProfile, PayBookPaymentMethod) -> Void)? = nil,
        onSaved: (() -> Void)? = nil,
        onSelectPerson: ((PayBookProfile) -> Void)? = nil
    ) {
        self.mode = mode
        self.onSelect = onSelect
        self.onSaved = onSaved
        self.onSelectPerson = onSelectPerson
    }

    private var filteredProfiles: [PayBookProfile] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return allProfiles }
        return allProfiles.filter { profile in
            if profile.name.lowercased().contains(term) { return true }
            return profile.paymentMethods.contains { method in
                method.displayProvider.lowercased().contains(term) ||
                method.accountIdentifier.contains(term)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                switch mode {
                case .selectForPayment:
                    if allProfiles.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.rectangle.stack")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("No PayBook Profiles Yet")
                                    .font(.headline)
                                Text("Add people to your PayBook so you can quickly populate payments.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        ForEach(filteredProfiles) { profile in
                            Section {
                                if profile.paymentMethods.isEmpty {
                                    HStack {
                                        avatarView(profile: profile, size: 36)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.name)
                                                .font(.headline)
                                            Text("No payment methods saved")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    ForEach(profile.paymentMethods) { method in
                                        Button(action: {
                                            HapticFeedback.selection()
                                            onSelect?(profile, method)
                                            dismiss()
                                        }) {
                                            HStack(spacing: 12) {
                                                avatarView(profile: profile, size: 38)

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(profile.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)

                                                    HStack(spacing: 6) {
                                                        Text(method.displayProvider)
                                                            .font(.caption)
                                                            .fontWeight(.medium)
                                                            .foregroundStyle(.secondary)

                                                        Text("•")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)

                                                        Text(method.accountIdentifier)
                                                            .font(.caption)
                                                            .fontDesign(.monospaced)
                                                            .foregroundStyle(.secondary)

                                                        if let label = method.label, !label.isEmpty {
                                                            Text("(\(label))")
                                                                .font(.caption2)
                                                                .foregroundStyle(.blue)
                                                        }
                                                    }
                                                }

                                                Spacer()

                                                Image(systemName: "arrow.up.left.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.blue)
                                            }
                                            .padding(.vertical, 2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(profile.name)
                                    Spacer()
                                    Text(profile.paymentMethodCountText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                case .selectPerson:
                    Section {
                        Button(action: {
                            newPersonName = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            showingNewPersonAlert = true
                        }) {
                            Label("New Person", systemImage: "person.badge.plus")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                    }

                    Section {
                        ForEach(filteredProfiles.filter { !$0.isArchived }) { profile in
                            Button(action: {
                                HapticFeedback.selection()
                                onSelectPerson?(profile)
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    avatarView(profile: profile, size: 36)
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("PEOPLE")
                    }

                case .saveRecipient(let name, let provider, let account):
                    // Summary of current payment details being saved
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECIPIENT TO SAVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)

                            Text(name.isEmpty ? "Unknown Recipient" : name)
                                .font(.headline)

                            HStack(spacing: 8) {
                                if !provider.isEmpty {
                                    Text(provider)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                }
                                if !account.isEmpty {
                                    Text(account)
                                        .font(.subheadline)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Option 1: Create New Profile
                        Button(action: {
                            showingCreateNewSheet = true
                        }) {
                            Label("Create New Profile", systemImage: "person.badge.plus")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                    } header: {
                        Text("SAVE RECIPIENT")
                    }

                    // Option 2: Select Existing Profile
                    if !allProfiles.isEmpty {
                        Section {
                            ForEach(filteredProfiles) { profile in
                                Button(action: {
                                    saveToExistingProfile(profile: profile, provider: provider, account: account)
                                }) {
                                    HStack(spacing: 12) {
                                        avatarView(profile: profile, size: 40)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)

                                            Text(profile.paymentMethodCountText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text("Add Account")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("OR ADD TO EXISTING PERSON")
                        } footer: {
                            Text("Adds this payment account under their profile without creating a duplicate person.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search people or accounts...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("New Person", isPresented: $showingNewPersonAlert) {
                TextField("Name", text: $newPersonName)
                Button("Add") { addNewPerson() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adds a person to PayBook. Payment details are optional.")
            }
            .sheet(isPresented: $showingCreateNewSheet) {
                if case .saveRecipient(let name, let provider, let account) = mode {
                    AddPayBookProfileView(
                        initialName: name,
                        initialProvider: provider,
                        initialAccount: account
                    )
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .selectForPayment:
            return "Select from PayBook"
        case .saveRecipient:
            return "Save Recipient"
        case .selectPerson:
            return "Choose Person"
        }
    }

    private func avatarView(profile: PayBookProfile, size: CGFloat) -> some View {
        ZStack {
            if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(Color.blue)
                    )
            }
        }
    }

    private func addNewPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = PayBookProfile(name: name)
        modelContext.insert(profile)
        try? modelContext.save()
        HapticFeedback.notification(.success)
        onSelectPerson?(profile)
        dismiss()
    }

    private func saveToExistingProfile(profile: PayBookProfile, provider: String, account: String) {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty else { return }

        // Check duplicate under this person
        let normAcc = cleanAccount.filter { $0.isNumber || $0.isLetter }.lowercased()
        let normProv = cleanProvider.lowercased()
        let alreadyHas = profile.paymentMethods.contains {
            $0.displayProvider.lowercased() == normProv && $0.normalizedIdentifier == normAcc
        }

        if !alreadyHas {
            let method = PayBookPaymentMethod(
                paymentType: .bankAccount,
                provider: cleanProvider.isEmpty ? "Bank Account" : cleanProvider,
                accountIdentifier: cleanAccount,
                profile: profile
            )
            modelContext.insert(method)
            profile.paymentMethods.append(method)
            profile.updatedAt = Date()
            try? modelContext.save()
        }

        HapticFeedback.notification(.success)
        onSaved?()
        dismiss()
    }
}
