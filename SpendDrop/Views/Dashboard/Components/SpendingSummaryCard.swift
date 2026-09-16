import SwiftUI

public struct SpendingSummaryCard: View {
    public let title: String
    public let amount: Double
    public let currency: String
    public let icon: String
    public let tintColor: Color

    public init(
        title: String,
        amount: Double,
        currency: String = "RM",
        icon: String = "calendar",
        tintColor: Color = .blue
    ) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.icon = icon
        self.tintColor = tintColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Spacer()
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tintColor)
            }

            Text(CurrencyFormatter.format(amount: amount, currency: currency))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}
