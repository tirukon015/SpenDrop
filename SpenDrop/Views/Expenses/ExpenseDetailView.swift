import SwiftUI
import SwiftData

public struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var expense: Expense
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingSplitEditor = false
    /// Re-renders when settlements change (debts are calculated, not stored).
    @Query private var allocations: [SettlementAllocation]
    @Query private var movements: [MoneyMovement]

    public init(expense: Expense) {
        self.expense = expense
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // HERO CARD
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(expense.category.color.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: expense.category.icon)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(expense.category.color)
                        }

                        Text(expense.formattedAmount)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(expense.merchant)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        if expense.isShared {
                            Text("Your share \(format(expense.myShareMinor))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                            ForEach(DebtLedger.debts(for: expense)) { debt in
                                Label(debt.isSettled ? "\(debt.personName) · settled" : debt.statusText,
                                      systemImage: debt.isSettled ? "checkmark.circle.fill" : (debt.direction > 0 ? "arrow.down.left.circle" : "arrow.up.right.circle"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(debt.isSettled ? Color.green : (debt.direction > 0 ? Color.blue : Color.orange))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    // DETAILS SECTION
                    VStack(spacing: 0) {
                        detailRow(title: "Category", value: expense.category.rawValue, icon: expense.category.icon, iconColor: expense.category.color)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Funding Method", value: expense.effectiveFundingAccount, icon: "building.columns.fill", iconColor: .blue)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Payment Channel", value: expense.paymentChannel.displayName, icon: expense.paymentChannel.iconName, iconColor: expense.paymentChannel.tintColor)

                        if let instrument = expense.fundingInstrument, !instrument.isEmpty {
                            Divider().padding(.leading, 48)
                            detailRow(title: "Funding Instrument", value: instrument, icon: "creditcard", iconColor: .orange)
                        }

                        Divider().padding(.leading, 48)

                        if expense.isReconciled {
                            detailRow(title: "Status", value: "Reconciled", icon: "checkmark.seal.fill", iconColor: .blue)
                            Divider().padding(.leading, 48)
                        }

                        detailRow(title: "Date", value: expense.date.formatted(date: .long, time: .omitted), icon: "calendar", iconColor: .blue)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Time", value: expense.date.formatted(date: .omitted, time: .shortened), icon: "clock.fill", iconColor: .teal)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Source", value: expense.sourceType.displayName, icon: expense.sourceType.icon, iconColor: .indigo)

                        if let ref = expense.transactionReference, !ref.isEmpty {
                            Divider().padding(.leading, 48)
                            detailRow(title: "Reference", value: ref, icon: "number", iconColor: .gray)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // SHARED EXPENSE
                    splitSection

                    // WHO OWES WHOM (per person, with settlements)
                    let debts = DebtLedger.debts(for: expense)
                    if !debts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHO OWES WHOM")
                                .font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1.0)
                                .padding(.horizontal, 4)
                            ForEach(debts) { debt in
                                DebtCard(debt: debt, person: person(for: debt), context: modelContext)
                            }
                        }
                    }

                    // NOTES SECTION
                    if let notes = expense.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    // ORIGINAL IMAGE (Section 19: when practical)
                    if let imagePath = expense.imageRelativePath,
                       let uiImage = ImageStorageService.shared.loadImage(relativePath: imagePath) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ORIGINAL RECEIPT / SCREENSHOT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    // DELETE BUTTON
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Delete Expense", systemImage: "trash.fill")
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
            .navigationTitle("Expense Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EditExpenseView(expense: expense)
            }
            .sheet(isPresented: $showingSplitEditor) {
                SplitEditorView(totalMinor: expense.amountMinor, currency: expense.currency, merchant: expense.merchant,
                                initial: SplitDraft(expense: expense), editingExpenseID: expense.id) { result in
                    if let result {
                        result.apply(to: expense, in: modelContext)
                    } else {
                        SplitDraft.removeSplit(from: expense, in: modelContext)
                    }
                    try? modelContext.save()
                }
            }
            .alert("Delete Expense?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    HapticFeedback.notification(.warning)
                    modelContext.delete(expense)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this expense of \(expense.formattedAmount)?")
            }
        }
    }

    private func format(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: expense.currency)
    }

    private func person(for debt: Debt) -> PayBookProfile? {
        expense.shares.compactMap(\.person).first { $0.id == debt.personID } ?? (expense.payer?.id == debt.personID ? expense.payer : nil)
    }

    @ViewBuilder
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(expense.isShared ? "SHARED WITH \(expense.shares.count) PEOPLE" : "SHARED EXPENSE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Spacer()
                Button(expense.isShared ? "Edit Split" : "Split with others") {
                    showingSplitEditor = true
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("detail.split")
            }
            .padding(.horizontal, 4)

            if expense.isShared {
                VStack(spacing: 0) {
                    detailRow(title: "Paid by", value: expense.paidByMe ? "Me" : (expense.payer?.name ?? expense.payerNameSnapshot ?? "Someone"),
                              icon: "creditcard.fill", iconColor: .green)
                    ForEach(expense.shares.sorted { ($0.isMe ? 0 : 1, $0.sortIndex) < ($1.isMe ? 0 : 1, $1.sortIndex) }) { share in
                        Divider().padding(.leading, 48)
                        detailRow(title: share.isMe ? "Me" : (share.person?.name ?? share.nameSnapshot),
                                  value: format(share.amountMinor),
                                  icon: share.isMe ? "person.crop.circle.fill" : "person.crop.circle", iconColor: .blue)
                    }
                    if !expense.sharesMatchAmount {
                        Divider().padding(.leading, 48)
                        detailRow(title: "Needs attention", value: "Shares don't add up", icon: "exclamationmark.triangle.fill", iconColor: .orange)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func detailRow(title: String, value: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}


// MARK: - Debt card, payment sheet and settlement history (shared by Expense Details and PayBook)

/// One debt from one transaction: original share, paid, outstanding, status, and the actions that make sense.
struct DebtCard: View {
    let debt: Debt
    let person: PayBookProfile?
    let context: ModelContext
    @State private var showingPayment = false
    @State private var confirmMarkPaid = false
    @State private var errorMessage: String?

    private func format(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: debt.currency)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: debt.isSettled ? "checkmark.circle.fill" : (debt.direction > 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill"))
                    .foregroundStyle(debt.isSettled ? Color.green : (debt.direction > 0 ? Color.blue : Color.orange))
                    .accessibilityHidden(true)
                Text(debt.isSettled ? "Settled with \(debt.personName)" : debt.statusText)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(debt.isSettled ? "Settled" : (debt.isPartiallyPaid ? "Partly paid" : "Outstanding"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((debt.isSettled ? Color.green : Color.orange).opacity(0.15), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            Divider().padding(.leading, 16)
            row(debt.direction > 0 ? "\(debt.personName)'s share" : "Your share (\(debt.personName) paid)", format(debt.originalMinor))
            row("Paid", format(debt.settledMinor))
            row("Outstanding", format(debt.outstandingMinor), bold: true)
            if !debt.isSettled, let person {
                Divider().padding(.leading, 16)
                HStack(spacing: 12) {
                    Button {
                        confirmMarkPaid = true
                    } label: {
                        Label("Mark as Paid", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Mark transaction as paid")
                    .accessibilityIdentifier("debt.markPaid")
                    Button {
                        showingPayment = true
                    } label: {
                        Label("Record Payment", systemImage: "banknote").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Record partial payment")
                    .accessibilityIdentifier("debt.recordPayment")
                }
                .padding(12)
                .confirmationDialog("Mark as paid?", isPresented: $confirmMarkPaid, titleVisibility: .visible) {
                    Button("Mark \(format(debt.outstandingMinor)) as Paid") {
                        do { try SettlementService.markPaid(debt, person: person, in: context) }
                        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't record the payment." }
                    }
                } message: {
                    Text(debt.direction > 0 ? "\(debt.personName) paid you \(format(debt.outstandingMinor)) for \(debt.title). Only this transaction is settled."
                                           : "You paid \(debt.personName) \(format(debt.outstandingMinor)) for \(debt.title). Only this transaction is settled.")
                }
                .sheet(isPresented: $showingPayment) {
                    RecordPaymentSheet(person: person, debts: [debt], direction: debt.direction, currency: debt.currency, context: context)
                }
            }
            SettlementHistoryList(groups: DebtLedger.settlementGroups(personID: debt.personID, expenseID: debt.expenseID, loanID: debt.loanID, in: context),
                                  context: context)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .alert("Couldn't Record Payment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func row(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(bold ? .bold : .medium)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Past settlements with Undo. Undo removes that settlement (and the payment it created); the original
/// transaction is never changed.
struct SettlementHistoryList: View {
    let groups: [DebtLedger.SettlementGroup]
    let context: ModelContext
    @State private var pendingUndo: DebtLedger.SettlementGroup?

    var body: some View {
        if !groups.isEmpty {
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 0) {
                Text("PAYMENTS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 10)
                ForEach(groups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(group)).font(.subheadline)
                            Text(group.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Undo") { pendingUndo = group }
                            .font(.caption.weight(.semibold))
                            .accessibilityLabel("Undo this settlement")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .confirmationDialog("Undo this settlement?", isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }),
                                titleVisibility: .visible, presenting: pendingUndo) { group in
                Button("Undo Settlement", role: .destructive) { try? SettlementService.undo(groupID: group.id, in: context) }
            } message: { _ in
                Text("The amount becomes outstanding again. The original transaction is not changed.")
            }
        }
    }

    private func title(_ group: DebtLedger.SettlementGroup) -> String {
        func f(_ minor: Int) -> String { CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: group.currency) }
        if group.totalMinor == 0 && group.offsetMinor > 0 { return "Offset \(f(group.offsetMinor)) (no money moved)" }
        if let payment = group.payment {
            let verb = group.direction > 0 ? "Received" : "Paid"
            let applied = DebtLedger.allocations(in: context).filter { $0.paymentID == payment.id }.reduce(0) { $0 + $1.amountMinor }
            let credit = payment.amountMinor - applied
            return credit > 0 ? "\(verb) \(f(payment.amountMinor)) · applied \(f(applied)) · \(f(credit)) credit" : "\(verb) \(f(payment.amountMinor))"
        }
        return "Applied \(f(group.totalMinor)) of earlier payments (credit)"
    }
}

/// Record a payment from/to a person: type an amount, then apply it to one or more transactions — automatically
/// (oldest first) or by entering each amount. Shows exactly what will happen before anything is saved.
struct RecordPaymentSheet: View {
    let person: PayBookProfile
    let debts: [Debt]
    let direction: Int
    let currency: String
    let context: ModelContext
    /// Set to apply existing credit instead of recording new money (no amount to type).
    var creditAvailableMinor: Int? = nil
    @Environment(\.dismiss) private var dismiss

    enum Allocation: String, CaseIterable, Identifiable {
        case auto = "Auto Apply", manual = "Choose Amounts"
        var id: String { rawValue }
    }

    @State private var amountText = ""
    @State private var allocation: Allocation = .auto
    @State private var manual: [String: String] = [:]
    @State private var date = Date()
    @State private var errorMessage: String?

    private var open: [Debt] { debts.filter { $0.direction == direction && $0.outstandingMinor > 0 } }
    private var isCredit: Bool { creditAvailableMinor != nil }
    private var amountMinor: Int { creditAvailableMinor ?? (Money.minorUnits(parsing: amountText) ?? 0) }
    private var totalOutstanding: Int { open.reduce(0) { $0 + $1.outstandingMinor } }

    private var plan: [(Debt, Int)] {
        switch allocation {
        case .auto: return SettlementService.autoAllocate(amountMinor: amountMinor, to: open)
        case .manual: return open.map { ($0, Money.minorUnits(parsing: manual[$0.id] ?? "") ?? 0) }.filter { $0.1 > 0 }
        }
    }
    private var appliedMinor: Int { plan.reduce(0) { $0 + $1.1 } }

    private var problem: String? {
        if amountMinor <= 0 { return "Enter the amount paid." }
        if let over = plan.first(where: { $0.1 > $0.0.outstandingMinor }) {
            return "\(format(over.1 - over.0.outstandingMinor)) more than what's left on \(over.0.title) (\(format(over.0.outstandingMinor))). Lower it; any extra stays as credit."
        }
        if appliedMinor > amountMinor {
            return "The amounts applied are \(format(appliedMinor - amountMinor)) more than the \(isCredit ? "credit available" : "payment") (\(format(amountMinor)))."
        }
        if isCredit && appliedMinor == 0 { return "Choose how much credit to apply." }
        return nil
    }

    private func format(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isCredit {
                        HStack {
                            Text("Credit available")
                            Spacer()
                            Text(format(amountMinor)).fontWeight(.semibold)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("payment.amount")
                        DatePicker("Date", selection: $date)
                    }
                } header: {
                    Text(isCredit ? (direction > 0 ? "Earlier payments from \(person.name) not yet applied" : "Earlier payments to \(person.name) not yet applied")
                                  : (direction > 0 ? "\(person.name) paid you" : "You paid \(person.name)"))
                } footer: {
                    Text("Outstanding on the selected transactions: \(format(totalOutstanding))")
                }
                if open.count > 1 {
                    Section {
                        Picker("Apply", selection: $allocation) {
                            ForEach(Allocation.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("payment.allocation")
                    } footer: {
                        Text(allocation == .auto ? "Oldest transactions are paid first." : "Enter how much of the payment goes to each transaction.")
                    }
                }
                Section("What will happen") {
                    ForEach(open) { debt in
                        let applied = plan.first { $0.0.id == debt.id }?.1 ?? 0
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(debt.title).font(.subheadline)
                                Text("\(debt.date.formatted(date: .abbreviated, time: .omitted)) · left \(format(debt.outstandingMinor))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if allocation == .manual && open.count > 1 {
                                TextField("0.00", text: Binding(get: { manual[debt.id] ?? "" }, set: { manual[debt.id] = $0 }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                                    .accessibilityLabel("Amount for \(debt.title)")
                            } else {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(applied > 0 ? "−\(format(applied))" : "—").font(.subheadline.weight(.semibold))
                                    Text("then \(format(debt.outstandingMinor - applied))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack {
                        Text(isCredit ? "Credit applied" : "Applied")
                        Spacer()
                        Text(format(appliedMinor)).fontWeight(.semibold)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("payment.applied")
                    if amountMinor > appliedMinor && problem == nil {
                        HStack {
                            Text(isCredit ? "Credit left" : "Remaining credit")
                            Spacer()
                            Text(format(amountMinor - appliedMinor)).fontWeight(.semibold)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("payment.credit")
                        Text("\(format(amountMinor - appliedMinor)) isn't applied to a transaction. It's kept as credit with \(person.name): it still counts in your balance, and you can apply it later.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem { Text(problem).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("payment.problem") }
                }
            }
            .navigationTitle(isCredit ? "Apply Credit" : (direction > 0 ? "Receive Payment" : "Pay \(person.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(problem != nil)
                        .accessibilityIdentifier("payment.save")
                }
            }
            .alert("Couldn't Record Payment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear {
                if !isCredit, amountText.isEmpty, open.count == 1 {
                    amountText = String(format: "%.2f", Money.majorAmount(fromMinor: open[0].outstandingMinor))
                }
            }
        }
    }

    private func save() {
        do {
            if isCredit {
                try SettlementService.applyCredit(person: person, direction: direction, allocations: plan, currency: currency, in: context)
            } else {
                try SettlementService.recordPayment(person: person, direction: direction, amountMinor: amountMinor, allocations: plan,
                                                    currency: currency, date: date, in: context)
            }
            HapticFeedback.notification(.success)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't record the payment."
        }
    }
}
