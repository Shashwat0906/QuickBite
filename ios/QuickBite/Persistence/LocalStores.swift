import Foundation

/// Small disk cache of recent API responses (home feed, cafe menus) so the app
/// can show something useful offline. Stored as JSON files in Caches/, which
/// iOS may purge under storage pressure — fine for a cache.
final class ResponseCache {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "QuickBite.ResponseCache", qos: .utility)

    struct Entry<T: Codable>: Codable {
        let savedAt: Date
        let value: T
    }

    init(folder: String = "ResponseCache") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent("\(safe).json")
    }

    /// Writes in the background (never blocks the main thread).
    func store<T: Codable>(_ value: T, for key: String) {
        let entry = Entry(savedAt: Date(), value: value)
        let target = url(for: key)
        queue.async { [encoder] in
            guard let data = try? encoder.encode(entry) else { return }
            try? data.write(to: target, options: .atomic)
        }
    }

    func load<T: Codable>(_ type: T.Type, for key: String) -> Entry<T>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(Entry<T>.self, from: data)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// Recent search terms (most recent first, max 8).
final class RecentSearchesStore {
    private let defaults: UserDefaults
    private let key = "qb.recentSearches"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var terms: [String] { defaults.stringArray(forKey: key) ?? [] }

    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var list = terms.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(8)), forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}

/// Where the user wants delivery right now (a saved address or GPS location).
/// Drives the Home header, cafe distances and delivery estimates.
final class DeliveryLocationStore {
    struct Location: Codable, Equatable {
        var title: String
        var subtitle: String
        var latitude: Double
        var longitude: Double
        var addressId: String?
    }

    /// Connaught Place, New Delhi — where the demo cafes are.
    static let fallback = Location(title: "Connaught Place", subtitle: "New Delhi", latitude: 28.6315, longitude: 77.2167, addressId: nil)

    private let defaults: UserDefaults
    private let key = "qb.deliveryLocation"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var current: Location {
        get {
            guard let data = defaults.data(forKey: key), let location = try? JSONDecoder().decode(Location.self, from: data) else { return Self.fallback }
            return location
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key)
            NotificationCenter.default.post(name: .deliveryLocationDidChange, object: nil)
        }
    }

    func use(_ address: Address) {
        current = Location(title: address.label, subtitle: address.shortText, latitude: address.latitude, longitude: address.longitude, addressId: address.id)
    }
}

extension Notification.Name {
    static let deliveryLocationDidChange = Notification.Name("QuickBite.deliveryLocationDidChange")
}
