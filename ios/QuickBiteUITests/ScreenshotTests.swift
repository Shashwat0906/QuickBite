import XCTest

/// Captures README screenshots against a REAL running backend (see
/// .github/workflows/screenshots.yml). Skipped unless QB_SCREENSHOT_DIR is set
/// (CI passes it as TEST_RUNNER_QB_SCREENSHOT_DIR).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let dir = ProcessInfo.processInfo.environment["QB_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set QB_SCREENSHOT_DIR to capture screenshots")
        }
        outputDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func snap(_ name: String, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: outputDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testCaptureScreens() {
        // Onboarding (fresh install)
        app.launchArguments = ["-resetState", "-screenshots"]
        app.launch()
        XCTAssertTrue(element("onboardingTitle_0").waitForExistence(timeout: 10))
        snap("01-onboarding")
        app.buttons["onboardingGuest"].tap()

        // Home with real data + images
        XCTAssertTrue(element("homeSearch").waitForExistence(timeout: 20))
        snap("02-home", settle: 5)
        app.swipeUp()
        snap("03-home-cafes", settle: 3)
        app.swipeDown()
        app.swipeDown()

        // Cafe menu
        let cafe = element("cafeCard_Brew & Bloom")
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        cafe.tap()
        XCTAssertTrue(app.cells["foodItem_Signature Cappuccino"].waitForExistence(timeout: 10))
        snap("04-cafe-menu", settle: 4)

        // Customisation sheet
        app.cells["foodItem_Signature Cappuccino"].buttons["addToCart"].tap()
        XCTAssertTrue(element("confirmCustomization").waitForExistence(timeout: 5))
        element("option_Large").tap()
        element("option_Oat milk").tap()
        snap("05-customize")
        element("confirmCustomization").tap()

        let croissant = app.cells["foodItem_Butter Croissant"]
        for _ in 0..<4 where !croissant.exists || !croissant.buttons["addToCart"].isHittable { app.swipeUp() }
        if croissant.buttons["addToCart"].exists { croissant.buttons["addToCart"].tap() }

        // Cart
        element("viewCartBar").tap()
        XCTAssertTrue(app.buttons["checkoutButton"].waitForExistence(timeout: 5))
        snap("06-cart", settle: 2)

        // Sign in with the seeded demo account
        app.buttons["checkoutButton"].tap()
        XCTAssertTrue(app.buttons["loginButton"].waitForExistence(timeout: 5))
        snap("07-login")
        let email = app.textFields["loginEmail"]
        email.tap()
        email.typeText("demo@quickbite.app")
        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("Demo@1234")
        app.buttons["loginButton"].tap()

        // Checkout
        let place = app.buttons["placeOrderButton"]
        XCTAssertTrue(place.waitForExistence(timeout: 15))
        element("payment_MOCK").tap()
        snap("08-checkout", settle: 2)
        place.tap()
        XCTAssertTrue(app.buttons["mockPaySuccess"].waitForExistence(timeout: 10))
        snap("09-demo-payment")
        app.buttons["mockPaySuccess"].tap()
        XCTAssertTrue(element("orderPlacedTitle").waitForExistence(timeout: 10))
        snap("10-order-placed")
        app.buttons["trackOrderButton"].tap()

        // Live tracking (backend runs with short demo steps)
        XCTAssertTrue(element("trackingStatus").waitForExistence(timeout: 10))
        snap("11-tracking", settle: 6)
        Thread.sleep(forTimeInterval: 12)
        snap("12-tracking-progress", settle: 1)

        // Orders + profile
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        snap("13-orders", settle: 2)
        app.tabBars.buttons.element(boundBy: 3).tap()
        snap("14-profile")

        // Search
        app.tabBars.buttons.element(boundBy: 1).tap()
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("latte")
            snap("15-search", settle: 3)
        }
    }
}
