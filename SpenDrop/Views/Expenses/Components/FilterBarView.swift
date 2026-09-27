import SwiftUI

public struct FilterBarView: View {
    @Bindable public var engine: TransactionFilterEngine = TransactionFilterEngine.shared
    @State private var showingCustomDatePicker = false

    public init(engine: TransactionFilterEngine = TransactionFilterEngine.shared) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - 10 Quick Date Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickDateFilter.allCases) { filter in
                        let isSelected = engine.selectedDateFilter == filter
                        Button {
                            HapticFeedback.selection()
                            engine.selectedDateFilter = filter
                            if filter == .custom {
                                showingCustomDatePicker = true
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(filter.displayName)
                                    .fontWeight(isSelected ? .bold : .regular)

                                if isSelected {
                                    Text("(\(engine.dateSubtitle(for: filter)))")
                                        .font(.caption2)
                                        .opacity(0.85)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            // MARK: - Active Dimension Filter Tags (Category, Funding, Channel)
            if engine.selectedCategory != nil || engine.selectedFundingAccount != nil || engine.selectedPaymentChannel != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Filters:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        // Active Category Chip
                        if let cat = engine.selectedCategory {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                Text(cat.rawValue)
                                Button {
                                    HapticFeedback.selection()
                                    engine.selectedCategory = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(cat.color.opacity(0.2))
                            .foregroundStyle(cat.color)
                            .clipShape(Capsule())
                        }

                        // Active Funding Account Chip
                        if let funding = engine.selectedFundingAccount {
                            HStack(spacing: 4) {
                                Image(systemName: "building.columns.fill")
                                Text(funding)
                                Button {
                                    HapticFeedback.selection()
                                    engine.selectedFundingAccount = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(Color.blue)
                            .clipShape(Capsule())
                        }

                        // Active Payment Channel Chip
                        if let channel = engine.selectedPaymentChannel {
                            HStack(spacing: 4) {
                                Image(systemName: channel.iconName)
                                Text(channel.displayName)
                                Button {
                                    HapticFeedback.selection()
                                    engine.selectedPaymentChannel = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(channel.tintColor.opacity(0.18))
                            .foregroundStyle(channel.tintColor)
                            .clipShape(Capsule())
                        }

                        // Reset / Clear All Filters button
                        Button {
                            HapticFeedback.impact(.light)
                            engine.selectedCategory = nil
                            engine.selectedFundingAccount = nil
                            engine.selectedPaymentChannel = nil
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .sheet(isPresented: $showingCustomDatePicker) {
            NavigationStack {
                Form {
                    Section("Select Date Range") {
                        DatePicker("Start Date", selection: $engine.customStartDate, displayedComponents: [.date])
                        DatePicker("End Date", selection: $engine.customEndDate, displayedComponents: [.date])
                    }
                }
                .navigationTitle("Custom Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            showingCustomDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.4)])
        }
    }
}
