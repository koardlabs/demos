import XCTest

final class StandardDemoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["KOARD_TEST_APP_ID"] ?? "com.koard.KoardMerchantSDK-Demo")
    }

    @MainActor
    func testRegisterTicketReviewAndCustomAmount() {
        launchPreview()
        let checkout = app.buttons["pos.checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 15))
        XCTAssertFalse(checkout.isEnabled)
        let latte = app.buttons["pos.item.latte"]
        XCTAssertTrue(latte.isHittable)
        latte.tap(); latte.tap()
        XCTAssertTrue(checkout.isEnabled)
        screenshot("ios-register-light")
        let compactTicket = app.buttons["pos.ticket"].exists
        if compactTicket { app.buttons["pos.ticket"].tap() }
        let decrease = app.buttons["pos.quantity.latte.minus"]
        XCTAssertTrue(decrease.waitForExistence(timeout: 5))
        decrease.tap()
        XCTAssertEqual(app.staticTexts["pos.total"].label, "$5.50")
        if compactTicket { app.buttons["Done"].tap() }
        app.buttons["pos.customAmount"].tap()
        XCTAssertTrue(app.buttons["pos.customAdd"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pos.customAdd"].isEnabled)
        app.buttons["Digit 1"].tap(); app.buttons["Digit 2"].tap(); app.buttons["Digit 3"].tap()
        XCTAssertEqual(app.staticTexts["pos.customTotal"].label, "$1.23")
        app.buttons["pos.customAdd"].tap()
        XCTAssertTrue(checkout.waitForExistence(timeout: 5))
        checkout.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sale'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Auth'")).firstMatch.isHittable)
        screenshot("ios-payment-review")
        app.buttons["Cancel"].tap()
        if compactTicket { app.buttons["pos.ticket"].tap() }
        XCTAssertEqual(app.staticTexts["pos.total"].label, "$6.73")
        app.buttons["pos.clear"].tap()
        XCTAssertEqual(app.staticTexts["pos.total"].label, "$0.00")
    }

    @MainActor
    func testAuthorizationsOfferTipAdjustAndExistingFollowups() {
        launchPreview()
        app.buttons["Activity"].tap()
        let filter = app.buttons["Authorizations"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS '4444'")).firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        payment.tap()
        for action in ["Capture", "Incremental Auth", "Reverse", "Tip Adjust", "Refund"] {
            let button = app.buttons["transaction.action.\(action)"]
            reveal(button)
            XCTAssertTrue(button.isEnabled && button.isHittable, "Missing usable follow-up: \(action)")
        }
        app.buttons["transaction.action.Tip Adjust"].tap()
        XCTAssertTrue(app.buttons["Adjust Tip"].waitForExistence(timeout: 5))
        let amount = app.textFields["transaction.amount"]
        amount.tap()
        let previous = amount.value as? String ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        XCTAssertFalse(app.buttons["Adjust Tip"].isEnabled)
        amount.typeText("0")
        XCTAssertFalse(app.buttons["Adjust Tip"].isEnabled)
        amount.typeText(XCUIKeyboardKey.delete.rawValue)
        amount.typeText("1")
        XCTAssertTrue(app.buttons["Adjust Tip"].isEnabled)
        screenshot("ios-preauth-tip-adjust")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testLocationPickerReopensAndDarkModePersists() {
        launchPreview()
        XCTAssertTrue(app.buttons["pos.location"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            app.buttons["pos.location"].tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Downtown Coffee'")).firstMatch.waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
        }
        app.buttons["Settings"].tap()
        let dark = app.switches["settings.darkMode"]
        reveal(dark); dark.tap()
        XCTAssertTrue(waitForValue(dark, "1"))
        let guide = app.buttons["settings.tutorial"]
        reveal(guide); guide.tap()
        XCTAssertTrue(app.buttons["tutorial.apple.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tutorial.apple.open"].isHittable)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Register"].tap()
        screenshot("ios-register-dark")
        app.terminate()
        app.launchArguments = ["-pos-preview"]
        app.launch()
        app.buttons["Settings"].tap()
        reveal(dark)
        XCTAssertTrue(waitForValue(dark, "1"))
        XCTAssertFalse(app.buttons["Tap to Confirm"].exists)
        XCTAssertFalse(app.buttons["Travel"].exists)
    }

    @MainActor
    func testLoginFieldsRemainInteractive() {
        app.launchArguments = ["-pos-login-preview"]
        app.launch()
        let code = app.textFields["login.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap(); code.typeText("ABC123456789")
        XCTAssertEqual(code.value as? String, "ABC123456789")
        let pin = app.secureTextFields["login.pin"]
        reveal(pin); pin.tap(); pin.typeText("123456")
        app.buttons["login.done"].tap()
        XCTAssertTrue(app.buttons["Open register"].isEnabled)
        // Do not submit preview credentials to the service.
    }

    @MainActor
    func testLiveCertLoginLocationsAndHistory() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let code = environment["KOARD_TEST_MERCHANT_CODE"], let pin = environment["KOARD_TEST_MERCHANT_PIN"] else {
            throw XCTSkip("Provide a private credentials file to run the live cert integration.")
        }
        app.launchArguments = ["-demo.hasLaunchedBefore", "NO"]
        app.launch()
        let codeField = app.textFields["login.code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 15))
        codeField.tap(); codeField.typeText(code)
        let pinField = app.secureTextFields["login.pin"]
        reveal(pinField); pinField.tap(); pinField.typeText(pin)
        app.buttons["login.done"].tap()
        app.buttons["Open register"].tap()
        XCTAssertTrue(app.buttons["pos.location"].waitForExistence(timeout: 45))
        for _ in 0..<2 {
            app.buttons["pos.location"].tap()
            XCTAssertTrue(app.navigationBars["Select Location"].waitForExistence(timeout: 5))
            let location = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ProPay'")).firstMatch
            reveal(location)
            XCTAssertTrue(location.isHittable)
            app.buttons["Done"].tap()
        }
        app.buttons["Activity"].tap()
        XCTAssertTrue(app.scrollViews["history.loaded"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["history.error"].exists)
        screenshot("ios-live-cert-activity")
    }

    @MainActor private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor private func launchPreview() {
        app.launchArguments = ["-pos-preview", "-demo.appearance", "light"]
        app.launch()
    }

    @MainActor private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() }
            else if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else { app.tables.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
