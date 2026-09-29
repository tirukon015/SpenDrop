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

