import SwiftUI
import SwiftData

public struct PayBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var contact: PayBookContact

    @State private var showingEditSheet: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var isCopied: Bool = false

    public init(contact: PayBookContact) {
        self.contact = contact
        if ProcessInfo.processInfo.arguments.contains("--open-edit") {
            _showingEditSheet = State(initialValue: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-copied") {
            _isCopied = State(initialValue: true)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // HERO HEADER
                VStack(spacing: 8) {
                    Text(contact.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(contact.bankName)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // BANK ACCOUNT DETAILS CARD
                VStack(spacing: 0) {
                    // Account Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ACCOUNT NAME")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)

                        Text(contact.accountHolderName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    Divider().padding(.horizontal, 16)

                    // Account Number with Copy Button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCOUNT NUMBER")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)

                        HStack(alignment: .center) {
                            Text(contact.accountNumber)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)

                            Spacer()

                            Button(action: copyAccountNumber) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    // Optional Phone Number
                    if let phone = contact.phoneNumber, !phone.isEmpty {
                        Divider().padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("PHONE NUMBER")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)

                            Text(phone)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // DELETE ACTION BUTTON
                Button(role: .destructive, action: {
                    showingDeleteAlert = true
                }) {
                    Label("Delete Contact", systemImage: "trash.fill")
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
        .navigationTitle("Payee Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPayBookContactView(contact: contact)
        }
        .alert("Delete Contact?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                HapticFeedback.notification(.warning)
                modelContext.delete(contact)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(contact.name)?")
        }
    }

    private func copyAccountNumber() {
        UIPasteboard.general.string = contact.accountNumber
        HapticFeedback.notification(.success)

        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }

        // Reset badge back to "Copy" after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
