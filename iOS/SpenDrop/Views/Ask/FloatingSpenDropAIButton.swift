import SwiftUI
import UIKit

/// The floating SpenDrop AI robot. Opens the single Ask SpenDrop screen.
struct FloatingSpenDropAIButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var floating = false

    var size: CGFloat { sizeClass == .regular ? 76 : 64 }

    var body: some View {
        Button(action: action) {
            SpenDropRobotImage(size: size)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                .offset(y: floating ? -3 : 0)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask SpenDrop AI")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("ai.floatingButton")
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    /// A gentle 3pt bob over ~3.5s (1.75s up, 1.75s down). Off when Reduce Motion is on.
    private func updateAnimation() {
        if reduceMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { floating = false }
        } else {
            floating = false
            withAnimation(.easeInOut(duration: 1.75).repeatForever(autoreverses: true)) { floating = true }
        }
    }
}

/// Places the floating robot bottom-trailing on a tab's content (so it sits above the tab bar and inside the
/// safe area). Hidden when turned off in Settings, while the Ask screen is shown, and while the keyboard is
/// up. Adds matching bottom safe-area padding so the last rows of scrolling screens can scroll clear of it.
struct FloatingSpenDropAIModifier: ViewModifier {
    @AppStorage(AskSpenDropSettings.floatingAssistantKey) private var enabled = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var presenter = AskSpenDropPresenter.shared
    @State private var keyboardVisible = false

    /// UI tests keep their existing layout unless they opt in with `--ui-testing-ai-button`.
    private static let allowedInThisRun: Bool = {
        guard ExpenseDataContainer.isUITesting else { return true }
        return ProcessInfo.processInfo.arguments.contains("--ui-testing-ai-button")
    }()

    private var visible: Bool {
        Self.allowedInThisRun && enabled && !presenter.isPresented && !keyboardVisible
    }

    private var reservedHeight: CGFloat { (sizeClass == .regular ? 76 : 64) + 12 }

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, visible ? reservedHeight : 0)
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    FloatingSpenDropAIButton { presenter.open() }
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: visible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
    }
}

extension View {
    func floatingSpenDropAI() -> some View {
        modifier(FloatingSpenDropAIModifier())
    }
}
