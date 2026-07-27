#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

/// Exercises endpoint-declared authentication end to end: each endpoint below declares
/// its own auth instance, so tests stay isolated while sharing one transport.
@Suite("Authenticated Endpoints", .serialized)
struct AuthenticatedEndpointTests {

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func retriesAfterReauthentication() async throws {
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: testURL("/auth/retry"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: testURL("/auth/retry"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        TestURLProtocol.register(path: "/auth/retry") { _ in try responses.next() }
        defer { TestURLProtocol.unregister(path: "/auth/retry") }

        let response = try await TestURLProtocol.makeSession().response(with: RetryEndpoint())

        #expect(response.value == "ok")

        let counts = await RetryEndpoint.auth.counts()
        #expect(counts.authenticate == 2)
        #expect(counts.reauthenticate == 1)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func retryExhaustionSurfacesFinalErrorResponse() async throws {
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: testURL("/auth/exhaustion"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: testURL("/auth/exhaustion"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        ])

        TestURLProtocol.register(path: "/auth/exhaustion") { _ in try responses.next() }
        defer { TestURLProtocol.unregister(path: "/auth/exhaustion") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: ExhaustionEndpoint())
            Issue.record("Expected errorResponse to be thrown")
        } catch {
            guard case .errorResponse(let httpResponse, let errorResponse) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(httpResponse.statusCode == 401)
            #expect(errorResponse.message == "unauthorized")
        }

        let counts = await ExhaustionEndpoint.auth.counts()
        #expect(counts.authenticate == 2)
        #expect(counts.reauthenticate == 1)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func refreshFailureSurfacesAsAuthenticationError() async throws {
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))

        TestURLProtocol.register(path: "/auth/failing-refresh") { _ in
            (HTTPURLResponse(url: testURL("/auth/failing-refresh"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/failing-refresh") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: FailingRefreshEndpoint())
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
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: testURL("/auth/jwt"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: testURL("/auth/jwt"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/jwt") { request in
            recorder.record(request)
            return try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/auth/jwt") }

        await JWTEndpoint.auth.setTokens(.init(accessToken: "old-access", refreshToken: "old-refresh"))

        let response = try await TestURLProtocol.makeSession().response(with: JWTEndpoint())

        #expect(response.value == "ok")

        let sentAuthorization = recorder.all().map { $0.value(forHTTPHeaderField: Header.authorization.name) }
        #expect(sentAuthorization == ["Bearer old-access", "Bearer new-access"])
        #expect(await JWTEndpoint.auth.tokens?.accessToken == "new-access")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func jwtWithoutTokensFailsWithoutSendingRequest() async throws {
        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/unauthenticated-jwt") { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { TestURLProtocol.unregister(path: "/auth/unauthenticated-jwt") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: UnauthenticatedJWTEndpoint())
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
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))

        TestURLProtocol.register(path: "/auth/refresh-failure") { _ in
            (HTTPURLResponse(url: testURL("/auth/refresh-failure"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/refresh-failure") }

        await RefreshFailureEndpoint.auth.setTokens(.init(accessToken: "old", refreshToken: "refresh"))

        do {
            _ = try await TestURLProtocol.makeSession().response(with: RefreshFailureEndpoint())
            Issue.record("Expected authenticationError to be thrown")
        } catch {
            guard case .authenticationError(.refreshFailed(let underlying)) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(underlying is TestRefreshError)
        }

        #expect(await RefreshFailureRecorder.shared.error is TestRefreshError)
        #expect(await RefreshFailureEndpoint.auth.tokens?.accessToken == "old")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func jwtProactiveRefreshHappensBeforeRequest() async throws {
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/proactive") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: testURL("/auth/proactive"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/proactive") }

        await ProactiveEndpoint.auth.setTokens(
            .init(accessToken: "expired-access", refreshToken: "old-refresh", expiresAt: Date(timeIntervalSinceNow: -60))
        )

        let response = try await TestURLProtocol.makeSession().response(with: ProactiveEndpoint())

        #expect(response.value == "ok")

        // The expired token never went over the wire: one request, already refreshed.
        let sentAuthorization = recorder.all().map { $0.value(forHTTPHeaderField: Header.authorization.name) }
        #expect(sentAuthorization == ["Bearer new-access"])
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func staticAuthDoesNotRetryOn401() async throws {
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/static-key") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: testURL("/auth/static-key"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/static-key") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: StaticKeyEndpoint())
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

    // MARK: - Declaration semantics

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func endpointInheritsServerAuth() async throws {
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/inherited") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: testURL("/auth/inherited"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/inherited") }

        _ = try await TestURLProtocol.makeSession().response(with: InheritedAuthEndpoint())

        // The endpoint declares no auth of its own and picks up its server's.
        #expect(recorder.all().first?.value(forHTTPHeaderField: Header.authorization.name) == "Bearer server-key")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func endpointCanOptOutOfServerAuth() async throws {
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/opted-out") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: testURL("/auth/opted-out"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/opted-out") }

        _ = try await TestURLProtocol.makeSession().response(with: OptedOutEndpoint())

        // Same server as InheritedAuthEndpoint, but this endpoint overrides with NoAuth.
        #expect(recorder.all().first?.value(forHTTPHeaderField: Header.authorization.name) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func endpointCanUseADifferentMethodThanItsServer() async throws {
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/auth/overridden") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: testURL("/auth/overridden"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/auth/overridden") }

