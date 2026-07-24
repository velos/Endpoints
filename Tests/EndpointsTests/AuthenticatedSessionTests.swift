#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

@Suite("Authenticated Session", .serialized)
struct AuthenticatedSessionTests {

    private static let url = URL(string: "https://api.velosmobile.com/auth/test")!

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func retriesAfterReauthentication() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestEndpoint.Response(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        TestURLProtocol.register(path: "/auth/test") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let auth = TestAuth()
        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: auth, maxRetryAttempts: 1)

        let response = try await session.response(with: AuthTestEndpoint())

        #expect(response.value == "ok")

        let counts = await auth.counts()
        #expect(counts.authenticate == 2)
        #expect(counts.reauthenticate == 1)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func retryExhaustionSurfacesFinalErrorResponse() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        ])

        TestURLProtocol.register(path: "/auth/test") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let auth = TestAuth()
        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: auth, maxRetryAttempts: 1)

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected errorResponse to be thrown")
        } catch {
            guard case .errorResponse(let httpResponse, let errorResponse) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(httpResponse.statusCode == 401)
            #expect(errorResponse.message == "unauthorized")
        }

        let counts = await auth.counts()
        #expect(counts.authenticate == 2)
        #expect(counts.reauthenticate == 1)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func refreshFailureSurfacesAsAuthenticationError() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        ])

        TestURLProtocol.register(path: "/auth/test") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: FailingRefreshAuth(), maxRetryAttempts: 1)

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected authenticationError to be thrown")
        } catch {
            guard case .authenticationError(.refreshFailed) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func jwtRefreshFlowEndToEnd() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestEndpoint.Response(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/test") { request in
            recorder.record(request)
            return try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old-access", refreshToken: "old-refresh"),
            refreshHandler: { refreshToken in
                #expect(refreshToken == "old-refresh")
                return JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh")
            }
        )
        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: auth, maxRetryAttempts: 1)

        let response = try await session.response(with: AuthTestEndpoint())

        #expect(response.value == "ok")

        let sentAuthorization = recorder.all().map { $0.value(forHTTPHeaderField: Header.authorization.name) }
        #expect(sentAuthorization == ["Bearer old-access", "Bearer new-access"])
        #expect(await auth.tokens == JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh"))
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func jwtWithoutTokensFailsWithoutSendingRequest() async throws {
        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/test") { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let auth = JWTAuth(initialTokens: nil) { _ in
            JWTAuth.TokenPair(accessToken: "new", refreshToken: "refresh")
        }
        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: auth)

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected authenticationError to be thrown")
        } catch {
            guard case .authenticationError(.notAuthenticated) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        #expect(recorder.all().isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func jwtRefreshFailureInvokesFailureHandler() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        ])

        TestURLProtocol.register(path: "/auth/test") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let failureBox = ErrorBox()
        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
            refreshHandler: { _ in throw TestRefreshError() },
            onRefreshFailed: { error in await failureBox.set(error) }
        )
        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: auth, maxRetryAttempts: 1)

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected authenticationError to be thrown")
        } catch {
            guard case .authenticationError(.refreshFailed(let underlying)) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(underlying is TestRefreshError)
        }

        #expect(await failureBox.error is TestRefreshError)
        #expect((await auth.tokens)?.accessToken == "old")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func staticAuthDoesNotRetryOn401() async throws {
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        ])

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/test") { request in
            recorder.record(request)
            return try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: HeaderKeyAuth(key: "static-key"), maxRetryAttempts: 1)

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected errorResponse to be thrown")
        } catch {
            guard case .errorResponse(let httpResponse, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(httpResponse.statusCode == 401)
        }

        let sent = recorder.all()
        #expect(sent.count == 1)
        #expect(sent.first?.value(forHTTPHeaderField: Header.authorization.name) == "Bearer static-key")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func voidResponse() async throws {
        let voidUrl = URL(string: "https://api.velosmobile.com/auth/void")!
        let responses = ResponseQueue([
            (HTTPURLResponse(url: voidUrl, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        ])

        TestURLProtocol.register(path: "/auth/void") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/void") }

        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: NoAuth())

        try await session.response(with: AuthVoidEndpoint())
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func dataResponse() async throws {
        let dataUrl = URL(string: "https://api.velosmobile.com/auth/data")!
        let payload = Data([0xde, 0xad, 0xbe, 0xef])
        let responses = ResponseQueue([
            (HTTPURLResponse(url: dataUrl, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        ])

        TestURLProtocol.register(path: "/auth/data") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/data") }

        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: NoAuth())

        let response = try await session.response(with: AuthDataEndpoint())
        #expect(response == payload)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func decodeFailureSurfacesAsResponseParseError() async throws {
        let garbage = Data("not json".utf8)
        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!, garbage)
        ])

        TestURLProtocol.register(path: "/auth/test") { _ in
            try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/test") }

        let session = AuthenticatedSession(session: TestURLProtocol.makeSession(), auth: NoAuth())

        do {
            _ = try await session.response(with: AuthTestEndpoint())
            Issue.record("Expected responseParseError to be thrown")
        } catch {
            guard case .responseParseError(let data, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(data == garbage)
        }
    }
}

struct AuthTestEndpoint: Endpoint {
    typealias Server = TestServer

    static let definition: Definition<AuthTestEndpoint> = Definition(
        method: .get,
        path: "auth/test"
    )

    struct Response: Codable, Sendable {
        let value: String
    }

    struct ErrorResponse: Codable, Sendable, Equatable {
        let message: String
    }
}

struct AuthVoidEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void

    static let definition: Definition<AuthVoidEndpoint> = Definition(
        method: .post,
        path: "auth/void"
    )
}

struct AuthDataEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Data

    static let definition: Definition<AuthDataEndpoint> = Definition(
        method: .get,
        path: "auth/data"
    )
}

actor TestAuth: AuthenticationMethod {
    private var authenticateCount = 0
    private var reauthenticateCount = 0

    func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        authenticateCount += 1
        return request
    }

    nonisolated func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        response?.statusCode == 401
    }

    func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError) {
        reauthenticateCount += 1
    }

    func counts() -> (authenticate: Int, reauthenticate: Int) {
        (authenticateCount, reauthenticateCount)
    }
}

struct FailingRefreshAuth: AuthenticationMethod {
    func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        request
    }

    func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        response?.statusCode == 401
    }

    func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError) {
        throw .refreshFailed(underlying: URLError(.userAuthenticationRequired))
    }
}

struct TestRefreshError: Error {}

actor ErrorBox {
    private(set) var error: Error?

    func set(_ error: Error) {
        self.error = error
    }
}
#endif
