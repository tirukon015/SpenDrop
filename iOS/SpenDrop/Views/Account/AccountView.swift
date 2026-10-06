import SwiftUI
import SwiftData

/// More → Account. Optional sign-in for cloud backup. SpenDrop works fully without it (local-first).
public struct AccountView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var auth = AuthService.shared
    @State private var cloud = CloudBackupService.shared
    @State private var launcher = SystemWebAuthLauncher()

    @State private var emailMode: EmailAuthView.Mode?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmSignOut = false
    @State private var confirmEnableBackup = false
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
                .accessibilityIdentifier("account.profile")
                Section {
                    Toggle("Cloud Backup", isOn: Binding(get: { cloud.cloudBackupEnabled },
                                                         set: { on in
                                                             // Turning on needs explicit consent; turning off is immediate and keeps existing backups.
                                                             if on { confirmEnableBackup = true } else { cloud.disableCloudBackup() }
                                                         }))
                        .accessibilityIdentifier("account.autoBackup")
                    if cloud.cloudBackupEnabled {
                        Toggle("Automatic Daily Backup", isOn: Binding(get: { cloud.dailyBackupEnabled },
                                                                       set: { cloud.dailyBackupEnabled = $0 }))
                            .accessibilityIdentifier("account.dailyBackup")
                        if cloud.dailyBackupEnabled {
                            DatePicker("Backup Time", selection: backupTime, displayedComponents: .hourAndMinute)
                                .accessibilityIdentifier("account.backupTime")
                                .accessibilityHint("Daily backups run around this time. iOS decides the exact moment.")
                        }
                    }
                    row("Status", cloud.status.title)
                    if let progress = cloud.phase.title {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(progress).font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("account.backupProgress")
                    }
                    if let report = cloud.lastReport, cloud.phase == .idle {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.message).font(.subheadline).foregroundStyle(report.succeeded ? Color.primary : Color.orange)
                            Text(report.screenshotSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("account.backupReport")
                    } else if case .failed(let reason) = cloud.status {
                        Text(reason).font(.caption).foregroundStyle(.orange)
                    }
                    row("Last Automatic Backup", cloud.lastAutomaticBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    row("Last Manual Backup", cloud.lastManualBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    row("Last Successful Backup", cloud.lastBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    Picker("Keep Backups For", selection: Binding(get: { cloud.backupRetentionDays }, set: { cloud.backupRetentionDays = $0 })) {
                        ForEach(CloudBackupService.retentionChoices, id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .accessibilityIdentifier("account.retention")
                    row("Backup Format", "Version \(UserDataBackupService.BackupPayload.currentVersion) · schema \(SpenDropSchemaV5.versionIdentifier)")
                    if cloud.lastBackupSizeBytes > 0 {
                        row("Last Backup Size", ByteCountFormatter.string(fromByteCount: Int64(cloud.lastBackupSizeBytes), countStyle: .file))
                    }
                    Button(cloud.status.isFailure ? "Retry Backup" : "Back Up Now") {
                        Task { await cloud.runBackup(kind: .manual) }
                    }
                    .disabled(cloud.isBackupRunning || cloud.status == .restoring)
                    .accessibilityIdentifier("account.backupNow")
                    NavigationLink("Restore from Cloud Backup") {
                        CloudRestoreView(cloud: cloud)
                    }
                } header: {
                    Text("Cloud Backup")
                } footer: {
                    Text(backupFooter)
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
        .alert("Enable Cloud Backup?", isPresented: $confirmEnableBackup) {
            Button("Cancel", role: .cancel) {}
            Button("Enable Cloud Backup") {
                Task { await cloud.enableCloudBackup() }
            }
        } message: {
            Text("Your SpenDrop data will be securely backed up to your private cloud account: the first backup starts now, then daily around \(timeText). Only you can access it. Receipt screenshots on this iPhone are made smaller first; the screenshots themselves are not uploaded. Nothing on this iPhone is deleted.")
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await auth.signOut(); cloud.refreshStatus(); cloud.rescheduleDailyBackup() } }
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

    /// The daily backup time as a Date today (only hour and minute matter).
    private var backupTime: Binding<Date> {
        Binding(get: {
            let minutes = cloud.dailyBackupMinutes
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            cloud.dailyBackupMinutes = (parts.hour ?? 3) * 60 + (parts.minute ?? 0)
        })
    }

    private var timeText: String {
        backupTime.wrappedValue.formatted(date: .omitted, time: .shortened)
    }

    private var backupFooter: String {
        guard cloud.cloudBackupEnabled else {
            return "Off until you turn it on — signing in never uploads anything. Local backups on this iPhone continue as before."
        }
        let schedule = cloud.dailyBackupEnabled ? "Daily around \(timeText) (iOS decides the exact time; if it's missed, the backup runs the next time you open SpenDrop). " : ""
        return schedule + "Before every backup, large receipt screenshots are made smaller. Backups older than \(cloud.backupRetentionDays) days are removed only after a newer backup is verified; this never deletes transactions on your iPhone, which always keep your full history. Turning backup off keeps your existing cloud backups."
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

    /// Authentication only: never downloads, uploads or merges anything after sign-in.
    private func afterSignIn() {
        cloud.refreshStatus()
    }

    private func deleteAccount() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.deleteAccount { try await cloud.deleteAllCloudData() }
            cloud.refreshStatus()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Email sign-in, account creation and password reset in one sheet. Passwords go only to Supabase Auth over
/// HTTPS; SpenDrop never stores or logs them.
struct EmailAuthView: View {
    enum Mode: String, Identifiable {
        case signIn, create, forgot
        var id: String { rawValue }
        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .create: return "Create Account"
            case .forgot: return "Reset Password"
            }
        }
    }

    let auth: AuthService
    let onFinish: (Bool) -> Void

    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var errorMessage: String?
    /// Set after a confirmation or reset email was sent: shows the "Check your email" state.
    @State private var sentTo: (email: String, kind: Mode)?

    init(mode: Mode, auth: AuthService, onFinish: @escaping (Bool) -> Void) {
        self.auth = auth
        self.onFinish = onFinish
        _mode = State(initialValue: mode)
    }

    private var problem: String? {
        if mode == .forgot { return AuthValidation.emailProblem(email) }
        return AuthValidation.problem(email: email, password: password, confirm: mode == .create ? confirm : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sent = sentTo {
                    checkEmail(sent.email, kind: sent.kind)
                } else {
                    fields
                }
            }
            .navigationTitle(sentTo == nil ? mode.title : "Check Your Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentTo == nil ? "Cancel" : "Close") { onFinish(false) }
                }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
            .onChange(of: email) { errorMessage = nil }
            .onChange(of: password) { errorMessage = nil }
            .onChange(of: confirm) { errorMessage = nil }
        }
    }

    @ViewBuilder private var fields: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("auth.email")
            if mode != .forgot {
                SecureField("Password", text: $password)
                    .textContentType(mode == .create ? .newPassword : .password)
                    .accessibilityIdentifier("auth.password")
            }
            if mode == .create {
                SecureField("Confirm Password", text: $confirm)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("auth.confirm")
            }
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("auth.error")
            } else if let problem, !email.isEmpty || !password.isEmpty {
                Text(problem).foregroundStyle(.secondary).accessibilityIdentifier("auth.problem")
            } else if mode == .create {
                Text("\(AuthValidation.passwordHint) Your password is handled by the sign-in service and never stored by SpenDrop.")
            } else if mode == .forgot {
                Text("We'll email you a link to choose a new password. Open it on this iPhone.")
            }
        }
        Section {
            Button(mode == .forgot ? "Send Reset Link" : mode.title) {
                Task { await submit() }
            }
            .disabled(problem != nil || busy)
            .accessibilityIdentifier("auth.submit")
        }
        Section {
            switch mode {
            case .signIn:
                Button("Forgot Password?") { switchTo(.forgot) }.accessibilityIdentifier("auth.toForgot")
                Button("Create Account") { switchTo(.create) }.accessibilityIdentifier("auth.toCreate")
            case .create:
                Button("Already have an account? Sign In") { switchTo(.signIn) }.accessibilityIdentifier("auth.toSignIn")
            case .forgot:
                Button("Back to Sign In") { switchTo(.signIn) }.accessibilityIdentifier("auth.toSignIn")
            }
        }
        .disabled(busy)
    }

    @ViewBuilder private func checkEmail(_ address: String, kind: Mode) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Check your email", systemImage: "envelope.badge").font(.headline)
                Text(kind == .create
                     ? "We've sent a verification link to \(address). Please verify your email before signing in. If you open the link on this iPhone, you'll be signed in automatically."
                     : "If an account exists for \(address), we've sent a link to reset your password. Open it on this iPhone to choose a new password.")
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("auth.checkEmail")
        }
        Section {
            Button("Back to Sign In") {
                sentTo = nil
                switchTo(.signIn)
            }
            .accessibilityIdentifier("auth.toSignIn")
        }
    }

    private func switchTo(_ newMode: Mode) {
        mode = newMode
        password = ""
        confirm = ""
        errorMessage = nil
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            switch mode {
            case .create:
                switch try await auth.signUp(email: email, password: password) {
                case .signedIn:
                    onFinish(true)
                case .confirmationRequired:
                    sentTo = (email.trimmingCharacters(in: .whitespaces), .create)
                }
            case .signIn:
                try await auth.signIn(email: email, password: password)
                onFinish(true)
            case .forgot:
                try await auth.requestPasswordReset(email: email)
                sentTo = (email.trimmingCharacters(in: .whitespaces), .forgot)
            }
        } catch {
            errorMessage = AuthService.friendlyMessage(error)
        }
    }
}

