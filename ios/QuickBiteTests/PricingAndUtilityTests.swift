import XCTest
@testable import QuickBite

/// Mirrors backend/tests/unit/pricing.test.js so app estimates and server bills agree.
final class PricingCalculatorTests: XCTestCase {
    func testNormalOrderChargesDeliveryAndFivePercentTax() {
        let bill = PricingCalculator.bill(lines: [.init(unitPricePaise: 15000, quantity: 2)], deliveryFee: 2500, minOrder: 9900)
        XCTAssertEqual(bill, Bill(subtotalPaise: 30000, discountPaise: 0, deliveryFeePaise: 2500, taxPaise: 1500, totalPaise: 34000))
    }

    func testFreeDeliveryFromFourNinetyNine() {
        let bill = PricingCalculator.bill(lines: [.init(unitPricePaise: 49900, quantity: 1)], deliveryFee: 2500, minOrder: 9900)
        XCTAssertEqual(bill.deliveryFeePaise, 0)
    }

    func testSmallOrderFeeBelowMinimum() {
        let bill = PricingCalculator.bill(lines: [.init(unitPricePaise: 5000, quantity: 1)], deliveryFee: 2500, minOrder: 9900)
        XCTAssertEqual(bill.deliveryFeePaise, 2500 + PricingCalculator.smallOrderFee)
    }

    func testTaxIsOnDiscountedAmountAndDiscountIsCapped() {
        let bill = PricingCalculator.bill(lines: [.init(unitPricePaise: 20000, quantity: 1)], deliveryFee: 2500, minOrder: 9900, discount: 10000)
        XCTAssertEqual(bill.taxPaise, 500)
        let capped = PricingCalculator.bill(lines: [.init(unitPricePaise: 10000, quantity: 1)], deliveryFee: 2500, minOrder: 9900, discount: 99999)
        XCTAssertEqual(capped.discountPaise, 10000)
        XCTAssertGreaterThanOrEqual(capped.totalPaise, 0)
    }

    func testUnitPriceAddsExtras() {
        XCTAssertEqual(PricingCalculator.unitPrice(base: 18000, optionExtras: [3000, 4000]), 25000)
    }

    func testAmountToFreeDelivery() {
        XCTAssertEqual(PricingCalculator.amountToFreeDelivery(subtotal: 40000), 9900)
        XCTAssertNil(PricingCalculator.amountToFreeDelivery(subtotal: 50000))
    }
}

final class CouponRulesTests: XCTestCase {
    private let percent = Offer(code: "WELCOME50", description: "", type: "PERCENT", value: 50, minOrderPaise: 19900, maxDiscountPaise: 10000)
    private let flat = Offer(code: "QUICK75", description: "", type: "FLAT", value: 7500, minOrderPaise: 34900, maxDiscountPaise: nil)

    func testPercentCouponIsCapped() {
        XCTAssertEqual(CouponRules.evaluate(percent, subtotal: 40000), .valid(discount: 10000))
        XCTAssertEqual(CouponRules.evaluate(percent, subtotal: 20000), .valid(discount: 10000))
    }

    func testFlatCoupon() {
        XCTAssertEqual(CouponRules.evaluate(flat, subtotal: 40000), .valid(discount: 7500))
    }

    func testBelowMinimumExplainsHowMuchMore() {
        guard case .invalid(let reason) = CouponRules.evaluate(flat, subtotal: 30000) else { return XCTFail("expected invalid") }
        XCTAssertTrue(reason.contains("₹49"), reason)
    }

    func testHeadline() {
        XCTAssertEqual(CouponRules.headline(for: percent), "50% OFF up to ₹100")
        XCTAssertEqual(CouponRules.headline(for: flat), "₹75 OFF")
    }
}

/// Exercises the Objective-C QBPriceFormatter through the Swift `Money` wrapper.
final class PriceFormatterTests: XCTestCase {
    func testWholeRupees() { XCTAssertEqual(Money.format(24900), "₹249") }
    func testPaise() { XCTAssertEqual(Money.format(129950), "₹1,299.50") }
    func testIndianGrouping() {
        XCTAssertEqual(Money.format(12_345_600), "₹1,23,456")
        XCTAssertEqual(Money.format(1_234_567_800), "₹1,23,45,678")
    }
    func testSmallAmounts() {
        XCTAssertEqual(Money.format(0), "₹0")
        XCTAssertEqual(Money.format(5), "₹0.05")
    }
    func testDiscountAndSpoken() {
        XCTAssertEqual(Money.discount(7500), "−₹75")
        XCTAssertEqual(Money.spoken(24950), "249 rupees 50 paise")
        XCTAssertEqual(Money.spoken(100), "1 rupee")
    }
}

final class OrderStatusTests: XCTestCase {
    func testTrackingStepsOrder() {
        XCTAssertEqual(OrderStatus.trackingSteps.first, .placed)
        XCTAssertEqual(OrderStatus.trackingSteps.last, .delivered)
        XCTAssertEqual(OrderStatus.preparing.stepIndex, 2)
    }

    func testActiveAndFinal() {
        XCTAssertTrue(OrderStatus.outForDelivery.isActive)
        XCTAssertFalse(OrderStatus.delivered.isActive)
        XCTAssertFalse(OrderStatus.pendingPayment.isActive)
        XCTAssertTrue(OrderStatus.cancelled.isFinal)
        XCTAssertNil(OrderStatus.cancelled.stepIndex)
    }

    func testDecodesFromAPIValue() throws {
        let data = Data(#""READY_FOR_PICKUP""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(OrderStatus.self, from: data), .readyForPickup)
    }
}

final class SocketIOPacketTests: XCTestCase {
    func testOpenPacket() {
        XCTAssertEqual(SocketIOPacket.parse(#"0{"sid":"abc","pingInterval":25000,"pingTimeout":20000}"#), .open(pingInterval: 25, pingTimeout: 20))
    }

    func testPingAndConnect() {
        XCTAssertEqual(SocketIOPacket.parse("2"), .ping)
        XCTAssertEqual(SocketIOPacket.parse(#"40{"sid":"x"}"#), .connected)
        XCTAssertEqual(SocketIOPacket.parse(#"44{"message":"UNAUTHORIZED"}"#), .connectError("UNAUTHORIZED"))
    }

    func testEventWithPayload() throws {
        guard case let .event(name, payload) = SocketIOPacket.parse(#"42["order:status",{"orderId":"o1","status":"PREPARING"}]"#) else { return XCTFail("not an event") }
        XCTAssertEqual(name, "order:status")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(payload)) as? [String: String])
        XCTAssertEqual(json["status"], "PREPARING")
    }

    func testAckWithId() {
        guard case let .ack(id, payload) = SocketIOPacket.parse(#"4317[{"ok":true}]"#) else { return XCTFail("not an ack") }
        XCTAssertEqual(id, 17)
        XCTAssertNotNil(payload)
    }

    func testEncoding() {
        XCTAssertEqual(SocketIOPacket.encodeEvent("order:subscribe", argument: "o1", ackId: 3), #"423["order:subscribe","o1"]"#)
        XCTAssertTrue(SocketIOPacket.encodeConnect(token: "t").hasPrefix(#"40{"token":"t""#))
    }
}
