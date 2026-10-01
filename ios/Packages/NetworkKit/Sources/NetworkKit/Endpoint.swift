import Foundation

/// HTTP verbs used by the API.
public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"

    /// Idempotent requests can be retried safely after a network failure.
    public var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: return true
        case .post, .patch: return false
        }
    }
}

/// A typed description of one API call.
///
/// ```swift
/// let endpoint = Endpoint<HomeFeed>(path: "/home", query: ["lat": "28.63"])
/// let feed = try await client.send(endpoint)
/// ```
/// The generic `Response` ties the request to the type it decodes into, so a
/// call site can never decode the wrong model.
public struct Endpoint<Response: Decodable>: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var query: [String: String]
    public var body: Data?
    public var headers: [String: String]
    public var requiresAuth: Bool
    /// `nil` = use the method's default (retry idempotent requests only).
    public var allowsRetry: Bool?
    public var timeout: TimeInterval?

    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresAuth: Bool = false,
        allowsRetry: Bool? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.headers = headers
        self.requiresAuth = requiresAuth
        self.allowsRetry = allowsRetry
        self.timeout = timeout
    }

    /// Convenience initialiser that JSON-encodes an `Encodable` body.
    public init<Body: Encodable>(
        path: String,
        method: HTTPMethod,
        jsonBody: Body,
        query: [String: String] = [:],
        requiresAuth: Bool = false,
        allowsRetry: Bool? = nil
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.init(
            path: path,
            method: method,
            query: query,
            body: try encoder.encode(jsonBody),
            headers: ["Content-Type": "application/json"],
            requiresAuth: requiresAuth,
            allowsRetry: allowsRetry
        )
    }

    var shouldRetry: Bool { allowsRetry ?? method.isIdempotent }
}

/// Decodes 204 No Content / empty bodies.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}
