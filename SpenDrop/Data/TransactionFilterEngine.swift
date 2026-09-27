import SwiftUI
import SwiftData

public enum QuickDateFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last3Days = "Last 3 Days"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case custom = "Custom Range"

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

public struct DailySpendingPoint: Identifiable {
    public let id: String
    public let date: Date
    public let dayLabel: String
    public let fullDateString: String
    public let amount: Double
    public let count: Int

    public init(date: Date, dayLabel: String, fullDateString: String, amount: Double, count: Int) {
        self.id = fullDateString
        self.date = date
        self.dayLabel = dayLabel
        self.fullDateString = fullDateString
        self.amount = amount
        self.count = count
    }
}

public struct CategoryBreakdownItem: Identifiable {
    public var id: String { category.rawValue }
    public let category: ExpenseCategory
    public let total: Double
    public let count: Int
    public let percentage: Double
}

public struct ChannelBreakdownItem: Identifiable {
    public var id: String { channel.rawValue }
    public let channel: PaymentChannel
    public let total: Double
    public let count: Int
    public let percentage: Double
}

public struct FundingBreakdownItem: Identifiable {
    public var id: String { name }
    public let name: String
    public let total: Double
    public let count: Int
    public let percentage: Double
    public let paymentSource: PaymentSource?
}

public struct PeriodComparison {
    public let currentTotal: Double
    public let previousTotal: Double
    public let difference: Double
    public let percentageChange: Double?
    public let isIncreased: Bool
    public let previousPeriodSubtitle: String
}

@Observable
public final class TransactionFilterEngine {
    public static let shared = TransactionFilterEngine()

    // MARK: - Filter States
    public var selectedDateFilter: QuickDateFilter = .last7Days
    public var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    public var customEndDate: Date = Date()

    public var selectedCategory: ExpenseCategory? = nil
    public var selectedPaymentChannel: PaymentChannel? = nil
    public var selectedFundingAccount: String? = nil
    public var searchText: String = ""

    // Raw transaction cache from database
    private var allExpenses: [Expense] = []

    public init() {}

    public func update(expenses: [Expense]) {
        self.allExpenses = expenses
    }

    // MARK: - Date Interval Resolution

    public func dateInterval(for filter: QuickDateFilter, now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        switch filter {
        case .today:
            return (startOfToday, endOfToday)

        case .yesterday:
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            let endOfYesterday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: startOfYesterday)!
            return (startOfYesterday, endOfYesterday)

        case .last3Days:
            // Today + previous 2 calendar days = 3 days
            let start = calendar.date(byAdding: .day, value: -2, to: startOfToday)!
            return (start, endOfToday)

        case .last7Days:
            // Today + previous 6 calendar days = 7 days
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday)!
            return (start, endOfToday)

