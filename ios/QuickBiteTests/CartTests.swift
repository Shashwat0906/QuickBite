import XCTest
@testable import QuickBite

@MainActor
final class CartStoreTests: XCTestCase {
    private let cafe = CartCafe(Fixtures.cafe())

    func testAddingSameItemAndOptionsMergesLines() throws {
        let cart = makeCart()
        let item = Fixtures.item(customizable: true)
        try cart.add(item, from: cafe, optionIds: ["o-large", "o-shot"])
        try cart.add(item, from: cafe, optionIds: ["o-shot", "o-large"], quantity: 2)
        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.lines[0].quantity, 3)
        XCTAssertEqual(cart.lines[0].unitPricePaise, 18900 + 4000 + 4000)
    }

    func testDifferentOptionsAreSeparateLines() throws {
        let cart = makeCart()
        let item = Fixtures.item(customizable: true)
        try cart.add(item, from: cafe, optionIds: ["o-reg"])
        try cart.add(item, from: cafe, optionIds: ["o-large"])
        XCTAssertEqual(cart.lines.count, 2)
        XCTAssertEqual(cart.quantity(of: item.id), 2)
    }

    func testOtherCafeRequiresExplicitReplace() throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: cafe)
        let other = CartCafe(Fixtures.cafe(id: "c2", name: "Chai Chowk"))
        XCTAssertThrowsError(try cart.add(Fixtures.item(id: "i2", cafeId: "c2"), from: other)) { error in
            XCTAssertEqual(error as? CartError, .differentCafe(currentCafeName: "Brew & Bloom"))
        }
        try cart.add(Fixtures.item(id: "i2", cafeId: "c2"), from: other, replacingOtherCafe: true)
        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.cafe?.id, "c2")
    }

    func testQuantityZeroRemovesAndEmptiesCafe() throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: cafe)
        cart.setQuantity(0, forLine: cart.lines[0].id)
        XCTAssertTrue(cart.isEmpty)
        XCTAssertNil(cart.cafe)
    }

    func testQuantityIsCapped() throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: cafe, quantity: 19)
        try cart.add(Fixtures.item(), from: cafe, quantity: 5)
        XCTAssertEqual(cart.lines[0].quantity, CartStore.maxQuantityPerLine)
        XCTAssertThrowsError(try cart.add(Fixtures.item(), from: cafe))
    }

    func testStepperChangeQuantityRepeatsLastCustomisation() throws {
        let cart = makeCart()
        let item = Fixtures.item(customizable: true)
        try cart.add(item, from: cafe, optionIds: ["o-large"])
        try cart.changeQuantity(of: item, from: cafe, to: 3)
        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.lines[0].quantity, 3)
        try cart.changeQuantity(of: item, from: cafe, to: 1)
        XCTAssertEqual(cart.quantity(of: item.id), 1)
    }

    func testEditingOptionsMergesIntoIdenticalLine() throws {
        let cart = makeCart()
        let item = Fixtures.item(customizable: true)
        try cart.add(item, from: cafe, optionIds: ["o-reg"])
        try cart.add(item, from: cafe, optionIds: ["o-large"])
        cart.updateOptions(["o-large"], forLine: cart.lines[0].id)
        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.lines[0].quantity, 2)
    }

    func testPersistsAcrossInstances() throws {
        let stack = CoreDataStack(inMemory: true)
        let first = CartStore(stack: stack)
        try first.add(Fixtures.item(customizable: true), from: cafe, optionIds: ["o-large"], quantity: 2)
        first.applyCoupon(" welcome50 ")
        let second = CartStore(stack: stack)
        XCTAssertEqual(second.lines.count, 1)
        XCTAssertEqual(second.lines[0].quantity, 2)
        XCTAssertEqual(second.lines[0].optionIds, ["o-large"])
        XCTAssertEqual(second.cafe, cafe)
        XCTAssertEqual(second.couponCode, "WELCOME50")
    }

    func testEstimateUsesCafeFees() throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(price: 15000), from: cafe, quantity: 2)
        XCTAssertEqual(cart.estimate.totalPaise, 34000)
    }

    func testPostsChangeNotification() throws {
        let cart = makeCart()
        let expectation = expectation(forNotification: .cartDidChange, object: cart)
        try cart.add(Fixtures.item(), from: cafe)
        wait(for: [expectation], timeout: 1)
    }
}

@MainActor
final class ItemCustomizationViewModelTests: XCTestCase {
    func testDefaultsToFirstRequiredOption() {
        let vm = ItemCustomizationViewModel(item: Fixtures.item(customizable: true))
        XCTAssertEqual(vm.selectedIds, ["o-reg"])
        XCTAssertNil(vm.validationMessage)
    }

    func testSingleChoiceReplacesSelection() {
        let vm = ItemCustomizationViewModel(item: Fixtures.item(customizable: true))
        vm.toggle(Fixtures.size.options[1], in: Fixtures.size)
        XCTAssertEqual(vm.selectedIds, ["o-large"])
        XCTAssertEqual(vm.unitPrice, 18900 + 4000)
    }

    func testMaxSelectAndUnavailableAreRejected() {
        let vm = ItemCustomizationViewModel(item: Fixtures.item(customizable: true))
        XCTAssertNil(vm.toggle(Fixtures.extras.options[0], in: Fixtures.extras))
        XCTAssertNil(vm.toggle(Fixtures.extras.options[1], in: Fixtures.extras))
        XCTAssertNotNil(vm.toggle(Fixtures.extras.options[2], in: Fixtures.extras), "unavailable option")
        XCTAssertEqual(vm.selectedIds.count, 3)
    }

    func testRequiredGroupValidation() {
        let vm = ItemCustomizationViewModel(item: Fixtures.item(customizable: true), preselected: [])
        XCTAssertEqual(vm.validationMessage, "Please choose size")
    }

    func testQuantityAndTotal() {
        let vm = ItemCustomizationViewModel(item: Fixtures.item(customizable: true))
        vm.setQuantity(3)
        XCTAssertEqual(vm.totalPrice, 18900 * 3)
        vm.setQuantity(0)
        XCTAssertEqual(vm.quantity, 1)
    }
}
