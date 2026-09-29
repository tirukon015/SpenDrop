import SwiftUI
import SwiftData

private func formatMinor(_ minor: Int, currency: String) -> String {
    CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
}

/// More → Accounts. Shows RECORDED activity per account. This is not a bank balance.
public struct AccountsView: View {
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \MoneyMovement.date, order: .reverse) private var movements: [MoneyMovement]

    @State private var showingAddAccount = false

    public init() {}

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }
    private var unlinkedMovements: [MoneyMovement] { movements.filter { $0.account == nil && $0.counterAccount == nil } }

    public var body: some View {
        List {
            Section {
                if activeAccounts.isEmpty {
                    Text("No accounts yet. Accounts are created automatically from your expenses, or add one with +.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(activeAccounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountSummaryRow(account: account)
                    }
                }
            } header: {
                Text("My Accounts")
            } footer: {
                Text("Totals are what you have recorded in SpenDrop. They are not your real bank balance.")
            }

            if !unlinkedMovements.isEmpty {
                Section {
                    NavigationLink {
                        UnlinkedMovementsView()
                    } label: {
                        Label("\(unlinkedMovements.count) not linked to an account", systemImage: "tray")
                    }
                }
            }

            if !archivedAccounts.isEmpty {
                Section("Archived") {
                    ForEach(archivedAccounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            AccountSummaryRow(account: account)
                                .opacity(0.6)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAccount = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Account")
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountFormSheet(account: nil)
        }
    }
}

struct AccountSummaryRow: View {
    let account: Account

    var body: some View {
        let activity = FinancialCalculator.accountActivity(for: account)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: account.type.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 22)
                Text(account.name)
                    .font(.headline)
                Spacer()
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                labeled("Recorded In", formatMinor(activity.inMinor, currency: account.currency), color: .green)
                labeled("Recorded Out", formatMinor(activity.outMinor, currency: account.currency), color: .primary)
                labeled("Recorded Net", formatMinor(activity.netMinor, currency: account.currency),
                        color: activity.netMinor < 0 ? .orange : .primary)
            }
        }
        .padding(.vertical, 4)
    }

    private func labeled(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Account detail

/// One account's recorded expenses and money movements, newest first.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let account: Account

    @State private var showingEdit = false
    @State private var selectedExpense: Expense?
    @State private var selectedMovement: MoneyMovement?

    private enum Item: Identifiable {
        case expense(Expense)
        case movement(MoneyMovement, incoming: Bool)

        var id: UUID {
            switch self {
            case .expense(let e): return e.id
            case .movement(let m, _): return m.id
            }
        }

        var date: Date {
            switch self {
            case .expense(let e): return e.date
            case .movement(let m, _): return m.date
            }
        }
    }

    private var items: [Item] {
        let expenses = account.expenses.map { Item.expense($0) }
        let outgoing = account.movements.map { Item.movement($0, incoming: $0.kind.direction == .moneyIn) }
        let incoming = account.incomingTransfers.map { Item.movement($0, incoming: true) }
        return (expenses + outgoing + incoming).sorted { $0.date > $1.date }
    }

    var body: some View {
        let activity = FinancialCalculator.accountActivity(for: account)
        List {
            Section {
                row("Recorded In", formatMinor(activity.inMinor, currency: account.currency))
                row("Recorded Out", formatMinor(activity.outMinor, currency: account.currency))
                row("Recorded Net", formatMinor(activity.netMinor, currency: account.currency))
            } footer: {
                Text("Based only on what is recorded in SpenDrop. This is not your real \(account.name) balance.")
            }

            Section("Recorded Transactions") {
                if items.isEmpty {
                    Text("Nothing recorded for this account yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    switch item {
                    case .expense(let expense):
                        Button { selectedExpense = expense } label: { expenseRow(expense) }
                            .buttonStyle(.plain)
                    case .movement(let movement, let incoming):
                        Button { selectedMovement = movement } label: { movementRow(movement, incoming: incoming) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AccountFormSheet(account: account)
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailView(expense: expense)
        }
        .sheet(item: $selectedMovement) { movement in
            MoneyMovementEditSheet(movement: movement)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant).font(.subheadline.weight(.semibold))
                Text("Expense · \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.paidByMe ? "-\(expense.formattedAmount)" : "Paid by \(expense.payerNameSnapshot ?? "someone")")
                .font(.subheadline.weight(.semibold))
        }
        .contentShape(Rectangle())
    }
}

/// Shared row for a money movement, seen from one account (or from no account).
struct MovementRow: View {
    let movement: MoneyMovement
    let incoming: Bool
    /// Transactions timeline: transfers are shown neutrally ("Not spending") instead of in/out of one account.
    var timelineStyle: Bool = false

    private var isNeutralTransfer: Bool { timelineStyle && movement.kind == .ownTransfer }

    var body: some View {
        HStack {
            Image(systemName: movement.kind == .ownTransfer ? "arrow.left.arrow.right.circle" : (incoming ? "arrow.down.circle" : "arrow.up.right.circle"))
                .foregroundStyle(incoming ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text((isNeutralTransfer ? "" : (incoming ? "+" : "-")) + formatMinor(movement.amountMinor, currency: movement.currency))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isNeutralTransfer ? Color.secondary : (incoming ? Color.green : Color.primary))
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let date = movement.date.formatted(date: .abbreviated, time: .omitted)
        if movement.kind == .ownTransfer {
            return timelineStyle ? "Transfer · Not spending · \(date)" : "\(movement.kind.displayName) · \(date)"
        }
        if timelineStyle, let account = movement.account?.name {
            return "\(movement.kind.displayName) · \(account) · \(date)"
        }
        return "\(movement.kind.displayName) · \(date)"
    }

    private var title: String {
        if movement.kind == .ownTransfer {
            return "\(movement.account?.name ?? "?") → \(movement.counterAccount?.name ?? "?")"
        }
        if let name = movement.person?.name ?? movement.personNameSnapshot {
            return movement.kind.direction == .moneyIn ? "From \(name)" : "To \(name)"
        }
        return movement.note ?? movement.kind.displayName
    }
}

private extension AccountDetailView {
    func movementRow(_ movement: MoneyMovement, incoming: Bool) -> some View {
        MovementRow(movement: movement, incoming: incoming)
    }
}

// MARK: - Records without an account

struct UnlinkedMovementsView: View {
    @Query(sort: \MoneyMovement.date, order: .reverse) private var movements: [MoneyMovement]
    @State private var selectedMovement: MoneyMovement?

    var body: some View {
        List {
            Section {
                ForEach(movements.filter { $0.account == nil && $0.counterAccount == nil }) { movement in
                    Button { selectedMovement = movement } label: {
                        MovementRow(movement: movement, incoming: movement.kind.direction == .moneyIn)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Money In and Money Out records saved without an account. Tap one to edit it or add an account.")
            }
        }
        .navigationTitle("Not Linked")
        .sheet(item: $selectedMovement) { movement in
            MoneyMovementEditSheet(movement: movement)
        }
    }
}

// MARK: - Add / edit / archive an account

struct AccountFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]

    let account: Account?

    @State private var name: String
    @State private var type: AccountType

    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .bank)
    }

    private var validationMessage: String? {
        AccountFormValidation.problem(name: name, editing: account, existing: allAccounts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Maybank)", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                } footer: {
                    if let validationMessage, !name.isEmpty {
                        Text(validationMessage).foregroundStyle(.orange)
                    }
                }

                if let account {
                    Section {
                        Button(account.isArchived ? "Unarchive Account" : "Archive Account") {
                            account.isArchived.toggle()
                            try? modelContext.save()
                            HapticFeedback.notification(.success)
                            dismiss()
                        }
                        .foregroundStyle(account.isArchived ? .blue : .orange)
                    } footer: {
                        Text("Archived accounts are hidden from pickers. Their recorded transactions are kept.")
                    }
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(validationMessage != nil)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account {
            account.name = trimmed
            account.type = type
        } else {
            let nextIndex = (allAccounts.map(\.sortIndex).max() ?? -1) + 1
            modelContext.insert(Account(name: trimmed, type: type, sortIndex: nextIndex))
        }
        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}

/// Pure validation for the account form (tested).
enum AccountFormValidation {
    static func problem(name: String, editing: Account?, existing: [Account]) -> String? {
        guard let key = AccountLinker.normalizedKey(name) else {
            return "Enter a name. \"Unknown\" and \"Other\" can't be used."
        }
        if existing.contains(where: { $0.id != editing?.id && $0.nameKey == key }) {
            return "An account with this name already exists."
        }
        return nil
    }
}

