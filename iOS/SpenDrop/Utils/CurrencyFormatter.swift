import Foundation

public struct CurrencyFormatter {
    public static func format(amount: Double, currency: String = "RM") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "\(currency) "
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }

    public static func parse(string: String) -> Double? {
        let cleaned = string
            .replacingOccurrences(of: "RM", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "MYR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }
}
