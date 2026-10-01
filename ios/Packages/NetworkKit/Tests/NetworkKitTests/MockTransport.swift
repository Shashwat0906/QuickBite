import Foundation
import NetworkKit

/// Programmable transport for tests: queue responses per path, inspect requests.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case json(Int, String)
        case error(URLError.Code)
    }

    private let lock = NSLock()
    private var queues: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []
    var delayNanoseconds: UInt64 = 0

    func enqueue(_ path: String, _ replies: Reply...) {
        lock.lock(); defer { lock.unlock() }
        queues[path, default: []].append(contentsOf: replies)
    }

    func requestCount(for path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.url?.path == path }.count
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let reply: Reply = {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            guard var queue = queues[path], !queue.isEmpty else { return .json(404, #"{"error":{"code":"NOT_FOUND","message":"no stub"}}"#) }
            let next = queue.removeFirst()
            // Keep returning the last reply once the queue is exhausted.
            queues[path] = queue.isEmpty ? [next] : queue
            return next
        }()
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        switch reply {
        case .json(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        case .error(let code):
            throw URLError(code)
        }
    }
}

final class MockTokenProvider: AuthTokenProvider, @unchecked Sendable {
    var token: String?
    var refreshedToken: String?
    private(set) var refreshCalls = 0

    init(token: String?, refreshedToken: String? = nil) {
        self.token = token
        self.refreshedToken = refreshedToken
    }

    func accessToken() async -> String? { token }

    func refreshAccessToken() async throws -> String? {
        refreshCalls += 1
        token = refreshedToken
        return refreshedToken
    }
}
