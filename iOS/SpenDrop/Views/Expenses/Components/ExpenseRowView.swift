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

    /// My share for shared expenses (spending when someone else paid).
    private var myShareText: String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: expense.myShareMinor), currency: expense.currency)
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Category Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(expense.category.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: expense.category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(expense.category.color)
            }

            // Merchant, Category, and Funding • Channel
            VStack(alignment: .leading, spacing: 3) {
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

                    if expense.isShared {
                        Label("\(expense.shares.count)", systemImage: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Shared with \(expense.shares.count) people")
                    }
                }

                HStack(spacing: 5) {
                    Text(expense.category.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(expense.category.color)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Funding Account · Payment Channel
                    HStack(spacing: 3) {
                        if let src = fundingSource {
                            ProviderLogoView(source: src, size: 10)
                        } else {
                            Image(systemName: expense.paymentChannel.iconName)
                                .font(.system(size: 9))
                        }

                        Text(expense.displayFundingAndChannel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }

                if let notes = expense.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Amount & Date
            VStack(alignment: .trailing, spacing: 3) {
                Text(expense.paidByMe ? expense.formattedAmount : myShareText)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if expense.isShared {
                    Text(expense.paidByMe ? "You \(myShareText)" : "Paid by \(expense.payer?.name ?? expense.payerNameSnapshot ?? "someone")")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }

                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
