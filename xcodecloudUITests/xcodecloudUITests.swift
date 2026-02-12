import XCTest

final class xcodecloudUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSettingsCredentialsPersistAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["open-settings-button"].tap()
        app.buttons["settings-credentials-link"].tap()

        let keyField = app.textFields["credentials-key-id-field"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 3))
        keyField.tap()
        keyField.clearAndTypeText("persist-key-id")

        app.buttons["Done"].tap()
        app.terminate()

        app.launch()
        app.buttons["open-settings-button"].tap()
        app.buttons["settings-credentials-link"].tap()

        XCTAssertTrue(app.textFields["credentials-key-id-field"].value as? String == "persist-key-id")
    }

    @MainActor
    func testTestConnectionShowsValidationMessage() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["open-settings-button"].tap()
        app.buttons["settings-credentials-link"].tap()
        app.buttons["credentials-test-button"].tap()

        let resultLabel = app.staticTexts["credentials-result-label"]
        XCTAssertTrue(resultLabel.waitForExistence(timeout: 3))
    }

    @MainActor
    func testClearCredentialsShowsMissingState() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["open-settings-button"].tap()
        app.buttons["settings-credentials-link"].tap()

        let keyField = app.textFields["credentials-key-id-field"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 3))
        keyField.tap()
        keyField.clearAndTypeText("temp-key")

        app.buttons["credentials-clear-button"].tap()
        app.buttons["Done"].tap()

        let statusView = app.otherElements["dashboard-status-view"]
        XCTAssertTrue(statusView.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String else {
            typeText(text)
            return
        }

        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(deleteString + text)
    }
}
