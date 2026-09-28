import SwiftUI

public struct FilterBarView: View {
    @Bindable public var engine: TransactionFilterEngine = TransactionFilterEngine.shared

    @State private var showingCustomDatePicker = false
    @State private var showingAccountsSheet = false
    @State private var showingCategoriesSheet = false
    @State private var showingPaymentChannelsSheet = false

    public init(engine: TransactionFilterEngine = TransactionFilterEngine.shared) {
        self.engine = engine
    }

    private let primaryFilters: [QuickDateFilter] = [
        .today,
        .last7Days,
        .last30Days,
        .thisMonth
    ]

    private var isSecondaryFilterActive: Bool {
        !primaryFilters.contains(engine.selectedDateFilter)
    }

    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - PRIMARY DATE CONTROLS: [ Today ] [ Last 7 Days ] [ Last 30 Days ] [ This Month ] [ ⋯ ]
            HStack(spacing: 6) {
                ForEach(primaryFilters) { filter in
                    let isSelected = engine.selectedDateFilter == filter
                    Button {
                        HapticFeedback.selection()
                        engine.selectedDateFilter = filter
                    } label: {
                        Text(filter.displayName)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                // THREE-DOT ⋯ MENU FOR SECONDARY DATE RANGES
                Menu {
                    Section("Date Range") {
                        secondaryDateButton(.yesterday)
                        secondaryDateButton(.last3Days)
                        secondaryDateButton(.thisWeek)
                        secondaryDateButton(.lastWeek)
                        secondaryDateButton(.lastMonth)

                        Button {
                            showingCustomDatePicker = true
                        } label: {
                            HStack {
                                Text("Custom Range...")
                                if engine.selectedDateFilter == .custom {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        if isSecondaryFilterActive {
                            Text(engine.selectedDateFilter.displayName)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .padding(.horizontal, isSecondaryFilterActive ? 8 : 12)
                    .padding(.vertical, 8)
                    .background(isSecondaryFilterActive ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(isSecondaryFilterActive ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 14)

            // Live Date Subtitle
            HStack {
                Text(engine.currentSubtitle)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if engine.selectedDateFilter == .custom {
                    Button("Edit Dates") {
                        showingCustomDatePicker = true
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)

            // MARK: - MULTI-SELECT FILTER DROPDOWNS: [ Accounts ▾ ] [ Categories ▾ ] [ Payment ▾ ] [ Reset ]
            HStack(spacing: 8) {
                // Accounts Multi-Select Dropdown
                let hasAccounts = !engine.selectedFundingAccounts.isEmpty
                Button {
                    HapticFeedback.selection()
                    showingAccountsSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 11))
                        Text(engine.accountsSummaryLabel)
                            .font(.system(size: 12, weight: hasAccounts ? .bold : .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasAccounts ? Color.blue.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(hasAccounts ? Color.blue : Color.primary)
                    .clipShape(Capsule())
                }

                // Categories Multi-Select Dropdown
                let hasCategories = !engine.selectedCategories.isEmpty
                Button {
                    HapticFeedback.selection()
                    showingCategoriesSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11))
                        Text(engine.categoriesSummaryLabel)
                            .font(.system(size: 12, weight: hasCategories ? .bold : .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasCategories ? Color.purple.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(hasCategories ? Color.purple : Color.primary)
                    .clipShape(Capsule())
                }

                // Payment Channel Multi-Select Dropdown
                let hasChannels = !engine.selectedPaymentChannels.isEmpty
                Button {
                    HapticFeedback.selection()
                    showingPaymentChannelsSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 11))
                        Text(engine.paymentChannelsSummaryLabel)
                            .font(.system(size: 12, weight: hasChannels ? .bold : .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasChannels ? Color.teal.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(hasChannels ? Color.teal : Color.primary)
                    .clipShape(Capsule())
                }

                Spacer()

                // Reset / Clear Filters Button (Clears accounts, categories, channels; keeps date filter)
                if engine.hasActiveDimensionFilters {
                    Button {
                        HapticFeedback.notification(.warning)
                        engine.clearDimensionFilters()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Reset")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(Color.red)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .sheet(isPresented: $showingAccountsSheet) {
            AccountsMultiSelectSheet(engine: engine)
        }
        .sheet(isPresented: $showingCategoriesSheet) {
            CategoriesMultiSelectSheet(engine: engine)
        }
        .sheet(isPresented: $showingPaymentChannelsSheet) {
            PaymentChannelsMultiSelectSheet(engine: engine)
        }
        .sheet(isPresented: $showingCustomDatePicker) {
            CustomDateRangeSheet(engine: engine, isPresented: $showingCustomDatePicker)
        }
    }

    @ViewBuilder
    private func secondaryDateButton(_ filter: QuickDateFilter) -> some View {
        Button {
            engine.selectedDateFilter = filter
        } label: {
            HStack {
                Text(filter.displayName)
                if engine.selectedDateFilter == filter {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

// MARK: - Multi-Select Accounts Sheet
struct AccountsMultiSelectSheet: View {
    @Bindable var engine: TransactionFilterEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select All") {
                            HapticFeedback.selection()
                            engine.selectedFundingAccounts = Set(engine.availableFundingAccounts)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                        Spacer()

                        Button("Clear All") {
                            HapticFeedback.selection()
                            engine.selectedFundingAccounts.removeAll()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Funding Accounts (Where Money Came From)") {
                    ForEach(engine.availableFundingAccounts, id: \.self) { account in
                        let isSelected = engine.selectedFundingAccounts.contains(where: { $0.caseInsensitiveCompare(account) == .orderedSame })
                        let ps = PaymentSource.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(account) == .orderedSame })

                        Button {
                            HapticFeedback.selection()
                            engine.toggleFundingAccount(account)
                        } label: {
                            HStack(spacing: 12) {
                                if let source = ps {
                                    ProviderLogoView(source: source, size: 24)
                                } else {
                                    Image(systemName: "building.columns.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                }

                                Text(account)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Funding Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Multi-Select Categories Sheet
struct CategoriesMultiSelectSheet: View {
    @Bindable var engine: TransactionFilterEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select All") {
                            HapticFeedback.selection()
                            engine.selectedCategories = Set(ExpenseCategory.allCases)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.purple)

                        Spacer()

                        Button("Clear All") {
                            HapticFeedback.selection()
                            engine.selectedCategories.removeAll()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Categories") {
                    ForEach(ExpenseCategory.allCases) { category in
                        let isSelected = engine.selectedCategories.contains(category)

                        Button {
                            HapticFeedback.selection()
                            engine.toggleCategory(category)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(category.color)
                                    .frame(width: 24)

                                Text(category.rawValue)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? category.color : Color.secondary.opacity(0.4))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Multi-Select Payment Channels Sheet
struct PaymentChannelsMultiSelectSheet: View {
    @Bindable var engine: TransactionFilterEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select All") {
                            HapticFeedback.selection()
                            engine.selectedPaymentChannels = Set(PaymentChannel.allCases)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.teal)

                        Spacer()

                        Button("Clear All") {
                            HapticFeedback.selection()
                            engine.selectedPaymentChannels.removeAll()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Payment Channels (How Payment Was Made)") {
                    ForEach(PaymentChannel.allCases) { channel in
                        let isSelected = engine.selectedPaymentChannels.contains(channel)

                        Button {
                            HapticFeedback.selection()
                            engine.toggleChannel(channel)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: channel.iconName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(channel.tintColor)
                                    .frame(width: 24)

                                Text(channel.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? channel.tintColor : Color.secondary.opacity(0.4))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Payment Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Custom Date Range Sheet
struct CustomDateRangeSheet: View {
    @Bindable var engine: TransactionFilterEngine
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Start Date") {
                    DatePicker("Start", selection: $engine.customStartDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                }

                Section("End Date") {
                    DatePicker("End", selection: $engine.customEndDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        engine.selectedDateFilter = .custom
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
