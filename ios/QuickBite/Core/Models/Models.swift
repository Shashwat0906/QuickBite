import Foundation

// Codable models mirroring the backend JSON contract (see docs/API.md).
// Money is always an `Int` number of paise, never a Double.

typealias Paise = Int

// MARK: - Auth & user

struct User: Codable, Equatable {
    let id: String
    var name: String
    var email: String
    var phone: String?
    var authProvider: String
    var notifyOrderUpdates: Bool
    var notifyPromotions: Bool

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct AuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct AuthResponse: Decodable {
    let user: User
    let tokens: AuthTokens
    let isDemo: Bool?
}

struct TokensResponse: Decodable { let tokens: AuthTokens }
struct UserResponse: Decodable { let user: User }

// MARK: - Addresses

struct Address: Codable, Equatable, Hashable {
    let id: String
    var label: String
    var line1: String
    var line2: String?
    var city: String
    var pincode: String
    var latitude: Double
    var longitude: Double
    var isDefault: Bool

    var shortText: String { [line1, line2].compactMap { $0 }.joined(separator: ", ") }
    var fullText: String { "\(shortText), \(city) \(pincode)" }
}

struct AddressInput: Encodable {
    var label: String
    var line1: String
    var line2: String?
    var city: String
    var pincode: String
    var latitude: Double
    var longitude: Double
    var isDefault: Bool
}

struct AddressResponse: Decodable { let address: Address }
struct AddressListResponse: Decodable { let addresses: [Address] }

// MARK: - Catalogue

enum Diet: String, Codable {
    case veg = "VEG", nonVeg = "NON_VEG", egg = "EGG"
}

struct Cafe: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let slug: String
    let description: String
    let imageUrl: String
    let bannerUrl: String
    let cuisines: [String]
    let rating: Double
    let ratingCount: Int
    let deliveryFeePaise: Paise
    let minOrderPaise: Paise
    let isOpenNow: Bool
    let opensAt: String
    let closesAt: String
    let isFeatured: Bool
    let latitude: Double
    let longitude: Double
    let addressLine: String
    let phone: String
    let distanceKm: Double?
    let deliveryMinutes: Int?

    var imageURL: URL? { URL(string: imageUrl) }
    var bannerURL: URL? { URL(string: bannerUrl) }
    var cuisineText: String { cuisines.map { $0.capitalized }.joined(separator: " · ") }
}

struct CustomizationOption: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let extraPricePaise: Paise
    let isAvailable: Bool
}

struct CustomizationGroup: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let minSelect: Int
    let maxSelect: Int
    let options: [CustomizationOption]

    var isRequired: Bool { minSelect > 0 }
    var isSingleChoice: Bool { maxSelect == 1 }
}

struct MenuItem: Codable, Equatable, Hashable {
    let id: String
    let cafeId: String
    let categoryId: String
    let name: String
    let description: String
    let imageUrl: String
    let pricePaise: Paise
    let diet: Diet
    let isAvailable: Bool
    let isBestseller: Bool
    let popularity: Int
    let cafeName: String?
    let customizations: [CustomizationGroup]

    var imageURL: URL? { URL(string: imageUrl) }
    var isCustomizable: Bool { !customizations.isEmpty }
}

struct MenuSection: Codable, Equatable {
    let id: String
    let name: String
    let items: [MenuItem]
}

struct CafeDetailResponse: Codable {
    let cafe: Cafe
    let menu: [MenuSection]
}

struct Offer: Codable, Equatable, Hashable {
    let code: String
    let description: String
    let type: String
    let value: Int
    let minOrderPaise: Paise
    let maxDiscountPaise: Paise?
}

struct HomeFeed: Codable {
    let offers: [Offer]
    let featuredCafes: [Cafe]
    let nearbyCafes: [Cafe]
    let categories: [String]
    let popularDishes: [MenuItem]
    let bestsellers: [MenuItem]
    let fastestDeliveryMinutes: Int?
}

struct PageMeta: Codable, Equatable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int
    let hasMore: Bool
}

struct CafeListResponse: Codable {
    let cafes: [Cafe]
    let meta: PageMeta
}

struct SearchResponse: Codable {
    let query: String
    let cafes: [Cafe]
    let items: [MenuItem]
    let meta: PageMeta
}

struct SearchSuggestions: Codable {
    let suggestions: [String]
    let categories: [String]
}

