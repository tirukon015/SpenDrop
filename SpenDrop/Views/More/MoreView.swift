import SwiftUI

/// Home for secondary features. Future modules (Accounts, Data & Backup, Diagnostics…) are added here
/// instead of as new bottom tabs.
public struct MoreView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Account")
                                Text("Optional sign-in for cloud backup")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .accessibilityIdentifier("more.account")
                }

                Section {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accounts")
                                Text("Recorded money in and out per account")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .accessibilityIdentifier("more.accounts")
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Settings")
                                Text("Account, backup & restore, preferences, diagnostics, about")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                    .accessibilityIdentifier("more.settings")
                }
            }
            .navigationTitle("More")
        }
    }
}

