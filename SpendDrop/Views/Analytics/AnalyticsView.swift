import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @State private var selectedPeriodIndex = 0
    private let periodOptions = ["This Month", "Last 30 Days", "All Time"]

    public init() {}

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    private var filteredExpenses: [Expense] {
        switch selectedPeriodIndex {
        case 0:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return allExpenses }
            return allExpenses.filter { interval.contains($0.date) }
        case 1:
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return allExpenses }
            return allExpenses.filter { $0.date >= thirtyDaysAgo && $0.date <= now }
        default:
            return allExpenses
        }
    }

    private var totalSpent: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }

    private var transactionCount: Int {
        filteredExpenses.count
    }

    private var averageTransaction: Double {
        transactionCount > 0 ? totalSpent / Double(transactionCount) : 0.0
    }

    // Category breakdown
    private var categoryTotals: [(category: ExpenseCategory, total: Double, count: Int)] {
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.category })
        return grouped.map { (category, items) in
            let total = items.reduce(0) { $0 + $1.amount }
            return (category: category, total: total, count: items.count)
        }.sorted { $0.total > $1.total }
    }

    // Payment source breakdown
    private var paymentSourceTotals: [(source: PaymentSource, total: Double, count: Int)] {
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.paymentSource })
        return grouped.map { (source, items) in
            let total = items.reduce(0) { $0 + $1.amount }
            return (source: source, total: total, count: items.count)
        }.sorted { $0.total > $1.total }
    }

    // Top merchant
    private var merchantTotals: [(merchant: String, total: Double, count: Int)] {
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.merchant })
        return grouped.map { (merchant, items) in
            let total = items.reduce(0) { $0 + $1.amount }
            return (merchant: merchant, total: total, count: items.count)
        }.sorted { $0.total > $1.total }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // PERIOD SELECTOR
                    Picker("Period", selection: $selectedPeriodIndex) {
                        ForEach(0..<periodOptions.count, id: \.self) { index in
                            Text(periodOptions[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if filteredExpenses.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)

                            Text("No expenses in this period")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Analytics will appear automatically as you record expenses.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // SUMMARY METRICS CARDS
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                metricCard(title: "TOTAL SPENT", value: CurrencyFormatter.format(amount: totalSpent), subtitle: "\(transactionCount) transactions", color: .primary)
                                metricCard(title: "AVG / TRANSACTION", value: CurrencyFormatter.format(amount: averageTransaction), subtitle: "per drop", color: .blue)
                            }

                            if let topCat = categoryTotals.first {
                                HStack(spacing: 12) {
                                    metricCard(title: "TOP CATEGORY", value: topCat.category.rawValue, subtitle: CurrencyFormatter.format(amount: topCat.total), color: topCat.category.color)
                                    if let topPay = paymentSourceTotals.first {
                                        metricCard(title: "TOP PAYMENT", value: topPay.source.shortName, subtitle: CurrencyFormatter.format(amount: topPay.total), color: topPay.source.brandColor)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // CATEGORY DONUT / BAR CHART
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Spending by Category")
                                .font(.headline)
                                .fontWeight(.bold)

                            Chart(categoryTotals, id: \.category.rawValue) { item in
                                SectorMark(
                                    angle: .value("Amount", item.total),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .cornerRadius(5)
                                .foregroundStyle(item.category.color)
                            }
                            .frame(height: 220)
                            .padding(.vertical, 8)

                            // Category breakdown rows
                            VStack(spacing: 10) {
                                ForEach(categoryTotals, id: \.category.rawValue) { item in
                                    HStack {
                                        Image(systemName: item.category.icon)
                                            .foregroundStyle(item.category.color)
                                            .frame(width: 24)

                                        Text(item.category.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Spacer()

                                        let percentage = totalSpent > 0 ? (item.total / totalSpent) * 100 : 0
                                        Text(String(format: "%.1f%%", percentage))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(CurrencyFormatter.format(amount: item.total))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                    }
                                    if item.category != categoryTotals.last?.category {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)

                        // PAYMENT SOURCES BREAKDOWN
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Spending by Payment Source")
                                .font(.headline)
                                .fontWeight(.bold)

                            Chart(paymentSourceTotals, id: \.source.rawValue) { item in
                                BarMark(
                                    x: .value("Amount", item.total),
                                    y: .value("Source", item.source.shortName)
                                )
                                .foregroundStyle(item.source.brandColor)
                                .cornerRadius(6)
                            }
                            .frame(height: max(160, CGFloat(paymentSourceTotals.count * 36)))
                            .padding(.vertical, 8)

                            VStack(spacing: 10) {
                                ForEach(paymentSourceTotals, id: \.source.rawValue) { item in
                                    HStack {
                                        Image(systemName: item.source.icon)
                                            .foregroundStyle(item.source.brandColor)
                                            .frame(width: 24)

                                        Text(item.source.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Spacer()

                                        Text("\(item.count) txns")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(CurrencyFormatter.format(amount: item.total))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                    }
                                    if item.source != paymentSourceTotals.last?.source {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)

                        // TOP MERCHANTS LIST
                        if !merchantTotals.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Top Merchants")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                VStack(spacing: 10) {
                                    ForEach(Array(merchantTotals.prefix(6)), id: \.merchant) { item in
                                        HStack {
                                            Text(item.merchant)
                                                .font(.subheadline)
                                                .fontWeight(.medium)

                                            Spacer()

                                            Text("\(item.count) drops")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text(CurrencyFormatter.format(amount: item.total))
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                        }
                                        if item.merchant != Array(merchantTotals.prefix(6)).last?.merchant {
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
                    }
                }
                .padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analytics")
        }
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
}
