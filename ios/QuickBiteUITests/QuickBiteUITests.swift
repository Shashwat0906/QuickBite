import XCTest

/// End-to-end UI tests. The app is launched with `-uiTesting`, which swaps the
/// network layer for an in-process stub backend (see StubBackend.swift), so the
/// tests are fast and deterministic and need no server.
final class QuickBiteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(skipOnboarding: Bool = true) {
        app.launchArguments = ["-uiTesting", "-resetState"] + (skipOnboarding ? ["-skipOnboarding"] : [])
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    // MARK: Onboarding

    func testOnboardingNavigation() {
        launch(skipOnboarding: false)
        XCTAssertTrue(element("onboardingTitle_0").waitForExistence(timeout: 5))
        let next = app.buttons["onboardingNext"]
        next.tap()
        XCTAssertTrue(element("onboardingTitle_1").waitForExistence(timeout: 2))
        next.tap()
        XCTAssertTrue(element("onboardingTitle_2").waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["onboardingSkip"].isHittable, "Skip hides on the last page")
        next.tap() // "Get started" → sign in
        XCTAssertTrue(app.buttons["loginButton"].waitForExistence(timeout: 5))
    }

    func testGuestBrowsingFromOnboarding() {
        launch(skipOnboarding: false)
        app.buttons["onboardingGuest"].tap()
        XCTAssertTrue(element("homeSearch").waitForExistence(timeout: 5))
    }

    // MARK: Login

    private func openLogin() {
        app.tabBars.buttons.element(boundBy: 3).tap()
        let signIn = element("profileRow_signIn")
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        XCTAssertTrue(app.buttons["loginButton"].waitForExistence(timeout: 5))
    }

    private func signIn() {
        openLogin()
        let email = app.textFields["loginEmail"]
        email.tap()
        email.typeText("test@quickbite.app")
        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("Passw0rd!")
        app.buttons["loginButton"].tap()
        XCTAssertTrue(app.buttons["loginButton"].waitForNonExistence(timeout: 5))
    }

    func testLoginFormValidation() {
        launch()
        openLogin()
        app.buttons["loginButton"].tap()
        XCTAssertTrue(app.staticTexts["Enter your email"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Enter your password"].exists)

        let email = app.textFields["loginEmail"]
        email.tap()
        email.typeText("not-an-email")
        app.buttons["loginButton"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address"].waitForExistence(timeout: 2))

        email.tap()
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        email.typeText("test@quickbite.app")
        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("wrong-password")
        app.buttons["loginButton"].tap()
        XCTAssertTrue(app.staticTexts["Incorrect email or password"].waitForExistence(timeout: 5))
    }

    func testSuccessfulLoginShowsProfile() {
        launch()
        signIn()
        XCTAssertTrue(app.staticTexts["Test User"].waitForExistence(timeout: 5))
    }

    // MARK: Cart

    private func openCafeAndAddCroissant() {
        let cafe = element("cafeCard_Brew & Bloom")
        XCTAssertTrue(cafe.waitForExistence(timeout: 8))
        cafe.tap()
        let row = app.cells["foodItem_Butter Croissant"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        var attempts = 0
        while !row.buttons["addToCart"].isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        row.buttons["addToCart"].tap()
        XCTAssertTrue(row.staticTexts["quantityValue"].waitForExistence(timeout: 2))
        XCTAssertEqual(row.staticTexts["quantityValue"].label, "1")
    }

    func testAddingItemsToCart() {
        launch()
        openCafeAndAddCroissant()
        let row = app.cells["foodItem_Butter Croissant"]
        row.buttons["increaseQuantity"].tap()
        XCTAssertEqual(row.staticTexts["quantityValue"].label, "2")
        let bar = element("viewCartBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 2))
        XCTAssertTrue(bar.label.contains("2 items"), bar.label)
    }

    func testUpdatingCartQuantities() {
        launch()
        openCafeAndAddCroissant()
        element("viewCartBar").tap()
        let line = app.cells["cartLine_Butter Croissant"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.buttons["increaseQuantity"].tap()
        line.buttons["increaseQuantity"].tap()
        XCTAssertEqual(line.staticTexts["quantityValue"].label, "3")
        XCTAssertTrue(line.staticTexts["₹447"].exists, "3 × ₹149")
        line.buttons["decreaseQuantity"].tap()
        XCTAssertEqual(line.staticTexts["quantityValue"].label, "2")
        line.buttons["decreaseQuantity"].tap()
        line.buttons["decreaseQuantity"].tap()
        XCTAssertTrue(app.staticTexts["Your cart is empty"].waitForExistence(timeout: 3))
    }

    // MARK: Checkout + tracking

    func testCheckoutWithDemoPaymentAndTracking() {
        launch()
        signIn()
        app.tabBars.buttons.element(boundBy: 0).tap()
        openCafeAndAddCroissant()
        app.cells["foodItem_Butter Croissant"].buttons["increaseQuantity"].tap()
        element("viewCartBar").tap()

        let checkout = app.buttons["checkoutButton"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: checkout)
        waitForExpectations(timeout: 5)
        checkout.tap()

        let place = app.buttons["placeOrderButton"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        expectation(for: enabled, evaluatedWith: place)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(element("address_Home").exists)
        element("payment_MOCK").tap()
        place.tap()

        let pay = app.buttons["mockPaySuccess"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()

        XCTAssertTrue(element("orderPlacedTitle").waitForExistence(timeout: 5))
        app.buttons["trackOrderButton"].tap()

        XCTAssertTrue(element("trackingStatus").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Order placed"].exists)
        XCTAssertTrue(app.staticTexts["Out for delivery"].exists, "all six steps are listed")
    }

    func testOrdersTabRequiresSignIn() {
        launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your orders"].waitForExistence(timeout: 3))
    }
}
