import SwiftUI
import SwiftData

/// Form for Money In / Money Out / Own Transfer. Used inside the Add sheet (new record) and in
/// `MoneyMovementEditSheet` (existing record). A person is only asked for when the type needs one.
public struct MoneyMovementFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortIndex) private var allAccounts: [Account]

    private let entryType: TransactionEntryType
    private let existing: MoneyMovement?
    private let onFinished: () -> Void

    @State private var draft: MoneyMovementDraft
    @State private var showingPersonPicker = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var amountFocused: Bool

