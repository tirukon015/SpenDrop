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
    @State private var selectedDebtIDs = Set<String>()
    @State private var confirmSettleSelected = false
    @State private var debtToSettle: Debt?
    @State private var settleAllCurrency: String?
    @State private var paymentSheet: PaymentSheetRequest?
    /// Re-renders when payments or settlements change (debts are calculated, not stored).
    @Query private var allocations: [SettlementAllocation]
    @Query private var movements: [MoneyMovement]

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

                // RECEIVE / GIVE MONEY
                moneyActions

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
        .sheet(item: $paymentSheet) { request in
            RecordPaymentSheet(person: profile, debts: request.debts, direction: request.direction, currency: request.currency,
                               context: modelContext, creditAvailableMinor: request.creditMinor)
        }
        .confirmationDialog("Mark as paid?", isPresented: Binding(get: { debtToSettle != nil }, set: { if !$0 { debtToSettle = nil } }),
                            titleVisibility: .visible, presenting: debtToSettle) { debt in
            Button("Mark \(PersonLedger.format(debt.outstandingMinor, debt.currency)) as Paid") {
                try? SettlementService.markPaid(debt, person: profile, in: modelContext)
                selectedDebtIDs.remove(debt.id)
            }
        } message: { debt in
            Text("Only \(debt.title) is settled. Other transactions stay outstanding.")
        }
        .confirmationDialog("Settle everything with \(profile.name)?", isPresented: Binding(get: { settleAllCurrency != nil }, set: { if !$0 { settleAllCurrency = nil } }),
                            titleVisibility: .visible, presenting: settleAllCurrency) { currency in
            Button("Settle All") {
                try? SettlementService.settleAll(person: profile, currency: currency, in: modelContext)
                selectedDebtIDs.removeAll()
            }
        } message: { currency in
            let value = PersonLedger.balances(for: profile)[currency] ?? 0
            Text("Debts in both directions are cancelled against each other and one payment of \(PersonLedger.format(abs(value), currency)) is recorded (\(value > 0 ? "\(profile.name) paid you" : "you paid \(profile.name)")). Every transaction is kept; you can undo this.")
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
        let debts = DebtLedger.debts(for: profile)
        if !balances.isEmpty || PersonLedger.hasHistory(profile) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NET BALANCE").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1.0)
                if balances.isEmpty {
                    Label("Settled — nothing owed either way", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    ForEach(balances.sorted { $0.key < $1.key }, id: \.key) { currency, value in
                        let open = debts.filter { $0.currency == currency && !$0.isSettled }
                        let theyOwe = open.filter { $0.direction > 0 }.reduce(0) { $0 + $1.outstandingMinor }
                        let iOwe = open.filter { $0.direction < 0 }.reduce(0) { $0 + $1.outstandingMinor }
                        let unassigned = DebtLedger.unassignedMinor(for: profile, currency: currency)
                        HStack {
                            Image(systemName: value > 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                .foregroundStyle(value > 0 ? .green : .orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PersonLedger.directionText(name: profile.name, balanceMinor: value, currency: currency))
                                    .font(.headline)
                                    .accessibilityIdentifier("person.netBalance")
                                Text("Net \(value > 0 ? "+" : "−")\(PersonLedger.format(abs(value), currency))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        if theyOwe > 0 && iOwe > 0 {
                            Text("\(profile.name) owes you \(PersonLedger.format(theyOwe, currency)) and you owe \(profile.name) \(PersonLedger.format(iOwe, currency)); the difference is shown above. Both transactions are kept.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let creditFromThem = DebtLedger.creditMinor(for: profile, currency: currency, direction: 1)
                        let creditFromMe = DebtLedger.creditMinor(for: profile, currency: currency, direction: -1)
                        if creditFromThem > 0 {
                            creditRow("\(PersonLedger.format(creditFromThem, currency)) credit available from \(profile.name)",
                                      canApply: theyOwe > 0) {
                                paymentSheet = PaymentSheetRequest(direction: 1, currency: currency, debts: open, creditMinor: creditFromThem)
                            }
                        }
                        if creditFromMe > 0 {
                            creditRow("\(PersonLedger.format(creditFromMe, currency)) you paid \(profile.name) not yet applied",
                                      canApply: iOwe > 0) {
                                paymentSheet = PaymentSheetRequest(direction: -1, currency: currency, debts: open, creditMinor: creditFromMe)
                            }
                        }
                        if unassigned != 0 && creditFromThem == 0 && creditFromMe == 0 {
                            Text("Includes \(PersonLedger.format(abs(unassigned), currency)) not linked to a transaction.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            if theyOwe > 0 {
                                Button {
                                    paymentSheet = PaymentSheetRequest(direction: 1, currency: currency, debts: open)
                                } label: {
                                    Label("Receive Payment", systemImage: "arrow.down.circle").font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("person.recordRepayment")
                            }
                            if iOwe > 0 {
                                Button {
                                    paymentSheet = PaymentSheetRequest(direction: -1, currency: currency, debts: open)
                                } label: {
                                    Label("Pay \(profile.name)", systemImage: "arrow.up.circle").font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                            if theyOwe == 0 && iOwe == 0 {
                                // Only unlinked amounts are left: record a general repayment as before.
                                Button {
                                    if let draft = PersonLedger.repaymentDraft(for: profile, currency: currency) {
                                        repayment = PrefilledMovement(draft: draft)
                                    }
                                } label: {
                                    Label(value > 0 ? "Record Repayment Received" : "Record Repayment Made", systemImage: "banknote")
                                        .font(.subheadline.weight(.semibold))
                                }
                            } else {
                                Button {
                                    settleAllCurrency = currency
                                } label: {
                                    Label("Settle All", systemImage: "checkmark.seal").font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel("Settle all with \(profile.name)")
                                .accessibilityIdentifier("person.settleAll")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            debtsSection(debts)
        }
    }

    private func creditRow(_ text: String, canApply: Bool, apply: @escaping () -> Void) -> some View {
        HStack {
            Label(text, systemImage: "creditcard.and.123").font(.subheadline)
            Spacer()
            if canApply {
                Button("Apply Credit", action: apply)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("person.applyCredit")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("person.credit")
    }

    /// Money that moved between me and this person, in either direction, even when nothing is owed yet.
    private var moneyActions: some View {
        let debts = DebtLedger.debts(for: profile).filter { !$0.isSettled }
        let currency = debts.first?.currency ?? "RM"
        return HStack(spacing: 12) {
            Menu {
                Button("Payment from \(profile.name)") {
                    paymentSheet = PaymentSheetRequest(direction: 1, currency: currency, debts: debts)
                }
                Button("I borrowed from \(profile.name)") { loanDraft(.loanReceived) }
            } label: {
                Label("Receive Money", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("person.receiveMoney")
            Menu {
                Button("Pay back what I owe") {
                    paymentSheet = PaymentSheetRequest(direction: -1, currency: currency, debts: debts)
                }
                Button("Lend to \(profile.name) (they'll owe you)") { loanDraft(.loanGiven) }
            } label: {
                Label("Give Money", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("person.giveMoney")
        }
    }

    private func loanDraft(_ kind: MoneyMovementKind) {
        var draft = MoneyMovementDraft(entryType: kind.direction == .moneyIn ? .moneyIn : .moneyOut)
        draft.kind = kind
        draft.person = profile
        repayment = PrefilledMovement(draft: draft)
    }

    /// Outstanding transactions one by one (select several to settle together), settled ones, and payments.
    @ViewBuilder
    private func debtsSection(_ debts: [Debt]) -> some View {
        let open = debts.filter { !$0.isSettled }.sorted { $0.date > $1.date }
        let settled = debts.filter(\.isSettled).sorted { $0.date > $1.date }
        let selected = open.filter { selectedDebtIDs.contains($0.id) }
        let selectedTotal = selected.reduce(0) { $0 + $1.outstandingMinor }
        let oneDirection = Set(selected.map(\.direction)).count <= 1 && Set(selected.map(\.currency)).count <= 1
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("OUTSTANDING TRANSACTIONS").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1.0)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(open) { debt in
                        HStack(spacing: 12) {
                            Button {
                                if selectedDebtIDs.contains(debt.id) { selectedDebtIDs.remove(debt.id) } else { selectedDebtIDs.insert(debt.id) }
                            } label: {
                                Image(systemName: selectedDebtIDs.contains(debt.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedDebtIDs.contains(debt.id) ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select transaction \(debt.title)")
                            .accessibilityAddTraits(selectedDebtIDs.contains(debt.id) ? .isSelected : [])
                            .accessibilityIdentifier("person.select.\(debt.title)")
                            Button {
                                if let expense = debt.expense { selectedExpense = expense } else if let loan = debt.loan { selectedMovement = loan }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.title).font(.subheadline.weight(.semibold))
                                    Text("\(debt.date.formatted(date: .abbreviated, time: .omitted)) · \(debt.detail)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if debt.isPartiallyPaid {
                                        Text("Paid \(PersonLedger.format(debt.settledMinor, debt.currency)) of \(PersonLedger.format(debt.originalMinor, debt.currency))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((debt.direction > 0 ? "+" : "−") + PersonLedger.format(debt.outstandingMinor, debt.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(debt.direction > 0 ? .green : .orange)
                                Text(debt.direction > 0 ? "owes you" : "you owe").font(.caption2).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            Button("Settle") { debtToSettle = debt }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Mark \(debt.title) as paid")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        if debt.id != open.last?.id { Divider().padding(.leading, 48) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if !selected.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected: \(selected.count) · \(PersonLedger.format(selectedTotal, selected.first?.currency ?? "RM"))")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("person.selectedTotal")
                        if oneDirection, let first = selected.first {
                            HStack {
                                Button("Settle Selected") { confirmSettleSelected = true }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("person.settleSelected")
                                Button("Different Amount…") {
                                    paymentSheet = PaymentSheetRequest(direction: first.direction, currency: first.currency, debts: selected)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Text("Choose transactions in one direction (all owed to you, or all owed by you).")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 4)
                    .confirmationDialog("Settle selected?", isPresented: $confirmSettleSelected, titleVisibility: .visible) {
                        Button("Settle \(PersonLedger.format(selectedTotal, selected.first?.currency ?? "RM"))") {
                            if let first = selected.first {
                                try? SettlementService.recordPayment(person: profile, direction: first.direction, amountMinor: selectedTotal,
                                                                     allocations: selected.map { ($0, $0.outstandingMinor) },
                                                                     currency: first.currency, note: "Settled \(selected.count) transactions",
                                                                     in: modelContext)
                                selectedDebtIDs.removeAll()
                            }
                        }
                    } message: {
                        Text("Records one payment of \(PersonLedger.format(selectedTotal, selected.first?.currency ?? "RM")) for the \(selected.count) selected transactions. Others stay outstanding.")
                    }
                }
            }
        }
        if !settled.isEmpty {
            DisclosureGroup("Settled transactions (\(settled.count))") {
                VStack(spacing: 0) {
                    ForEach(settled) { debt in
                        Button {
                            if let expense = debt.expense { selectedExpense = expense } else if let loan = debt.loan { selectedMovement = loan }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.title).font(.subheadline)
                                    Text(debt.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Label("Settled \(PersonLedger.format(debt.originalMinor, debt.currency))", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        let groups = DebtLedger.settlementGroups(personID: profile.id, in: modelContext)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SETTLEMENT HISTORY").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1.0)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    SettlementHistoryList(groups: groups, context: modelContext)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
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

/// Identifiable wrapper so a prefilled draft can drive `.sheet(item:)`.
struct PrefilledMovement: Identifiable {
    let id = UUID()
    let draft: MoneyMovementDraft
}

/// Opens the payment sheet for some debts in one direction.
struct PaymentSheetRequest: Identifiable {
    let id = UUID()
    let direction: Int
    let currency: String
    let debts: [Debt]
    /// Set to apply existing credit instead of recording new money.
    var creditMinor: Int? = nil
}
