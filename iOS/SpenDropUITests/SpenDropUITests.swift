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

    /// Turns on "Split Transaction" in Add Expense (the split section opens in place).
    private func turnOnSplit() {
        let toggle = app.switches["addExpense.splitToggle"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        if (toggle.value as? String) != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        XCTAssertTrue(app.buttons["split.addPerson"].waitForExistence(timeout: 5))
    }

    private func addNewPersonToSplit(_ person: String) {
        let add = app.buttons["split.addPerson"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()
        let newPerson = app.buttons["New Person"]
        XCTAssertTrue(newPerson.waitForExistence(timeout: 5))
        newPerson.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText(person)
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts[person].waitForExistence(timeout: 5))
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
        let add = app.navigationBars["Bank Accounts"].buttons["Add Account"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields["Name (e.g. Maybank)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.navigationBars["New Account"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        app.navigationBars["Bank Accounts"].buttons.element(boundBy: 0).tap()   // back to More
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
        turnOnSplit()
        addNewPersonToSplit("Bijoy")
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 15.00"].waitForExistence(timeout: 5), "equal split shown inline, no extra screen")
        snap("Split inline")
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
        // Builds without CloudConfig/SupabaseConfig.plist say cloud isn't set up; configured builds ask to sign in.
        // Either way the screen must say local data stays on the iPhone.
        let notConfigured = app.staticTexts["Cloud backup isn't set up in this build"]
        let signIn = app.staticTexts["Sign in to enable cloud backup"]
        XCTAssertTrue(notConfigured.waitForExistence(timeout: 5) || signIn.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "iPhone")).firstMatch.exists)
        if signIn.exists {
            // Signed-out state offers every sign-in option and no account actions.
            XCTAssertTrue(app.buttons["account.google"].exists)
            XCTAssertTrue(app.buttons["account.signIn"].exists)
            XCTAssertTrue(app.buttons["account.create"].exists)
            XCTAssertFalse(app.buttons["Sign Out"].exists)
        }
        snap("More Account")
    }

    func test07_SignedInAccountScreen() throws {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-signed-in"]
        app.launch()
        tab("More")
        app.buttons["more.account"].tap()
        guard !app.staticTexts["Cloud backup isn't set up in this build"].waitForExistence(timeout: 3) else {
            throw XCTSkip("This build has no Supabase config, so there is no signed-in state to show.")
        }
        XCTAssertTrue(app.staticTexts["ui.test@gmail.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Google"].exists)
        XCTAssertTrue(app.staticTexts["Signed in"].exists)
        let autoBackup = app.switches["account.autoBackup"]
        XCTAssertTrue(autoBackup.exists)
        XCTAssertEqual(autoBackup.value as? String, "0", "Automatic cloud backup must be off after signing in")
        // Turning it on asks first; cancelling leaves it off and uploads nothing.
        autoBackup.switches.firstMatch.tap()
        XCTAssertTrue(app.alerts["Enable Cloud Backup?"].waitForExistence(timeout: 5))
        app.alerts["Enable Cloud Backup?"].buttons["Cancel"].tap()
        XCTAssertEqual(autoBackup.value as? String, "0")
        XCTAssertFalse(app.buttons["account.google"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Sign Out"].exists)
        snap("More Account Signed In")
    }

    /// Local restore with a date range: options, preview counts from the real backup, explicit confirmation,
    /// Cancel changes nothing, Restore merges and shows a summary. Uses a fixed backup (5 Oct 2026, 7 expenses).
    func test08_RestoreRangePreviewConfirmAndSummary() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-backup-fixture"]
        app.launch()

        func openRestore() {
            tab("More")
            let restore = app.buttons["settings.restoreLocal"]
            if !restore.waitForExistence(timeout: 2) {  // the More tab may still be showing Settings
                XCTAssertTrue(app.buttons["more.settings"].waitForExistence(timeout: 5))
                app.buttons["more.settings"].tap()
            }
            for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
            restore.tap()
            XCTAssertTrue(app.buttons["restore.option.everything"].waitForExistence(timeout: 10))
        }

        /// Rows below the options are created only when scrolled into view.
        func scrolledTo(_ element: XCUIElement) -> XCUIElement {
            for _ in 0..<5 where !element.exists || !element.isHittable { app.swipeUp() }
            return element
        }
        func backToTop() { for _ in 0..<3 { app.swipeDown() } }

        openRestore()
        XCTAssertTrue(app.staticTexts["restore.backupCounts"].label.contains("7 expenses"))
        for option in ["everything", "last7", "last30", "last2Months", "last3Months", "custom"] {
            XCTAssertTrue(scrolledTo(app.buttons["restore.option.\(option)"]).exists, "option \(option) missing")
        }
        XCTAssertTrue(scrolledTo(app.staticTexts["restore.found"]).label.contains("7 expenses"), "Everything must not be date-filtered")

        backToTop()
        scrolledTo(app.buttons["restore.option.last7"]).tap()
        XCTAssertTrue(app.buttons["restore.option.last7"].isSelected)
        XCTAssertTrue(scrolledTo(app.staticTexts["restore.found"]).label.contains("3 expenses"))
        snap("Restore range: last 7 days")

        // Confirmation required; Cancel restores nothing.
        scrolledTo(app.buttons["restore.continue"]).tap()
        let confirm = app.alerts["Restore Last 7 days?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3 expenses")).firstMatch.exists)
        confirm.buttons["Cancel"].tap()
        app.navigationBars.buttons["Close"].tap()
        tab("Transactions")
        XCTAssertFalse(app.staticTexts["Fixture Today"].waitForExistence(timeout: 2), "Cancel must not restore anything")

        // Restore → summary → only the 7-day expenses are added.
        openRestore()
        scrolledTo(app.buttons["restore.option.last7"]).tap()
        scrolledTo(app.buttons["restore.continue"]).tap()
        XCTAssertTrue(app.alerts["Restore Last 7 days?"].waitForExistence(timeout: 5))
        app.alerts["Restore Last 7 days?"].buttons["Restore"].tap()
        let added = app.staticTexts["restore.summary.added"]
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        XCTAssertTrue(added.label.contains("3 expenses"))
        snap("Restore complete")
        app.buttons["restore.done"].tap()
        app.navigationBars.buttons["Close"].tap()
        tab("Transactions")
        XCTAssertTrue(app.staticTexts["Fixture Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrolledTo(app.staticTexts["Fixture Six Days"]).exists)
        XCTAssertFalse(scrolledTo(app.staticTexts["Fixture Old"]).exists)
    }

    /// "I paid RM100 for Bijoy" twice (both kept), then Mark as Paid on one: only that one is settled.
    func test11_PaidForSomeoneAndMarkOneAsPaid() {
        for round in 0..<2 {
            openAdd("Expense")
            typeAmount("100")
            let paidFor = app.buttons["addExpense.paidFor"]
            for _ in 0..<3 where !paidFor.isHittable { app.swipeUp() }
            paidFor.tap()
            // Opens the same inline split section as every other screen, already set to Paid for Someone.
            let addPerson = app.buttons["split.addPerson"]
            XCTAssertTrue(addPerson.waitForExistence(timeout: 5), "inline split opens in Paid for Someone mode")
            for _ in 0..<4 where !addPerson.isHittable { app.swipeUp() }
            addPerson.tap()
            if round == 0 {
                XCTAssertTrue(app.buttons["New Person"].waitForExistence(timeout: 5))
                app.buttons["New Person"].tap()
                let name = app.alerts.textFields.firstMatch
                XCTAssertTrue(name.waitForExistence(timeout: 5))
                name.typeText("Bijoy")
                app.alerts.buttons["Add"].tap()
            } else {
                let existing = app.staticTexts["Bijoy"].firstMatch
                XCTAssertTrue(existing.waitForExistence(timeout: 5))
                existing.tap()
            }
            XCTAssertTrue(app.staticTexts["Bijoy owes you RM 100.00"].waitForExistence(timeout: 5), "preview shows the debt; no share typed")
            if round == 0 { snap("Paid for someone") }
            let save = app.buttons["Save Expense"]
            for _ in 0..<5 where !save.isHittable { app.swipeUp() }
            save.tap()
        }

        tab("PayBook")
        // PayBook opens on "They Owe Me"; "I Owe Them" is empty here; switching back shows Bijoy again.
        let filter = app.segmentedControls["paybook.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        XCTAssertTrue(filter.buttons["They Owe Me"].isSelected)
        XCTAssertTrue(app.staticTexts["Bijoy"].firstMatch.exists)
        filter.buttons["I Owe Them"].tap()
        XCTAssertTrue(app.staticTexts["You don't owe anyone right now."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bijoy"].firstMatch.exists)
        snap("PayBook I Owe Them")
        filter.buttons["They Owe Me"].tap()
        app.staticTexts["Bijoy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 200.00"].waitForExistence(timeout: 5), "two identical RM100 transactions both count")
        // Each outstanding row's "Settle" button is labelled for VoiceOver as "Mark <transaction> as paid".
        let settle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' as paid'")).firstMatch
        for _ in 0..<3 where !settle.isHittable { app.swipeUp() }
        settle.tap()
        let confirm = app.buttons["Mark RM 100.00 as Paid"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the outstanding amount is used automatically")
        confirm.tap()
        for _ in 0..<3 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 100.00"].waitForExistence(timeout: 5), "only one transaction was settled")
        snap("One of two settled")
    }

    /// Load and remove sample data, each only after confirming.
    func test12_SampleDataNeedsConfirmation() {
        tab("More")
        app.buttons["more.settings"].tap()
        let load = app.buttons["settings.loadSample"]
        for _ in 0..<6 where !load.isHittable { app.swipeUp() }
        XCTAssertTrue(load.isEnabled, "a new install has no sample data")
        XCTAssertFalse(app.buttons["settings.removeSample"].exists)

        load.tap()
        XCTAssertTrue(app.alerts["Load Sample Data?"].waitForExistence(timeout: 5))
        app.alerts["Load Sample Data?"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["settings.removeSample"].exists, "Cancel loads nothing")

        load.tap()
        app.alerts["Load Sample Data?"].buttons["Load Sample Data"].tap()
        XCTAssertTrue(app.alerts["Sample Data Loaded"].waitForExistence(timeout: 5))
        app.alerts["Sample Data Loaded"].buttons["OK"].tap()
        XCTAssertFalse(load.isEnabled, "loading twice is not possible")
        let remove = app.buttons["settings.removeSample"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        snap("Sample data loaded")

        remove.tap()
        let confirmRemove = app.alerts["Remove Sample Data?"]
        XCTAssertTrue(confirmRemove.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmRemove.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "will not be affected")).firstMatch.exists)
        confirmRemove.buttons["Remove Sample Data"].tap()
        XCTAssertTrue(app.alerts["Sample Data Removed"].waitForExistence(timeout: 5))
        app.alerts["Sample Data Removed"].buttons["OK"].tap()
        XCTAssertTrue(load.isEnabled)
        XCTAssertFalse(remove.exists)
    }

    /// Opens a URL the way Mail/Safari would, accepting the system's "Open in SpenDrop?" prompt.
    private func openLink(_ string: String) {
        app.open(URL(string: string)!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 5) { springboard.buttons["Open"].tap() }
    }

    func test09_EmailLinksReturnToTheApp() throws {
        // Expired confirmation/reset link → clear message, nothing else changes.
        openLink("spendrop://auth-callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")
        let expired = app.alerts["Link Couldn't Be Used"]
        guard expired.waitForExistence(timeout: 10) else {
            XCTAssertFalse(app.staticTexts["Cloud backup isn't set up in this build"].exists)
            throw XCTSkip("This build has no Supabase config, so email links are not handled.")
        }
        XCTAssertTrue(expired.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "expired")).firstMatch.exists)
        snap("Expired email link")
        expired.buttons["OK"].tap()

        // Confirmation link opened where the account wasn't created → verified, please sign in (no localhost involved).
        openLink("spendrop://auth-callback?code=opened-on-another-device")
        let verified = app.alerts["Email Verified"]
        XCTAssertTrue(verified.waitForExistence(timeout: 10))
        snap("Email verified")
        verified.buttons["OK"].tap()
    }

    func test10_EmailSignInCreateAccountAndForgotPassword() throws {
        tab("More")
        app.buttons["more.account"].tap()
        guard app.buttons["account.signIn"].waitForExistence(timeout: 5) else {
            throw XCTSkip("This build has no Supabase config, so email sign-in is not available.")
        }
        app.buttons["account.signIn"].tap()

        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        let submit = app.buttons["auth.submit"]
        XCTAssertFalse(submit.isEnabled, "Sign In stays disabled until the form is valid")
        email.tap(); email.typeText("not-an-email")
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 3))

        // Create Account: password rules and confirmation must match.
        app.buttons["auth.toCreate"].tap()
        XCTAssertTrue(app.navigationBars["Create Account"].waitForExistence(timeout: 3))
        email.tap(); email.clearAndType("new.user@example.com")
        app.secureTextFields["auth.password"].tap(); app.secureTextFields["auth.password"].typeText("Password1")
        app.secureTextFields["auth.confirm"].tap(); app.secureTextFields["auth.confirm"].typeText("Password2")
        XCTAssertTrue(app.staticTexts["Passwords don't match."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["auth.submit"].isEnabled)
        snap("Create account validation")

        // Forgot Password: only the email; a network failure is shown in plain words and can be retried.
        app.buttons["auth.toSignIn"].tap()
        app.buttons["auth.toForgot"].tap()
        XCTAssertTrue(app.navigationBars["Reset Password"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.secureTextFields["auth.password"].exists)
        email.tap(); email.clearAndType("me@example.com")
        XCTAssertTrue(app.buttons["auth.submit"].isEnabled)
        app.buttons["auth.submit"].tap()  // UI tests have no network: every request fails as offline
        XCTAssertTrue(app.staticTexts["You're offline. Connect to the internet and try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["auth.submit"].isEnabled, "Retry stays possible")
        snap("Forgot password offline")
    }

    /// Split Transaction inside Add Expense: Custom Amount 70/30, Remaining must reach RM 0.00 before saving,
    /// and PayBook then shows Bijoy owes RM 30.
    func test13_InlineCustomSplitMustAddUp() {
        openAdd("Expense")
        typeAmount("100")
        turnOnSplit()
        addNewPersonToSplit("Bijoy")
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let autoCalc = app.switches["split.autoCalculate"]
        for _ in 0..<4 where !autoCalc.isHittable { app.swipeUp() }
        if (autoCalc.value as? String) == "1" { autoCalc.switches.firstMatch.exists ? autoCalc.switches.firstMatch.tap() : autoCalc.tap() }
        let mine = app.textFields["split.amount.me"]
        for _ in 0..<4 where !mine.isHittable { app.swipeDown() }
        mine.replaceText("60")
        let problem = app.descendants(matching: .any)["split.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "60 + 50 of 100 is reported")
        XCTAssertTrue(problem.label.contains("exceed"), problem.label)
        XCTAssertFalse(app.buttons["Save Expense"].isEnabled, "can't save while the split doesn't add up")
        mine.replaceText("70")
        let theirs = app.textFields["split.amount.Bijoy"]
        theirs.replaceText("30")
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 30.00"].waitForExistence(timeout: 5))
        snap("Custom split balanced")
        let save = app.buttons["Save Expense"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        tab("PayBook")
        app.staticTexts["Bijoy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 30.00"].waitForExistence(timeout: 5))
        snap("PayBook after custom split")
    }

    /// Screenshot → share → OCR → review: "Split Money" is on the review screen BEFORE the first save.
    /// RM 100: You 40, Bijoy 30, Riyad 30 → one save → PayBook shows both debts; no edit afterwards.
    func test14_ShareReviewSplitMoneyBeforeFirstSave() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-share-review", "100.00"]
        app.launch()
        let toggle = app.switches["share.splitToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Split Money is offered before saving")
        snap("Share review before split")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        addNewPersonToSplit("Bijoy")
        addNewPersonToSplit("Riyad")
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let autoCalc = app.switches["split.autoCalculate"]
        for _ in 0..<4 where !autoCalc.isHittable { app.swipeUp() }
        if (autoCalc.value as? String) == "1" { autoCalc.switches.firstMatch.exists ? autoCalc.switches.firstMatch.tap() : autoCalc.tap() }
        for (field, value) in [("split.amount.me", "40"), ("split.amount.Bijoy", "30"), ("split.amount.Riyad", "30")] {
            let box = app.textFields[field]
            bringIntoView(box)
            box.replaceText(value)
        }
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 30.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Riyad owes you RM 30.00"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["split.problem"].exists, "Remaining RM 0.00")
        snap("Share review split 40/30/30")
        let save = app.buttons["Save Expense"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        tab("PayBook")
        XCTAssertTrue(app.staticTexts["Bijoy"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Riyad"].firstMatch.exists)
        app.staticTexts["Bijoy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 30.00"].waitForExistence(timeout: 5), "PayBook updated from the one save")
        snap("PayBook after share split")
    }

    /// RM 150 split equally between You, Person A and Person B → RM 50 each, saved once.
    func test15_ShareReviewEqualSplit() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-share-review", "150.00"]
        app.launch()
        let toggle = app.switches["share.splitToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        addNewPersonToSplit("Person A")
        addNewPersonToSplit("Person B")
        XCTAssertTrue(app.staticTexts["Person A owes you RM 50.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Person B owes you RM 50.00"].exists)
        snap("Share review equal split")
        let save = app.buttons["Save Expense"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()
        tab("PayBook")
        app.staticTexts["Person A"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Person A owes you RM 50.00"].waitForExistence(timeout: 5))
    }

    /// RM200 shared by Me, Vijay, Riyadh; the pin icon beside Vijay sets a RM50 fixed amount → 50 / 100 / 50.
    /// Then Auto Calculate OFF for one transaction (70/50/80 typed, nothing changed by itself) and the next new
    /// transaction starts with Auto Calculate ON again.
    func test16_FixedAmountAndPerTransactionAutoCalculate() {
        openAdd("Expense")
        typeAmount("200")
        turnOnSplit()
        addNewPersonToSplit("Vijay")
        addNewPersonToSplit("Riyadh")
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let pin = app.buttons["split.fixed.Vijay"]
        for _ in 0..<4 where !pin.isHittable { app.swipeUp() }
        pin.tap()
        let fixedField = app.textFields["fixed.amount"]
        XCTAssertTrue(fixedField.waitForExistence(timeout: 5))
        fixedField.tap(); fixedField.typeText("50")
        snap("Fixed amount sheet")
        app.buttons["fixed.save"].tap()
        XCTAssertTrue(app.staticTexts["Vijay owes you RM 100.00"].waitForExistence(timeout: 5), "50 fixed + 50 equal share")
        XCTAssertTrue(app.staticTexts["Riyadh owes you RM 50.00"].exists)
        XCTAssertTrue(app.staticTexts["✓ Balanced · Your share RM 50.00"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Your share RM 50.00'")).firstMatch.exists)
        snap("Fixed amount result")
        var save = app.buttons["Save Expense"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()

        // Transaction 2: Auto Calculate starts ON; turn it OFF just for this one
        openAdd("Expense")
        typeAmount("200")
        turnOnSplit()
        for person in ["Vijay", "Riyadh"] {
            let add = app.buttons["split.addPerson"]
            for _ in 0..<4 where !add.isHittable { app.swipeUp() }
            add.tap()
            let existing = app.staticTexts[person].firstMatch
            XCTAssertTrue(existing.waitForExistence(timeout: 5))
            existing.tap()
        }
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let autoCalc = app.switches["split.autoCalculate"]
        for _ in 0..<4 where !autoCalc.isHittable { app.swipeUp() }
        XCTAssertEqual(autoCalc.value as? String, "1", "a new transaction starts with Auto Calculate ON")
        autoCalc.switches.firstMatch.exists ? autoCalc.switches.firstMatch.tap() : autoCalc.tap()
        XCTAssertEqual(autoCalc.value as? String, "0")
        for (field, value) in [("split.amount.me", "70"), ("split.amount.Vijay", "50"), ("split.amount.Riyadh", "50")] {
            let box = app.textFields[field]
            bringIntoView(box)
            box.replaceText(value)
        }
        let problem = app.descendants(matching: .any)["split.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertEqual(problem.label, "RM 30.00 remains unassigned.")
        XCTAssertEqual(app.textFields["split.amount.Riyadh"].value as? String, "50", "nothing redistributed")
        bringIntoView(app.textFields["split.amount.Riyadh"])
        app.textFields["split.amount.Riyadh"].replaceText("80")
        save = app.buttons["Save Expense"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Transaction 3: ON again
        openAdd("Expense")
        typeAmount("90")
        turnOnSplit()
        let add = app.buttons["split.addPerson"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()
        app.staticTexts["Vijay"].firstMatch.tap()
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let autoCalc3 = app.switches["split.autoCalculate"]
        for _ in 0..<4 where !autoCalc3.isHittable { app.swipeUp() }
        XCTAssertEqual(autoCalc3.value as? String, "1", "OFF applied only to the previous transaction")
        snap("Next transaction Auto Calculate ON")
    }

    /// Hybrid Split in Add Expense: RM200; group RM100 divided between Riad + Bijoy; Bijoy +RM20 individual; the rest by
    /// You, Riad and Bijoy → You 26.67, Riad 76.67, Bijoy 96.66. Saved once; Edit restores the Hybrid Split.
    /// Scrolls slowly until the element sits in the visible middle of the screen (not under the navigation bar or the
    /// keyboard), so taps land on it on small iPhones and with large text too.
    private func bringIntoView(_ element: XCUIElement) {
        let height = app.frame.height
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : height - 40
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > 150 && element.frame.maxY < keyboardTop - 10 { return }
            if element.exists && element.frame.minY <= 150 { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
    }

    func test19_HybridSplitInAddExpense() {
        openAdd("Expense")
        typeAmount("200")
        let merchant = app.textFields["e.g. McDonald's, Mamak, Rahim (optional)"]
        for _ in 0..<4 where !merchant.isHittable { app.swipeUp() }
        merchant.tap(); merchant.typeText("Steamboat")
        turnOnSplit()
        for person in ["Riad", "Bijoy"] { addNewPersonToSplit(person) }

        let toggle = app.switches["split.hybrid"]
        for _ in 0..<10 where !(toggle.exists && toggle.isHittable) { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.segmentedControls["split.method"].exists, "the method picker is not used while Hybrid Split is on")

        let problem = app.descendants(matching: .any)["split.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertEqual(problem.label, "Add a group fixed amount or an individual fixed amount.")
        XCTAssertFalse(app.buttons["Save Expense"].isEnabled)

        let groupAmount = app.textFields["split.group1.amount"]
        XCTAssertTrue(groupAmount.waitForExistence(timeout: 5))
        bringIntoView(groupAmount)
        groupAmount.tap(); groupAmount.typeText("100")
        XCTAssertEqual(problem.label, "Choose who shares group fixed amount 1.")
        for id in ["split.group1.member.Riad", "split.group1.member.Bijoy"] {
            let box = app.buttons[id]
            bringIntoView(box)
            box.tap()
            XCTAssertEqual(box.value as? String, "Selected")
        }
        XCTAssertEqual(app.staticTexts["split.group1.preview"].label, "Riad RM 50.00 · Bijoy RM 50.00")
        snap("Hybrid group card")

        let addIndividual = app.buttons["split.addIndividual"]
        bringIntoView(addIndividual)
        addIndividual.tap()
        let personMenu = app.buttons["split.individual1.person"]
        XCTAssertTrue(personMenu.waitForExistence(timeout: 5))
        bringIntoView(personMenu)
        personMenu.tap()
        let bijoyItem = app.buttons.matching(NSPredicate(format: "label == 'Bijoy' AND NOT (identifier BEGINSWITH 'split.')")).firstMatch
        XCTAssertTrue(bijoyItem.waitForExistence(timeout: 5))
        bijoyItem.tap()
        XCTAssertEqual(problem.label, "Enter the individual fixed amount for Bijoy.")
        let individualAmount = app.textFields["split.individual1.amount"]
        bringIntoView(individualAmount)
        individualAmount.tap(); individualAmount.typeText("20")
        snap("Hybrid individual card")

        XCTAssertEqual(app.staticTexts["split.hybridRemaining"].label, "RM 80.00")
        XCTAssertFalse(problem.exists, "the split is complete")
        let detail = app.staticTexts["split.finalDetail.Bijoy"]
        for _ in 0..<4 where !detail.isHittable { app.swipeUp() }
        XCTAssertEqual(detail.label, "RM 50.00 group + RM 20.00 individual + RM 26.66 remaining")
        XCTAssertEqual(app.staticTexts["split.final.Bijoy"].label, "RM 96.66")
        XCTAssertEqual(app.staticTexts["split.final.Riad"].label, "RM 76.67")
        XCTAssertEqual(app.staticTexts["split.final.me"].label, "RM 26.67")
        XCTAssertTrue(app.staticTexts["Riad owes you RM 76.67"].exists)
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 96.66"].exists)
        snap("Hybrid split")

        // Live: a bigger group amount updates everything at once (no Calculate button).
        bringIntoView(groupAmount)
        groupAmount.replaceText("120")
        XCTAssertEqual(app.staticTexts["split.group1.preview"].label, "Riad RM 60.00 · Bijoy RM 60.00")
        XCTAssertEqual(app.staticTexts["split.final.Bijoy"].label, "RM 100.00")
        groupAmount.replaceText("100")
        XCTAssertEqual(app.staticTexts["split.final.Bijoy"].label, "RM 96.66")

        let save = app.buttons["Save Expense"]
        for _ in 0..<8 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        tab("PayBook")
        app.staticTexts["Bijoy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bijoy owes you RM 96.66"].waitForExistence(timeout: 5))

        tab("Transactions")
        let row = app.staticTexts["Steamboat"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let restored = app.switches["split.hybrid"]
        for _ in 0..<12 where !(restored.exists && restored.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, "1", "Edit restores Hybrid Split")
        XCTAssertEqual(app.textFields["split.group1.amount"].value as? String, "100.00")
        XCTAssertEqual(app.buttons["split.group1.member.Riad"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["split.group1.member.me"].value as? String, "Not selected")
        XCTAssertEqual(app.textFields["split.individual1.amount"].value as? String, "20.00")
        XCTAssertEqual(app.buttons["split.individual1.person"].label.hasPrefix("Bijoy"), true, app.buttons["split.individual1.person"].label)
        let bijoyFinal = app.staticTexts["split.final.Bijoy"]
        for _ in 0..<8 where !bijoyFinal.isHittable { app.swipeUp() }
        XCTAssertEqual(bijoyFinal.label, "RM 96.66")
        snap("Edit restores hybrid split")
    }

    /// The screenshot case, through the Share Extension review: Paid by Riyad, You left empty, Riyad RM100 → valid,
    /// saved once; Edit restores Paid by Riyad and the amounts.
    func test17_ShareReviewPaidByOtherPersonPersistsAndEdits() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-share-review", "100.00"]
        app.launch()
        let toggle = app.switches["share.splitToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        addNewPersonToSplit("Riyad")
        app.segmentedControls["split.method"].buttons["Custom Amount"].tap()
        let autoCalc = app.switches["split.autoCalculate"]
        for _ in 0..<4 where !autoCalc.isHittable { app.swipeUp() }
        if (autoCalc.value as? String) == "1" { autoCalc.switches.firstMatch.exists ? autoCalc.switches.firstMatch.tap() : autoCalc.tap() }
        let mine = app.textFields["split.amount.me"]
        for _ in 0..<4 where !mine.isHittable { app.swipeDown() }
        mine.replaceText("")
        app.textFields["split.amount.Riyad"].replaceText("100")
        let paidBy = app.buttons["split.paidBy"]
        for _ in 0..<4 where !paidBy.isHittable { app.swipeUp() }
        paidBy.tap()
        app.buttons["Riyad"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Enter an amount'")).firstMatch.exists, "no 'Enter an amount for Me'")
        XCTAssertFalse(app.descendants(matching: .any)["split.problem"].exists, "split is valid")
        snap("Share review paid by Riyad")
        let save = app.buttons["Save Expense"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        tab("Transactions")
        let row = app.staticTexts["RESTORAN SELERA KAMPUNG"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let restoredPayer = app.buttons["split.paidBy"]
        for _ in 0..<6 where !restoredPayer.isHittable { app.swipeUp() }
        XCTAssertTrue(restoredPayer.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredPayer.label.contains("Riyad"), "Edit restores Paid by Riyad, not Me: \(restoredPayer.label)")
        XCTAssertEqual(app.textFields["split.amount.Riyad"].value as? String, "100.00")
        snap("Edit restores paid by Riyad")
    }

    /// Bulk Import from Home with fixture screenshots (a receipt, a 2-row history, the same receipt again, one with no
    /// text): review queue, the full editor inside a card, duplicate skipped by default, "Add 3", each saved separately.
    func test18_BulkImportReviewQueue() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-bulk-import"]
        app.launch()
        let entry = app.buttons["home.bulkImport"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Bulk Import is offered on Home")
        entry.tap()

        let add = app.buttons["bulk.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "review queue appears after reading")
        XCTAssertEqual(add.label, "Add 3 Transactions", "the duplicate of screenshot 1 is skipped by default")
        XCTAssertEqual(app.staticTexts["bulk.summary"].label, "4 screenshots · 4 transactions detected")
        XCTAssertTrue(app.staticTexts["Possible Duplicate"].exists)
        let unreadable = app.descendants(matching: .any)["bulk.unreadable.4"]
        for _ in 0..<4 where !unreadable.exists { app.swipeUp() }
        XCTAssertTrue(unreadable.exists, "a screenshot without a transaction is listed")
        snap("Bulk import review queue")
        for _ in 0..<4 { app.swipeDown() }

        // A card opens into the normal editor (Save as, fields, Split Money).
        let card = app.buttons["bulk.card.1.0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let split = app.switches["share.splitToggle"]
        for _ in 0..<5 where !split.isHittable { app.swipeUp() }
        XCTAssertTrue(split.exists, "the full editor with Split Money is inside the card")
        XCTAssertTrue(app.buttons["draft.paidFor"].exists, "Paid for Someone is offered")
        snap("Bulk import card expanded")
        let collapse = app.buttons["bulk.collapse"]
        for _ in 0..<5 where !collapse.isHittable { app.swipeUp() }
        collapse.tap()

        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["Added 3 transactions"].waitForExistence(timeout: 10))
        app.buttons["bulk.done"].tap()

        tab("Transactions")
        // The two history rows are dated today (the receipt is dated 16 Sep, outside the default period).
        for name in ["Grab", "Starbucks"] {
            XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5), "\(name) saved as its own transaction")
        }
        snap("Bulk import saved")
    }
}

private extension XCUIElement {
    /// Puts the cursor at the end of a filled text field, deletes what's there and types `text`.
    func replaceText(_ text: String) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = (value as? String) ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    func clearAndType(_ text: String) {
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
