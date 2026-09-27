import SwiftUI

public struct ExpenseRowView: View {
    public let expense: Expense

    public init(expense: Expense) {
        self.expense = expense
    }

    private var fundingSource: PaymentSource? {
        let funding = expense.effectiveFundingAccount
        return PaymentSource.allCases.first { $0.rawValue.caseInsensitiveCompare(funding) == .orderedSame }
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
                HStack(spacing: 4) {
                    Text(expense.merchant)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if expense.isReconciled {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 6) {
                    // Payment badge: Funding Account • Payment Channel
                    HStack(spacing: 4) {
                        if let src = fundingSource {
                            ProviderLogoView(source: src, size: 12)
                        } else {
                            Image(systemName: expense.paymentChannel.iconName)
                                .font(.system(size: 10))
                        }

                        Text(expense.displayFundingAndChannel)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(.primary)
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
