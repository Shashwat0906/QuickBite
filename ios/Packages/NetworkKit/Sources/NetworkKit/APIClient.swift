import Foundation

/// Abstraction over `URLSession` so tests can inject canned responses.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await self.data(for: request, delegate: nil)
    }
}

/// Supplies and refreshes the access token. Implemented by the app's session
/// store (which keeps tokens in the Keychain).
public protocol AuthTokenProvider: AnyObject, Sendable {
    func accessToken() async -> String?
    /// Exchanges the refresh token for a new access token. Return `nil` (or
    /// throw) when the session can't be renewed — the user must sign in again.
    func refreshAccessToken() async throws -> String?
}

/// Anything that can perform typed requests. View models and services depend
/// on this protocol, never on `URLSession`, so they can be unit tested.
public protocol APIClient: Sendable {
    func send<Response: Decodable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

public struct APIClientConfiguration: Sendable {
    public var baseURL: URL
    public var defaultTimeout: TimeInterval
    public var maxRetries: Int
    /// Base delay for exponential backoff (0.5s → 1s → 2s …).
    public var retryBaseDelay: TimeInterval
    public var logging: Bool
    public var defaultHeaders: [String: String]

    public init(
        baseURL: URL,
        defaultTimeout: TimeInterval = 15,
        maxRetries: Int = 2,
        retryBaseDelay: TimeInterval = 0.5,
        logging: Bool = false,
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.defaultTimeout = defaultTimeout
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
        self.logging = logging
        self.defaultHeaders = defaultHeaders
    }
}

/// `URLSession`-backed client with:
/// - async/await API
/// - automatic bearer token + one silent refresh-and-retry on `401`
/// - retries with exponential backoff for idempotent requests on transient failures
/// - de-duplication of identical in-flight GET requests
/// - debug logging
public final class URLSessionAPIClient: APIClient, @unchecked Sendable {
    private let configuration: APIClientConfiguration
    private let transport: HTTPTransport
    private weak var tokenProvider: AuthTokenProvider?
    private let inFlight = InFlightRequests()
    private let logger: NetworkLogger
    public let decoder: JSONDecoder

    public init(
        configuration: APIClientConfiguration,
        transport: HTTPTransport = URLSession.shared,
        tokenProvider: AuthTokenProvider? = nil
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.logger = NetworkLogger(enabled: configuration.logging)
        self.decoder = JSONDecoder.api
    }

    public func setTokenProvider(_ provider: AuthTokenProvider) {
        tokenProvider = provider
    }

    public func send<Response: Decodable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let data = try await perform(endpoint)
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response { return empty }
        do {
            return try decoder.decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            logger.log("❌ decoding \(Response.self): \(error)")
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - Pipeline

    private func perform<Response>(_ endpoint: Endpoint<Response>) async throws -> Data {
        // Identical GETs that are already running share one network call.
        if endpoint.method == .get {
            let key = try makeRequest(endpoint, token: nil).url?.absoluteString ?? endpoint.path
            return try await inFlight.run(key: key) { [self] in try await self.performWithRetry(endpoint) }
        }
        return try await performWithRetry(endpoint)
    }

    private func performWithRetry<Response>(_ endpoint: Endpoint<Response>) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await performAuthorized(endpoint)
            } catch {
                let apiError = APIError.from(error)
                guard endpoint.shouldRetry, apiError.isTransient, attempt < configuration.maxRetries else { throw apiError }
                let delay = configuration.retryBaseDelay * pow(2, Double(attempt))
                logger.log("↻ retry \(attempt + 1) for \(endpoint.method.rawValue) \(endpoint.path) in \(delay)s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    private func performAuthorized<Response>(_ endpoint: Endpoint<Response>) async throws -> Data {
        let token = endpoint.requiresAuth ? await tokenProvider?.accessToken() : nil
        if endpoint.requiresAuth && token == nil { throw APIError.unauthorized(message: "Please sign in to continue.") }
        do {
            return try await execute(makeRequest(endpoint, token: token))
        } catch APIError.unauthorized(let message) where endpoint.requiresAuth {
            // Access token expired → refresh once and replay the request.
            guard let provider = tokenProvider, let fresh = try? await provider.refreshAccessToken() else {
                throw APIError.unauthorized(message: message)
            }
            return try await execute(makeRequest(endpoint, token: fresh))
        }
    }

    func makeRequest<Response>(_ endpoint: Endpoint<Response>, token: String?) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Invalid URL for \(endpoint.path)")
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.transport("Invalid URL for \(endpoint.path)") }
        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout ?? configuration.defaultTimeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        configuration.defaultHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        endpoint.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let started = Date()
        logger.logRequest(request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            logger.log("✖︎ \(request.httpMethod ?? "") \(request.url?.path ?? "") failed: \(error.localizedDescription)")
            throw APIError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Not an HTTP response") }
        logger.logResponse(http, data: data, duration: Date().timeIntervalSince(started))

        switch http.statusCode {
        case 200..<300:
            return data
        default:
            let body = try? decoder.decode(ServerErrorBody.self, from: data)
            let message = body?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized
            if http.statusCode == 401 { throw APIError.unauthorized(message: message) }
            throw APIError.server(status: http.statusCode, code: body?.error.code ?? "HTTP_\(http.statusCode)", message: message)
        }
    }
}

/// Coalesces concurrent identical requests into one task.
actor InFlightRequests {
    private var tasks: [String: Task<Data, Error>] = [:]

    func run(key: String, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let existing = tasks[key] { return try await existing.value }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

public extension JSONDecoder {
    /// Decoder matching the API: ISO-8601 dates with or without fractional seconds.
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601Parsing.fractional.date(from: string) ?? ISO8601Parsing.plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }
}

enum ISO8601Parsing {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