// MARK: - Server-priced cart

struct Bill: Codable, Equatable {
    let subtotalPaise: Paise
    let discountPaise: Paise
    let deliveryFeePaise: Paise
    let taxPaise: Paise
    let totalPaise: Paise
}

struct CartIssue: Codable, Equatable {
    let code: String
    let message: String
    let menuItemId: String?
}

struct PricedCartLine: Codable, Equatable {
    let id: String?
    let menuItem: MenuItem
    let quantity: Int
    let optionIds: [String]
    let unitPricePaise: Paise
    let lineTotalPaise: Paise
    let issue: CartIssue?
}

struct CouponResult: Codable, Equatable {
    let code: String
    let isValid: Bool
    let message: String
    let discountPaise: Paise
}

struct PricedCart: Codable, Equatable {
    let cafe: Cafe?
    let lines: [PricedCartLine]
    let bill: Bill?
    let coupon: CouponResult?
    let issues: [CartIssue]
    let canCheckout: Bool
}

struct PricedCartResponse: Decodable {
    let cart: PricedCart
    let skippedItems: [String]?
}

struct CartSyncRequest: Encodable {
    struct Line: Encodable { let menuItemId: String; let quantity: Int; let optionIds: [String] }
    let items: [Line]
    let couponCode: String?
}

// MARK: - Orders

enum OrderStatus: String, Codable, CaseIterable {
    case pendingPayment = "PENDING_PAYMENT"
    case placed = "PLACED"
    case confirmed = "CONFIRMED"
    case preparing = "PREPARING"
    case readyForPickup = "READY_FOR_PICKUP"
    case outForDelivery = "OUT_FOR_DELIVERY"
    case delivered = "DELIVERED"
    case cancelled = "CANCELLED"

    /// The six customer-visible tracking steps, in order.
    static let trackingSteps: [OrderStatus] = [.placed, .confirmed, .preparing, .readyForPickup, .outForDelivery, .delivered]

    var title: String {
        switch self {
        case .pendingPayment: return "Awaiting payment"
        case .placed: return "Order placed"
        case .confirmed: return "Cafe confirmed"
        case .preparing: return "Preparing"
        case .readyForPickup: return "Ready for pickup"
        case .outForDelivery: return "Out for delivery"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .pendingPayment: return "creditcard"
        case .placed: return "doc.text.fill"
        case .confirmed: return "checkmark.seal.fill"
        case .preparing: return "flame.fill"
        case .readyForPickup: return "bag.fill"
        case .outForDelivery: return "bicycle"
        case .delivered: return "house.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .pendingPayment: return "Complete the payment to send your order to the cafe."
        case .placed: return "We've sent your order to the cafe."
        case .confirmed: return "The cafe has accepted your order."
        case .preparing: return "Your food is being freshly prepared."
        case .readyForPickup: return "Packed and waiting for the delivery partner."
        case .outForDelivery: return "Your order is on its way."
        case .delivered: return "Enjoy your meal!"
        case .cancelled: return "This order was cancelled."
        }
    }

    /// Index into `trackingSteps`, or nil for pending/cancelled.
    var stepIndex: Int? { Self.trackingSteps.firstIndex(of: self) }
    var isActive: Bool { stepIndex != nil && self != .delivered }
    var isFinal: Bool { self == .delivered || self == .cancelled }
}

struct OrderCafe: Codable, Equatable {
    let id: String
    let name: String
    let imageUrl: String
    let phone: String?
    let latitude: Double?
    let longitude: Double?
    let addressLine: String?
}

struct OrderSummary: Codable, Equatable, Hashable {
    let id: String
    let orderNumber: String
    let status: OrderStatus
    let statusLabel: String
    let cafe: OrderCafeSummary?
    let totalPaise: Paise
    let itemCount: Int?
    let itemsPreview: String?
    let createdAt: Date
    let estimatedMinutes: Int
    let isReviewed: Bool
}

struct OrderCafeSummary: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let imageUrl: String
}

struct OrderLine: Codable, Equatable {
    struct Option: Codable, Equatable { let id: String; let name: String; let extraPricePaise: Paise }
    let id: String
    let menuItemId: String
    let name: String
    let quantity: Int
    let unitPricePaise: Paise
    let lineTotalPaise: Paise
    let options: [Option]
}

