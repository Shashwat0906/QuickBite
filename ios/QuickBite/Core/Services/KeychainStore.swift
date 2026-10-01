import Foundation
import Security

/// Minimal Keychain wrapper for storing session tokens securely
/// (tokens must never go in UserDefaults).
struct KeychainStore {
    let service: String
    /// In-memory backing used by tests and UI-test runs, so they never touch
    /// the real Keychain (which can be slow or unavailable for unsigned builds).
    private let memory: MemoryBox?

    final class MemoryBox {
        var values: [String: Data] = [:]
    }

    init(service: String = "com.quickbite.session", inMemory: Bool = false) {
        self.service = service
        self.memory = inMemory ? MemoryBox() : nil
    }

    func set(_ data: Data, for key: String) {
        if let memory { memory.values[key] = data; return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func data(for key: String) -> Data? {
        if let memory { return memory.values[key] }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func remove(_ key: String) {
        if let memory { memory.values[key] = nil; return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func set<T: Encodable>(_ value: T, for key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) { set(data, for: key) }
    }

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data(for: key).flatMap { try? decoder.decode(T.self, from: $0) }
    }
}
