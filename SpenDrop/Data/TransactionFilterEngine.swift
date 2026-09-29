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

public enum DailySpendingRange: String, CaseIterable, Identifiable {
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"

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

    // MARK: - Primary Date Filter State
    public var selectedDateFilter: QuickDateFilter = .last7Days
    public var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    public var customEndDate: Date = Date()

    // MARK: - Multi-Select Dimension Filters
    public var selectedCategories: Set<ExpenseCategory> = []
    public var selectedPaymentChannels: Set<PaymentChannel> = []
    public var selectedFundingAccounts: Set<String> = []

    // Backward compatibility single-select computed accessors
    public var selectedCategory: ExpenseCategory? {
        get { selectedCategories.count == 1 ? selectedCategories.first : nil }
        set {
            if let val = newValue {
                selectedCategories = [val]
            } else {
                selectedCategories = []
            }
        }
    }

    public var selectedPaymentChannel: PaymentChannel? {
        get { selectedPaymentChannels.count == 1 ? selectedPaymentChannels.first : nil }
        set {
            if let val = newValue {
                selectedPaymentChannels = [val]
            } else {
                selectedPaymentChannels = []
            }
        }
    }

    public var selectedFundingAccount: String? {
        get { selectedFundingAccounts.count == 1 ? selectedFundingAccounts.first : nil }
        set {
            if let val = newValue {
                selectedFundingAccounts = [val]
            } else {
                selectedFundingAccounts = []
            }
        }
    }

    // MARK: - Daily Spending Separate Date Range
    public var dailySpendingRange: DailySpendingRange = .last7Days

    // MARK: - Search
    public var searchText: String = ""

    // Raw transaction cache from SwiftData store
    private var allExpenses: [Expense] = []
    private var allMovements: [MoneyMovement] = []

    public init() {}

    public func update(expenses: [Expense]) {
        self.allExpenses = expenses
    }

    public func update(movements: [MoneyMovement]) {
        self.allMovements = movements
    }

    /// Money In / Money Out / Transfers in the selected date range. They have no category, so an active
    /// category filter hides them. The account filter matches the movement's account or transfer destination.
    public var filteredMovements: [MoneyMovement] {
        guard selectedCategories.isEmpty else { return [] }
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allMovements.filter { movement in
            guard movement.date >= startDate && movement.date <= endDate else { return false }
            if !selectedPaymentChannels.isEmpty && !selectedPaymentChannels.contains(movement.paymentChannel) {
                return false
            }
            if !selectedFundingAccounts.isEmpty {
                let names = [movement.account?.name, movement.counterAccount?.name].compactMap { $0 }
                let match = names.contains { name in selectedFundingAccounts.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
                if !match { return false }
            }
            if !term.isEmpty {
                let fields = [movement.kind.displayName, movement.note ?? "", movement.person?.name ?? movement.personNameSnapshot ?? "",
                              movement.account?.name ?? "", movement.counterAccount?.name ?? "",
                              String(format: "%.2f", Money.majorAmount(fromMinor: movement.amountMinor))]
                if !fields.contains(where: { $0.lowercased().contains(term) }) { return false }
            }
            return true
        }
    }

    /// Shared expenses and refunds in the current filters (minor units, RM).
    public struct SharedSpendingSummary: Equatable {
        public var sharedCount = 0
        /// Full bills of shared expenses.
        public var sharedTotalMinor = 0
        /// My share of those bills.
        public var myShareMinor = 0
        public var refundsMinor = 0
        public var netSpendingMinor = 0
    }

    public var sharedSpendingSummary: SharedSpendingSummary {
        let shared = filteredExpenses.filter(\.isShared)
        let summary = cashFlowSummary
        return SharedSpendingSummary(
            sharedCount: shared.count,
            sharedTotalMinor: shared.reduce(0) { $0 + $1.amountMinor },
            myShareMinor: shared.reduce(0) { $0 + $1.myShareMinor },
            refundsMinor: summary.refundsMinor,
            netSpendingMinor: summary.netSpendingMinor
        )
    }

    public struct MerchantBreakdownItem: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let total: Double
        public let count: Int
    }

    /// Spending per merchant for the current filters, largest first.
    public var merchantBreakdown: [MerchantBreakdownItem] {
        let grouped = Dictionary(grouping: filteredExpenses) { $0.merchant.trimmingCharacters(in: .whitespacesAndNewlines) }
        return grouped.map { name, items in
            MerchantBreakdownItem(name: name.isEmpty ? "Unknown" : name, total: items.reduce(0.0) { $0 + $1.spendingAmount }, count: items.count)
        }
        .sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
    }

    /// Money movements in the current filters grouped by kind (excluding own transfers), largest first.
    public var movementKindBreakdown: [(kind: MoneyMovementKind, totalMinor: Int, count: Int)] {
        let grouped = Dictionary(grouping: filteredMovements.filter { $0.kind != .ownTransfer }, by: \.kind)
        return grouped.map { (kind: $0.key, totalMinor: $0.value.reduce(0) { $0 + $1.amountMinor }, count: $0.value.count) }
            .sorted { $0.totalMinor > $1.totalMinor }
    }

