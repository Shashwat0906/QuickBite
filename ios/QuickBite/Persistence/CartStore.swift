import CoreData
import Foundation
import NetworkKit

extension Notification.Name {
    static let cartDidChange = Notification.Name("QuickBite.cartDidChange")
}

/// The cafe snapshot a cart needs for its estimate and header.
struct CartCafe: Codable, Equatable {
    let id: String
    let name: String
    let imageUrl: String
    let deliveryFeePaise: Paise
    let minOrderPaise: Paise

    init(_ cafe: Cafe) {
        id = cafe.id
        name = cafe.name
        imageUrl = cafe.imageUrl
        deliveryFeePaise = cafe.deliveryFeePaise
        minOrderPaise = cafe.minOrderPaise
    }

    init(id: String, name: String, imageUrl: String, deliveryFeePaise: Paise, minOrderPaise: Paise) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.deliveryFeePaise = deliveryFeePaise
        self.minOrderPaise = minOrderPaise
    }
}

/// One line in the local cart.
struct CartLine: Equatable, Hashable {
    let id: UUID
    let menuItem: MenuItem
    var optionIds: [String]
    var quantity: Int

    var selectedOptions: [CustomizationOption] {
        let all = menuItem.customizations.flatMap(\.options)
        return optionIds.compactMap { id in all.first { $0.id == id } }
    }

    var unitPricePaise: Paise { PricingCalculator.unitPrice(base: menuItem.pricePaise, optionExtras: selectedOptions.map(\.extraPricePaise)) }
    var lineTotalPaise: Paise { unitPricePaise * quantity }
    var optionsSummary: String? {
        let names = selectedOptions.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Same item + same options = same line.
    var mergeKey: String { "\(menuItem.id)|\(optionIds.sorted().joined(separator: ","))" }
}

enum CartError: Error, Equatable {
    /// The cart has items from a different cafe; the UI asks before replacing.
    case differentCafe(currentCafeName: String)
    case quantityLimit
}

/// Local cart persisted with Core Data.
///
/// Works for guests and offline. When the user checks out, the lines are sent
/// to the server (`CartService.sync`), which re-prices everything from the
/// database — so this estimate can never be used to underpay.
@MainActor
final class CartStore {
    static let maxQuantityPerLine = 20

    private let stack: CoreDataStack
    private(set) var lines: [CartLine] = []
    private(set) var cafe: CartCafe?
    private(set) var couponCode: String?

    init(stack: CoreDataStack) {
        self.stack = stack
        load()
    }

    // MARK: Reading

    var isEmpty: Bool { lines.isEmpty }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }

    func quantity(of menuItemId: String) -> Int {
        lines.filter { $0.menuItem.id == menuItemId }.reduce(0) { $0 + $1.quantity }
    }

    /// Local estimate of the bill (no coupon — coupons are validated by the server).
    var estimate: Bill {
        PricingCalculator.bill(
            lines: lines.map { .init(unitPricePaise: $0.unitPricePaise, quantity: $0.quantity) },
            deliveryFee: cafe?.deliveryFeePaise ?? 0,
            minOrder: cafe?.minOrderPaise ?? 0
        )
    }

    var syncLines: [CartSyncRequest.Line] {
        lines.map { .init(menuItemId: $0.menuItem.id, quantity: $0.quantity, optionIds: $0.optionIds) }
    }

    // MARK: Writing

    /// Adds an item (merging with an identical line).
    /// Throws `.differentCafe` unless `replacingOtherCafe` is true.
    func add(_ item: MenuItem, from cafe: CartCafe, optionIds: [String] = [], quantity: Int = 1, replacingOtherCafe: Bool = false) throws {
        if let current = self.cafe, current.id != cafe.id, !lines.isEmpty {
            guard replacingOtherCafe else { throw CartError.differentCafe(currentCafeName: current.name) }
            lines.removeAll()
            couponCode = nil
        }
        self.cafe = cafe
        let candidate = CartLine(id: UUID(), menuItem: item, optionIds: optionIds.sorted(), quantity: quantity)
        if let index = lines.firstIndex(where: { $0.mergeKey == candidate.mergeKey }) {
            guard lines[index].quantity < Self.maxQuantityPerLine else { throw CartError.quantityLimit }
            lines[index].quantity = min(Self.maxQuantityPerLine, lines[index].quantity + quantity)
        } else {
            lines.append(candidate)
        }
        persist()
    }