/// Handles `spendrop://auth-callback` links from confirmation and password-reset emails anywhere in the app:
/// shows the outcome and, after a reset link, asks for the new password.
struct AuthLinkHandling: ViewModifier {
    @State private var auth = AuthService.shared
    @State private var notice: (title: String, message: String)?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                Task {
                    guard let result = await auth.handleAuthCallback(url) else { return }
                    switch result {
                    case .signedIn:
                        notice = ("Email Verified", "You're signed in\(auth.currentUser?.email.map { " as \($0)" } ?? ""). Cloud Backup stays off until you turn it on.")
                    case .verifiedSignInNeeded:
                        notice = ("Email Verified", "Your email address is confirmed. Sign in with your email and password in More → Account.")
                    case .passwordRecovery:
                        break  // the sheet below opens
                    case .failed(let message):
                        notice = ("Link Couldn't Be Used", message)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { auth.awaitingNewPassword }, set: { _ in })) {
                NewPasswordView(auth: auth) { updated in
                    if updated { notice = ("Password Updated", "Sign in with your new password.") }
                }
                .interactiveDismissDisabled()
            }
            .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice?.message ?? "")
            }
    }
}

/// Choose a new password after opening a reset link.
struct NewPasswordView: View {
    let auth: AuthService
    let onDone: (Bool) -> Void

    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var problem: String? { AuthValidation.newPasswordProblem(password, confirm: confirm) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New Password", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("reset.password")
                    SecureField("Confirm New Password", text: $confirm)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("reset.confirm")
                } header: {
                    Text(auth.currentUser?.email ?? "")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if let problem, !password.isEmpty {
                        Text(problem).foregroundStyle(.secondary)
                    } else {
                        Text(AuthValidation.passwordHint)
                    }
                }
                Section {
                    Button("Save New Password") { Task { await save() } }
                        .disabled(problem != nil || busy)
                        .accessibilityIdentifier("reset.submit")
                }
            }
            .navigationTitle("Set New Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await auth.cancelPasswordRecovery(); onDone(false) } }
                        .disabled(busy)
                }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await auth.updatePassword(password)
            onDone(true)
        } catch {
            errorMessage = AuthService.friendlyMessage(error)
        }
    }
}