    /// Spending, Money In, Money Out and Net Cash Flow for the current filters (RM).
    public var cashFlowSummary: FinancialCalculator.Summary {
        FinancialCalculator.summary(expenses: filteredExpenses, movements: filteredMovements)
    }

    // MARK: - Dynamic Available Funding Accounts
    public var availableFundingAccounts: [String] {
        let standard = ["Maybank", "Wise", "CIMB", "RHB", "Touch 'n Go", "Cash"]
        let existing = Set(allExpenses.map { $0.effectiveFundingAccount }.filter { $0 != "Unknown" && !$0.isEmpty })
        var accounts = standard
        for acc in existing.sorted() {
            if !accounts.contains(where: { $0.caseInsensitiveCompare(acc) == .orderedSame }) {
                accounts.append(acc)
            }
        }
        return accounts
    }

    // MARK: - Filter Summary Button Labels
    public var accountsSummaryLabel: String {
        if selectedFundingAccounts.isEmpty {
            return "Accounts"
        } else if selectedFundingAccounts.count == 1 {
            return selectedFundingAccounts.first!
        } else if selectedFundingAccounts.count == 2 {
            let arr = Array(selectedFundingAccounts).sorted()
            return "\(arr[0]) + \(arr[1])"
        } else {
            return "Accounts (\(selectedFundingAccounts.count))"
        }
    }

    public var categoriesSummaryLabel: String {
        if selectedCategories.isEmpty {
            return "Categories"
        } else if selectedCategories.count == 1 {
            return selectedCategories.first!.rawValue
        } else if selectedCategories.count == 2 {
            let arr = Array(selectedCategories).map { $0.rawValue }.sorted()
            return "\(arr[0]) + \(arr[1])"
        } else {
            return "Categories (\(selectedCategories.count))"
        }
    }

