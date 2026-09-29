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

