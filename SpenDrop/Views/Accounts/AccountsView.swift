import SwiftUI
import SwiftData

private func formatMinor(_ minor: Int, currency: String) -> String {
    CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor), currency: currency)
}

/// More → Accounts. Shows RECORDED activity per account. This is not a bank balance.
public struct AccountsView: View {
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \MoneyMovement.date, order: .reverse) private var movements: [MoneyMovement]

    @State private var showingAddAccount = false

