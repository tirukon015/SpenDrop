import Foundation

/// Bulk Import: decides whether one screenshot is a single receipt or a list of transactions (a payment / bank
/// history), following Common/BusinessRules/bulk-import.md and its vectors (same rules as the Android
/// `ScreenshotSplitter`). Text only and conservative: anything that isn't clearly a list is a single receipt for the
/// existing `TransactionParser`.
public enum ScreenshotSplitter {
    /// A calendar day without a time zone (the vectors' "yyyy-MM-dd").
    public struct Day: Equatable, Comparable, CustomStringConvertible {
        public let year: Int, month: Int, day: Int
        public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

        /// The local calendar day of `date`.
        public init(_ date: Date, calendar: Calendar = .current) {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
        }

        /// nil when the day doesn't exist (31/02, month 13…).
        static func valid(year: Int, month: Int, day: Int) -> Day? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let back = cal.dateComponents([.year, .month, .day], from: date)
            guard back.year == year, back.month == month, back.day == day else { return nil }
            return Day(year: year, month: month, day: day)
        }

        public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
        public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    }

    public struct Row: Equatable {
        public let merchant: String
        public let amountMinor: Int
        /// "in" for a leading +, otherwise "out".
        public let direction: String
        public let day: Day
        public let hour: Int
        public let minute: Int

        public var time: String { String(format: "%02d:%02d", hour, minute) }
        public var isMoneyIn: Bool { direction == "in" }

        /// The row's local date and time.
        public func date(calendar: Calendar = .current) -> Date? {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))
        }
    }

    public enum Result: Equatable {
        case single
        case multiple([Row])
    }

    private static let months = "jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec"
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let amountRe = try! NSRegularExpression(
        pattern: #"(?<![\w.,])([+-])?\s?(?:(?:RM|MYR)\s?)?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d.])"#, options: [.caseInsensitive])
    private static let dateDmy = try! NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})\b"#)
    private static let dateIso = try! NSRegularExpression(pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#)
    private static let dateDMon = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})\s+("# + months + #")[a-z]*\.?(?:\s+(\d{4}))?\b"#, options: [.caseInsensitive])
    private static let timeRe = try! NSRegularExpression(pattern: #"\b(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?\b"#)
    private static let singleMarkers = ["payment successful", "transaction successful", "successful", "receipt", "total", "ref no", "reference"]
    private static let separators: Set<String> = ["—", "–", "-", "|", "·", "•", ":"]
    private static let trimSet = CharacterSet(charactersIn: " —–-|·•:")

    public static func classify(lines: [String], importDate: Day) -> Result {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let rows = clean.compactMap { row($0, importDate: importDate) }
        if rows.count < 2 { return .single }
        let lower = clean.joined(separator: "\n").lowercased()
        if rows.count == 2 && singleMarkers.contains(where: { lower.contains($0) }) { return .single }
        return .multiple(rows)
    }

    public static func classify(lines: [String], importDate: Date = Date(), calendar: Calendar = .current) -> Result {
        classify(lines: lines, importDate: Day(importDate, calendar: calendar))
    }

    // MARK: - Row

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        guard let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }

    static func row(_ line: String, importDate: Day) -> Row? {
        let ns = line as NSString
        let amounts = amountRe.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard amounts.count == 1, let a = amounts.first else { return nil }
        guard let (day, dateRange) = date(line, importDate: importDate) else { return nil }

        // Remove the amount, then the date text (first occurrence), as the shared rules describe.
        var rest = ns.replacingCharacters(in: a.range, with: "")
        let dateText = ns.substring(with: dateRange)
        if let r = rest.range(of: dateText) { rest.replaceSubrange(r, with: " ") }

        var hour = 12, minute = 0
        let restNS = rest as NSString
        if let t = timeRe.firstMatch(in: rest, range: NSRange(location: 0, length: restNS.length)) {
            var h = Int(group(t, 1, in: rest)) ?? -1
            let min = Int(group(t, 2, in: rest)) ?? -1
            switch group(t, 3, in: rest).lowercased() {
            case "pm": if h < 12 { h += 12 }
            case "am": if h == 12 { h = 0 }
            default: break
            }
            if (0...23).contains(h), (0...59).contains(min) { hour = h; minute = min }
            rest = restNS.replacingCharacters(in: t.range, with: "")
        }

        let merchant = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .filter { !$0.isEmpty && !separators.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: trimSet)
            .trimmingCharacters(in: .whitespaces)
        guard merchant.filter(\.isLetter).count >= 2 else { return nil }

        let whole = Int(group(a, 2, in: line).replacingOccurrences(of: ",", with: "")) ?? 0
        let fraction = Int(group(a, 3, in: line)) ?? 0
        let minor = whole * 100 + fraction
        guard minor > 0 else { return nil }
        return Row(merchant: merchant, amountMinor: minor, direction: group(a, 1, in: line) == "+" ? "in" : "out",
                   day: day, hour: hour, minute: minute)
    }

    private static func date(_ line: String, importDate: Day) -> (Day, NSRange)? {
        let full = NSRange(location: 0, length: (line as NSString).length)
        if let m = dateIso.firstMatch(in: line, range: full) {
            guard let d = Day.valid(year: Int(group(m, 1, in: line)) ?? 0, month: Int(group(m, 2, in: line)) ?? 0,
                                    day: Int(group(m, 3, in: line)) ?? 0) else { return nil }
            return (d, m.range)
        }
        if let m = dateDmy.firstMatch(in: line, range: full) {
            var y = Int(group(m, 3, in: line)) ?? 0
            if y < 100 { y += 2000 }
            guard let d = Day.valid(year: y, month: Int(group(m, 2, in: line)) ?? 0, day: Int(group(m, 1, in: line)) ?? 0) else { return nil }
            return (d, m.range)
        }
        if let m = dateDMon.firstMatch(in: line, range: full) {
            let month = (monthNames.firstIndex(of: String(group(m, 2, in: line).lowercased().prefix(3))) ?? -1) + 1
            let dayOfMonth = Int(group(m, 1, in: line)) ?? 0
            let explicit = Int(group(m, 3, in: line))
            guard let d = Day.valid(year: explicit ?? importDate.year, month: month, day: dayOfMonth) else { return nil }
            if explicit == nil && d > importDate {
                // 29 Feb a year earlier becomes 28 Feb (as LocalDate.minusYears does).
                let previous = Day.valid(year: d.year - 1, month: d.month, day: d.day) ?? Day(year: d.year - 1, month: d.month, day: 28)
                return (previous, m.range)
            }
            return (d, m.range)
        }
        return nil
    }
}
