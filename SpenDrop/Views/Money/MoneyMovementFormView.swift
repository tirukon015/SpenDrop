import SwiftUI
import SwiftData

/// Form for Money In / Money Out / Own Transfer. Used inside the Add sheet (new record) and in
/// `MoneyMovementEditSheet` (existing record). A person is only asked for when the type needs one.
public struct MoneyMovementFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortIndex) private var allAccounts: [Account]

    private let entryType: TransactionEntryType
    private let existing: MoneyMovement?
    private let onFinished: () -> Void

    @State private var draft: MoneyMovementDraft
    @State private var showingPersonPicker = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var amountFocused: Bool

    /// New record of the given type.
    public init(entryType: TransactionEntryType, onFinished: @escaping () -> Void) {
        self.entryType = entryType
        self.existing = nil
        self.onFinished = onFinished
        _draft = State(initialValue: MoneyMovementDraft(entryType: entryType))
    }

    /// New record from a prefilled draft (e.g. Record Repayment from PayBook, or a scanned screenshot).
    public init(draft: MoneyMovementDraft, onFinished: @escaping () -> Void) {
        self.entryType = draft.entryType
        self.existing = nil
        self.onFinished = onFinished
        _draft = State(initialValue: draft)
    }

    /// Edit an existing record.
    public init(editing movement: MoneyMovement, onFinished: @escaping () -> Void) {
        self.entryType = TransactionEntryType(kind: movement.kind)
        self.existing = movement
        self.onFinished = onFinished
        _draft = State(initialValue: MoneyMovementDraft(movement: movement))
    }

    /// Active accounts, plus the ones already on this record even if archived since.
    private var selectableAccounts: [Account] {
        allAccounts.filter { !$0.isArchived || $0.id == draft.account?.id || $0.id == draft.counterAccount?.id }
    }

    public var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(draft.currency)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $draft.amountText)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                }
            } header: {
                Text("Amount")
            }

            if draft.entryType != .transfer {
                Section("Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(draft.entryType.kinds) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if draft.kind.requiresPerson {
                Section {
                    Button {
                        showingPersonPicker = true
                    } label: {
                        HStack {
                            Text(draft.kind.direction == .moneyIn ? "From" : "To")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(draft.person?.name ?? "Choose person")
                                .foregroundStyle(draft.person == nil ? .blue : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Person")
                }
            }

            Section {
                if draft.entryType == .transfer {
                    accountPicker(title: "From", selection: $draft.account, allowsNone: false)
                    accountPicker(title: "To", selection: $draft.counterAccount, allowsNone: false)
                } else {
                    accountPicker(title: draft.entryType == .moneyIn ? "Into account" : "From account",
                                  selection: $draft.account, allowsNone: true)
                }
            } header: {
                Text("Account")
            } footer: {
                if selectableAccounts.count < (draft.entryType == .transfer ? 2 : 1) {
                    Text("Add accounts in More → Accounts.")
                } else if draft.entryType == .transfer {
                    Text("Moving money between your own accounts is not spending and does not change your cash flow.")
                }
            }

            Section {
                DatePicker("Date", selection: $draft.date)
                TextField("Note (optional)", text: $draft.note, axis: .vertical)
            }

            Section {
                Button(action: save) {
                    Text(existing == nil ? "Save \(draft.entryType.title)" : "Save Changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!draft.isValid)
            } footer: {
                if let issue = visibleIssue {
                    Text(issue.message)
                        .foregroundStyle(.orange)
                }
            }

            if existing != nil {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Text("Delete")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onChange(of: entryType) { _, newType in
            draft.setEntryType(newType)
        }
        .sheet(isPresented: $showingPersonPicker) {
            PayBookPickerSheet(mode: .selectPerson, onSelectPerson: { person in
                draft.person = person
            })
        }
        .confirmationDialog("Delete this record?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteExisting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from your records and from any account or person it belongs to.")
        }
        .onAppear {
            if existing == nil { amountFocused = true }
        }
    }

    /// Only nag about the amount once something has been typed.
    private var visibleIssue: MoneyMovementDraft.Issue? {
        let issues = draft.issues
        if draft.amountText.isEmpty { return issues.first { $0 != .invalidAmount } }
        return issues.first
    }

