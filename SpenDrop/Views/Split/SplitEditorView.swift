import SwiftUI
import SwiftData

/// "Split with others": who shared the expense, how it is divided, and who paid.
/// Returns the edited draft through `onDone`, or nil when the user removes the split.
public struct SplitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name) private var people: [PayBookProfile]

    private let totalMinor: Int
    private let currency: String
    private let merchant: String?
    private let editingExpenseID: UUID?
    private let allowsRemove: Bool
    private let onDone: (SplitDraft?) -> Void

    @State private var draft: SplitDraft
    @State private var showingPersonPicker = false
    @State private var showingPayerPicker = false
    @State private var lastTime: SplitDraft?

    public init(totalMinor: Int, currency: String = "RM", merchant: String?, initial: SplitDraft?, editingExpenseID: UUID? = nil,
                onDone: @escaping (SplitDraft?) -> Void) {
        self.totalMinor = totalMinor
        self.currency = currency
        self.merchant = merchant
        self.editingExpenseID = editingExpenseID
        self.allowsRemove = initial != nil
        self.onDone = onDone
        _draft = State(initialValue: initial ?? SplitDraft())
    }

    private var frequentSuggestions: [PayBookProfile] {
        people.filter { $0.isFrequent && !$0.isArchived && !draft.contains($0) }
    }

    private var amounts: [Int]? { draft.shares(totalMinor: totalMinor) }

    private func format(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(format(totalMinor)).fontWeight(.semibold)
                    }
                    Picker("Split", selection: $draft.method) {
                        Text("Equally").tag(SplitMethod.equal)
                        Text("Parts").tag(SplitMethod.parts)
                        Text("Amounts").tag(SplitMethod.amounts)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("split.method")
                }

                if draft.others.isEmpty, let lastTime {
                    Section {
                        Button {
                            draft = lastTime
                        } label: {
                            Label("Same as last time: \(lastTime.others.map(\.name).joined(separator: ", "))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }

                Section {
                    ForEach(draft.participants) { participant in
                        participantRow(participant)
                            .deleteDisabled(participant.isMe)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { draft.participants[$0].id }
                        ids.forEach { draft.remove(id: $0) }
                    }

                    if !frequentSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(frequentSuggestions) { person in
                                    Button {
                                        draft.add(person)
                                    } label: {
                                        Label(person.name, systemImage: "plus")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button {
                        showingPersonPicker = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("split.addPerson")
                } header: {
                    Text("People")
                } footer: {
                    if let problem = draft.problem(totalMinor: totalMinor) {
                        Text(problem).foregroundStyle(.orange)
                    } else if let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        Text("✓ Balanced · Your share \(format(mine))")
                    }
                }

                Section {
                    Menu {
                        Button("Me") { draft.payer = nil }
                        ForEach(draft.others.compactMap(\.person)) { person in
                            Button(person.name) { draft.payer = person }
                        }
                        Button("Someone else…") { showingPayerPicker = true }
                    } label: {
                        HStack {
                            Text("Paid by").foregroundStyle(.primary)
                            Spacer()
                            Text(draft.payer?.name ?? "Me").foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("split.paidBy")
                } footer: {
                    if let payer = draft.payer, let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        Text("You spent \(format(mine)) and owe \(payer.name) \(format(mine)). Nothing left your account.")
                    } else if let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        Text("You paid \(format(totalMinor)). Others owe you \(format(totalMinor - mine)).")
                    }
                }

                if allowsRemove {
                    Section {
                        Button("Remove Split", role: .destructive) {
                            onDone(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Split with Others")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid(totalMinor: totalMinor))
                    .accessibilityIdentifier("split.done")
                }
            }
            .sheet(isPresented: $showingPersonPicker) {
                PayBookPickerSheet(mode: .selectPerson, onSelectPerson: { person in
                    draft.add(person)
                })
            }
            .sheet(isPresented: $showingPayerPicker) {
                PayBookPickerSheet(mode: .selectPerson, onSelectPerson: { person in
                    draft.payer = person
                })
            }
            .task {
                lastTime = SplitDraft.lastTimeSuggestion(merchant: merchant, excluding: editingExpenseID, in: modelContext)
            }
        }
    }

    @ViewBuilder
    private func participantRow(_ participant: SplitDraft.Participant) -> some View {
        let index = draft.participants.firstIndex(where: { $0.id == participant.id }) ?? 0
        HStack {
            Image(systemName: participant.isMe ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(participant.isMe ? .blue : .secondary)
            Text(participant.name)
            if draft.payer?.id != nil && draft.payer?.id == participant.person?.id {
                Text("paid").font(.caption2).foregroundStyle(.secondary)
            } else if participant.isMe && draft.payer == nil {
                Text("paid").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            switch draft.method {
            case .equal:
                Text(amounts.map { format($0[index]) } ?? "—").foregroundStyle(.secondary)
            case .parts:
                Stepper(value: Binding(get: { participant.parts }, set: { draft.setParts($0, for: participant.id) }),
                        in: 1...SplitCalculator.maxParts) {
                    Text("\(participant.parts) × · \(amounts.map { format($0[index]) } ?? "—")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize()
            case .amounts:
                TextField("0.00", text: Binding(get: { participant.amountText }, set: { draft.setAmountText($0, for: participant.id) }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
        }
    }
}

/// Collapsed "Split with others" row used by Add Expense, Edit Expense and Expense Detail.
public struct SplitSummaryRow: View {
    let draft: SplitDraft?
    let totalMinor: Int
    let currency: String

