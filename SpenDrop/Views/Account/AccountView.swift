import SwiftUI
import SwiftData

/// More → Account. Optional sign-in for cloud backup. SpenDrop works fully without it (local-first).
public struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]

    @State private var auth = AuthService.shared
    @State private var cloud = CloudBackupService.shared
    @State private var launcher = SystemWebAuthLauncher()

    @State private var emailMode: EmailAuthView.Mode?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var offerFirstBackup = false
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false

    public init() {}

    public var body: some View {
        List {
            switch auth.state {
            case .notConfigured:
                Section {
                    Label("Cloud backup isn't set up in this build", systemImage: "icloud.slash")
                    Text("Everything works on this iPhone without an account. Your data is backed up locally on the device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Developer: add CloudConfig/SupabaseConfig.plist (see docs/SUPABASE_SETUP.md).")
                }

            case .signedOut(let message):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sign in to enable cloud backup").font(.headline)
                        Text("Your data stays on this iPhone either way. Signing in never replaces or deletes local data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let message {
                            Text(message).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        Label("Continue with Google", systemImage: "g.circle.fill")
                    }
                    .accessibilityIdentifier("account.google")
                    Button {
                        emailMode = .signIn
                    } label: {
                        Label("Sign In with Email", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("account.signIn")
                    Button {
                        emailMode = .create
                    } label: {
                        Label("Create Account", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("account.create")
                }
                .disabled(busy)

            case .signedIn(let user):
                Section("Profile") {
                    row("Name", user.name ?? "—")
                    row("Email", user.email ?? "—")
                    row("Signed in with", user.providerDisplayName)
                    row("Status", "Signed in")
                }
                Section {
                    row("Cloud Backup", cloud.status.title)
                    if case .failed(let reason) = cloud.status {
                        Text(reason).font(.caption).foregroundStyle(.orange)
                    }
                    row("Last Backup", cloud.lastBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    Button(cloud.status.isFailure ? "Retry" : "Backup Now") {
                        Task { await cloud.backupNow(force: true) }
                    }
                    .disabled(cloud.status == .uploading || cloud.status == .restoring)
                    .accessibilityIdentifier("account.backupNow")
                    NavigationLink("Restore from Cloud Backup") {
                        CloudRestoreView(cloud: cloud)
                    }
                } header: {
                    Text("Cloud Backup")
                } footer: {
                    Text("Backups upload automatically after changes when you're online. Local backups on this iPhone continue as before.")
                }
                Section {
                    Button("Sign Out") { confirmSignOut = true }
                } footer: {
                    Text("Signing out stops cloud backup. Local data remains on this iPhone.")
                }
                Section {
                    Button("Delete Cloud Account", role: .destructive) { confirmDeleteAccount = true }
                } footer: {
                    Text("Deletes your SpenDrop account and its cloud backups. It does not delete data on this iPhone — to remove local data, use Settings → Clear All Expenses.")
                }
            }
        }
        .navigationTitle("Account")
        .overlay {
            if busy { ProgressView().controlSize(.large) }
        }
        .sheet(item: $emailMode) { mode in
            EmailAuthView(mode: mode, auth: auth) { signedIn in
                emailMode = nil
                if signedIn { afterSignIn() }
            }
        }
        .alert("Couldn't complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Back up this iPhone's data?", isPresented: $offerFirstBackup) {
            Button("Back Up Now") { Task { await cloud.backupNow(force: true) } }
            Button("Later", role: .cancel) {}
        } message: {
            Text("You have \(expenses.count) expenses on this iPhone. They stay here; this uploads a copy to your account. Nothing on this iPhone is replaced.")
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await auth.signOut(); cloud.refreshStatus() } }
        } message: {
            Text("Local data remains on this iPhone. Cloud backup stops until you sign in again.")
        }
        .confirmationDialog("Delete your cloud account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete Cloud Account", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently deletes your SpenDrop account and all cloud backups. Data on this iPhone is NOT deleted.")
        }
        .onAppear { cloud.refreshStatus() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func signInWithGoogle() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.signInWithGoogle(using: launcher)
            afterSignIn()
        } catch CloudError.cancelled {
            // user closed the sheet
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Never downloads or overwrites anything after sign-in; only offers to back up existing local data.
    private func afterSignIn() {
        cloud.refreshStatus()
        cloud.startAutomaticBackups()
        if !expenses.isEmpty { offerFirstBackup = true }
    }

