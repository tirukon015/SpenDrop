import SwiftUI
import SwiftData

public struct PayBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var profile: PayBookProfile

    @State private var showingEditProfileSheet: Bool = false
    @State private var showingAddPaymentSheet: Bool = false
    @State private var methodToEdit: PayBookPaymentMethod?
    @State private var methodToDelete: PayBookPaymentMethod?
    @State private var showingDeleteProfileAlert: Bool = false
    @State private var showingDeleteMethodAlert: Bool = false

    // Copy Feedback states
    @State private var isNameCopied: Bool = false
    @State private var copiedMethodId: UUID?

    public init(profile: PayBookProfile) {
        self.profile = profile
        if ProcessInfo.processInfo.arguments.contains("--open-edit") {
            _showingEditProfileSheet = State(initialValue: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-copied") {
            _isNameCopied = State(initialValue: true)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // HERO PERSON CARD
                VStack(spacing: 12) {
                    // Profile Avatar
                    ZStack {
                        if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Text(profile.initials)
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundStyle(Color.blue)
                                )
                        }
                    }

                    // Person Name
                    Text(profile.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    // Notes (if any)
                    if let notes = profile.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // Copy Name Button
                    Button(action: copyPersonName) {
                        HStack(spacing: 6) {
                            Image(systemName: isNameCopied ? "checkmark" : "doc.on.doc")
                                .font(.subheadline)
                            Text(isNameCopied ? "Name Copied" : "Copy Name")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isNameCopied ? Color.green.opacity(0.15) : Color.blue.opacity(0.12))
                        .foregroundStyle(isNameCopied ? Color.green : Color.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // PAYMENT METHODS SECTION
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("PAYMENT ACCOUNTS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)

                        Spacer()

                        Button(action: {
                            showingAddPaymentSheet = true
                        }) {
                            Label("Add Method", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 4)

                    if profile.paymentMethods.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Text("No Payment Accounts")
                                .font(.headline)

                            Text("Add bank accounts, e-wallets, or payment IDs for \(profile.name).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: {
                                showingAddPaymentSheet = true
                            }) {
                                Label("Add Payment Method", systemImage: "plus")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(profile.paymentMethods) { method in
                                paymentMethodRow(method: method)
                            }
                        }
                    }
                }

                // DELETE PERSON PROFILE BUTTON
                Button(role: .destructive, action: {
                    showingDeleteProfileAlert = true
                }) {
                    Label("Delete Person Profile", systemImage: "trash.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditProfileSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditProfileSheet) {
            EditPayBookProfileView(profile: profile)
        }
        .sheet(isPresented: $showingAddPaymentSheet) {
            AddPaymentMethodView(profile: profile)
        }
        .sheet(item: $methodToEdit) { method in
            EditPaymentMethodView(method: method)
        }
        .alert("Delete \(profile.name)?", isPresented: $showingDeleteProfileAlert) {
            Button("Delete", role: .destructive) {
                deleteProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the profile and all saved payment methods under it.")
        }
        .alert("Delete this payment method?", isPresented: $showingDeleteMethodAlert) {
            Button("Delete", role: .destructive) {
                if let method = methodToDelete {
                    deletePaymentMethod(method: method)
                }
            }
            Button("Cancel", role: .cancel) {
                methodToDelete = nil
            }
        } message: {
            if let method = methodToDelete {
                Text("Delete \(method.displayProvider) (\(method.accountIdentifier))?")
            }
        }
    }

    private func paymentMethodRow(method: PayBookPaymentMethod) -> some View {
        let isCopied = copiedMethodId == method.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                // Provider icon & Name
                HStack(spacing: 8) {
                    Image(systemName: method.paymentType.icon)
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                    Text(method.displayProvider)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let label = method.label, !label.isEmpty {
                        Text(label)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Edit Button
                Button(action: {
                    methodToEdit = method
                }) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)

                // Delete Button
                Button(action: {
                    methodToDelete = method
                    showingDeleteMethodAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            // Identifier & Copy Button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.identifierLabel.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    Text(method.accountIdentifier)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(action: {
                    copyAccountIdentifier(method: method)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isCopied ? Color.green.opacity(0.15) : Color.blue.opacity(0.12))
                    .foregroundStyle(isCopied ? Color.green : Color.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let notes = method.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func copyPersonName() {
        UIPasteboard.general.string = profile.name
        HapticFeedback.notification(.success)

        withAnimation(.easeInOut(duration: 0.2)) {
            isNameCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isNameCopied = false
            }
        }
    }

    private func copyAccountIdentifier(method: PayBookPaymentMethod) {
        UIPasteboard.general.string = method.accountIdentifier
        HapticFeedback.notification(.success)

        withAnimation(.easeInOut(duration: 0.2)) {
            copiedMethodId = method.id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if copiedMethodId == method.id {
                    copiedMethodId = nil
                }
            }
        }
    }

    private func deletePaymentMethod(method: PayBookPaymentMethod) {
        HapticFeedback.notification(.warning)
        profile.paymentMethods.removeAll(where: { $0.id == method.id })
        profile.updatedAt = Date()
        modelContext.delete(method)
        try? modelContext.save()
        methodToDelete = nil
    }

    private func deleteProfile() {
        HapticFeedback.notification(.warning)
        modelContext.delete(profile)
        try? modelContext.save()
        dismiss()
    }
}