/// Lists cloud backups and restores one after showing exactly what it contains.
struct CloudRestoreView: View {
    let cloud: CloudBackupService
    @Environment(\.modelContext) private var modelContext

    @State private var records: [CloudBackupRecord] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange)
            } else if records.isEmpty {
                Text("No cloud backups yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                NavigationLink {
                    RestoreRangeView(source: cloudSource(record))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(index == 0 ? "Latest Backup" : "Older Backup").font(.caption).foregroundStyle(.secondary)
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("\(record.deviceName) · app \(record.appVersion) · format \(record.backupVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(record.expensesCount) expenses · \(record.accountsCount) accounts · \(record.movementsCount) money records · \(record.peopleCount) PayBook")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Restore from Cloud Backup")
        .task { await load() }
    }

    private func cloudSource(_ record: CloudBackupRecord) -> RestoreRangeView.Source {
        RestoreRangeView.Source(
            title: "Cloud Backup",
            createdAt: record.createdAt,
            detail: "\(record.deviceName) · app \(record.appVersion)",
            load: { try await cloud.downloadBackup(record) },
            localIDs: { UserDataBackupService.LocalRecordIDs.fetch(from: modelContext) },
            restore: { plan in try cloud.restore(plan) })
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            records = try await cloud.listBackups()
            errorMessage = nil
        } catch CloudError.offline {
            errorMessage = RestoreRangeView.offlineMessage
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Choose how much of a full backup to restore → preview → explicit confirmation → id-based merge → summary.
/// Restoring never deletes or replaces anything on this iPhone.
struct RestoreRangeView: View {
    struct Source {
        let title: String
        let createdAt: Date
        let detail: String?
        let load: @MainActor () async throws -> UserDataBackupService.BackupPayload
        let localIDs: @MainActor () -> UserDataBackupService.LocalRecordIDs
        let restore: @MainActor (UserDataBackupService.RestorePlan) async throws -> UserDataBackupService.RestoreResult
    }

    enum Option: String, CaseIterable, Identifiable {
        case everything, last7, last30, last2Months, last3Months, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .everything: return "Everything"
            case .last7: return "Last 7 days"
            case .last30: return "Last 30 days"
            case .last2Months: return "Last 2 months"
            case .last3Months: return "Last 3 months"
            case .custom: return "Custom range"
            }
        }
        var subtitle: String {
            switch self {
            case .everything: return "All data in this backup"
            case .custom: return "Choose start and end dates"
            default: return "Transactions up to the backup date"
            }
        }
    }

    static let offlineMessage = "Cloud restore requires an internet connection. Nothing on this iPhone was changed."

    let source: Source
    var calendar: Calendar = .current

    @State private var payload: UserDataBackupService.BackupPayload?
    @State private var localIDs = UserDataBackupService.LocalRecordIDs()
    @State private var loadError: String?
    @State private var option: Option = .everything
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var confirming = false
    @State private var restoring = false
    @State private var restoreError: String?
    @State private var result: RestoreOutcome?

    struct RestoreOutcome: Identifiable {
        let id = UUID()
        let result: UserDataBackupService.RestoreResult
    }

    private var referenceDay: Date { calendar.startOfDay(for: payload?.exportDate ?? source.createdAt) }

    private var range: RestoreRange {
        switch option {
        case .everything: return .everything
        case .last7: return .last7Days
        case .last30: return .last30Days
        case .last2Months: return .last2Months
        case .last3Months: return .last3Months
        case .custom: return .custom(start: customStart, end: customEnd)
        }
    }

    private var plan: UserDataBackupService.RestorePlan? {
        payload.map { UserDataBackupService.makeRestorePlan(from: $0, range: range, calendar: calendar, localIDs: localIDs) }
    }

    private func rangeText(_ range: RestoreRange) -> String {
        guard let payload else { return "" }
        return range.interval(reference: payload.exportDate, calendar: calendar)?.restoreDescription(calendar: calendar) ?? "All dates"
    }

    var body: some View {
        List {
            Section(source.title) {
                LabeledContent("Created", value: source.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let detail = source.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if let payload {
                    Text(Self.describe(UserDataBackupService.RecordCounts(
                        expenses: payload.expenses.count, accounts: payload.accounts?.count ?? 0,
                        movements: payload.moneyMovements?.count ?? 0, profiles: payload.paybookProfiles.count,
                        rules: payload.classificationRules?.count ?? 0), separator: " · "))
                        .font(.subheadline)
                        .accessibilityIdentifier("restore.backupCounts")
                }
            }

            if let loadError {
                Section { Text(loadError).foregroundStyle(.orange).accessibilityIdentifier("restore.error") }
            } else if payload == nil {
                Section { ProgressView("Loading backup…") }
            } else {
                Section("Restore") {
                    ForEach(Option.allCases) { item in
                        Button {
                            option = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item == .custom || item == .everything ? item.subtitle : rangeText(range(for: item)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if option == item { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item == .everything ? "All data in this backup" : item == .custom ? "Choose dates" : rangeText(range(for: item)))
                        .accessibilityAddTraits(option == item ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("restore.option.\(item.rawValue)")
                    }
                }

                if option == .custom {
                    Section("Custom range") {
                        DatePicker("From", selection: $customStart, in: Self.earliestDate...referenceDay, displayedComponents: .date)
                            .accessibilityIdentifier("restore.customStart")
                        DatePicker("To", selection: $customEnd, in: Self.earliestDate...referenceDay, displayedComponents: .date)
                            .accessibilityIdentifier("restore.customEnd")
                    }
                }

                if let plan {
                    Section("Selected range") {
                        Text(rangeText(range)).accessibilityIdentifier("restore.selectedRange")
                        if let problem = range.validationProblem(calendar: calendar) {
                            Text(problem).foregroundStyle(.orange).accessibilityIdentifier("restore.validation")
                        } else if plan.isEmpty {
                            Text("No records in this range.").foregroundStyle(.secondary).accessibilityIdentifier("restore.found")
                        } else {
                            Text("Records found: " + Self.describe(plan.counts, separator: ", "))
                                .accessibilityIdentifier("restore.found")
                        }
                    }
                    Section {
                        Button("Continue") { confirming = true }
                            .disabled(plan.isEmpty || range.validationProblem(calendar: calendar) != nil || restoring)
                            .accessibilityIdentifier("restore.continue")
                    } footer: {
                        Text("Restoring adds and merges records by ID. Nothing on this iPhone is deleted or duplicated. Receipt screenshots aren't part of backups.")
                    }
                }
            }
        }
        .navigationTitle("Restore")
        .overlay {
            if restoring, let plan {
                ProgressView("Restoring \(plan.counts.total) records…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await load() }
        .alert(confirmTitle, isPresented: $confirming, presenting: plan) { plan in
            Button("Cancel", role: .cancel) {}
            Button("Restore") { Task { await perform(plan) } }
        } message: { plan in
            Text(previewMessage(plan))
        }
        .alert("Restore Failed", isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
        .sheet(item: $result) { outcome in
            RestoreSummaryView(result: outcome.result, rangeText: rangeText(outcome.result.plan.range))
        }
    }

    private static var earliestDate: Date { Date(timeIntervalSince1970: 946_684_800) }  // 1 Jan 2000

    private func range(for item: Option) -> RestoreRange {
        switch item {
        case .everything: return .everything
        case .last7: return .last7Days
        case .last30: return .last30Days
        case .last2Months: return .last2Months
        case .last3Months: return .last3Months
        case .custom: return .custom(start: customStart, end: customEnd)
        }
    }

    private var confirmTitle: String {
        option == .everything ? "Restore Everything?" : "Restore \(option.title)?"
    }

    private func previewMessage(_ plan: UserDataBackupService.RestorePlan) -> String {
        var lines = ["Date range: \(rangeText(plan.range))", "", "Data to restore:", Self.describe(plan.counts, separator: "\n")]
        let existing = plan.alreadyOnDevice.expenses + plan.alreadyOnDevice.accounts + plan.alreadyOnDevice.movements + plan.alreadyOnDevice.profiles
        if existing > 0 { lines += ["", "\(existing) of these are already on this iPhone and will be merged by ID, not duplicated."] }
        lines += ["", "Nothing on this iPhone is deleted. A safety copy is saved first."]
        return lines.joined(separator: "\n")
    }

    static func describe(_ counts: UserDataBackupService.RecordCounts, separator: String) -> String {
        func item(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        return [item(counts.expenses, "expense", "expenses"), item(counts.accounts, "funding account", "funding accounts"),
                item(counts.movements, "money record", "money records"), item(counts.profiles, "PayBook person", "PayBook people"),
                item(counts.rules, "learned category", "learned categories")].joined(separator: separator)
    }

    private func load() async {
        guard payload == nil else { return }
        do {
            let loaded = try await source.load()
            localIDs = source.localIDs()
            customEnd = calendar.startOfDay(for: loaded.exportDate)
            customStart = calendar.date(byAdding: .day, value: -29, to: customEnd) ?? customEnd
            payload = loaded
        } catch CloudError.offline {
            loadError = Self.offlineMessage
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func perform(_ plan: UserDataBackupService.RestorePlan) async {
        restoring = true
        defer { restoring = false }
        try? await Task.sleep(for: .milliseconds(50))  // let the progress indicator appear before the merge runs
        do {
            let restored = try await source.restore(plan)
            HapticFeedback.notification(.success)
            localIDs = source.localIDs()
            result = RestoreOutcome(result: restored)
        } catch CloudError.offline {
            restoreError = Self.offlineMessage
        } catch {
            restoreError = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) + "\n\nNothing on this iPhone was deleted."
        }
    }
}

/// What a restore actually did.
struct RestoreSummaryView: View {
    let result: UserDataBackupService.RestoreResult
    let rangeText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Date range") { Text(rangeText) }
                Section("Restored (new on this iPhone)") {
                    Text(RestoreRangeView.describe(result.added, separator: "\n"))
                        .accessibilityIdentifier("restore.summary.added")
                }
                Section("Already on this iPhone (merged by ID, not duplicated)") {
                    let s = result.summary
                    Text(RestoreRangeView.describe(UserDataBackupService.RecordCounts(
                        expenses: s.expensesUpdated + s.expensesKeptNewer, accounts: result.plan.alreadyOnDevice.accounts,
                        movements: s.movementsUpdated + s.movementsKeptNewer, profiles: s.profilesUpdated + s.profilesKeptNewer, rules: 0), separator: "\n"))
                    let keptNewer = s.expensesKeptNewer + s.profilesKeptNewer + s.movementsKeptNewer
                    if keptNewer > 0 {
                        Text("\(keptNewer) were edited more recently on this iPhone and were kept as they are.").font(.caption)
                    }
                }
                Section("Failed") { Text("0") }
                if result.summary.missingReferences > 0 || result.plan.linksOutsideRange > 0 {
                    Section {
                        Text("\(result.summary.missingReferences) links point to records that aren't on this iPhone (for example outside the chosen dates). They were left empty; names are kept so history stays readable.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Restore Complete")
            .accessibilityIdentifier("restore.summary")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("restore.done")
                }
            }
        }
    }
}
