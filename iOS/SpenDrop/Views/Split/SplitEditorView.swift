import SwiftUI
import SwiftData

/// "Split with others" as a sheet (expense detail, Paid for Someone). Uses the SAME `InlineSplitSection` as Add /
/// Edit / scan review / Share Extension, so the split behaves identically everywhere. Returns the edited draft through
/// `onDone`, or nil when the user removes the split.
public struct SplitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let totalMinor: Int
    private let currency: String
    private let merchant: String?
    private let editingExpenseID: UUID?
    private let allowsRemove: Bool
    private let onDone: (SplitDraft?) -> Void

    @State private var draft: SplitDraft
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

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if draft.others.isEmpty, draft.purpose == .shared, let lastTime {
                        Button {
                            draft = lastTime
                        } label: {
                            Label("Same as last time: \(lastTime.others.map(\.name).joined(separator: ", "))", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                        }
                    }
                    InlineSplitSection(draft: $draft, totalMinor: totalMinor, currency: currency)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if allowsRemove {
                        Button("Remove Split", role: .destructive) {
                            onDone(nil)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
            .task {
                lastTime = SplitDraft.lastTimeSuggestion(merchant: merchant, excluding: editingExpenseID, in: modelContext)
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
        if draft.usesHybrid {
            if let amounts { return amounts.reduce(0, +) }
            let fixed = draft.groupAllocationMinor + draft.individualAllocationMinor
            let remaining = totalMinor - fixed
            return fixed + (!draft.remainderIDs.isEmpty && remaining > 0 ? remaining : 0)
        }
        if draft.method == .amounts { return draft.assignedMinor(totalMinor: totalMinor) }
        return amounts?.reduce(0, +) ?? 0
    }

    /// Rows shown: everyone (shared), the people I paid for, or just me (someone paid for me).
    private var visibleParticipants: [SplitDraft.Participant] {
        draft.paidForMe ? draft.participants.filter(\.isMe) : (draft.iPaidForOthers ? draft.others : draft.participants)
    }

    /// Amounts + Auto Calculate: the fixed icon is offered (not for Paid for Someone, not when calculating is off).
    private var fixedAvailable: Bool { draft.method == .amounts && draft.autoCalculate && draft.purpose == .shared && !draft.usesHybrid }

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

            Picker("Type", selection: $draft.purpose) {
                Text("Shared Expense").tag(SplitDraft.Purpose.shared)
                Text("Paid for Someone").tag(SplitDraft.Purpose.paidFor)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("split.purpose")

            if draft.purpose == .shared {
                Toggle("Hybrid Split", isOn: Binding(get: { draft.usesHybrid },
                                                     set: { on in withAnimation(.easeInOut(duration: 0.2)) { draft.setHybrid(on) } }))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("split.hybrid")
                    .accessibilityHint("Group fixed amounts, individual fixed amounts, and the rest split equally.")
            }

            if draft.usesHybrid {
                hybridSection
            }

            if draft.purpose == .paidFor {
                Text(draft.paidForMe ? "Someone paid the whole amount for you: it's all your share."
                                     : "You paid the whole amount for the people below. Your share is RM 0.00.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !draft.paidForMe && !draft.usesHybrid {
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
            }

            Text(draft.paidForMe ? "For" : draft.iPaidForOthers ? "Paid for" : draft.usesHybrid ? "FINAL CALCULATION" : "Split between")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(visibleParticipants) { participant in
                    participantRow(participant)
                    Divider()
                }
            }

            if !frequentSuggestions.isEmpty && !draft.paidForMe {
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

            if !draft.paidForMe {
                Button { showingPersonPicker = true } label: {
                    Label("Add Person", systemImage: "person.badge.plus").font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("split.addPerson")
            }

            if draft.method == .amounts && !draft.paidForMe && !draft.usesHybrid {
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

    // MARK: Hybrid Split

    private func displayName(_ participant: SplitDraft.Participant) -> String { participant.isMe ? "You" : participant.name }
    private func idSuffix(_ participant: SplitDraft.Participant) -> String { participant.isMe ? "me" : participant.name }

    /// "RM 50.00 group + RM 20.00 individual + RM 26.66 remaining" (only the parts this person has).
    private func hybridDetail(index: Int) -> String? {
        guard let split = try? draft.hybridSplit(totalMinor: totalMinor).get() else { return nil }
        var parts: [String] = []
        let group = split.groupTotal(for: index)
        if group > 0 { parts.append("\(format(group)) group") }
        if split.individualParts[index] > 0 { parts.append("\(format(split.individualParts[index])) individual") }
        if split.remainingParts[index] > 0 { parts.append("\(format(split.remainingParts[index])) remaining") }
        return parts.isEmpty ? "Not included" : parts.joined(separator: " + ")
    }

    private func checkbox(_ participant: SplitDraft.Participant, selected: Bool, id: String, set: @escaping (Bool) -> Void) -> some View {
        Button { set(!selected) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.blue : Color.secondary)
                Text(displayName(participant)).font(.subheadline).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayName(participant))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func moneyField(_ placeholder: String, text: Binding<String>, id: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(currency).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
        .font(.subheadline)
    }

    private func signed(_ minor: Int) -> String { minor < 0 ? "−\(format(-minor))" : format(minor) }

    @ViewBuilder
    private var hybridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HYBRID SPLIT").font(.caption.weight(.bold)).foregroundStyle(.secondary)

            // 1. Group fixed amounts: each amount is a TOTAL divided equally between its members.
            ForEach(Array(draft.hybridGroups.enumerated()), id: \.element.id) { position, group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(draft.hybridGroups.count > 1 ? "GROUP FIXED AMOUNT \(position + 1)" : "GROUP FIXED AMOUNT")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove", role: .destructive) { withAnimation { draft.removeHybridGroup(group.id) } }
                            .font(.caption)
                            .accessibilityIdentifier("split.group\(position + 1).remove")
                    }
                    HStack {
                        Text("Amount (total for the group)").font(.subheadline)
                        Spacer()
                        moneyField("0.00", text: Binding(get: { group.amountText }, set: { draft.setGroupAmountText($0, for: group.id) }),
                                   id: "split.group\(position + 1).amount", label: "Group \(position + 1) amount, total for the group")
                    }
                    Text("Divide this amount between").font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.participants) { participant in
                        checkbox(participant, selected: group.memberIDs.contains(participant.id),
                                 id: "split.group\(position + 1).member.\(idSuffix(participant))") { on in
                            draft.setGroupMember(on, participant: participant.id, group: group.id)
                        }
                    }
                    let preview = draft.groupPreview(group.id)
                    if !preview.isEmpty {
                        Text(preview.map { "\(displayName($0.participant)) \(format($0.minor))" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("split.group\(position + 1).preview")
                    }
                    HStack {
                        Text("Group allocation").foregroundStyle(.secondary)
                        Spacer()
                        Text(format(SplitDraft.positiveMinor(group.amountText) ?? 0))
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("split.group\(position + 1).allocation")
                }
                Divider()
            }
            Button { withAnimation { draft.addHybridGroup() } } label: {
                Label(draft.hybridGroups.isEmpty ? "Add Group Fixed Amount" : "Add Another Group", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("split.addGroup")
            Divider()

            // 2. Individual fixed amounts: for one person only, never divided.
            Text("INDIVIDUAL FIXED AMOUNTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(draft.hybridIndividuals.enumerated()), id: \.element.id) { position, row in
                let chosen = draft.participants.first { $0.id == row.participantID }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(draft.participants) { participant in
                            Button(displayName(participant)) { draft.setIndividualPerson(participant.id, for: row.id) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(chosen.map(displayName) ?? "Person")
                                .foregroundStyle(chosen == nil ? Color.secondary : Color.primary)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("split.individual\(position + 1).person")
                    Spacer()
                    moneyField("0.00", text: Binding(get: { row.amountText }, set: { draft.setIndividualAmountText($0, for: row.id) }),
                               id: "split.individual\(position + 1).amount", label: "Individual fixed amount \(position + 1)")
                    Button(role: .destructive) { withAnimation { draft.removeIndividual(row.id) } } label: {
                        Text("Remove").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("split.individual\(position + 1).remove")
                }
            }
            Button { withAnimation { draft.addIndividual() } } label: {
                Label("Add Individual Fixed Amount", systemImage: "plus").font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("split.addIndividual")
            HStack {
                Text("Individual allocation").foregroundStyle(.secondary)
                Spacer()
                Text(format(draft.individualAllocationMinor))
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("split.individualAllocation")
            Divider()

            // 3. Remaining amount: split equally.
            let remaining = draft.hybridRemainingMinor(totalMinor: totalMinor)
            HStack {
                Text("REMAINING AMOUNT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(signed(remaining))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(remaining < 0 ? Color.orange : Color.primary)
                    .accessibilityIdentifier("split.hybridRemaining")
            }
            Text("Split remaining between").font(.caption).foregroundStyle(.secondary)
            ForEach(draft.participants) { participant in
                checkbox(participant, selected: draft.remainderIDs.contains(participant.id), id: "split.remaining.\(idSuffix(participant))") { on in
                    draft.setInRemainder(on, participant: participant.id)
                }
            }
            Text("Auto Calculate: ON · split equally").font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }

    @ViewBuilder
    private func participantRow(_ participant: SplitDraft.Participant) -> some View {
        let index = draft.participants.firstIndex(where: { $0.id == participant.id }) ?? 0
        HStack(spacing: 8) {
            Image(systemName: participant.isMe ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(participant.isMe ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(participant.isMe ? "You" : participant.name).font(.subheadline)
                    if (participant.isMe && draft.payer == nil) || (draft.payer != nil && draft.payer?.id == participant.person?.id) {
                        Text("paid").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if fixedAvailable, let fixed = participant.fixedMinor {
                    Text("\(format(fixed)) fixed + equal share").font(.caption2).foregroundStyle(.secondary)
                }
                if draft.usesHybrid, let detail = hybridDetail(index: index) {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("split.finalDetail.\(participant.isMe ? "me" : participant.name)")
                }
            }
            Spacer()
            if draft.paidForMe {
                Text(format(totalMinor)).font(.subheadline).foregroundStyle(.secondary)
            } else if draft.usesHybrid {
                Text(amounts.map { format($0[index]) } ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(amounts == nil ? Color.secondary : Color.primary)
                    .accessibilityIdentifier("split.final.\(participant.isMe ? "me" : participant.name)")
            } else {
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
