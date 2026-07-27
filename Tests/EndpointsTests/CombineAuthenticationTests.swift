#if canImport(Combine) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
import Testing
import Foundation
import Combine

@testable import Endpoints

/// Covers the Combine publishers against authenticated endpoints, plus cancellation
/// propagating into the underlying request.
@Suite("Combine Authentication", .serialized)
struct CombineAuthenticationTests {

    private static func url(_ path: String) -> URL {
        URL(string: "https://api.velosmobile.com\(path)")!
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func publisherAppliesEndpointAuthentication() async throws {
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/combine/keyed") { request in
            recorder.record(request)
            return (HTTPURLResponse(url: Self.url("/combine/keyed"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/combine/keyed") }

        let values = TestURLProtocol.makeSession()
            .endpointPublisher(with: CombineKeyedEndpoint())
            .values

        var received: AuthTestResponse?
        for try await value in values {
            received = value
        }

        #expect(received?.value == "ok")
        #expect(recorder.all().first?.value(forHTTPHeaderField: Header.authorization.name) == "Bearer combine-key")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func publisherRetriesAfterReauthentication() async throws {
        let errorData = try JSONEncoder().encode(AuthTestErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestResponse(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: Self.url("/combine/jwt"), statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: Self.url("/combine/jwt"), statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/combine/jwt") { request in
            recorder.record(request)
            return try responses.next()
        }
        defer { TestURLProtocol.unregister(path: "/combine/jwt") }

        await CombineJWTEndpoint.auth.setTokens(.init(accessToken: "old-access", refreshToken: "old-refresh"))

        let values = TestURLProtocol.makeSession()
            .endpointPublisher(with: CombineJWTEndpoint())
            .values

        var received: AuthTestResponse?
        for try await value in values {
            received = value
        }

        #expect(received?.value == "ok")

        let sent = recorder.all().map { $0.value(forHTTPHeaderField: Header.authorization.name) }
        #expect(sent == ["Bearer old-access", "Bearer new-access"])
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func publisherSurfacesAuthenticationErrors() async throws {
        let recorder = RequestRecorder()
        TestURLProtocol.register(path: "/combine/unauthenticated") { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { TestURLProtocol.unregister(path: "/combine/unauthenticated") }

        let values = TestURLProtocol.makeSession()
            .endpointPublisher(with: CombineUnauthenticatedJWTEndpoint())
            .values

        do {
            for try await _ in values {}
            Issue.record("Expected authenticationError to be thrown")
        } catch let error as CombineUnauthenticatedJWTEndpoint.TaskError {
            guard case .authenticationError(.notAuthenticated) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(recorder.all().isEmpty)
    }

    /// Cancelling the subscription must cancel the in-flight `Task`, not merely stop
    /// delivery — Combine gives the latter for free, so this asserts the former by
    /// having the endpoint's auth observe its own cancellation.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func cancellingSubscriptionCancelsInFlightWork() async throws {
        let cancellable = TestURLProtocol.makeSession()
            .endpointPublisher(with: CombineCancelEndpoint())
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        // Wait until the request is genuinely in flight inside authenticate.
        await CancellationProbe.shared.waitForStart()

        cancellable.cancel()

        var observed = false
        for _ in 0..<40 {
            if await CancellationProbe.shared.didObserveCancellation {
                observed = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(observed, "Cancelling the subscription should cancel the underlying task")
    }
}

// MARK: - Fixtures

struct CombineTestServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        [.production: URL(string: "https://api.velosmobile.com")!]
    }

    static var defaultEnvironment: Environments { .production }
}

struct CombineKeyedEndpoint: Endpoint {
    typealias Server = CombineTestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = HeaderKeyAuth(key: "combine-key")
    static let definition: Definition<CombineKeyedEndpoint> = Definition(method: .get, path: "combine/keyed")
}

struct CombineJWTEndpoint: Endpoint {
    typealias Server = CombineTestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        #expect(refreshToken == "old-refresh")
        return JWTAuth.TokenPair(accessToken: "new-access", refreshToken: "new-refresh")
    }

    static let definition: Definition<CombineJWTEndpoint> = Definition(method: .get, path: "combine/jwt")
}

struct CombineUnauthenticatedJWTEndpoint: Endpoint {
    typealias Server = CombineTestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
    }

    static let definition: Definition<CombineUnauthenticatedJWTEndpoint> = Definition(method: .get, path: "combine/unauthenticated")
}

struct CombineCancelEndpoint: Endpoint {
    typealias Server = CombineTestServer
    typealias Response = AuthTestResponse
    typealias ErrorResponse = AuthTestErrorResponse

    static let auth = ProbeAuth()
    static let definition: Definition<CombineCancelEndpoint> = Definition(method: .get, path: "combine/cancel")
}

/// Blocks inside `authenticate` so a test can cancel mid-flight, and records whether
/// the cancellation actually reached the task.
struct ProbeAuth: AuthenticationMethod {
    func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        await CancellationProbe.shared.markStarted()

        do {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        } catch {
            // Task.sleep throws when the enclosing task is cancelled.
            await CancellationProbe.shared.markCancelled()
            throw .custom(underlying: error)
        }

        return request
    }
}

actor CancellationProbe {
    static let shared = CancellationProbe()

    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var didObserveCancellation = false

    func markStarted() {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func markCancelled() {
        didObserveCancellation = true
    }
}
#endif
