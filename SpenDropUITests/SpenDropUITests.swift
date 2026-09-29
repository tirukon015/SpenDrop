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

    private func typeAmount(_ text: String) {
        let field = app.textFields["0.00"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func choose(_ option: String, inPicker label: String) {
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "picker \(label) missing")
        picker.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "option \(option) missing")
        item.tap()
    }

    private func addAccount(_ name: String) {
        tab("More")
        app.buttons["more.accounts"].tap()
        let add = app.navigationBars["Accounts"].buttons["Add Account"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields["Name (e.g. Maybank)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.navigationBars["New Account"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        app.navigationBars["Accounts"].buttons.element(boundBy: 0).tap()   // back to More
    }

    func test01_FiveTabsInOrder() {
        let labels = app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["Home", "Transactions", "PayBook", "Breakdown", "More"])
        for name in labels {
            tab(name)
            snap("Tab \(name)")
        }
        XCTAssertTrue(app.staticTexts["Home"].exists || app.navigationBars["More"].exists)
    }

    func test02_AddNormalExpense() {
        openAdd("Expense")
        typeAmount("25")
        snap("Add Expense")
        app.buttons["Save Expense"].tap()
        tab("Transactions")
        XCTAssertTrue(app.staticTexts["RM 25.00"].firstMatch.waitForExistence(timeout: 5))
        snap("Transactions after expense")
    }

    func test03_SplitExpenseCreatesBalance() {
        openAdd("Expense")
        typeAmount("30")
        app.buttons["addExpense.split"].tap()
        app.buttons["split.addPerson"].tap()
        let newPerson = app.buttons["New Person"]
        XCTAssertTrue(newPerson.waitForExistence(timeout: 5))
        newPerson.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Bijoy")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Bijoy"].waitForExistence(timeout: 5))
        snap("Split editor")
        app.buttons["split.done"].tap()
        XCTAssertTrue(app.staticTexts["Shared · 2 people"].waitForExistence(timeout: 5))
        app.buttons["Save Expense"].tap()

        tab("PayBook")
        XCTAssertTrue(app.staticTexts["owes you"].waitForExistence(timeout: 5))
        snap("PayBook balances")
        app.staticTexts["Bijoy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 15.00"].waitForExistence(timeout: 5))
        snap("Person detail")
    }

    func test04_AccountsMoneyInAndTransfer() {
        addAccount("Maybank")
        addAccount("Touch n Go")

        openAdd("Money In")
        typeAmount("3500")
        choose("Maybank", inPicker: "Into account")
        snap("Money In form")
        app.buttons["Save Money In"].tap()

        openAdd("Transfer")
        typeAmount("200")
        choose("Maybank", inPicker: "From")
        choose("Touch n Go", inPicker: "To")
        snap("Transfer form")
        app.buttons["Save Transfer"].tap()

        tab("Transactions")
        app.buttons["transactions.filter.transfers"].tap()
        XCTAssertTrue(app.staticTexts["Maybank → Touch n Go"].waitForExistence(timeout: 5))
        snap("Transactions transfers")
        app.buttons["transactions.filter.moneyIn"].tap()
        XCTAssertTrue(app.staticTexts["+RM 3,500.00"].firstMatch.waitForExistence(timeout: 5))
        snap("Transactions money in")

        tab("More")
        app.buttons["more.accounts"].tap()
        XCTAssertTrue(app.staticTexts["RM 3,500.00"].firstMatch.waitForExistence(timeout: 5))
        snap("Accounts recorded")
    }

    func test05_HomeAndBreakdownCashFlow() {
        openAdd("Money In")
        typeAmount("1000")
        app.buttons["Save Money In"].tap()
        tab("Home")
        XCTAssertTrue(app.otherElements["home.cashFlow"].waitForExistence(timeout: 5) || app.staticTexts["CASH FLOW · THIS MONTH"].exists)
        snap("Home cash flow")
        tab("Breakdown")
        app.segmentedControls["breakdown.mode"].buttons["Cash Flow"].tap()
        XCTAssertTrue(app.staticTexts["NET CASH FLOW"].waitForExistence(timeout: 5))
        snap("Breakdown cash flow")
    }

    func test06_AccountScreenIsLocalFirst() {
        tab("More")
        app.buttons["more.account"].tap()
        XCTAssertTrue(app.staticTexts["Cloud backup isn't set up in this build"].waitForExistence(timeout: 5))
        snap("More Account")
    }
}