    /// Sets a line's quantity; 0 removes the line.
    func setQuantity(_ quantity: Int, forLine id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        if quantity <= 0 {
            lines.remove(at: index)
        } else {
            lines[index].quantity = min(Self.maxQuantityPerLine, quantity)
        }
        persist()
    }

    /// Stepper on a menu row: + repeats the most recent line for that item,
    /// − decrements it (handles customised items sensibly).
    func changeQuantity(of item: MenuItem, from cafe: CartCafe, to newTotal: Int) throws {
        let current = quantity(of: item.id)
        if newTotal > current {
            if let last = lines.last(where: { $0.menuItem.id == item.id }) {
                try add(item, from: cafe, optionIds: last.optionIds, quantity: newTotal - current)
            } else {
                try add(item, from: cafe, quantity: newTotal - current)
            }
        } else if newTotal < current, let last = lines.last(where: { $0.menuItem.id == item.id }) {
            setQuantity(last.quantity - (current - newTotal), forLine: last.id)
        }
    }

    func updateOptions(_ optionIds: [String], forLine id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].optionIds = optionIds.sorted()
        let key = lines[index].mergeKey
        if let duplicate = lines.indices.first(where: { $0 != index && lines[$0].mergeKey == key }) {
            lines[duplicate].quantity = min(Self.maxQuantityPerLine, lines[duplicate].quantity + lines[index].quantity)
            lines.remove(at: index)
        }
        persist()
    }

    func remove(line id: UUID) { setQuantity(0, forLine: id) }

    func applyCoupon(_ code: String?) {
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        couponCode = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persist()
    }

    func clear() {
        lines.removeAll()
        cafe = nil
        couponCode = nil
        persist()
    }

    /// Replace contents with a server cart (used by "Reorder").
    func replace(with priced: PricedCart) {
        lines = priced.lines.filter { $0.issue == nil }.map { CartLine(id: UUID(), menuItem: $0.menuItem, optionIds: $0.optionIds.sorted(), quantity: $0.quantity) }
        if let cafe = priced.cafe { self.cafe = CartCafe(cafe) }
        couponCode = nil
        persist()
    }

    // MARK: Persistence

    private func load() {
        let context = stack.viewContext
        let decoder = JSONDecoder.api
        let request = NSFetchRequest<NSManagedObject>(entityName: "CartLine")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let rows = (try? context.fetch(request)) ?? []
        lines = rows.compactMap { row in
            guard let id = row.value(forKey: "id") as? UUID,
                  let data = row.value(forKey: "menuItemJSON") as? Data,
                  let item = try? decoder.decode(MenuItem.self, from: data) else { return nil }
            let options = (row.value(forKey: "optionIDs") as? String).map { $0.split(separator: ",").map(String.init) } ?? []
            let quantity = (row.value(forKey: "quantity") as? Int64).map(Int.init) ?? 1
            return CartLine(id: id, menuItem: item, optionIds: options, quantity: quantity)
        }
        let meta = try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "CartMeta")).first
        cafe = (meta?.value(forKey: "cafeJSON") as? Data).flatMap { try? decoder.decode(CartCafe.self, from: $0) }
        couponCode = meta?.value(forKey: "couponCode") as? String
        if lines.isEmpty { cafe = nil }
    }

    private func persist() {
        if lines.isEmpty { cafe = nil; couponCode = nil }
        let context = stack.viewContext
        let encoder = JSONEncoder()
        // Rewrite all rows: a cart has at most a few dozen lines, so this is
        // simpler and safer than diffing.
        for entity in ["CartLine", "CartMeta"] {
            let rows = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? []
            rows.forEach(context.delete)
        }
        let now = Date()
        for (offset, line) in lines.enumerated() {
            let row = NSEntityDescription.insertNewObject(forEntityName: "CartLine", into: context)
            row.setValue(line.id, forKey: "id")
            row.setValue(try? encoder.encode(line.menuItem), forKey: "menuItemJSON")
            row.setValue(line.optionIds.joined(separator: ","), forKey: "optionIDs")
            row.setValue(Int64(line.quantity), forKey: "quantity")
            row.setValue(now.addingTimeInterval(Double(offset) / 1000), forKey: "createdAt")
        }
        let meta = NSEntityDescription.insertNewObject(forEntityName: "CartMeta", into: context)
        meta.setValue(cafe.flatMap { try? encoder.encode($0) }, forKey: "cafeJSON")
        meta.setValue(couponCode, forKey: "couponCode")
        stack.save()
        NotificationCenter.default.post(name: .cartDidChange, object: self)
    }
}
