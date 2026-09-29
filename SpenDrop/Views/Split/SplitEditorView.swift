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

