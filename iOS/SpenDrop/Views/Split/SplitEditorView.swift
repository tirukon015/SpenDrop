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

            Text(draft.paidForMe ? "For" : draft.iPaidForOthers ? "Paid for" : "Split between")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            if draft.usesHybrid {
                // The per-person amounts live in the Final Calculation card; here only who is in the split.
                FlowLayout(spacing: 6) {
                    ForEach(draft.participants) { participant in
                        Text(displayName(participant))
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("In the split: " + draft.participants.map(displayName).joined(separator: ", "))
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleParticipants) { participant in
                        participantRow(participant)
                        Divider()
                    }
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

            if draft.purpose == .shared {
                Toggle(isOn: Binding(get: { draft.usesHybrid },
                                     set: { on in withAnimation(.easeInOut(duration: 0.2)) { draft.setHybrid(on) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hybrid Split").font(.subheadline.weight(.semibold))
                        Text("Group and individual fixed amounts first, then the rest split equally")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("split.hybrid")
            }

            if draft.usesHybrid {
                hybridSection
            }

            if draft.method == .amounts && !draft.paidForMe && !draft.usesHybrid {
                Toggle("Auto Calculate", isOn: Binding(get: { draft.autoCalculate },
                                                       set: { draft.setAutoCalculate($0, totalMinor: totalMinor) }))
                    .font(.subheadline)
                    .accessibilityIdentifier("split.autoCalculate")
                    .accessibilityHint("When on, the person you haven't typed an amount for gets the rest of the total.")
            }

            if !draft.usesHybrid {
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
            }

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
    private func signed(_ minor: Int) -> String { minor < 0 ? "−\(format(-minor))" : format(minor) }
    /// An amount that never breaks across lines ("RM 50.00" with a no-break space).
    private func unbroken(_ minor: Int) -> String { format(minor).replacingOccurrences(of: " ", with: "\u{00A0}") }

    /// The parts of one person's final amount, e.g. [(5000, "group"), (2000, "individual"), (2666, "remaining")].
    private func hybridParts(index: Int) -> [(minor: Int, kind: String)]? {
        guard let split = try? draft.hybridSplit(totalMinor: totalMinor).get() else { return nil }
        return [(split.groupTotal(for: index), "group"), (split.individualParts[index], "individual"), (split.remainingParts[index], "remaining")]
            .filter { $0.0 > 0 }.map { (minor: $0.0, kind: $0.1) }
    }

    /// Soft rounded card with a numbered step badge, the layer title and its allocation on the right.
    private func layerCard<Content: View>(step: String, title: String, value: String, valueColor: Color = .primary, valueID: String? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Circle().fill(Color.blue))
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .fixedSize()
                    .accessibilityIdentifier(valueID ?? "")
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .separator).opacity(0.35)))
    }

    /// A selectable person pill (checkmark when selected).
    private func pill(_ participant: SplitDraft.Participant, selected: Bool, id: String, set: @escaping (Bool) -> Void) -> some View {
        Button { set(!selected) } label: {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(displayName(participant)).lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.blue : Color(uiColor: .secondarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayName(participant))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func amountField(_ placeholder: String, text: Binding<String>, id: String, label: String) -> some View {
        HStack(spacing: 4) {
            // "RM" never wraps: fixed-size prefix, and the field keeps room for an amount.
            Text(currency).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(minWidth: 72, idealWidth: 96, maxWidth: 120)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
        .font(.subheadline.monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func removeButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func addRowButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() } } label: {
            Label(title, systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var hybridSection: some View {
        let groups = draft.hybridGroups
        let several = groups.count > 1
        VStack(alignment: .leading, spacing: 12) {
            // ① Group fixed amounts: each amount is a TOTAL divided equally between its members.
            layerCard(step: "1", title: several ? "Group Fixed Amounts" : "Group Fixed Amount", value: format(draft.groupAllocationMinor),
                      valueID: "split.groupAllocation") {
                ForEach(Array(groups.enumerated()), id: \.element.id) { position, group in
                    VStack(alignment: .leading, spacing: 8) {
                        if position > 0 { Divider() }
                        HStack(spacing: 8) {
                            Text(several ? "Group \(position + 1) total" : "Total for the group").font(.subheadline)
                                .lineLimit(2).minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            amountField("0.00", text: Binding(get: { group.amountText }, set: { draft.setGroupAmountText($0, for: group.id) }),
                                        id: "split.group\(position + 1).amount", label: "Group \(position + 1) total")
                            if several {
                                removeButton("Remove group \(position + 1)", id: "split.group\(position + 1).remove") {
                                    withAnimation { draft.removeHybridGroup(group.id) }
                                }
                            }
                        }
                        Text("Divide this amount between").font(.caption).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(draft.participants) { participant in
                                pill(participant, selected: group.memberIDs.contains(participant.id),
                                     id: "split.group\(position + 1).member.\(idSuffix(participant))") { on in
                                    draft.setGroupMember(on, participant: participant.id, group: group.id)
                                }
                            }
                        }
                        let preview = draft.groupPreview(group.id)
                        if !preview.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(preview, id: \.participant.id) { line in
                                    HStack {
                                        Text(displayName(line.participant))
                                        Spacer()
                                        Text(unbroken(line.minor)).monospacedDigit()
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(preview.map { "\(displayName($0.participant)) \(format($0.minor))" }.joined(separator: " · "))
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityIdentifier("split.group\(position + 1).preview")
                        }
                    }
                }
                addRowButton(groups.isEmpty ? "Add Group Fixed Amount" : "Add Another Group", id: "split.addGroup") { draft.addHybridGroup() }
            }

            // ② Individual fixed amounts: for one person only, never divided.
            layerCard(step: "2", title: "Individual Fixed Amounts", value: format(draft.individualAllocationMinor),
                      valueID: "split.individualAllocation") {
                if draft.hybridIndividuals.isEmpty {
                    Text("An extra amount for one person only, on top of any group amount.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(chosen == nil ? Color.secondary : Color.primary)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator)))
                        }
                        .layoutPriority(0)
                        .frame(minWidth: 60)
                        .accessibilityLabel(chosen.map(displayName) ?? "Person")
                        .accessibilityIdentifier("split.individual\(position + 1).person")
                        amountField("0.00", text: Binding(get: { row.amountText }, set: { draft.setIndividualAmountText($0, for: row.id) }),
                                    id: "split.individual\(position + 1).amount", label: "Individual fixed amount \(position + 1)")
                        removeButton("Remove individual fixed amount \(position + 1)", id: "split.individual\(position + 1).remove") {
                            withAnimation { draft.removeIndividual(row.id) }
                        }
                    }
                }
                addRowButton("Add Individual Fixed Amount", id: "split.addIndividual") { draft.addIndividual() }
            }

            // ③ Remaining amount: split equally.
            let remaining = draft.hybridRemainingMinor(totalMinor: totalMinor)
            let fixed = draft.groupAllocationMinor + draft.individualAllocationMinor
            layerCard(step: "3", title: "Remaining Amount", value: signed(remaining), valueColor: remaining < 0 ? .orange : .primary,
                      valueID: "split.hybridRemaining") {
                Text("\(unbroken(totalMinor)) total − \(unbroken(fixed)) fixed")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("\(format(totalMinor)) total minus \(format(fixed)) fixed")
                Text("Split remaining between").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(draft.participants) { participant in
                        pill(participant, selected: draft.remainderIDs.contains(participant.id), id: "split.remaining.\(idSuffix(participant))") { on in
                            draft.setInRemainder(on, participant: participant.id)
                        }
                    }
                }
                Text("Auto Calculate: ON · split equally").font(.footnote).foregroundStyle(.secondary)
            }

            // ✓ Final calculation: one row per person, then the totals.
            let amounts = self.amounts
            layerCard(step: "✓", title: "Final Calculation", value: format(totalMinor)) {
                VStack(spacing: 0) {
                    ForEach(Array(draft.participants.enumerated()), id: \.element.id) { index, participant in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(participant)).font(.subheadline)
                                if let parts = hybridParts(index: index) {
                                    let plain = parts.isEmpty ? "Not included" : parts.map { "\(format($0.minor)) \($0.kind)" }.joined(separator: " + ")
                                    Text(parts.isEmpty ? "Not included" : parts.map { "\(unbroken($0.minor))\u{00A0}\($0.kind)" }.joined(separator: " +\u{00A0}"))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityLabel(plain)
                                        .accessibilityIdentifier("split.finalDetail.\(idSuffix(participant))")
                                }
                            }
                            Spacer(minLength: 8)
                            Text(amounts.map { format($0[index]) } ?? "—")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(amounts == nil ? Color.secondary : Color.primary)
                                .fixedSize()
                                .accessibilityIdentifier("split.final.\(idSuffix(participant))")
                            if participant.isMe {
                                Image(systemName: "xmark.circle.fill").font(.body).hidden().accessibilityHidden(true)
                            } else {
                                removeButton("Remove \(participant.name)", id: "split.finalRemove.\(participant.name)") {
                                    withAnimation { draft.remove(id: participant.id) }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        if index < draft.participants.count - 1 { Divider() }
                    }
                }
                Divider()
                HStack {
                    Text("Total allocated").foregroundStyle(.secondary)
                    Spacer()
                    Text(format(allocatedMinor)).monospacedDigit()
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                let left = totalMinor - allocatedMinor
                HStack {
                    Text("Remaining").foregroundStyle(.secondary)
                    Spacer()
                    Text(signed(left))
                        .fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(left == 0 ? Color.green : Color.orange)
                        .accessibilityIdentifier("split.remaining")
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
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
            }
            Spacer()
            if draft.paidForMe {
                Text(format(totalMinor)).font(.subheadline).foregroundStyle(.secondary)
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

/// Lays out pills left to right and wraps onto new lines (works at any width and Dynamic Type size).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + itemWidth > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
