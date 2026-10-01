import Foundation

/// A parsed Engine.IO v4 / Socket.IO v5 text frame.
///
/// Frame anatomy (first char = Engine.IO type, second = Socket.IO type):
/// ```
/// 0{"sid":"…","pingInterval":25000}   engine open
/// 2 / 3                               engine ping / pong
/// 40{"sid":"…"}                       socket connected (default namespace)
/// 44{"message":"UNAUTHORIZED"}        socket connect error
/// 42["order:status",{…}]              event
/// 4217["order:subscribe","id"]        event that wants an ack (id 17)
/// 4317[{"ok":true}]                   ack for id 17
/// ```
enum SocketIOPacket: Equatable {
    case open(pingInterval: TimeInterval, pingTimeout: TimeInterval)
    case ping
    case pong
    case close
    case connected
    case connectError(String)
    case disconnected
    case event(name: String, payload: Data?)
    case ack(id: Int, payload: Data?)
    case unknown(String)

    static func parse(_ text: String) -> SocketIOPacket {
        guard let engineType = text.first else { return .unknown(text) }
        let rest = String(text.dropFirst())
        switch engineType {
        case "0":
            let json = (try? JSONSerialization.jsonObject(with: Data(rest.utf8))) as? [String: Any]
            let interval = (json?["pingInterval"] as? Double ?? 25_000) / 1000
            let timeout = (json?["pingTimeout"] as? Double ?? 20_000) / 1000
            return .open(pingInterval: interval, pingTimeout: timeout)
        case "1": return .close
        case "2": return .ping
        case "3": return .pong
        case "4": return parseSocketPacket(rest)
        default: return .unknown(text)
        }
    }

    private static func parseSocketPacket(_ text: String) -> SocketIOPacket {
        guard let type = text.first else { return .unknown(text) }
        var body = Substring(text.dropFirst())
        // Optional namespace ("/admin,") — we only use the default one.
        if body.hasPrefix("/"), let comma = body.firstIndex(of: ",") { body = body[body.index(after: comma)...] }
        // Optional ack id digits before the JSON.
        let digits = body.prefix { $0.isNumber }
        let ackId = Int(digits)
        body = body.dropFirst(digits.count)
        let json = Data(body.utf8)

        switch type {
        case "0": return .connected
        case "1": return .disconnected
        case "4":
            let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
            return .connectError(object?["message"] as? String ?? "connect_error")
        case "2":
            guard let array = (try? JSONSerialization.jsonObject(with: json)) as? [Any], let name = array.first as? String else { return .unknown(text) }
            let payload = array.count > 1 ? try? JSONSerialization.data(withJSONObject: array[1], options: [.fragmentsAllowed]) : nil
            return .event(name: name, payload: payload)
        case "3":
            guard let ackId else { return .unknown(text) }
            let array = (try? JSONSerialization.jsonObject(with: json)) as? [Any]
            let payload = array?.first.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
            return .ack(id: ackId, payload: payload)
        default: return .unknown(text)
        }
    }

    /// Encodes `42<ackId>["name",arg]`.
    static func encodeEvent(_ name: String, argument: Any?, ackId: Int? = nil) -> String {
        var items: [Any] = [name]
        if let argument { items.append(argument) }
        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.fragmentsAllowed])) ?? Data("[]".utf8)
        return "42" + (ackId.map(String.init) ?? "") + (String(data: data, encoding: .utf8) ?? "[]")
    }

    /// Connect to the default namespace with an auth payload: `40{"token":"…"}`.
    static func encodeConnect(token: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["token": token])) ?? Data("{}".utf8)
        return "40" + (String(data: data, encoding: .utf8) ?? "{}")
    }
}

/// Live order updates from the backend's Socket.IO server, implemented directly
/// on `URLSessionWebSocketTask` (no third-party socket library).
///
/// - Reconnects with exponential backoff when the connection drops.
/// - Re-subscribes to watched orders after reconnecting.
/// - Refreshes the access token if the server rejects it.
final class RealtimeClient: NSObject, @unchecked Sendable {
    enum Event {
        case orderStatus(orderId: String, status: OrderStatus, estimatedMinutes: Int?)
        case riderLocation(orderId: String, location: RiderLocation)
        case notification(title: String, body: String, orderId: String?)
        case connectionChanged(Bool)
    }

