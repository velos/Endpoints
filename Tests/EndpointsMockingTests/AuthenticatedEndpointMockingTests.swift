import Testing
import Foundation
import Endpoints
@testable import EndpointsMocking

/// A server whose endpoints are authenticated, to confirm mocking short-circuits
/// before authentication runs.
struct MockAuthenticatedServer: ServerDefinition {
    static let auth = JWTAuth(initialTokens: nil) { refreshToken in
        JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
    }

    var baseUrls: [Environments: URL] {
        [.production: URL(string: "https://api.velosmobile.com")!]
    }

    static var defaultEnvironment: Environments { .production }
}

struct MockAuthenticatedEndpoint: Endpoint {
    typealias Server = MockAuthenticatedServer

    static let definition: Definition<MockAuthenticatedEndpoint> = Definition(
        method: .get,
        path: "authenticated"
    )

    struct Response: Codable {
        let value: String
    }
}

@Suite("Authenticated Endpoint Mocking")
struct AuthenticatedEndpointMockingTests {
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockedResponseWorks() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "mocked"))) {
            let endpoint = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await URLSession.shared.response(with: endpoint)
            #expect(response.response1 == "mocked")
        }
    }

    /// The endpoint's auth has no tokens, so a real request would throw
    /// `.authenticationError(.notAuthenticated)`. Getting a mocked value back proves
    /// mocking short-circuits ahead of authentication.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockingBypassesAuthentication() async throws {
        try await withMock(MockAuthenticatedEndpoint.self, action: .return(.init(value: "mocked"))) {
            let response = try await URLSession.shared.response(with: MockAuthenticatedEndpoint())
            #expect(response.value == "mocked")
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func multipleEndpointsIncludingAuthenticatedOnes() async throws {
        try await withMock { mocks in
            mocks.register(MockSimpleEndpoint.self, action: .return(.init(response1: "profile")))
            mocks.register(MockAuthenticatedEndpoint.self, action: .return(.init(value: "authed")))
        } test: {
            let simple = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
            #expect(simple.response1 == "profile")

            let authed = try await URLSession.shared.response(with: MockAuthenticatedEndpoint())
            #expect(authed.value == "authed")
        }
    }

    /// Conforms to AuthenticationMethod against the public API only (this target does
    /// not use @testable import Endpoints), proving external packages can implement
    /// custom authentication methods.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func externalCustomAuthMethodConformance() async throws {
        struct StampAuth: AuthenticationMethod {
            let stamp: String
            let failSigning: Bool

            struct SigningError: Error {}

            func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
                guard !failSigning else {
                    throw .custom(underlying: SigningError())
                }
                var request = request
                request.setValue(stamp, forHTTPHeaderField: "X-Stamp")
                return request
            }
        }

        let authenticated = try await StampAuth(stamp: "stamped", failSigning: false)
            .authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        #expect(authenticated.value(forHTTPHeaderField: "X-Stamp") == "stamped")

        // The default implementations come along for free.
        do {
            try await StampAuth(stamp: "stamped", failSigning: false)
                .reauthenticate(after: authenticated)
            Issue.record("Expected refreshNotSupported error")
        } catch {
            guard case .refreshNotSupported = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        // Implementation-specific failures surface through the custom case.
        do {
            _ = try await StampAuth(stamp: "stamped", failSigning: true)
                .authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected custom error")
        } catch {
            guard case .custom(let underlying) = error, underlying is StampAuth.SigningError else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockedAuthenticationErrorSurfacesTyped() async {
        await withMock(MockSimpleEndpoint.self, action: .throw(.authenticationError(.notAuthenticated))) {
            do throws(MockSimpleEndpoint.TaskError) {
                _ = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
                Issue.record("Expected authenticationError to be thrown")
            } catch {
                guard case .authenticationError(.notAuthenticated) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
            }
        }
    }
}
