import SwiftUI
import SwiftData

public struct PayBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name, order: .forward) private var allProfiles: [PayBookProfile]

    @State private var searchText: String = ""
    @State private var showingAddProfileSheet: Bool = {
        ProcessInfo.processInfo.arguments.contains("--open-add")
    }()
    @State private var autoSelectedProfile: PayBookProfile?
    @State private var profileToDelete: PayBookProfile?
    @State private var showingDeleteAlert: Bool = false
    @State private var showingArchived: Bool = false
    @State private var blockedDeleteProfile: PayBookProfile?
    /// They Owe Me by default; All shows everyone (including settled people) grouped as before.
    @State private var balanceFilter: PayBookBalanceFilter = .theyOweMe
    // Balances are calculated from these; observing them keeps the lists current when anything changes.
    @Query private var expenses: [Expense]
    @Query private var movements: [MoneyMovement]
    @Query private var shares: [ExpenseShare]

    public init() {}

    private var filteredProfiles: [PayBookProfile] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else {
            return allProfiles
        }
        return allProfiles.filter { profile in
            if profile.name.lowercased().contains(term) {
                return true
            }
            // Also search child payment methods (provider, account, label)
            return profile.paymentMethods.contains { method in
                method.displayProvider.lowercased().contains(term) ||
                method.accountIdentifier.contains(term) ||
                (method.label?.lowercased().contains(term) == true)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if allProfiles.isEmpty {
                    emptyState(
                        icon: "person.crop.rectangle.stack",
                        title: "Your Paybook is empty",
                        message: "Save people and their payment details so you can quickly reuse them later."
                    )
                } else if filteredProfiles.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No matching profiles",
                        message: "No person or account found matching '\(searchText)'."
                    )
                } else {
                    List {
                        let _ = (expenses.count, movements.count, shares.count)
                        if searchText.isEmpty {
                            Section {
                                Picker("Show", selection: $balanceFilter) {
                                    ForEach(PayBookBalanceFilter.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("paybook.filter")
                            }
                        }

                        // SUMMARY (only when someone owes money or has history)
                        let summary = PersonLedger.summary(of: allProfiles)
                        if !summary.isEmpty && searchText.isEmpty {
                            Section {
                                summaryView(summary)
                            }
                        }

                        if searchText.isEmpty && balanceFilter != .all {
                            outstandingSection(balanceFilter)
                        } else {
                        let groups = PayBookGrouping.groups(filteredProfiles)
                        if !groups.frequent.isEmpty {
                            Section("Frequent") {
                                ForEach(groups.frequent) { profile in profileRow(profile) }
                            }
                        }
                        if !groups.other.isEmpty {
                            Section(groups.frequent.isEmpty ? "People" : "Other People") {
                                ForEach(groups.other) { profile in profileRow(profile) }
                            }
                        }
                        if !groups.archived.isEmpty {
                            Section {
                                if showingArchived {
                                    ForEach(groups.archived) { profile in profileRow(profile) }
                                }
                            } header: {
                                Button(showingArchived ? "Hide Archived (\(groups.archived.count))" : "Show Archived (\(groups.archived.count))") {
                                    showingArchived.toggle()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Paybook")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people, banks, accounts...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddProfileSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(isPresented: $showingAddProfileSheet) {
                AddPayBookProfileView()
            }
            .navigationDestination(item: $autoSelectedProfile) { profile in
                PayBookDetailView(profile: profile)
            }
            .task {
                if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--open-detail"),
                   idx + 1 < ProcessInfo.processInfo.arguments.count {
                    let targetName = ProcessInfo.processInfo.arguments[idx + 1]
                    if let match = allProfiles.first(where: { $0.name.lowercased() == targetName.lowercased() }) {
                        autoSelectedProfile = match
                    }
                }
            }
            .alert("\(blockedDeleteProfile?.name ?? "This person") still has a balance",
                   isPresented: Binding(get: { blockedDeleteProfile != nil }, set: { if !$0 { blockedDeleteProfile = nil } })) {
                Button("Archive Instead") {
                    blockedDeleteProfile?.isArchived = true
                    try? modelContext.save()
                    blockedDeleteProfile = nil
                }
                Button("Cancel", role: .cancel) { blockedDeleteProfile = nil }
            } message: {
                Text("Settle up first, or archive to hide them while keeping the balance and history.")
            }
            .alert("Delete \(profileToDelete?.name ?? "Profile")?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let profile = profileToDelete {
                        HapticFeedback.notification(.warning)
                        modelContext.delete(profile)
                        try? modelContext.save()
                    }
                    profileToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    profileToDelete = nil
                }
            } message: {
                if let profile = profileToDelete {
                    Text("This removes \(profile.name) and their saved payment methods. Past shared expenses and money records are kept under their saved name.")
                }
            }
        }
    }

    // MARK: - They Owe Me / I Owe Them

    /// People who currently owe me (or whom I owe), largest amount first, from the canonical net balance.
    @ViewBuilder
    private func outstandingSection(_ filter: PayBookBalanceFilter) -> some View {
        let rows = PersonLedger.outstanding(allProfiles, filter: filter)
        let totals = Dictionary(grouping: rows, by: \.currency).mapValues { $0.reduce(0) { $0 + $1.amountMinor } }
        let totalText = totals.sorted { $0.key < $1.key }.map { PersonLedger.format($0.value, $0.key) }
        Section {
            if rows.isEmpty {
                Text(filter == .theyOweMe ? "Nobody owes you money right now." : "You don't owe anyone right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paybook.emptyOutstanding")
            } else {
                ForEach(rows) { row in profileRow(row.person) }
            }
        } header: {
            HStack {
                Text(filter.title)
                Spacer()
                if !totalText.isEmpty {
                    Text(totalText.joined(separator: " + "))
                        .accessibilityLabel("Total \(totalText.joined(separator: " and "))")
                }
            }
        }
    }

    // MARK: - Rows & summary (Phase 5)

    private func profileRow(_ profile: PayBookProfile) -> some View {
        NavigationLink(destination: PayBookDetailView(profile: profile)) {
            HStack(spacing: 14) {
                avatarView(profile: profile, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if profile.isArchived {
                            Text("Archived").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(profile.paymentMethodCountText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !profile.paymentMethods.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(profile.providersSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)

                Spacer()

                balanceBadge(profile)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if PersonLedger.canDelete(profile) {
                    profileToDelete = profile
                    showingDeleteAlert = true
                } else {
                    blockedDeleteProfile = profile
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                profile.isArchived.toggle()
                try? modelContext.save()
            } label: {
                Label(profile.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }

    @ViewBuilder
    private func balanceBadge(_ profile: PayBookProfile) -> some View {
        let balances = PersonLedger.balances(for: profile)
        if let first = balances.sorted(by: { $0.key < $1.key }).first {
            let currency = first.key, value = first.value
            VStack(alignment: .trailing, spacing: 1) {
                Text(value > 0 ? "owes you" : "you owe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(PersonLedger.format(abs(value), currency) + (balances.count > 1 ? " +" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(value > 0 ? .green : .orange)
            }
        }
    }

    private func summaryView(_ summary: PersonLedger.Summary) -> some View {
        HStack(spacing: 12) {
            summaryColumn("Owed to you", summary.owedToMe, count: summary.owingMeCount, color: .green)
            summaryColumn("You owe", summary.iOwe, count: summary.iOweCount, color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Settled").font(.caption2).foregroundStyle(.secondary)
                Text("\(summary.settledCount)").font(.subheadline.weight(.semibold))
                Text("people").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func summaryColumn(_ title: String, _ totals: [String: Int], count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(totals.isEmpty ? PersonLedger.format(0, "RM")
                 : totals.sorted { $0.key < $1.key }.map { PersonLedger.format($0.value, $0.key) }.joined(separator: "\n"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(totals.isEmpty ? .secondary : color)
            Text("\(count) \(count == 1 ? "person" : "people")").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatarView(profile: PayBookProfile, size: CGFloat) -> some View {
        ZStack {
            if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(Color.blue)
                    )
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if allProfiles.isEmpty {
                Button(action: {
                    showingAddProfileSheet = true
                }) {
                    Label("Add Person", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
