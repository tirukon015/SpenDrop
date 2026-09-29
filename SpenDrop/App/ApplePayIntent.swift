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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ExpenseDataContainer.shared.mainContext
        guard ExpenseDataContainer.isPersistentStoreHealthy else {
            return .result(dialog: "SpenDrop can't open its data right now. Open the app to check.")
        }
        let outcome = ApplePayAutomation.record(amount: amount, merchant: merchant, card: card, in: context)
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

struct SpenDropShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogApplePayPurchaseIntent(),
            phrases: ["Log Apple Pay purchase in \(.applicationName)"],
            shortTitle: "Log Apple Pay Purchase",
            systemImageName: "wallet.pass"
        )
    }
}