        _ = try await TestURLProtocol.makeSession().response(with: OverriddenAuthEndpoint())

        #expect(recorder.all().first?.value(forHTTPHeaderField: "X-Client-Key") == "client-key")
        #expect(recorder.all().first?.value(forHTTPHeaderField: Header.authorization.name) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func endpointsOnAServerShareOneAuthInstance() {
        // Identity matters: a shared instance is what lets refreshes coalesce across endpoints.
        #expect(SharedAuthEndpointA.auth === SharedAuthEndpointB.auth)
        #expect(SharedAuthEndpointA.auth === SharedAuthServer.auth)
    }
}

// MARK: - Servers

/// Declares a server-wide authentication method inherited by its endpoints.
struct KeyedServer: ServerDefinition {
    static let auth = HeaderKeyAuth(key: "server-key")

    var baseUrls: [Environments: URL] {
        [.production: URL(string: "https://api.velosmobile.com")!]
    }

    static var defaultEnvironment: Environments { .production }
}

struct SharedAuthServer: ServerDefinition {
    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
    }

    var baseUrls: [Environments: URL] {
        [.production: URL(string: "https://api.velosmobile.com")!]
    }

    static var defaultEnvironment: Environments { .production }
}

// MARK: - Endpoints

struct RetryEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = TestAuth()
    static let definition: Definition<RetryEndpoint> = Definition(method: .get, path: "auth/retry")
}

struct ExhaustionEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = TestAuth()
    static let definition: Definition<ExhaustionEndpoint> = Definition(method: .get, path: "auth/exhaustion")
}

struct FailingRefreshEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = FailingRefreshAuth()
    static let definition: Definition<FailingRefreshEndpoint> = Definition(method: .get, path: "auth/failing-refresh")
}

struct JWTEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        #expect(refreshToken == "old-refresh")
        return JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh")
    }

    static let definition: Definition<JWTEndpoint> = Definition(method: .get, path: "auth/jwt")
}

struct UnauthenticatedJWTEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
    }

    static let definition: Definition<UnauthenticatedJWTEndpoint> = Definition(method: .get, path: "auth/unauthenticated-jwt")
}

struct RefreshFailureEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(
        initialTokens: nil,
        refreshHandler: { _ in throw TestRefreshError() },
        onRefreshFailed: { error in await RefreshFailureRecorder.shared.set(error) }
    )

    static let definition: Definition<RefreshFailureEndpoint> = Definition(method: .get, path: "auth/refresh-failure")
}

struct ProactiveEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        #expect(refreshToken == "old-refresh")
        return JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: Date(timeIntervalSinceNow: 3600))
    }

    static let definition: Definition<ProactiveEndpoint> = Definition(method: .get, path: "auth/proactive")
}

struct StaticKeyEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = HeaderKeyAuth(key: "static-key")
    static let definition: Definition<StaticKeyEndpoint> = Definition(method: .get, path: "auth/static-key")
}

/// Declares no auth: inherits `KeyedServer.auth`.
struct InheritedAuthEndpoint: Endpoint {
    typealias Server = KeyedServer
    typealias Response = AuthTestResponse

    static let definition: Definition<InheritedAuthEndpoint> = Definition(method: .get, path: "auth/inherited")
}

/// On an authenticated server, but opts out — the shape a login endpoint takes.
struct OptedOutEndpoint: Endpoint {
    typealias Server = KeyedServer
    typealias Response = AuthTestResponse

    static var auth: NoAuth { NoAuth() }
    static let definition: Definition<OptedOutEndpoint> = Definition(method: .get, path: "auth/opted-out")
}

/// On an authenticated server, but uses a different method entirely.
struct OverriddenAuthEndpoint: Endpoint {
    typealias Server = KeyedServer
    typealias Response = AuthTestResponse

    static let auth = HeaderKeyAuth(key: "client-key", header: "X-Client-Key", prefix: nil)
    static let definition: Definition<OverriddenAuthEndpoint> = Definition(method: .get, path: "auth/overridden")
}

struct SharedAuthEndpointA: Endpoint {
    typealias Server = SharedAuthServer
    typealias Response = AuthTestResponse

    static let definition: Definition<SharedAuthEndpointA> = Definition(method: .get, path: "auth/shared-a")
}

struct SharedAuthEndpointB: Endpoint {
    typealias Server = SharedAuthServer
    typealias Response = AuthTestResponse

    static let definition: Definition<SharedAuthEndpointB> = Definition(method: .get, path: "auth/shared-b")
}

// MARK: - Test authentication methods

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

actor RefreshFailureRecorder {
    static let shared = RefreshFailureRecorder()

    private(set) var error: Error?

    func set(_ error: Error) {
        self.error = error
    }
}
#endif
