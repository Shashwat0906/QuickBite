import Foundation
import os

/// Development-only request/response logging (enabled via configuration).
/// Authorization headers are redacted so tokens never end up in logs.
struct NetworkLogger: Sendable {
    let enabled: Bool
    private let logger = Logger(subsystem: "NetworkKit", category: "HTTP")

    func log(_ message: String) {
        guard enabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    func logRequest(_ request: URLRequest) {
        guard enabled else { return }
        var line = "→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")"
        if request.value(forHTTPHeaderField: "Authorization") != nil { line += " [auth]" }
        if let body = request.httpBody, body.count < 2_000, let text = String(data: body, encoding: .utf8) {
            line += "\n  body: \(Self.redact(text))"
        }
        log(line)
    }

    func logResponse(_ response: HTTPURLResponse, data: Data, duration: TimeInterval) {
        guard enabled else { return }
        let ms = Int(duration * 1000)
        var line = "← \(response.statusCode) \(response.url?.path ?? "") (\(ms) ms, \(data.count) B)"
        if response.statusCode >= 400, let text = String(data: data.prefix(1_000), encoding: .utf8) {
            line += "\n  \(text)"
        }
        log(line)
    }

    /// Hide passwords / tokens in logged JSON bodies.
    static func redact(_ json: String) -> String {
        let keys = ["password", "refreshToken", "accessToken", "identityToken", "razorpaySignature"]
        var result = json
        for key in keys {
            let pattern = "\"\(key)\"\\s*:\\s*\"[^\"]*\""
            result = result.replacingOccurrences(of: pattern, with: "\"\(key)\":\"•••\"", options: .regularExpression)
        }
        return result
    }
}
