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

