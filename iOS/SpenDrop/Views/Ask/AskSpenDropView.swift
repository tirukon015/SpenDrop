import SwiftUI

/// Ask SpenDrop: questions about your own spending, answered by the shared SpenDrop AI server.
/// Requires SpenDrop Cloud sign-in; local data and the rest of the app work without it.
public struct AskSpenDropView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @Bindable private var model: AskSpenDropModel
    @AppStorage(AskSpenDropSettings.showMyNameKey) private var showMyName = true
    @FocusState private var composerFocused: Bool

    public init(model: AskSpenDropModel) {
        self.model = model
    }

    static let starterQuestions = [
        "How much did I spend this month?",
        "What did I spend most on last month?",
        "Compare this month with last month",
        "Show my biggest transactions this week"
    ]

    public var body: some View {
        NavigationStack {
            content
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Ask SpenDrop")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("ask.done")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.newChat()
                        } label: {
                            Label("New chat", systemImage: "square.and.pencil")
                        }
                        .disabled(model.turns.isEmpty && model.draft.isEmpty)
                        .accessibilityIdentifier("ask.newChat")
                    }
                }
        }
        .onChange(of: auth.currentUser) { _, user in
            if user != nil { model.clearSignInRequirement() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .notConfigured:
            AskStatusView(systemImage: "icloud.slash", title: "SpenDrop AI isn't available",
                          message: "This version of SpenDrop isn't connected to SpenDrop Cloud. Everything else works on this iPhone as usual.")
        case .signedOut:
            signInPrompt(message: "Your transactions stay on this iPhone either way. Signing in never replaces or deletes local data.")
        case .signedIn(let user):
            if model.needsSignIn {
                signInPrompt(message: "SpenDrop AI couldn't confirm your SpenDrop Cloud session. Open Account to sign in again, then try once more.",
                             showRetry: true)
            } else {
                chat(user: user)
            }
        }
    }

    private func signInPrompt(message: String, showRetry: Bool = false) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                SpenDropRobotImage(size: 96)
                    .padding(.top, 32)
                Text("Sign in to SpenDrop Cloud to use SpenDrop AI")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                NavigationLink {
                    AccountView()
                } label: {
                    Label("Sign in to SpenDrop Cloud", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("ask.signIn")
                if showRetry {
                    Button("Try again") { model.clearSignInRequirement() }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Chat

    private func chat(user: AuthUser) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if model.turns.isEmpty {
                            welcome(user: user)
                        }
                        ForEach(model.turns) { turn in
                            turnView(turn)
                                .id(turn.id)
                        }
                        if model.isSending {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("SpenDrop AI is looking at your transactions…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                            .id("loading")
                            .accessibilityIdentifier("ask.loading")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.turns) { _, turns in
                    guard let last = turns.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .top) }
                }
                .onChange(of: model.isSending) { _, sending in
                    if sending { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
                }
            }
            composer
        }
    }

    private func welcome(user: AuthUser) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SpenDropRobotImage(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AskSpenDropSettings.greeting(for: user, showName: showMyName))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("ask.greeting")
                    Text("Ask about your spending in your own words.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.starterQuestions, id: \.self) { question in
                    Button {
                        model.send(question)
                    } label: {
                        HStack {
                            Text(question)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func turnView(_ turn: AskTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 48)
                Text(turn.question)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
            if let answer = turn.answer {
                AskAnswerCard(answer: answer, onFollowUp: { model.send($0) }, followUpsEnabled: !model.isSending)
            } else if let error = turn.error {
                errorRow(error, turn: turn)
            }
        }
    }

    private func errorRow(_ error: AskError, turn: AskTurn) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if error.isRetryable {
                    Button {
                        model.retry(turn)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(model.isSending)
                    .accessibilityIdentifier("ask.retry")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        VStack(spacing: 4) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your spending…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { model.sendDraft() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("ask.input")
                Button {
                    model.sendDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .frame(width: 44, height: 44)
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("ask.send")
            }
            .padding(.horizontal, 12)
            if model.draft.count > AskService.maxMessageLength - 100 {
                Text("\(model.draft.count)/\(AskService.maxMessageLength)")
                    .font(.caption2)
                    .foregroundStyle(model.draft.count > AskService.maxMessageLength ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 6)
        .background(.bar)
    }
}

// MARK: - Answer card

struct AskAnswerCard: View {
    let answer: AskAnswer
    let onFollowUp: (String) -> Void
    var followUpsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                SpenDropRobotImage(size: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    if let preface = answer.preface {
                        Text(preface)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !answer.text.isEmpty {
                        Text(answer.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let understood = answer.understoodAs {
                        Text("I read this as \(understood)")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(Array(answer.blocks.enumerated()), id: \.offset) { _, block in
                AskBlockView(block: block)
            }

            if let insight = answer.insight {
                callout(insight, systemImage: "lightbulb.fill", tint: .yellow)
            }
            if let suggestion = answer.suggestion {
                callout(suggestion, systemImage: "sparkles", tint: .blue)
            }

            if let footer = answer.evidence.first?.footerText {
                Label(footer, systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ask.evidence")
            }

            if !answer.followUps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(answer.followUps, id: \.self) { followUp in
                            Button {
                                onFollowUp(followUp)
                            } label: {
                                Text(followUp)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(!followUpsEnabled)
                        }
                    }
                }
                .accessibilityIdentifier("ask.followUps")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("ask.answer")
    }

    private func callout(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Blocks

enum AskMoney {
    /// Server amounts are integer minor units (sen). Display only; never re-totalled on the device.
    static func format(_ minor: Int, currency: String) -> String {
        let code = currency.uppercased()
        let symbol = (code == "MYR" || code == "RM" || code.isEmpty) ? "RM" : code
        return CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: symbol)
    }

    static func signed(_ minor: Int, currency: String) -> String {
        (minor > 0 ? "+" : minor < 0 ? "−" : "") + format(abs(minor), currency: currency)
    }
}

struct AskBlockView: View {
    let block: AskBlock

    var body: some View {
        Group {
            switch block {
            case let .metric(label, valueMinor, currency, caption):
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(AskMoney.format(valueMinor, currency: currency))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case let .comparison(currency, a, b, diffMinor, pct):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        side(a, currency: currency)
                        side(b, currency: currency)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: diffMinor > 0 ? "arrow.up.right" : diffMinor < 0 ? "arrow.down.right" : "equal")
                        Text(AskMoney.signed(diffMinor, currency: currency))
                        if let pct {
                            Text("(\(pct >= 0 ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(0...1))))%)")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(diffMinor > 0 ? .orange : diffMinor < 0 ? .green : .secondary)
                }

            case let .breakdown(title, currency, _, items):
                let maxValue = max(items.map { abs($0.valueMinor) }.max() ?? 0, 1)
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.label).font(.subheadline).lineLimit(1)
                                if let count = item.count {
                                    Text("· \(count)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(AskMoney.format(item.valueMinor, currency: currency))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.blue.opacity(0.75))
                                    .frame(width: max(4, geo.size.width * CGFloat(abs(item.valueMinor)) / CGFloat(maxValue)))
                            }
                            .frame(height: 6)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                            .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

            case let .transactions(title, items, more):
                VStack(alignment: .leading, spacing: 0) {
                    if !title.isEmpty {
                        Text(title).font(.subheadline.weight(.semibold)).padding(.bottom, 6)
                    }
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.merchant).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(Self.subtitle(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AskMoney.format(item.amountMinor, currency: item.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                if item.isShared, let spend = item.spendMinor, spend != item.amountMinor {
                                    Text("Your share \(AskMoney.format(spend, currency: item.currency))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        if item.id != items.last?.id { Divider() }
                    }
                    if let more, more > 0 {
                        Text("+ \(more) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }

            case let .findings(title, items):
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, finding in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color.blue).frame(width: 6, height: 6).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.title).font(.subheadline.weight(.medium))
                                if let detail = finding.detail, !detail.isEmpty {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func side(_ side: AskComparisonSide, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(side.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(AskMoney.format(side.valueMinor, currency: currency))
                .font(.headline)
                .monospacedDigit()
            if let count = side.count {
                Text("\(count) transaction\(count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func subtitle(_ item: AskTransactionCard) -> String {
        let when = [item.localDate, item.localTime].compactMap { $0 }.joined(separator: " ")
        let parts = [when.isEmpty ? nil : when, item.category, item.fundingAccount].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared bits

struct AskStatusView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The SpenDrop AI robot, always aspect-fit (never cropped).
struct SpenDropRobotImage: View {
    let size: CGFloat

    var body: some View {
        Image("SpenDropRobot")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// User-facing SpenDrop AI preferences (display only; they never touch sign-in or data).
public enum AskSpenDropSettings {
    public static let floatingAssistantKey = "SpenDrop.ai.floatingAssistant"
    public static let showMyNameKey = "SpenDrop.ai.showMyName"

    /// "Hi, Rukon" from the display name (first word) or the email's local part; "Hi there" otherwise.
    public static func greeting(for user: AuthUser?, showName: Bool) -> String {
        guard showName, let name = displayName(for: user) else { return "Hi there" }
        return "Hi, \(name)"
    }

    public static func displayName(for user: AuthUser?) -> String? {
        guard let user else { return nil }
        if let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name.split(separator: " ").first.map(String.init) ?? name
        }
        if let local = user.email?.split(separator: "@").first, !local.isEmpty {
            return String(local)
        }
        return nil
    }
}
