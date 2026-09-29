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

