import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query(sort: \MoneyMovement.date, order: .reverse) private var allMovements: [MoneyMovement]
    @Bindable private var engine = TransactionFilterEngine.shared

    @AppStorage("analytics_daily_spending_range") private var storedDailySpendingRange: String = DailySpendingRange.last7Days.rawValue

    private enum Mode: String, CaseIterable, Identifiable {
        case spending = "Spending", cashFlow = "Cash Flow"
        var id: String { rawValue }
    }
    @AppStorage("breakdown_mode") private var storedMode: String = Mode.spending.rawValue
    @State private var trendGranularity: PeriodGrouping.Granularity = .weekly
    private var mode: Mode { Mode(rawValue: storedMode) ?? .spending }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Central Filter Bar
                    FilterBarView(engine: engine)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemBackground))

                    Picker("View", selection: $storedMode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .accessibilityIdentifier("breakdown.mode")

                    if mode == .cashFlow {
                        cashFlowContent
                    } else if engine.filteredExpenses.isEmpty {
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

                        // MARK: - SHARED, MY SHARE, REFUNDS, NET SPENDING
                        sharedAndRefundsSection

                        // MARK: - MERCHANTS
                        merchantSection

                        // MARK: - WEEKLY / MONTHLY TREND
                        trendSection(showsCashFlow: false)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Breakdown")
            .onAppear {
                if let savedRange = DailySpendingRange(rawValue: storedDailySpendingRange) {
                    engine.dailySpendingRange = savedRange
                }
                engine.update(expenses: allExpenses)
                engine.update(movements: allMovements)
            }
            .onChange(of: allExpenses) { _, newExpenses in
                engine.update(expenses: newExpenses)
            }
            .onChange(of: allMovements) { _, newMovements in
                engine.update(movements: newMovements)
            }
        }
    }

    // MARK: - Spending extras (Phase 7)

    private func money(_ minor: Int) -> String {
        CurrencyFormatter.format(amount: Money.majorAmount(fromMinor: minor))
    }

    @ViewBuilder
    private var sharedAndRefundsSection: some View {
        let shared = engine.sharedSpendingSummary
        if shared.sharedCount > 0 || shared.refundsMinor > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shared & Refunds").font(.headline)
                if shared.sharedCount > 0 {
                    row("Shared expenses", "\(shared.sharedCount) · bills \(money(shared.sharedTotalMinor))")
                    row("My share", money(shared.myShareMinor))
                }
                if shared.refundsMinor > 0 {
                    row("Gross spending", money(engine.cashFlowSummary.spendingMinor))
                    row("Refunds", "−" + money(shared.refundsMinor))
                    row("Net spending", money(shared.netSpendingMinor), bold: true)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var merchantSection: some View {
        let merchants = Array(engine.merchantBreakdown.prefix(8))
        if !merchants.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top Merchants").font(.headline)
                ForEach(merchants) { item in
                    row("\(item.name) · \(item.count)", CurrencyFormatter.format(amount: item.total))
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// Weekly / monthly (or daily) totals over all records; cash flow bars exclude own transfers.
    private func trendSection(showsCashFlow: Bool) -> some View {
        let buckets = PeriodGrouping.buckets(expenses: allExpenses, movements: allMovements, granularity: trendGranularity)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showsCashFlow ? "Cash Flow Trend" : "Spending Trend").font(.headline)
                Spacer()
                Picker("Period", selection: $trendGranularity) {
                    ForEach(PeriodGrouping.Granularity.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Chart(buckets) { bucket in
                if showsCashFlow {
                    BarMark(x: .value("Period", bucket.label), y: .value("RM", Money.majorAmount(fromMinor: bucket.inMinor)))
                        .foregroundStyle(by: .value("Type", "Money In"))
                        .position(by: .value("Type", "Money In"))
                    BarMark(x: .value("Period", bucket.label), y: .value("RM", Money.majorAmount(fromMinor: bucket.outMinor)))
                        .foregroundStyle(by: .value("Type", "Money Out"))
                        .position(by: .value("Type", "Money Out"))
                } else {
                    BarMark(x: .value("Period", bucket.label), y: .value("RM", Money.majorAmount(fromMinor: bucket.spendingMinor)))
                        .foregroundStyle(Color.blue.gradient)
                }
            }
            .chartForegroundStyleScale(["Money In": Color.green, "Money Out": Color.gray])
            .frame(height: 180)
            Text("All records · \(trendGranularity.rawValue.lowercased()) totals\(showsCashFlow ? " · own transfers excluded" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var cashFlowContent: some View {
        let flow = engine.cashFlowSummary
        HStack(spacing: 10) {
            metricCard(title: "MONEY IN", value: money(flow.moneyInMinor), subtitle: engine.selectedDateFilter.displayName, color: .green)
            metricCard(title: "MONEY OUT", value: money(flow.moneyOutMinor), subtitle: "expenses paid + other out", color: .primary)
        }
        .padding(.horizontal)
        metricCard(title: "NET CASH FLOW", value: (flow.netCashFlowMinor >= 0 ? "+" : "") + money(flow.netCashFlowMinor),
                   subtitle: "Money In − Money Out · spending is shown separately (\(money(flow.spendingMinor)))",
                   color: flow.netCashFlowMinor >= 0 ? .green : .orange)
            .padding(.horizontal)

        let kinds = engine.movementKindBreakdown
        if !kinds.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("By Type").font(.headline)
                ForEach(kinds, id: \.kind) { item in
                    row("\(item.kind.displayName) · \(item.count)", (item.kind.direction == .moneyIn ? "+" : "−") + money(item.totalMinor))
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }

        trendSection(showsCashFlow: true)
    }

    private func row(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(bold ? .bold : .semibold))
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
