import Foundation
import SwiftData

/// Creates Account records from the existing `fundingAccount` text and links expenses to them.
/// - Only meaningful values create accounts ("Unknown", "Other", empty… are ignored and stay unlinked).
/// - Names are matched case- and whitespace-insensitively, so "Maybank" and " MAYBANK " share one account.
/// - Only expenses without an account are linked; the `fundingAccount` text is never modified.
/// - Safe to run repeatedly (used by the V1 -> V2 migration and at app launch for newly saved expenses).
public enum AccountLinker {
    private static let ignoredKeys: Set<String> = ["", "unknown", "other", "none", "n/a", "na", "-", "null", "nil"]

    private static let eWalletKeys = ["touch 'n go", "touch n go", "tng", "grabpay", "boost", "shopeepay", "bigpay", "setel", "mae"]
    private static let bankKeys = [
        "maybank", "cimb", "rhb", "public bank", "bank islam", "hong leong", "ambank", "affin", "ocbc", "uob",
        "hsbc", "standard chartered", "bsn", "bank rakyat", "alliance", "agrobank", "bank muamalat", "citibank"
    ]

    /// Normalised identity for an account name, or nil when the value does not name a real account.
    public static func normalizedKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        return ignoredKeys.contains(collapsed) ? nil : collapsed
    }

    public static func inferredType(forName name: String) -> AccountType {
        guard let key = normalizedKey(name) else { return .other }
        if key == "cash" { return .cash }
        if eWalletKeys.contains(where: { key == $0 || key.hasPrefix($0 + " ") }) { return .eWallet }
        if bankKeys.contains(where: { key.contains($0) }) { return .bank }
        return .other
    }

    /// Finds the account for a funding-account name (case/space-insensitive, archived accounts included so no
    /// duplicate is ever created), or creates it. Returns nil for "Unknown", "Other", empty…
    @discardableResult
    public static func resolveAccount(named rawName: String, currency: String = "RM", in context: ModelContext) -> Account? {
        guard let key = normalizedKey(rawName) else { return nil }
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
        let matches = accounts.filter { $0.nameKey == key }
        if let active = matches.first(where: { !$0.isArchived }) ?? matches.first {
            return active
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(name: name, type: inferredType(forName: name), currency: currency,
                              sortIndex: (accounts.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(account)
        return account
    }

    /// Makes `expense.account` match its `fundingAccount` text. Used when an expense is saved or edited,
    /// so the link never goes stale. "Unknown"/empty text clears the link.
    @discardableResult
    public static func relink(_ expense: Expense, in context: ModelContext) -> Account? {
        guard let key = normalizedKey(expense.fundingAccount) else {
            expense.account = nil
            return nil
        }
        if let current = expense.account, current.nameKey == key {
            return current
        }
        let account = resolveAccount(named: expense.fundingAccount, currency: expense.currency, in: context)
        expense.account = account
        return account
    }

    /// Funding-account choices for the expense forms: the existing fixed list, plus any active account the user
    /// added, with "Other" kept last. Names already in the list are not repeated.
    public static func fundingOptions(base: [String], accounts: [Account]) -> [String] {
        var options = base.filter { normalizedKey($0) != nil }
        var keys = Set(options.compactMap { normalizedKey($0) })
        for account in accounts.sorted(by: { $0.sortIndex < $1.sortIndex }) where !account.isArchived {
            if let key = account.nameKey, !keys.contains(key) {
                options.append(account.name)
                keys.insert(key)
            }
        }
        if base.contains("Other") { options.append("Other") }
        return options
    }

