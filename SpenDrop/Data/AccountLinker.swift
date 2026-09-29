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

