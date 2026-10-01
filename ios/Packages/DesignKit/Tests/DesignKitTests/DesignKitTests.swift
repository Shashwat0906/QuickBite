import XCTest
@testable import DesignKit

final class DesignKitTests: XCTestCase {
    func testHexColorParsing() {
        let color = DK.Color.hex(0xE2572B)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 226 / 255, accuracy: 0.001)
        XCTAssertEqual(g, 87 / 255, accuracy: 0.001)
        XCTAssertEqual(b, 43 / 255, accuracy: 0.001)
    }

    func testDynamicColorsDifferInDarkMode() {
        let light = DK.Color.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = DK.Color.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    func testSpacingFollowsFourPointGrid() {
        for value in [DK.Spacing.xs, DK.Spacing.s, DK.Spacing.m, DK.Spacing.l, DK.Spacing.xl, DK.Spacing.xxl, DK.Spacing.xxxl] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) is off-grid")
        }
    }

    @MainActor
    func testQuantityStepperClampsAndNotifies() {
        let stepper = QuantityStepper()
        stepper.maximum = 3
        var received: [Int] = []
        stepper.onChange = { received.append($0) }
        stepper.setValue(10)
        XCTAssertEqual(stepper.value, 3, "setValue clamps to maximum")
        XCTAssertTrue(received.isEmpty, "setValue must not fire onChange")
        stepper.setValue(-2)
        XCTAssertEqual(stepper.value, 0)
    }

    @MainActor
    func testButtonLoadingStateBlocksInteraction() {
        let button = QBButton(title: "Place order")
        button.isLoading = true
        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertEqual(button.configuration?.title, "")
        button.isLoading = false
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertEqual(button.configuration?.title, "Place order")
    }

    @MainActor
    func testTextFieldErrorMessage() {
        let field = QBTextField(title: "Email", placeholder: "you@example.com")
        field.errorMessage = "Enter a valid email"
        field.errorMessage = nil
        field.text = "a@b.co"
        XCTAssertEqual(field.text, "a@b.co")
    }

    func testImageDownsamplingProducesSmallerImage() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }())
        let big = renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let data = try XCTUnwrap(big.jpegData(compressionQuality: 0.8))
        let small = try XCTUnwrap(ImagePipeline.decode(data, targetSize: CGSize(width: 100, height: 100), scale: 2))
        XCTAssertLessThanOrEqual(max(small.size.width, small.size.height), 200)
    }
}
