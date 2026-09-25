import SwiftUI

public struct ExpenseRowView: View {
    public let expense: Expense

    public init(expense: Expense) {
        self.expense = expense
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Category Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(expense.category.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: expense.category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(expense.category.color)
            }

            // Merchant & Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.merchant)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Payment badge
                    HStack(spacing: 4) {
                        ProviderLogoView(source: expense.paymentSource, size: 12)
                        if expense.paymentSource == .applePay, let bank = expense.underlyingBank, bank != .unknown {
                            ProviderLogoView(source: bank, size: 12)
                        }
                        Text(expense.paymentSource == .applePay && expense.underlyingBank != nil ? "Apple Pay • \(expense.underlyingBank!.shortName)" : expense.paymentSource.shortName)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(expense.paymentSource.brandColor.opacity(0.12))
                    .foregroundStyle(expense.paymentSource.brandColor)
                    .clipShape(Capsule())

                    if let notes = expense.notes, !notes.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Amount & Time
            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.formattedAmount)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(expense.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
