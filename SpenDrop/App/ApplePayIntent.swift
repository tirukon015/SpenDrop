import AppIntents
import SwiftData

/// Shortcuts action for the Wallet "Transaction" automation:
/// Shortcuts → Automation → Wallet → choose cards → "Log Apple Pay Purchase" with the Merchant and Amount variables.
struct LogApplePayPurchaseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Apple Pay Purchase"
    static var description = IntentDescription("Adds an Apple Pay purchase to SpenDrop. Use it in a Shortcuts Wallet “Transaction” automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Card")
    var card: String?

