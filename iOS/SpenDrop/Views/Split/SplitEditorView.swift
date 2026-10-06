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
                purpose: SplitDraft.Purpose? = nil, onDone: @escaping (SplitDraft?) -> Void) {
        self.totalMinor = totalMinor
        self.currency = currency
        self.merchant = merchant
        self.editingExpenseID = editingExpenseID
        self.allowsRemove = initial != nil
        self.onDone = onDone
        var start = initial ?? SplitDraft()
        if let purpose { start.purpose = purpose }
        _draft = State(initialValue: start)
    }

    /// Rows shown under People: everyone (shared), the people I paid for, or just me (someone paid for me).
    private var visibleParticipants: [SplitDraft.Participant] {
        draft.paidForMe ? draft.participants.filter(\.isMe) : (draft.iPaidForOthers ? draft.others : draft.participants)
    }

    /// "Bijoy owes you RM 70.00" lines for the preview.
    private var debtPreview: [String] {
        guard let amounts else { return [] }
        if let payer = draft.payer {
            let mine = draft.paidForMe ? totalMinor : (draft.participants.firstIndex(where: \.isMe).map { amounts[$0] } ?? 0)
            return mine > 0 ? ["You owe \(payer.name) \(format(mine))"] : []
        }
        return draft.participants.enumerated().compactMap { index, p in
            guard !p.isMe, amounts[index] > 0 else { return nil }
            return "\(p.name) owes you \(format(amounts[index]))"
        }
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
                    Picker("Type", selection: $draft.purpose) {
                        Text("Shared Expense").tag(SplitDraft.Purpose.shared)
                        Text("Paid for Someone").tag(SplitDraft.Purpose.paidFor)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("split.purpose")
                    if !draft.paidForMe {
                        Picker("Split", selection: $draft.method) {
                            Text("Equally").tag(SplitMethod.equal)
                            Text("Parts").tag(SplitMethod.parts)
                            Text("Amounts").tag(SplitMethod.amounts)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("split.method")
                    }
                    if draft.method == .amounts && !draft.paidForMe {
                        Toggle("Auto Calculate", isOn: Binding(get: { draft.autoCalculate },
                                                               set: { draft.setAutoCalculate($0, totalMinor: totalMinor) }))
                            .accessibilityIdentifier("split.autoCalculate")
                            .accessibilityHint("When on, the person you haven't typed an amount for gets the rest of the total.")
                        HStack {
                            Text("Assigned")
                            Spacer()
                            Text(format(draft.assignedMinor(totalMinor: totalMinor))).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        HStack {
                            Text("Remaining")
                            Spacer()
                            let remaining = draft.remainingMinor(totalMinor: totalMinor)
                            Text(remaining < 0 ? "−\(format(-remaining))" : format(remaining))
                                .foregroundStyle(remaining == 0 ? Color.secondary : Color.orange)
                                .accessibilityIdentifier("split.remaining")
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    if draft.purpose == .paidFor {
                        Text(draft.paidForMe ? "Someone paid the whole amount for you: it's all your share."
                                             : "You paid the whole amount for the people below. Your share is RM 0.00.")
                    }
                }

                if draft.others.isEmpty, draft.purpose == .shared, let lastTime {
                    Section {
                        Button {
                            draft = lastTime
                        } label: {
                            Label("Same as last time: \(lastTime.others.map(\.name).joined(separator: ", "))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }

                Section {
                    ForEach(visibleParticipants) { participant in
                        participantRow(participant)
                            .deleteDisabled(participant.isMe)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { visibleParticipants[$0].id }
                        ids.forEach { draft.remove(id: $0) }
                    }

                    if !frequentSuggestions.isEmpty && !draft.paidForMe {
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

                    if !draft.paidForMe {
                        Button {
                            showingPersonPicker = true
                        } label: {
                            Label("Add Person", systemImage: "person.badge.plus")
                        }
                        .accessibilityIdentifier("split.addPerson")
                    }
                } header: {
                    Text(draft.paidForMe ? "For" : (draft.iPaidForOthers ? "Paid for" : "People"))
                } footer: {
                    if let problem = draft.problem(totalMinor: totalMinor) {
                        Text(problem).foregroundStyle(.orange).accessibilityIdentifier("split.problem")
                    } else if let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✓ Balanced · Your share \(format(mine))")
                            ForEach(debtPreview, id: \.self) { Text($0).fontWeight(.semibold) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("split.preview")
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
                        Text("\(payer.name) paid. You owe \(payer.name) \(format(mine)). Nothing left your account.")
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
            .navigationTitle(draft.purpose == .paidFor ? "Paid for Someone" : "Split with Others")
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
            case _ where draft.paidForMe:
                Text(format(totalMinor)).foregroundStyle(.secondary)
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
                if draft.paidForMe {
                    Text(format(totalMinor)).foregroundStyle(.secondary)
                } else {
                    TextField(draft.isCalculated(participant.id) ? draft.displayAmountText(for: participant.id, totalMinor: totalMinor) : "0.00",
                              text: Binding(get: { draft.isCalculated(participant.id) ? "" : participant.amountText },
                                            set: { draft.setAmountText($0, for: participant.id, totalMinor: totalMinor) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityLabel("\(participant.name)'s amount")
                        .accessibilityIdentifier("split.amount.\(participant.isMe ? "me" : participant.name)")
                }
            }
        }
    }
}

/// Collapsed "Split with others" row used by Add Expense, Edit Expense and Expense Detail.
public struct SplitSummaryRow: View {
    let draft: SplitDraft?
    let totalMinor: Int
    let currency: String

    public init(draft: SplitDraft?, totalMinor: Int, currency: String = "RM") {
        self.draft = draft
        self.totalMinor = totalMinor
        self.currency = currency
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft == nil ? "Split with others" : (draft!.paidForMe ? "Paid for you by \(draft!.payer?.name ?? "someone")"
                     : draft!.iPaidForOthers ? "Paid for \(draft!.others.map(\.name).joined(separator: ", "))"
                     : "Shared · \(draft!.participants.count) people"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let draft {
                    if let problem = draft.problem(totalMinor: totalMinor) {
                        Text(problem).font(.caption).foregroundStyle(.orange)
                    } else if let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        Text("Your share \(CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: mine), currency: currency)) · Paid by \(draft.payer?.name ?? "Me")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Optional").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// "Split Transaction" shown directly inside Add / Edit Expense (no separate screen): who shares the amount,
/// Split Equally or Custom Amount, Total allocated / Remaining, who paid, and what everyone will owe in PayBook.
/// Edits a `SplitDraft`; saving is the parent form's job (it stays disabled while the split doesn't add up).
public struct InlineSplitSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name) private var people: [PayBookProfile]

    @Binding var draft: SplitDraft
    let totalMinor: Int
    let currency: String

    @State private var showingPersonPicker = false
    @State private var showingPayerPicker = false
    /// The person whose fixed amount is being edited (small sheet).
    @State private var fixedEditing: SplitDraft.Participant?

    public init(draft: Binding<SplitDraft>, totalMinor: Int, currency: String = "RM") {
        _draft = draft
        self.totalMinor = totalMinor
        self.currency = currency
    }

    private var amounts: [Int]? { draft.shares(totalMinor: totalMinor) }

    private var allocatedMinor: Int {
        if draft.method == .amounts { return draft.assignedMinor(totalMinor: totalMinor) }
        return amounts?.reduce(0, +) ?? 0
    }

    /// Amounts + Auto Calculate: the fixed icon is offered (not for Paid for Someone, not when calculating is off).
    private var fixedAvailable: Bool { draft.method == .amounts && draft.autoCalculate && draft.purpose == .shared }

    private var frequentSuggestions: [PayBookProfile] {
        people.filter { $0.isFrequent && !$0.isArchived && !draft.contains($0) }
    }

    private func format(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
    }

    /// "Bijoy owes you RM 30.00" / "You owe Bijoy RM 70.00" — what PayBook will show after saving.
    private var paybookPreview: [String] {
        guard let amounts else { return [] }
        if let payer = draft.payer {
            let mine = draft.participants.firstIndex(where: \.isMe).map { amounts[$0] } ?? 0
            return mine > 0 ? ["You owe \(payer.name) \(format(mine))"] : []
        }
        return draft.participants.enumerated().compactMap { index, p in
            guard !p.isMe, amounts[index] > 0 else { return nil }
            return "\(p.name) owes you \(format(amounts[index]))"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total").foregroundStyle(.secondary)
                Spacer()
                Text(format(totalMinor)).fontWeight(.semibold)
            }
            .font(.subheadline)

            Picker("Split", selection: Binding(get: { draft.method }, set: { method in
                switch method {
                case .amounts: draft.useCustomAmounts(totalMinor: totalMinor)
                case .equal: draft.useEqualSplit()
                case .parts: draft.method = .parts
                }
            })) {
                Text("Split Equally").tag(SplitMethod.equal)
                Text("Custom Amount").tag(SplitMethod.amounts)
                if draft.method == .parts { Text("Parts").tag(SplitMethod.parts) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("split.method")

            Text("Split between").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(draft.participants) { participant in
                    participantRow(participant)
                    Divider()
                }
            }

            if !frequentSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentSuggestions) { person in
                            Button { draft.add(person) } label: {
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

            Button { showingPersonPicker = true } label: {
                Label("Add Person", systemImage: "person.badge.plus").font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("split.addPerson")

            if draft.method == .amounts {
                Toggle("Auto Calculate", isOn: Binding(get: { draft.autoCalculate },
                                                       set: { draft.setAutoCalculate($0, totalMinor: totalMinor) }))
                    .font(.subheadline)
                    .accessibilityIdentifier("split.autoCalculate")
                    .accessibilityHint("When on, the person you haven't typed an amount for gets the rest of the total.")
            }

            Divider()
            if fixedAvailable && draft.fixedTotalMinor > 0 {
                HStack {
                    Text("Fixed").foregroundStyle(.secondary)
                    Spacer()
                    Text(format(draft.fixedTotalMinor))
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("split.fixedTotal")
                let typedMinor = draft.sharingParticipants.filter { !draft.isCalculated($0.id) }
                    .reduce(0) { $0 + (Money.minorUnits(parsing: $1.amountText) ?? 0) }
                HStack {
                    Text("Shared equally").foregroundStyle(.secondary)
                    Spacer()
                    Text(format(max(0, totalMinor - draft.fixedTotalMinor - typedMinor)))
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("split.sharedRemainder")
            }
            HStack {
                Text("Total allocated").foregroundStyle(.secondary)
                Spacer()
                Text(format(allocatedMinor))
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
            HStack {
                let remaining = totalMinor - allocatedMinor
                Text("Remaining").foregroundStyle(.secondary)
                Spacer()
                Text(remaining < 0 ? "−\(format(-remaining))" : format(remaining))
                    .fontWeight(.semibold)
                    .foregroundStyle(remaining == 0 ? Color.green : Color.orange)
                    .accessibilityIdentifier("split.remaining")
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)

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
                .font(.subheadline)
            }
            .accessibilityIdentifier("split.paidBy")

            if let problem = draft.problem(totalMinor: totalMinor) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("split.problem")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if let mine = draft.myShareMinor(totalMinor: totalMinor) {
                        Text("✓ Balanced · Your share \(format(mine))").foregroundStyle(.secondary)
                    }
                    ForEach(paybookPreview, id: \.self) { Text($0).fontWeight(.semibold) }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("split.preview")
            }
        }
        .sheet(isPresented: $showingPersonPicker) {
            PayBookPickerSheet(mode: .selectPerson, onSelectPerson: { person in draft.add(person) })
        }
        .sheet(isPresented: $showingPayerPicker) {
            PayBookPickerSheet(mode: .selectPerson, onSelectPerson: { person in draft.payer = person })
        }
        .sheet(item: $fixedEditing) { participant in
            FixedAmountSheet(name: participant.isMe ? "You" : participant.name, currentMinor: participant.fixedMinor) { minor in
                draft.setFixed(minor, for: participant.id, totalMinor: totalMinor)
            }
            .presentationDetents([.height(260)])
        }
    }

    @ViewBuilder
    private func participantRow(_ participant: SplitDraft.Participant) -> some View {
        let index = draft.participants.firstIndex(where: { $0.id == participant.id }) ?? 0
        HStack(spacing: 8) {
            Image(systemName: participant.isMe ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(participant.isMe ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(participant.isMe ? "You" : participant.name).font(.subheadline)
                if fixedAvailable, let fixed = participant.fixedMinor {
                    Text("\(format(fixed)) fixed + equal share").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch draft.method {
            case .equal:
                Text(amounts.map { format($0[index]) } ?? "—").font(.subheadline).foregroundStyle(.secondary)
            case .parts:
                Stepper(value: Binding(get: { participant.parts }, set: { draft.setParts($0, for: participant.id) }),
                        in: 1...SplitCalculator.maxParts) {
                    Text("\(participant.parts) × · \(amounts.map { format($0[index]) } ?? "—")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize()
            case .amounts:
                if fixedAvailable {
                    Button { fixedEditing = participant } label: {
                        Image(systemName: participant.fixedMinor == nil ? "pin" : "pin.fill")
                            .font(.footnote)
                            .foregroundStyle(participant.fixedMinor == nil ? Color.secondary : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fixed amount for \(participant.isMe ? "you" : participant.name)")
                    .accessibilityIdentifier("split.fixed.\(participant.isMe ? "me" : participant.name)")
                }
                // Calculated amounts are shown greyed (as the placeholder); typing an amount sets it exactly.
                TextField(draft.isCalculated(participant.id) ? draft.displayAmountText(for: participant.id, totalMinor: totalMinor) : "0.00",
                          text: Binding(get: { draft.isCalculated(participant.id) ? "" : participant.amountText },
                                        set: { draft.setAmountText($0, for: participant.id, totalMinor: totalMinor) }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .accessibilityLabel("\(participant.isMe ? "Your" : participant.name + "'s") amount")
                    .accessibilityIdentifier("split.amount.\(participant.isMe ? "me" : participant.name)")
            }
            if !participant.isMe {
                Button { draft.remove(id: participant.id) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(participant.name)")
            }
        }
        .padding(.vertical, 8)
    }
}

/// "Fixed Amount" for one person: a base amount added to their equal part of what's left of the total.
struct FixedAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let currentMinor: Int?
    let onSave: (Int?) -> Void
    @State private var text: String

    init(name: String, currentMinor: Int?, onSave: @escaping (Int?) -> Void) {
        self.name = name
        self.currentMinor = currentMinor
        self.onSave = onSave
        _text = State(initialValue: currentMinor.map { String(format: "%.2f", Money.majorAmount(fromMinor: $0)) } ?? "")
    }

    private var parsed: Int? { Money.minorUnits(parsing: text) }
    private var isValid: Bool { (parsed ?? -1) >= 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Added to \(name == "You" ? "your" : name + "'s") equal share of what's left.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("RM").foregroundStyle(.secondary)
                    TextField("0.00", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("fixed.amount")
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !text.isEmpty && !isValid {
                    Text("Enter an amount of RM 0.00 or more.").font(.caption).foregroundStyle(.orange)
                }
                if currentMinor != nil {
                    Button("Remove Fixed Amount", role: .destructive) { onSave(nil); dismiss() }
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("\(name) · Fixed Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(parsed); dismiss() }
                        .disabled(!isValid)
                        .accessibilityIdentifier("fixed.save")
                }
            }
        }
    }
}
