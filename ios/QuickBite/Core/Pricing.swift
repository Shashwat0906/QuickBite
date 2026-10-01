import Foundation

/// Swift-friendly wrapper around the Objective-C `QBPriceFormatter`
/// (demonstrates Swift ⇄ Objective-C interoperability via the bridging header).
enum Money {
    static func format(_ paise: Paise) -> String { QBPriceFormatter.string(fromPaise: paise) }
    static func discount(_ paise: Paise) -> String { QBPriceFormatter.discountString(fromPaise: paise) }
    static func spoken(_ paise: Paise) -> String { QBPriceFormatter.accessibilityString(fromPaise: paise) }
}

/// Mirrors the backend pricing rules so the cart can show an instant estimate
/// (even offline). The server always recalculates before an order is created —
/// these numbers are never sent to the API.
enum PricingCalculator {
    static let taxRateBasisPoints = 500 // 5% GST
    static let freeDeliveryThreshold: Paise = 49_900
    static let smallOrderFee: Paise = 1_500

    struct Line {
        let unitPricePaise: Paise
        let quantity: Int
    }

    static func unitPrice(base: Paise, optionExtras: [Paise]) -> Paise {
        optionExtras.reduce(base, +)
    }

    static func bill(lines: [Line], deliveryFee: Paise, minOrder: Paise, discount: Paise = 0) -> Bill {
        let subtotal = lines.reduce(0) { $0 + $1.unitPricePaise * $1.quantity }
        let appliedDiscount = min(max(discount, 0), subtotal)
        var delivery = subtotal >= freeDeliveryThreshold ? 0 : deliveryFee
        if subtotal > 0 && subtotal < minOrder { delivery += smallOrderFee }
        if subtotal == 0 { delivery = 0 }
        let tax = Int((Double((subtotal - appliedDiscount) * taxRateBasisPoints) / 10_000).rounded())
        return Bill(
            subtotalPaise: subtotal,
            discountPaise: appliedDiscount,
            deliveryFeePaise: delivery,
            taxPaise: tax,
            totalPaise: subtotal - appliedDiscount + delivery + tax
        )
    }

    /// How much more to add to unlock free delivery (nil when already free).
    static func amountToFreeDelivery(subtotal: Paise) -> Paise? {
        subtotal >= freeDeliveryThreshold ? nil : freeDeliveryThreshold - subtotal
    }
}

/// Client-side coupon rules for instant feedback on advertised offers.
/// The authoritative check (usage limits, expiry) happens on the server.
enum CouponRules {
    enum Result: Equatable {
        case valid(discount: Paise)
        case invalid(reason: String)
    }

    static func evaluate(_ offer: Offer, subtotal: Paise) -> Result {
        guard subtotal >= offer.minOrderPaise else {
            let short = offer.minOrderPaise - subtotal
            return .invalid(reason: "Add \(Money.format(short)) more to use \(offer.code)")
        }
        var discount: Paise
        switch offer.type {
        case "FLAT": discount = offer.value
        case "PERCENT": discount = subtotal * offer.value / 100
        default: return .invalid(reason: "Unsupported coupon")
        }
        if let cap = offer.maxDiscountPaise { discount = min(discount, cap) }
        return .valid(discount: min(discount, subtotal))
    }

    static func headline(for offer: Offer) -> String {
        switch offer.type {
        case "PERCENT":
            let cap = offer.maxDiscountPaise.map { " up to \(Money.format($0))" } ?? ""
            return "\(offer.value)% OFF\(cap)"
        default:
            return "\(Money.format(offer.value)) OFF"
        }
    }
}
