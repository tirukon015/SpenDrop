import SwiftUI

public struct FilterBarView: View {
    @Binding public var selectedCategory: ExpenseCategory?
    @Binding public var selectedPaymentSource: PaymentSource?

    public init(
        selectedCategory: Binding<ExpenseCategory?>,
        selectedPaymentSource: Binding<PaymentSource?>
    ) {
        self._selectedCategory = selectedCategory
        self._selectedPaymentSource = selectedPaymentSource
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" filter chip
                Button(action: {
                    HapticFeedback.selection()
                    selectedCategory = nil
                    selectedPaymentSource = nil
                }) {
                    Text("All")
                        .font(.subheadline)
                        .fontWeight(selectedCategory == nil && selectedPaymentSource == nil ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedCategory == nil && selectedPaymentSource == nil
                                ? Color.primary
                                : Color(uiColor: .secondarySystemFill)
                        )
                        .foregroundStyle(
                            selectedCategory == nil && selectedPaymentSource == nil
                                ? Color(uiColor: .systemBackground)
                                : Color.primary
                        )
                        .clipShape(Capsule())
                }

                // Cash quick filter
                Button(action: {
                    HapticFeedback.selection()
                    if selectedPaymentSource == .cash {
                        selectedPaymentSource = nil
                    } else {
                        selectedPaymentSource = .cash
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: PaymentSource.cash.icon)
                        Text("Cash Only")
                    }
                    .font(.subheadline)
                    .fontWeight(selectedPaymentSource == .cash ? .semibold : .regular)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        selectedPaymentSource == .cash
                            ? Color.green
                            : Color(uiColor: .secondarySystemFill)
                    )
                    .foregroundStyle(
                        selectedPaymentSource == .cash
                            ? Color.white
                            : Color.primary
                    )
                    .clipShape(Capsule())
                }

                // Touch 'n Go quick filter
                Button(action: {
                    HapticFeedback.selection()
                    if selectedPaymentSource == .touchNGo {
                        selectedPaymentSource = nil
                    } else {
                        selectedPaymentSource = .touchNGo
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: PaymentSource.touchNGo.icon)
                        Text("TNG")
                    }
                    .font(.subheadline)
                    .fontWeight(selectedPaymentSource == .touchNGo ? .semibold : .regular)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        selectedPaymentSource == .touchNGo
                            ? Color.blue
                            : Color(uiColor: .secondarySystemFill)
                    )
                    .foregroundStyle(
                        selectedPaymentSource == .touchNGo
                            ? Color.white
                            : Color.primary
                    )
                    .clipShape(Capsule())
                }

                // Category chips
                ForEach(ExpenseCategory.allCases) { category in
                    Button(action: {
                        HapticFeedback.selection()
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                        }
                        .font(.subheadline)
                        .fontWeight(selectedCategory == category ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedCategory == category
                                ? category.color
                                : Color(uiColor: .secondarySystemFill)
                        )
                        .foregroundStyle(
                            selectedCategory == category
                                ? Color.white
                                : Color.primary
                        )
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
