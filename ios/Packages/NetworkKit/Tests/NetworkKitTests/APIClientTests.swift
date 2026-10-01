import XCTest
@testable import NetworkKit

private struct Cafe: Decodable, Equatable {
    let id: String
    let name: String
    let createdAt: Date?
}

private struct CafeList: Decodable { let cafes: [Cafe] }

final class APIClientTests: XCTestCase {
    private var transport: MockTransport!
    private var tokens: MockTokenProvider!
    private var client: URLSessionAPIClient!

    override func setUp() {
        super.setUp()
        transport = MockTransport()
        tokens = MockTokenProvider(token: "access-1", refreshedToken: "access-2")
        client = URLSessionAPIClient(
            configuration: APIClientConfiguration(baseURL: URL(string: "https://api.test/api/v1")!, maxRetries: 2, retryBaseDelay: 0.001),
            transport: transport,
            tokenProvider: tokens
        )
    }

    func testDecodesResponseWithFractionalSecondDates() async throws {
        transport.enqueue("/api/v1/cafes", .json(200, #"{"cafes":[{"id":"1","name":"Brew","createdAt":"2026-10-02T10:15:30.123Z"}]}"#))
        let list = try await client.send(Endpoint<CafeList>(path: "/cafes"))
        XCTAssertEqual(list.cafes.first?.name, "Brew")
        XCTAssertNotNil(list.cafes.first?.createdAt)
    }

    func testBuildsQueryAndHeaders() async throws {
        transport.enqueue("/api/v1/search", .json(200, #"{"cafes":[]}"#))
        _ = try await client.send(Endpoint<CafeList>(path: "/search", query: ["q": "cold brew", "veg": "true"], requiresAuth: true))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.query, "q=cold%20brew&veg=true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testMapsServerErrorBody() async {
        transport.enqueue("/api/v1/cart/items", .json(409, #"{"error":{"code":"CART_CAFE_CONFLICT","message":"Your cart has items from another cafe."}}"#))
        do {
            _ = try await client.send(Endpoint<EmptyResponse>(path: "/cart/items", method: .post, requiresAuth: true))
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 409, code: "CART_CAFE_CONFLICT", message: "Your cart has items from another cafe."))
            XCTAssertEqual(error.code, "CART_CAFE_CONFLICT")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRetriesIdempotentRequestOnServiceUnavailable() async throws {
        transport.enqueue("/api/v1/cafes", .json(503, "{}"), .json(503, "{}"), .json(200, #"{"cafes":[]}"#))
        _ = try await client.send(Endpoint<CafeList>(path: "/cafes"))
        XCTAssertEqual(transport.requestCount(for: "/api/v1/cafes"), 3)
    }

    func testGivesUpAfterMaxRetries() async {
        transport.enqueue("/api/v1/cafes", .error(.timedOut))
        do {
            _ = try await client.send(Endpoint<CafeList>(path: "/cafes"))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .timeout)
            XCTAssertEqual(transport.requestCount(for: "/api/v1/cafes"), 3) // 1 + 2 retries
        }
    }

    func testDoesNotRetryNonIdempotentPost() async {
        transport.enqueue("/api/v1/orders", .json(503, "{}"))
        _ = try? await client.send(Endpoint<EmptyResponse>(path: "/orders", method: .post, requiresAuth: true))
        XCTAssertEqual(transport.requestCount(for: "/api/v1/orders"), 1)
    }

    func testOfflineIsReportedAsOffline() async {
        transport.enqueue("/api/v1/home", .error(.notConnectedToInternet))
        do {
            _ = try await client.send(Endpoint<CafeList>(path: "/home", allowsRetry: false))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
    }

    func testRefreshesTokenOnceOn401AndReplays() async throws {
        transport.enqueue(
            "/api/v1/auth/me",
            .json(401, #"{"error":{"code":"TOKEN_EXPIRED","message":"Access token expired"}}"#),
            .json(200, #"{"cafes":[]}"#)
        )
        _ = try await client.send(Endpoint<CafeList>(path: "/auth/me", requiresAuth: true))
        XCTAssertEqual(tokens.refreshCalls, 1)
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testUnauthorizedWhenRefreshFails() async {
        tokens.refreshedToken = nil
        transport.enqueue("/api/v1/auth/me", .json(401, #"{"error":{"code":"UNAUTHORIZED","message":"Please sign in again"}}"#))
        do {
            _ = try await client.send(Endpoint<CafeList>(path: "/auth/me", requiresAuth: true))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized(message: "Please sign in again"))
        }
    }

    func testAuthRequiredWithoutTokenFailsFast() async {
        tokens.token = nil
        do {
            _ = try await client.send(Endpoint<CafeList>(path: "/cart", requiresAuth: true))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? APIError)?.statusCode, 401)
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testConcurrentIdenticalGetsShareOneRequest() async throws {
        transport.delayNanoseconds = 50_000_000
        transport.enqueue("/api/v1/home", .json(200, #"{"cafes":[]}"#))
        async let a = client.send(Endpoint<CafeList>(path: "/home"))
        async let b = client.send(Endpoint<CafeList>(path: "/home"))
        async let c = client.send(Endpoint<CafeList>(path: "/home"))
        _ = try await (a, b, c)
        XCTAssertEqual(transport.requestCount(for: "/api/v1/home"), 1)
    }

    func testEmptyResponseFor204() async throws {
        transport.enqueue("/api/v1/auth/logout", .json(204, ""))
        let result = try await client.send(Endpoint<EmptyResponse>(path: "/auth/logout", method: .post))
        XCTAssertEqual(result, EmptyResponse())
    }

    func testDecodingErrorIsWrapped() async {
        transport.enqueue("/api/v1/cafes", .json(200, #"{"wrong":true}"#))
        do {
            _ = try await client.send(Endpoint<CafeList>(path: "/cafes"))
            XCTFail("expected error")
        } catch {
            guard case .decoding = error as? APIError else { return XCTFail("expected decoding error, got \(error)") }
        }
    }

    func testJSONBodyEncoding() throws {
        struct Login: Encodable { let email: String; let password: String }
        let endpoint = try Endpoint<EmptyResponse>(path: "/auth/login", method: .post, jsonBody: Login(email: "a@b.co", password: "x"))
        let json = try XCTUnwrap(String(data: endpoint.body ?? Data(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"email\":\"a@b.co\""))
        XCTAssertEqual(endpoint.headers["Content-Type"], "application/json")
    }

    func testLoggerRedactsSecrets() {
        let redacted = NetworkLogger.redact(#"{"email":"a@b.co","password":"hunter2","refreshToken":"abc"}"#)
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("abc\""))
        XCTAssertTrue(redacted.contains("a@b.co"))
    }

    func testUserMessages() {
        XCTAssertTrue(APIError.offline.userMessage.contains("offline"))
        XCTAssertEqual(APIError.server(status: 422, code: "X", message: "Readable").userMessage, "Readable")
    }
}
