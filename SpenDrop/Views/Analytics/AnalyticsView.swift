import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Bindable private var engine = TransactionFilterEngine.shared

    @AppStorage("analytics_daily_spending_range") private var storedDailySpendingRange: String = DailySpendingRange.last7Days.rawValue

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Central Filter Bar
                    FilterBarView(engine: engine)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemBackground))

                    if engine.filteredExpenses.isEmpty {
                        emptyStateView
                    } else {
                        // MARK: - SUMMARY METRICS (Total, Count, Avg/Day)
                        metricsSummarySection

                        // MARK: - PERIOD COMPARISON (Today vs Yesterday, Last 7 vs Prev 7, etc.)
                        periodComparisonSection

                        // MARK: - DAILY SPENDING CHART (Separate 7-Day or 30-Day Range)
                        dailySpendingSection

                        // MARK: - CATEGORY BREAKDOWN (Multi-Select Interactive)
                        categoryBreakdownSection

                        // MARK: - PAYMENT CHANNEL BREAKDOWN (Multi-Select Interactive)
                        paymentChannelBreakdownSection

                        // MARK: - FUNDING ACCOUNT BREAKDOWN (Multi-Select Interactive)
                        fundingAccountBreakdownSection
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analytics")
            .onAppear {
                if let savedRange = DailySpendingRange(rawValue: storedDailySpendingRange) {
                    engine.dailySpendingRange = savedRange
                }
                engine.update(expenses: allExpenses)
            }
            .onChange(of: allExpenses) { _, newExpenses in
                engine.update(expenses: newExpenses)
            }
        }
    }

    // MARK: - Metrics Summary Grid

    private var metricsSummarySection: some View {
        HStack(spacing: 10) {
            metricCard(
                title: "TOTAL SPENT",
                value: CurrencyFormatter.format(amount: engine.totalSpending),
                subtitle: "\(engine.transactionCount) transaction\(engine.transactionCount == 1 ? "" : "s")",
                color: .primary
            )

            metricCard(
                title: "AVERAGE / DAY",
                value: CurrencyFormatter.format(amount: engine.averagePerDay),
                subtitle: "over \(engine.numberOfCalendarDays) day\(engine.numberOfCalendarDays == 1 ? "" : "s")",
                color: .blue
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Period Comparison Card (Section 19)

    private var periodComparisonSection: some View {
        let comparison = engine.previousPeriodComparison

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(engine.selectedDateFilter.displayName.uppercased()) COMPARISON")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Spacer()

                Text(comparison.previousPeriodSubtitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CurrencyFormatter.format(amount: engine.totalSpending))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(engine.selectedDateFilter.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: comparison.isIncreased ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(comparison.isIncreased ? .red : .green)

                        Text("\(comparison.isIncreased ? "+" : "-")\(CurrencyFormatter.format(amount: abs(comparison.difference)))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(comparison.isIncreased ? .red : .green)
                    }

                    if let pct = comparison.percentageChange {
                        Text("\(comparison.isIncreased ? "+" : "-")\(String(format: "%.1f%%", abs(pct))) \(comparison.previousPeriodSubtitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Daily Spending Section (Separate from Main Date Filter: 7 Days or 30 Days)

    private var dailySpendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Spending")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text("\(engine.dailySpendingSubtitle) • Avg \(CurrencyFormatter.format(amount: engine.dailySpendingAverage))/day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Separate Range Selector: [ Last 7 Days ▾ ] / [ Last 30 Days ▾ ]
                Menu {
                    ForEach(DailySpendingRange.allCases) { range in
                        Button {
                            HapticFeedback.selection()
                            engine.dailySpendingRange = range
                            storedDailySpendingRange = range.rawValue
                        } label: {
                            HStack {
                                Text(range.displayName)
                                if engine.dailySpendingRange == range {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(engine.dailySpendingRange.displayName)
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.14))
                    .foregroundStyle(Color.blue)
                    .clipShape(Capsule())
                }
            }

            // CHART RENDERING (7 Days Standard vs 30 Days Horizontal Scrollable)
            if engine.dailySpendingRange == .last7Days {
                // 7 Days: Clean 7-bar chart with Day of Week
                Chart(engine.dailySpending) { point in
                    BarMark(
                        x: .value("Day", point.dayLabel),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(6)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            } else {
                // 30 Days: Full 30 calendar days scrollable without squeezing
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Chart(engine.dailySpending) { point in
                            BarMark(
                                x: .value("Day", point.dayLabel),
                                y: .value("Amount", point.amount)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                        }
                        .frame(width: max(CGFloat(engine.dailySpending.count) * 32.0, 960), height: 180)
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .padding(.horizontal, 8)
                        .id("chart_end_anchor")
                    }
                    .onAppear {
                        proxy.scrollTo("chart_end_anchor", anchor: .trailing)
                    }
                }

                Text("Showing all 30 days (scroll to explore) • Zero-spending days included")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Category Breakdown (Multi-Select Interactive)

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Category")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to multi-select")
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
                .frame(height: 170)
                .padding(.vertical, 4)
            }

            // Breakdown Rows
            VStack(spacing: 8) {
                ForEach(engine.categoryBreakdown) { item in
                    let isFiltered = engine.selectedCategories.contains(item.category)

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

    // MARK: - Payment Channel Breakdown (Multi-Select Interactive)

    private var paymentChannelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Payment Channel")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to multi-select")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(engine.paymentChannelBreakdown) { item in
                    let isFiltered = engine.selectedPaymentChannels.contains(item.channel)

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

    // MARK: - Funding Account Breakdown (Multi-Select Interactive)

    private var fundingAccountBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spending by Funding Account")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Tap to multi-select")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(engine.fundingAccountBreakdown) { item in
                    let isFiltered = engine.selectedFundingAccounts.contains(where: { $0.caseInsensitiveCompare(item.name) == .orderedSame })

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

            Text("No transactions match current filters")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Try choosing another date filter or resetting your account/category filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if engine.hasActiveFilters {
                Button("Reset All Filters") {
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