    private let baseURL: URL
    private let tokenProvider: SessionStore
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var isConnected = false
    private var shouldRun = false
    private var reconnectAttempt = 0
    private var watchedOrders = Set<String>()
    private var nextAckId = 0
    private var observers: [UUID: (Event) -> Void] = [:]
    private let lock = NSLock()

    init(baseURL: URL, tokenProvider: SessionStore) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        super.init()
        session = URLSession(configuration: .default)
    }

    // MARK: Public API

    @discardableResult
    func observe(_ handler: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { observers[id] = handler }
        return id
    }

    func removeObserver(_ id: UUID) { lock.withLock { observers[id] = nil } }

    func connect() {
        lock.withLock { shouldRun = true }
        guard task == nil else { return }
        Task { await self.open() }
    }

    func disconnect() {
        lock.withLock {
            shouldRun = false
            isConnected = false
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func watch(orderId: String) {
        lock.withLock { _ = watchedOrders.insert(orderId) }
        connect()
        if lock.withLock({ isConnected }) { subscribe(orderId) }
    }

    func unwatch(orderId: String) {
        lock.withLock { _ = watchedOrders.remove(orderId) }
        send(SocketIOPacket.encodeEvent("order:unsubscribe", argument: orderId))
    }

    // MARK: Connection

    private func socketURL() -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/socket.io/"
        components?.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]
        return components?.url
    }

    private func open() async {
        guard lock.withLock({ shouldRun }), let url = socketURL(), await tokenProvider.accessToken() != nil else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(on: task)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task else { return }
            switch result {
            case .success(.string(let text)):
                self.handle(SocketIOPacket.parse(text))
                self.receive(on: task)
            case .success:
                self.receive(on: task)
            case .failure:
                self.connectionLost()
            }
        }
    }

    private func handle(_ packet: SocketIOPacket) {
        switch packet {
        case .open:
            Task {
                guard let token = await tokenProvider.accessToken() else { return }
                send(SocketIOPacket.encodeConnect(token: token))
            }
        case .ping:
            send("3")
        case .connected:
            lock.withLock {
                isConnected = true
                reconnectAttempt = 0
            }
            emit(.connectionChanged(true))
            lock.withLock { Array(watchedOrders) }.forEach(subscribe)
        case .connectError(let message):
            if message == "UNAUTHORIZED" {
                // Token probably expired: refresh, then reconnect.
                Task {
                    _ = try? await tokenProvider.refreshAccessToken()
                    connectionLost()
                }
            } else {
                connectionLost()
            }
        case .event(let name, let payload):
            handleEvent(name, payload)
        case .close, .disconnected:
            connectionLost()
        case .pong, .ack, .unknown:
            break
        }
    }

    private func handleEvent(_ name: String, _ payload: Data?) {
        guard let payload, let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
        switch name {
        case "order:status":
            guard let orderId = json["orderId"] as? String, let raw = json["status"] as? String, let status = OrderStatus(rawValue: raw) else { return }
            emit(.orderStatus(orderId: orderId, status: status, estimatedMinutes: json["estimatedMinutes"] as? Int))
        case "order:location":
            guard let orderId = json["orderId"] as? String,
                  let lat = json["latitude"] as? Double, let lng = json["longitude"] as? Double else { return }
            let location = RiderLocation(latitude: lat, longitude: lng, progress: json["progress"] as? Double, isSimulated: json["isSimulated"] as? Bool ?? true)
            emit(.riderLocation(orderId: orderId, location: location))
        case "notification":
            guard let title = json["title"] as? String, let body = json["body"] as? String else { return }
            emit(.notification(title: title, body: body, orderId: json["orderId"] as? String))
        default:
            break
        }
    }

    private func subscribe(_ orderId: String) {
        let id: Int = lock.withLock { nextAckId += 1; return nextAckId }
        send(SocketIOPacket.encodeEvent("order:subscribe", argument: orderId, ackId: id))
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    private func connectionLost() {
        let (wasConnected, run, attempt): (Bool, Bool, Int) = lock.withLock {
            let state = (isConnected, shouldRun, reconnectAttempt)
            isConnected = false
            reconnectAttempt += 1
            return state
        }
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        if wasConnected { emit(.connectionChanged(false)) }
        guard run else { return }
        let delay = min(30, pow(2, Double(attempt)))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { await self?.open() }
        }
    }

    private func emit(_ event: Event) {
        let handlers = lock.withLock { Array(observers.values) }
        DispatchQueue.main.async { handlers.forEach { $0(event) } }
    }
}