struct TimelineEvent: Codable, Equatable {
    let status: OrderStatus
    let label: String
    let note: String?
    let at: Date
}

enum PaymentProvider: String, Codable {
    case razorpay = "RAZORPAY", mock = "MOCK", cashOnDelivery = "CASH_ON_DELIVERY"
}

enum PaymentStatus: String, Codable {
    case created = "CREATED", pending = "PENDING", succeeded = "SUCCEEDED", failed = "FAILED", cancelled = "CANCELLED", refunded = "REFUNDED"
}

struct PaymentInfo: Codable, Equatable {
    let id: String
    let provider: PaymentProvider
    let status: PaymentStatus
    let amountPaise: Paise
    let providerOrderId: String?
    let failureReason: String?
    let createdAt: Date
    let razorpayKeyId: String?
    let isMock: Bool?
}

struct DeliveryAddressSnapshot: Codable, Equatable {
    let label: String?
    let line1: String?
    let line2: String?
    let city: String?
    let pincode: String?
    let latitude: Double?
    let longitude: Double?
    let redacted: Bool?

    var text: String {
        if redacted == true { return "Address removed" }
        return [line1, line2, city].compactMap { $0 }.joined(separator: ", ")
    }
}

struct OrderDetail: Codable, Equatable {
    let id: String
    let orderNumber: String
    let status: OrderStatus
    let statusLabel: String
    let cafe: OrderCafe?
    let totalPaise: Paise
    let createdAt: Date
    let estimatedMinutes: Int
    let isReviewed: Bool
    let items: [OrderLine]
    let bill: Bill
    let couponCode: String?
    let deliveryAddress: DeliveryAddressSnapshot?
    let timeline: [TimelineEvent]
    let payments: [PaymentInfo]
    let isDemoTracking: Bool
    let cancelReason: String?
    let deliveredAt: Date?
    let canCancel: Bool
    let canReview: Bool
    let paymentMethod: PaymentProvider?

    var latestPayment: PaymentInfo? { payments.last }
}

struct OrderDetailResponse: Decodable { let order: OrderDetail }
struct OrderListResponse: Decodable { let orders: [OrderSummary]; let meta: PageMeta? }

struct PlaceOrderRequest: Encodable {
    let addressId: String
    let paymentMethod: String
    let idempotencyKey: String
}

struct PlaceOrderResponse: Decodable {
    let order: OrderDetail
    let payment: PaymentInfo?
    let replayed: Bool
}

struct Coordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct RiderLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let progress: Double?
    let isSimulated: Bool
}

struct OrderTracking: Codable, Equatable {
    let orderId: String
    let status: OrderStatus
    let estimatedMinutes: Int
    let placedAt: Date
    let cafeLocation: Coordinate
    let destination: Coordinate?
    let rider: RiderLocation?
    let isDemoTracking: Bool
    let timeline: [TimelineEvent]
}

// MARK: - Payments

struct PaymentMethodOption: Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let isMock: Bool
}

struct PaymentMethodsResponse: Decodable { let methods: [PaymentMethodOption] }
struct PaymentAttemptResponse: Decodable { let payment: PaymentInfo }

// MARK: - Reviews & notifications

struct Review: Codable, Equatable, Hashable {
    let id: String
    let orderId: String
    let cafeId: String
    let rating: Int
    let comment: String?
    let createdAt: Date
    let userName: String?
    let cafeName: String?
}

struct ReviewResponse: Decodable { let review: Review }

struct ReviewListResponse: Decodable {
    let reviews: [Review]
    let distribution: [String: Int]?
    let meta: PageMeta
}

struct AppNotification: Codable, Equatable, Hashable {
    let id: String
    let title: String
    let body: String
    let orderId: String?
    let isRead: Bool
    let createdAt: Date
}

struct NotificationListResponse: Decodable {
    let notifications: [AppNotification]
    let unreadCount: Int
    let meta: PageMeta
}

struct NotificationPreferences: Codable, Equatable {
    var notifyOrderUpdates: Bool
    var notifyPromotions: Bool
}

struct HealthResponse: Decodable {
    struct Features: Decodable {
        let razorpay: Bool
        let mockPayments: Bool
        let fcm: Bool
        let demoOrderProgression: Bool
        let socialLoginDemo: Bool
    }
    let status: String
    let database: String
    let version: String
    let features: Features
}
