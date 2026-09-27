import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Bindable private var engine = TransactionFilterEngine.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Central Filter Bar
                    FilterBarView(engine: engine)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemBackground))

                    if engine.filteredExpenses.isEmpty {
                        emptyStateView
                    } else {
                        // MARK: - SUMMARY METRICS (Total, Count, Avg/Day, Previous Period)
                        metricsSummarySection

                        // MARK: - DAILY SPENDING CHART (Last 7 Days / Selected Interval)
                        dailySpendingSection

                        // MARK: - CATEGORY BREAKDOWN (% of Total Spending)
                        categoryBreakdownSection

                        // MARK: - PAYMENT CHANNEL BREAKDOWN (% of Total Spending)
                        paymentChannelBreakdownSection

                        // MARK: - FUNDING ACCOUNT BREAKDOWN (% of Total Spending)
                        fundingAccountBreakdownSection
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analytics")
            .onAppear {
                engine.update(expenses: allExpenses)
            }
            .onChange(of: allExpenses) { _, newExpenses in
                engine.update(expenses: newExpenses)
            }
        }
    }

    // MARK: - Metrics Summary Grid

    private var metricsSummarySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(
                    title: "TOTAL SPENT",
                    value: CurrencyFormatter.format(amount: engine.totalSpending),
                    subtitle: "\(engine.transactionCount) transactions",
                    color: .primary
                )

                metricCard(
                    title: "AVG / DAY",
                    value: CurrencyFormatter.format(amount: engine.averagePerDay),
                    subtitle: "over \(engine.numberOfCalendarDays) calendar day\(engine.numberOfCalendarDays == 1 ? "" : "s")",
                    color: .blue
                )
            }

            let comparison = engine.previousPeriodComparison
            HStack(spacing: 12) {
                metricCard(
                    title: "AVG / TRANSACTION",
                    value: CurrencyFormatter.format(amount: engine.averagePerTransaction),
                    subtitle: "per payment",
                    color: .purple
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("VS PREVIOUS PERIOD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    HStack(spacing: 4) {
                        Image(systemName: comparison.isIncreased ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline)
                            .foregroundStyle(comparison.isIncreased ? .red : .green)

                        Text(CurrencyFormatter.format(amount: abs(comparison.difference)))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(comparison.isIncreased ? .red : .green)
                            .lineLimit(1)
                    }

                    if let pct = comparison.percentageChange {
                        Text("\(comparison.isIncreased ? "+" : "-")\(String(format: "%.1f%%", abs(pct))) vs \(comparison.previousPeriodSubtitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Daily Spending Chart

    private var dailySpendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Spending")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(engine.currentSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Avg \(CurrencyFormatter.format(amount: engine.averagePerDay))/day")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            Chart(engine.dailySpending) { point in
                BarMark(
                    x: .value("Day", point.dayLabel),
                    y: .value("Amount", point.amount)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
            }
            .frame(height: 180)
            .padding(.vertical, 4)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Category")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to filter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Donut Chart
            if engine.categoryBreakdown.count > 1 {
                Chart(engine.categoryBreakdown) { item in
                    SectorMark(
                        angle: .value("Amount", item.total),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(item.category.color)
                }
                .frame(height: 180)
                .padding(.vertical, 4)
            }

            // Breakdown Rows
            VStack(spacing: 8) {
                ForEach(engine.categoryBreakdown) { item in
                    let isFiltered = engine.selectedCategory == item.category
                    Button {
                        HapticFeedback.selection()
                        engine.toggleCategory(item.category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.category.icon)
                                .foregroundStyle(item.category.color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.category.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(isFiltered ? .bold : .medium)
                                        .foregroundStyle(.primary)

                                    if isFiltered {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(item.category.color)
                                    }
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(uiColor: .tertiarySystemFill))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(item.category.color)
                                            .frame(width: max(4, geo.size.width * CGFloat(item.percentage / 100.0)), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyFormatter.format(amount: item.total))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                Text(String(format: "%.1f%% (%d txns)", item.percentage, item.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(isFiltered ? item.category.color.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if item.id != engine.categoryBreakdown.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Payment Channel Breakdown

    private var paymentChannelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Payment Channel")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to filter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(engine.paymentChannelBreakdown) { item in
                    let isFiltered = engine.selectedPaymentChannel == item.channel
                    Button {
                        HapticFeedback.selection()
                        engine.toggleChannel(item.channel)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.channel.iconName)
                                .foregroundStyle(item.channel.tintColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.channel.displayName)
                                        .font(.subheadline)
                                        .fontWeight(isFiltered ? .bold : .medium)
                                        .foregroundStyle(.primary)

                                    if isFiltered {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(item.channel.tintColor)
                                    }
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(uiColor: .tertiarySystemFill))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(item.channel.tintColor)
                                            .frame(width: max(4, geo.size.width * CGFloat(item.percentage / 100.0)), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyFormatter.format(amount: item.total))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                Text(String(format: "%.1f%% (%d txns)", item.percentage, item.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(isFiltered ? item.channel.tintColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if item.id != engine.paymentChannelBreakdown.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Funding Account Breakdown

    private var fundingAccountBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Funding Account")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to filter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(engine.fundingAccountBreakdown) { item in
                    let isFiltered = engine.selectedFundingAccount == item.name
                    Button {
                        HapticFeedback.selection()
                        engine.toggleFundingAccount(item.name)
                    } label: {
                        HStack(spacing: 12) {
                            if let ps = item.paymentSource {
                                ProviderLogoView(source: ps, size: 18)
                                    .frame(width: 24)
                            } else {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline)
                                        .fontWeight(isFiltered ? .bold : .medium)
                                        .foregroundStyle(.primary)

                                    if isFiltered {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(uiColor: .tertiarySystemFill))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.blue)
                                            .frame(width: max(4, geo.size.width * CGFloat(item.percentage / 100.0)), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyFormatter.format(amount: item.total))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                Text(String(format: "%.1f%% (%d txns)", item.percentage, item.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(isFiltered ? Color.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if item.id != engine.fundingAccountBreakdown.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    private func metricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(.top, 40)

            Text("No transactions in this period")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Try changing the date filter or clearing active filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if engine.hasActiveFilters {
                Button("Clear All Filters") {
                    HapticFeedback.selection()
                    engine.clearAllFilters()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
