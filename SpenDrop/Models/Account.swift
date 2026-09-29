import Foundation
import SwiftData

public enum AccountType: String, CaseIterable, Codable, Identifiable {
    case bank = "bank"
    case eWallet = "eWallet"
    case cash = "cash"
    case other = "other"

    public var id: String { rawValue }
}

