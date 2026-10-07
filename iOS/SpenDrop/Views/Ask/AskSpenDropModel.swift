import Foundation
import Observation

/// One question and its answer (or error) in the Ask SpenDrop conversation.
public struct AskTurn: Identifiable, Equatable {
    public let id = UUID()
    public let question: String
    public var answer: AskAnswer?
    public var error: AskError?
}

/// Conversation state for the Ask screen. Lives for the app session (in the presenter), so closing and
/// reopening the screen keeps the chat; "New chat" starts a fresh server conversation.
@MainActor
@Observable
public final class AskSpenDropModel {
    public private(set) var turns: [AskTurn] = []
    public private(set) var conversationId: String?
    public private(set) var isSending = false
    /// Set when the server or the session says the user must sign in again.
    public private(set) var needsSignIn = false
    public var draft = ""

    @ObservationIgnored private let service: AskService
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(service: AskService? = nil) {
        // UI tests never reach the real AI server: every request fails as "offline".
        self.service = service ?? (ExpenseDataContainer.isUITesting ? AskService(transport: OfflineAskTransport()) : AskService())
    }

    private struct OfflineAskTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw CloudError.offline }
    }

    public var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSending && !trimmed.isEmpty && trimmed.count <= AskService.maxMessageLength
    }

    public func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        send(text)
    }

    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !trimmed.isEmpty else { return }
        turns.append(AskTurn(question: trimmed))
        run(index: turns.count - 1)
    }

    /// Re-asks a failed question in place.
    public func retry(_ turn: AskTurn) {
        guard !isSending, let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
        turns[index].error = nil
        run(index: index)
    }

    public func newChat() {
        task?.cancel()
        task = nil
        turns = []
        conversationId = nil
        isSending = false
        draft = ""
    }

    /// Called when the user is signed in again.
    public func clearSignInRequirement() {
        needsSignIn = false
    }

    private func run(index: Int) {
        let question = turns[index].question
        let turnID = turns[index].id
        isSending = true
        needsSignIn = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.service.send(message: question, conversationId: self.conversationId)
                guard !Task.isCancelled, let i = self.turns.firstIndex(where: { $0.id == turnID }) else { return }
                self.conversationId = response.conversationId
                self.turns[i].answer = response.answer
                self.turns[i].error = nil
            } catch {
                guard !Task.isCancelled, let i = self.turns.firstIndex(where: { $0.id == turnID }) else { return }
                let askError = (error as? AskError) ?? .server(status: 0, code: "", message: error.localizedDescription)
                if askError == .notSignedIn { self.needsSignIn = true }
                self.turns[i].error = askError
            }
            self.isSending = false
        }
    }
}

/// Owns the single Ask SpenDrop screen. The floating robot and Settings open it through here, so there is
/// only ever one Ask screen on top of the tabs.
@MainActor
@Observable
public final class AskSpenDropPresenter {
    public static let shared = AskSpenDropPresenter()

    /// `--ui-testing --ui-testing-open-ask` opens the Ask screen at launch (UI tests and screenshots only).
    public var isPresented = ExpenseDataContainer.isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-open-ask")
    @ObservationIgnored public let model = AskSpenDropModel()

    public func open() {
        guard !isPresented else { return }
        isPresented = true
    }
}
