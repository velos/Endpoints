#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

@Suite("Authenticated Session", .serialized)
struct AuthenticatedSessionTests {

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

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

        TestURLProtocol.handler = { _ in
            try responses.next()
        }
        defer { TestURLProtocol.handler = nil }

        let auth = TestAuth()
        let session = AuthenticatedSession(session: Self.makeSession(), auth: auth, maxRetryAttempts: 1)

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

        TestURLProtocol.handler = { _ in
            try responses.next()
        }
        defer { TestURLProtocol.handler = nil }

        let auth = TestAuth()
        let session = AuthenticatedSession(session: Self.makeSession(), auth: auth, maxRetryAttempts: 1)

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

        TestURLProtocol.handler = { _ in
            try responses.next()
        }
        defer { TestURLProtocol.handler = nil }

        let session = AuthenticatedSession(session: Self.makeSession(), auth: FailingRefreshAuth(), maxRetryAttempts: 1)

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
        TestURLProtocol.handler = { request in
            recorder.record(request)
            return try responses.next()
        }
        defer { TestURLProtocol.handler = nil }

        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old-access", refreshToken: "old-refresh"),
            refreshHandler: { refreshToken in
                #expect(refreshToken == "old-refresh")
                return JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh")
            }
        )
        let session = AuthenticatedSession(session: Self.makeSession(), auth: auth, maxRetryAttempts: 1)

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
        TestURLProtocol.handler = { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { TestURLProtocol.handler = nil }

        let auth = JWTAuth(initialTokens: nil) { _ in
            JWTAuth.TokenPair(accessToken: "new", refreshToken: "refresh")
        }
        let session = AuthenticatedSession(session: Self.makeSession(), auth: auth)

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

final class ResponseQueue: @unchecked Sendable {
    private var responses: [(HTTPURLResponse, Data)]
    private let lock = NSLock()

    init(_ responses: [(HTTPURLResponse, Data)]) {
        self.responses = responses
    }

    func next() throws -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }

        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }
}

final class RequestRecorder: @unchecked Sendable {
    private var requests: [URLRequest] = []
    private let lock = NSLock()

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    func all() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

final class TestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
#endif
