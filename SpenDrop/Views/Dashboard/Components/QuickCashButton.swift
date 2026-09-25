import SwiftUI

public struct QuickCashButton: View {
    public let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "banknote.fill")
                    .font(.subheadline)
                Text("Quick Cash")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}
