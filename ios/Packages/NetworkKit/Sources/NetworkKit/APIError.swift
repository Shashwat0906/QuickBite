import Foundation

/// Every failure the networking layer can produce, already translated into
/// something the UI can show. View models switch on this instead of on raw
/// `URLError`s or status codes.
public enum APIError: Error, Equatable, Sendable {
    /// No internet connection.
    case offline
    /// The server didn't answer in time.
    case timeout
    /// Not signed in, or the session expired and couldn't be refreshed.
    case unauthorized(message: String)
    /// The API returned an error body: `{ "error": { "code", "message", "details" } }`.
    case server(status: Int, code: String, message: String)
    /// The response JSON didn't match the expected model.
    case decoding(String)
    /// Anything else at the transport level.
    case transport(String)
    case cancelled

    /// Text that is safe to show to a user.
    public var userMessage: String {
        switch self {
        case .offline: return "You're offline. Check your connection and try again."
        case .timeout: return "The server is taking too long to respond. Please try again."
        case .unauthorized(let message): return message
        case .server(_, _, let message): return message
        case .decoding: return "Something went wrong reading the server's response."
        case .transport: return "Couldn't reach QuickBite. Please try again."
        case .cancelled: return "The request was cancelled."
        }
    }

    /// The API's machine-readable error code, if any (e.g. `CART_CAFE_CONFLICT`).
    public var code: String? {
        if case .server(_, let code, _) = self { return code }
        if case .unauthorized = self { return "UNAUTHORIZED" }
        return nil
    }

    public var statusCode: Int? {
        if case .server(let status, _, _) = self { return status }
        if case .unauthorized = self { return 401 }
        return nil
    }

    /// Worth retrying automatically (for idempotent requests).
    var isTransient: Bool {
        switch self {
        case .timeout, .transport: return true
        case .server(let status, _, _): return status == 502 || status == 503 || status == 504
        default: return false
        }
    }

    static func from(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .transport(error.localizedDescription) }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .transport(urlError.localizedDescription)
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

/// Shape of the backend's error JSON.
struct ServerErrorBody: Decodable {
    struct Inner: Decodable {
        let code: String
        let message: String
    }
    let error: Inner
}
