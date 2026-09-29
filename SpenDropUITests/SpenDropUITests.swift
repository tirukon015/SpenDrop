import XCTest

/// Drives SpenDrop like a user. The app is launched with `--ui-testing`, which uses a fresh temporary
/// database for every launch and never touches the user's data or backup files.
final class SpenDropUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(name) missing")
        button.tap()
    }

    /// Opens the Add sheet from Transactions and switches to a record type ("Expense", "Money In", …).
    private func openAdd(_ type: String) {
        tab("Transactions")
        let add = app.navigationBars.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        if type != "Expense" {
            let menu = app.buttons["Record type: Expense"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            let ids = ["Money In": "addType.moneyIn", "Money Out": "addType.moneyOut", "Transfer": "addType.transfer"]
            let item = app.buttons[ids[type] ?? type]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
        }
    }

