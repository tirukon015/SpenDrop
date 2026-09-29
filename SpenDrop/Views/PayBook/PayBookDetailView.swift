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

    // Balances & history (Phase 5)
    @State private var repayment: PrefilledMovement?
    @State private var selectedExpense: Expense?
    @State private var selectedMovement: MoneyMovement?
    @State private var showingCannotDeleteAlert: Bool = false

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

                // BALANCE (always calculated; positive = they owe me)
                balanceSection

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

                // HISTORY
                historySection

                // FREQUENT / ARCHIVE
                VStack(spacing: 0) {
                    Toggle(isOn: $profile.isFrequent) {
                        Label("Frequent", systemImage: "star.fill")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                    Toggle(isOn: $profile.isArchived) {
                        Label("Archived", systemImage: "archivebox")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: profile.isFrequent) { _, _ in profile.updatedAt = Date(); try? modelContext.save() }
                .onChange(of: profile.isArchived) { _, _ in profile.updatedAt = Date(); try? modelContext.save() }

                // DELETE PERSON PROFILE BUTTON (blocked while money is owed either way)
                Button(role: .destructive, action: {
                    if PersonLedger.canDelete(profile) {
                        showingDeleteProfileAlert = true
                    } else {
                        showingCannotDeleteAlert = true
                    }
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
        .sheet(item: $repayment) { item in
            MoneyMovementCreateSheet(draft: item.draft)
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailView(expense: expense)
        }
        .sheet(item: $selectedMovement) { movement in
            MoneyMovementEditSheet(movement: movement)
        }
        .alert("\(profile.name) still has a balance", isPresented: $showingCannotDeleteAlert) {
            Button("Archive Instead") {
                profile.isArchived = true
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Settle up first, or archive \(profile.name) to hide them while keeping the balance and history.")
        }
        .alert("Delete \(profile.name)?", isPresented: $showingDeleteProfileAlert) {
            Button("Delete", role: .destructive) {
                deleteProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile and its saved payment methods. Past shared expenses and money records are kept under their saved name.")
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

    // MARK: - Balance & History (Phase 5)

    @ViewBuilder
    private var balanceSection: some View {
        let balances = PersonLedger.balances(for: profile)
        if !balances.isEmpty || PersonLedger.hasHistory(profile) {
            VStack(alignment: .leading, spacing: 10) {
                if balances.isEmpty {
                    Label("Settled — nothing owed either way", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    ForEach(balances.sorted { $0.key < $1.key }, id: \.key) { currency, value in
                        HStack {
                            Image(systemName: value > 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                .foregroundStyle(value > 0 ? .green : .orange)
                            Text(PersonLedger.directionText(name: profile.name, balanceMinor: value, currency: currency))
                                .font(.headline)
                            Spacer()
                        }
                        Button {
                            if let draft = PersonLedger.repaymentDraft(for: profile, currency: currency) {
                                repayment = PrefilledMovement(draft: draft)
                            }
                        } label: {
                            Label(value > 0 ? "Record Repayment Received" : "Record Repayment Made", systemImage: "banknote")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("person.recordRepayment")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let entries = PersonLedger.entries(for: profile)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("HISTORY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            switch entry.source {
                            case .expense(let expense): selectedExpense = expense
                            case .movement(let movement): selectedMovement = movement
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(.subheadline.weight(.semibold))
                                    Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.detail)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if entry.effectMinor != 0 {
                                    Text((entry.effectMinor > 0 ? "+" : "−") + PersonLedger.format(abs(entry.effectMinor), entry.currency))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(entry.effectMinor > 0 ? .green : .orange)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("+ means \(profile.name) owes you more; − means you owe \(profile.name) more (or they owe you less).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func deleteProfile() {
        HapticFeedback.notification(.warning)
        modelContext.delete(profile)
        try? modelContext.save()
        dismiss()
    }
}
