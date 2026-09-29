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

    /// New record of the given type.
    public init(entryType: TransactionEntryType, onFinished: @escaping () -> Void) {
        self.entryType = entryType
        self.existing = nil
        self.onFinished = onFinished
        _draft = State(initialValue: MoneyMovementDraft(entryType: entryType))
    }

    /// New record from a prefilled draft (e.g. Record Repayment from PayBook, or a scanned screenshot).
    public init(draft: MoneyMovementDraft, onFinished: @escaping () -> Void) {
        self.entryType = draft.entryType
        self.existing = nil
        self.onFinished = onFinished
        _draft = State(initialValue: draft)
    }

