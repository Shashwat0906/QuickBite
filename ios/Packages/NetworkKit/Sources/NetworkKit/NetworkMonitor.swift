import Foundation
import Network

/// Publishes connectivity changes (wraps `NWPathMonitor`). The app shows an
/// offline banner and falls back to cached content when `isOnline` is false.
public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    public private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkKit.NetworkMonitor")
    private var observers: [UUID: (Bool) -> Void] = [:]
    private let lock = NSLock()

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            self.lock.lock()
            let changed = online != self.isOnline
            self.isOnline = online
            let callbacks = Array(self.observers.values)
            self.lock.unlock()
            guard changed else { return }
            DispatchQueue.main.async { callbacks.forEach { $0(online) } }
        }
        monitor.start(queue: queue)
    }

    /// Observe changes on the main queue. Keep the returned token; pass it to
    /// `removeObserver` (or let the owner deinit and remove it).
    @discardableResult
    public func addObserver(_ handler: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        lock.lock(); observers[id] = handler; lock.unlock()
        return id
    }

    public func removeObserver(_ id: UUID) {
        lock.lock(); observers[id] = nil; lock.unlock()
    }
}
