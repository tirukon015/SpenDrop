import SwiftUI
import SwiftData

/// "Split with others": who shared the expense, how it is divided, and who paid.
/// Returns the edited draft through `onDone`, or nil when the user removes the split.
public struct SplitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name) private var people: [PayBookProfile]

    private let totalMinor: Int
    private let currency: String
    private let merchant: String?
    private let editingExpenseID: UUID?
    private let allowsRemove: Bool
    private let onDone: (SplitDraft?) -> Void

    @State private var draft: SplitDraft
    @State private var showingPersonPicker = false
    @State private var showingPayerPicker = false
    @State private var lastTime: SplitDraft?

    public init(totalMinor: Int, currency: String = "RM", merchant: String?, initial: SplitDraft?, editingExpenseID: UUID? = nil,
                onDone: @escaping (SplitDraft?) -> Void) {
        self.totalMinor = totalMinor
        self.currency = currency
        self.merchant = merchant
        self.editingExpenseID = editingExpenseID
        self.allowsRemove = initial != nil
        self.onDone = onDone
        _draft = State(initialValue: initial ?? SplitDraft())
    }

    private var frequentSuggestions: [PayBookProfile] {
        people.filter { $0.isFrequent && !$0.isArchived && !draft.contains($0) }
    }

    private var amounts: [Int]? { draft.shares(totalMinor: totalMinor) }