        case .last30Days:
            // Today + previous 29 calendar days = 30 days
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday)!
            return (start, endOfToday)

        case .thisWeek:
            // ISO week Monday to Sunday
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = 2 // Monday in Gregorian
            let startOfWeek = calendar.date(from: comps) ?? startOfToday
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek).flatMap {
                calendar.date(bySettingHour: 23, minute: 59, second: 59, of: $0)
            } ?? endOfToday
            return (startOfWeek, endOfWeek)

        case .lastWeek:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekOfYear = (comps.weekOfYear ?? 1) - 1
            comps.weekday = 2
            let startOfLastWeek = calendar.date(from: comps) ?? calendar.date(byAdding: .day, value: -7, to: startOfToday)!
            let endOfLastWeek = calendar.date(byAdding: .day, value: 6, to: startOfLastLastDay(startOfLastWeek)).flatMap {
                calendar.date(bySettingHour: 23, minute: 59, second: 59, of: $0)
            } ?? calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            return (startOfLastWeek, endOfLastWeek)

        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: comps) ?? startOfToday
            let range = calendar.range(of: .day, in: .month, for: now) ?? 1..<31
            let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: startOfMonth) ?? now
            let endOfMonth = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDay) ?? endOfToday
            return (startOfMonth, endOfMonth)

        case .lastMonth:
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.month = (comps.month ?? 1) - 1
            let startOfLastMonth = calendar.date(from: comps) ?? calendar.date(byAdding: .month, value: -1, to: startOfToday)!
            let range = calendar.range(of: .day, in: .month, for: startOfLastMonth) ?? 1..<31
            let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: startOfLastMonth) ?? startOfLastMonth
            let endOfLastMonth = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDay) ?? endOfToday
            return (startOfLastMonth, endOfLastMonth)

        case .custom:
            let s = calendar.startOfDay(for: customStartDate)
            let e = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            return (min(s, e), max(s, e))
        }
    }

    private func startOfLastLastDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Formats explicit date range subtitle e.g. "22 Sep — 28 Sep"
    public func dateSubtitle(for filter: QuickDateFilter, now: Date = Date()) -> String {
        let (start, end) = dateInterval(for: filter, now: now)
        let df = DateFormatter()

        switch filter {
        case .today, .yesterday:
            df.dateFormat = "d MMM yyyy"
            return df.string(from: start)
        default:
            let sYear = Calendar.current.component(.year, from: start)
            let eYear = Calendar.current.component(.year, from: end)
            if sYear == eYear {
                df.dateFormat = "d MMM"
                let startStr = df.string(from: start)
                let endStr = df.string(from: end)
                return "\(startStr) — \(endStr)"
            } else {
                df.dateFormat = "d MMM yyyy"
                let startStr = df.string(from: start)
                let endStr = df.string(from: end)
                return "\(startStr) — \(endStr)"
            }
        }
    }

    public var currentSubtitle: String {
        dateSubtitle(for: selectedDateFilter)
    }

    // MARK: - Active Filter State Flags

    public var hasActiveFilters: Bool {
        selectedCategory != nil ||
        selectedPaymentChannel != nil ||
        selectedFundingAccount != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedDateFilter != .last7Days
    }

    public func clearAllFilters() {
        selectedCategory = nil
        selectedPaymentChannel = nil
        selectedFundingAccount = nil
        searchText = ""
        selectedDateFilter = .last7Days
    }

    public func toggleCategory(_ category: ExpenseCategory) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
        }
    }

    public func toggleChannel(_ channel: PaymentChannel) {
        if selectedPaymentChannel == channel {
            selectedPaymentChannel = nil
        } else {
            selectedPaymentChannel = channel
        }
    }

    public func toggleFundingAccount(_ account: String) {
        if selectedFundingAccount == account {
            selectedFundingAccount = nil
        } else {
            selectedFundingAccount = account
        }
    }

    // MARK: - Filtered Transactions Engine

    public var filteredExpenses: [Expense] {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return allExpenses.filter { expense in
            // Date Filter
            guard expense.date >= startDate && expense.date <= endDate else {
                return false
            }

            // Category Filter
            if let cat = selectedCategory, expense.category != cat {
                return false
            }

            // Payment Channel Filter
            if let channel = selectedPaymentChannel, expense.paymentChannel != channel {
                return false
            }

            // Funding Account Filter
            if let funding = selectedFundingAccount {
                let expenseFunding = expense.effectiveFundingAccount
                if expenseFunding.caseInsensitiveCompare(funding) != .orderedSame {
                    return false
                }
            }

            // Search Text Filter
            if !term.isEmpty {
                let matchMerchant = expense.merchant.lowercased().contains(term)
                let matchCategory = expense.category.rawValue.lowercased().contains(term)
                let matchFunding = expense.effectiveFundingAccount.lowercased().contains(term)
                let matchChannel = expense.paymentChannel.displayName.lowercased().contains(term)
                let matchNotes = expense.notes?.lowercased().contains(term) ?? false
                let matchAmount = String(format: "%.2f", expense.amount).contains(term)
                if !(matchMerchant || matchCategory || matchFunding || matchChannel || matchNotes || matchAmount) {
                    return false
                }
            }

            return true
        }
    }

    // MARK: - Aggregated KPIs

    public var totalSpending: Double {
        filteredExpenses.reduce(0.0) { $0 + $1.amount }
    }

    public var transactionCount: Int {
        filteredExpenses.count
    }

    public var numberOfCalendarDays: Int {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let cal = Calendar.current
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        let diff = cal.dateComponents([.day], from: s, to: e).day ?? 0
        return max(1, diff + 1)
    }

    public var averagePerDay: Double {
        let days = numberOfCalendarDays
        return days > 0 ? totalSpending / Double(days) : 0.0
    }

    public var averagePerTransaction: Double {
        transactionCount > 0 ? totalSpending / Double(transactionCount) : 0.0
    }

    // MARK: - Daily Spending (Vital for Last 7 Days & Charts)

    public var dailySpending: [DailySpendingPoint] {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let cal = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE" // e.g. Mon, Tue
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "yyyy-MM-dd"

        var points: [DailySpendingPoint] = []
        var currentDate = cal.startOfDay(for: startDate)
        let finalDate = cal.startOfDay(for: endDate)

        // Pre-group transactions by day
        let expensesByDay = Dictionary(grouping: filteredExpenses) { expense in
            fullFormatter.string(from: expense.date)
        }

        while currentDate <= finalDate {
            let key = fullFormatter.string(from: currentDate)
            let dayExpenses = expensesByDay[key] ?? []
            let sum = dayExpenses.reduce(0.0) { $0 + $1.amount }
            let count = dayExpenses.count
            let label = dayFormatter.string(from: currentDate)

            points.append(DailySpendingPoint(
                date: currentDate,
                dayLabel: label,
                fullDateString: key,
                amount: sum,
                count: count
            ))

            guard let next = cal.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = next
        }

        return points
    }

    // MARK: - Breakdown Calculations (% of Total Spending)

    public var categoryBreakdown: [CategoryBreakdownItem] {
        let total = totalSpending
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.category })
        return grouped.map { (cat, items) in
            let sum = items.reduce(0.0) { $0 + $1.amount }
            let pct = total > 0 ? (sum / total) * 100.0 : 0.0
            return CategoryBreakdownItem(category: cat, total: sum, count: items.count, percentage: pct)
        }.sorted { $0.total > $1.total }
    }

    public var paymentChannelBreakdown: [ChannelBreakdownItem] {
        let total = totalSpending
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.paymentChannel })
        return grouped.map { (channel, items) in
            let sum = items.reduce(0.0) { $0 + $1.amount }
            let pct = total > 0 ? (sum / total) * 100.0 : 0.0
            return ChannelBreakdownItem(channel: channel, total: sum, count: items.count, percentage: pct)
        }.sorted { $0.total > $1.total }
    }

    public var fundingAccountBreakdown: [FundingBreakdownItem] {
        let total = totalSpending
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.effectiveFundingAccount })
        return grouped.map { (account, items) in
            let sum = items.reduce(0.0) { $0 + $1.amount }
            let pct = total > 0 ? (sum / total) * 100.0 : 0.0
            let ps = PaymentSource.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(account) == .orderedSame })
            return FundingBreakdownItem(name: account, total: sum, count: items.count, percentage: pct, paymentSource: ps)
        }.sorted { $0.total > $1.total }
    }

    // MARK: - Previous Period Comparison

    public var previousPeriodComparison: PeriodComparison {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let cal = Calendar.current
        let duration = max(86400, endDate.timeIntervalSince(startDate))

        // Preceding interval with equal length
        let prevEnd = startDate.addingTimeInterval(-1)
        let prevStart = prevEnd.addingTimeInterval(-duration)

        let prevExpenses = allExpenses.filter { $0.date >= prevStart && $0.date <= prevEnd }
        let prevTotal = prevExpenses.reduce(0.0) { $0 + $1.amount }
        let currentTotal = totalSpending
        let diff = currentTotal - prevTotal

        let pctChange: Double?
        if prevTotal > 0 {
            pctChange = ((currentTotal - prevTotal) / prevTotal) * 100.0
        } else if currentTotal > 0 {
            pctChange = 100.0
        } else {
            pctChange = 0.0
        }

        let df = DateFormatter()
        df.dateFormat = "d MMM"
        let sub = "\(df.string(from: prevStart)) — \(df.string(from: prevEnd))"

        return PeriodComparison(
            currentTotal: currentTotal,
            previousTotal: prevTotal,
            difference: diff,
            percentageChange: pctChange,
            isIncreased: diff > 0,
            previousPeriodSubtitle: sub
        )
    }
}