    public var paymentChannelsSummaryLabel: String {
        if selectedPaymentChannels.isEmpty {
            return "Payment"
        } else if selectedPaymentChannels.count == 1 {
            return selectedPaymentChannels.first!.displayName
        } else if selectedPaymentChannels.count == 2 {
            let arr = Array(selectedPaymentChannels).map { $0.displayName }.sorted()
            return "\(arr[0]) + \(arr[1])"
        } else {
            return "Payment (\(selectedPaymentChannels.count))"
        }
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
            let endOfLastWeek = calendar.date(byAdding: .day, value: 6, to: startOfLastWeek).flatMap {
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
        hasActiveDimensionFilters || selectedDateFilter != .last7Days
    }

    public var hasActiveDimensionFilters: Bool {
        !selectedCategories.isEmpty ||
        !selectedPaymentChannels.isEmpty ||
        !selectedFundingAccounts.isEmpty ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func clearDimensionFilters() {
        selectedCategories.removeAll()
        selectedPaymentChannels.removeAll()
        selectedFundingAccounts.removeAll()
        searchText = ""
    }

    public func clearAllFilters(keepDateFilter: Bool = true) {
        clearDimensionFilters()
        if !keepDateFilter {
            selectedDateFilter = .last7Days
        }
    }

    public func toggleCategory(_ category: ExpenseCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    public func toggleChannel(_ channel: PaymentChannel) {
        if selectedPaymentChannels.contains(channel) {
            selectedPaymentChannels.remove(channel)
        } else {
            selectedPaymentChannels.insert(channel)
        }
    }

    public func toggleFundingAccount(_ account: String) {
        if let existing = selectedFundingAccounts.first(where: { $0.caseInsensitiveCompare(account) == .orderedSame }) {
            selectedFundingAccounts.remove(existing)
        } else {
            selectedFundingAccounts.insert(account)
        }
    }

    // MARK: - Filtered Transactions Engine (Single Source of Truth)

    public var filteredExpenses: [Expense] {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return allExpenses.filter { expense in
            // 1. Date Filter (Strict Calendar Boundaries)
            guard expense.date >= startDate && expense.date <= endDate else {
                return false
            }

            // 2. Multi-Select Category Filter (OR logic within categories)
            if !selectedCategories.isEmpty && !selectedCategories.contains(expense.category) {
                return false
            }

            // 3. Multi-Select Payment Channel Filter (OR logic within channels)
            if !selectedPaymentChannels.isEmpty && !selectedPaymentChannels.contains(expense.paymentChannel) {
                return false
            }

            // 4. Multi-Select Funding Account Filter (OR logic within accounts)
            if !selectedFundingAccounts.isEmpty {
                let expenseFunding = expense.effectiveFundingAccount
                let match = selectedFundingAccounts.contains { $0.caseInsensitiveCompare(expenseFunding) == .orderedSame }
                if !match {
                    return false
                }
            }

            // 5. Search Text Filter
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

    // MARK: - Daily Spending (Separate from Main Date Filter: 7 Days or 30 Days)

    public var dailySpendingSubtitle: String {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let df = DateFormatter()
        df.dateFormat = "d MMM"

        switch dailySpendingRange {
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -6, to: startOfToday)!
            return "\(df.string(from: start)) — \(df.string(from: now))"
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -29, to: startOfToday)!
            return "\(df.string(from: start)) — \(df.string(from: now))"
        }
    }

    public var dailySpending: [DailySpendingPoint] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        let startDate: Date
        let endDate: Date = endOfToday

        switch dailySpendingRange {
        case .last7Days:
            // Today + previous 6 calendar days = 7 days
            startDate = cal.date(byAdding: .day, value: -6, to: startOfToday)!
        case .last30Days:
            // Today + previous 29 calendar days = 30 days
            startDate = cal.date(byAdding: .day, value: -29, to: startOfToday)!
        }

        let dayFormatter = DateFormatter()
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "yyyy-MM-dd"

        // Filter transactions within the daily spending interval respecting dimension filters
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingExpenses = allExpenses.filter { expense in
            guard expense.date >= startDate && expense.date <= endDate else {
                return false
            }
            if !selectedCategories.isEmpty && !selectedCategories.contains(expense.category) {
                return false
            }
            if !selectedPaymentChannels.isEmpty && !selectedPaymentChannels.contains(expense.paymentChannel) {
                return false
            }
            if !selectedFundingAccounts.isEmpty {
                let expenseFunding = expense.effectiveFundingAccount
                let match = selectedFundingAccounts.contains { $0.caseInsensitiveCompare(expenseFunding) == .orderedSame }
                if !match {
                    return false
                }
            }
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

        let expensesByDay = Dictionary(grouping: matchingExpenses) { expense in
            fullFormatter.string(from: expense.date)
        }

        var points: [DailySpendingPoint] = []
        var currentDate = cal.startOfDay(for: startDate)
        let finalDate = cal.startOfDay(for: endDate)

        while currentDate <= finalDate {
            let key = fullFormatter.string(from: currentDate)
            let dayExpenses = expensesByDay[key] ?? []
            let sum = dayExpenses.reduce(0.0) { $0 + $1.amount }
            let count = dayExpenses.count

            let label: String
            if dailySpendingRange == .last7Days {
                dayFormatter.dateFormat = "EEE" // e.g. Mon, Tue
                label = dayFormatter.string(from: currentDate)
            } else {
                dayFormatter.dateFormat = "d" // e.g. 1, 2, ... 28
                label = dayFormatter.string(from: currentDate)
            }

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

    public var dailySpendingAverage: Double {
        let count = dailySpending.count
        guard count > 0 else { return 0.0 }
        let total = dailySpending.reduce(0.0) { $0 + $1.amount }
        return total / Double(count)
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

    // MARK: - Previous Period Comparison (Respects Accounts, Categories, Channels)

    public var previousPeriodComparison: PeriodComparison {
        let (startDate, endDate) = dateInterval(for: selectedDateFilter)
        let cal = Calendar.current
        let duration = max(86400, endDate.timeIntervalSince(startDate))

        // Preceding interval with equal length
        let prevEnd = startDate.addingTimeInterval(-1)
        let prevStart = prevEnd.addingTimeInterval(-duration)

        // Filter preceding expenses by the EXACT SAME multi-select dimensions!
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prevExpenses = allExpenses.filter { expense in
            guard expense.date >= prevStart && expense.date <= prevEnd else {
                return false
            }
            if !selectedCategories.isEmpty && !selectedCategories.contains(expense.category) {
                return false
            }
            if !selectedPaymentChannels.isEmpty && !selectedPaymentChannels.contains(expense.paymentChannel) {
                return false
            }
            if !selectedFundingAccounts.isEmpty {
                let expenseFunding = expense.effectiveFundingAccount
                let match = selectedFundingAccounts.contains { $0.caseInsensitiveCompare(expenseFunding) == .orderedSame }
                if !match {
                    return false
                }
            }
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

        // Contextual previous period subtitle matching Section 19
        let sub: String
        switch selectedDateFilter {
        case .today:
            sub = "vs Yesterday"
        case .yesterday:
            sub = "vs Previous Day"
        case .last3Days:
            sub = "vs Previous 3 Days"
        case .last7Days:
            sub = "vs Previous 7 Days"
        case .last30Days:
            sub = "vs Previous 30 Days"
        case .thisWeek:
            sub = "vs Previous Week"
        case .lastWeek:
            sub = "vs Prior Week"
        case .thisMonth:
            sub = "vs Previous Month"
        case .lastMonth:
            sub = "vs Prior Month"
        case .custom:
            let df = DateFormatter()
            df.dateFormat = "d MMM"
            sub = "vs \(df.string(from: prevStart)) — \(df.string(from: prevEnd))"
        }

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
