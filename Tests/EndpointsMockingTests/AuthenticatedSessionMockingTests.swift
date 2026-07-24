import Testing
import Foundation
import Endpoints
@testable import EndpointsMocking

@Suite("Authenticated Session Mocking")
struct AuthenticatedSessionMockingTests {
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockedResponseWorks() async throws {
        let auth = HeaderKeyAuth(key: "test")
        let session = AuthenticatedSession(auth: auth)

        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "mocked"))) {
            let endpoint = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await session.response(with: endpoint)
            #expect(response.response1 == "mocked")
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func multipleEndpointsThroughAuthenticatedSession() async throws {
        let auth = JWTAuth(initialTokens: .init(accessToken: "access", refreshToken: "refresh")) { refreshToken in
            JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
        }
        let session = AuthenticatedSession(auth: auth)

        try await withMock { mocks in
            mocks.register(MockSimpleEndpoint.self, action: .return(.init(response1: "profile")))
            mocks.register(MockSecondEndpoint.self, action: .return(.init(value: 99)))
        } test: {
            let simple = try await session.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
            #expect(simple.response1 == "profile")

            let second = try await session.response(with: MockSecondEndpoint())
            #expect(second.value == 99)
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
        let session = AuthenticatedSession(auth: HeaderKeyAuth(key: "test"))

        await withMock(MockSimpleEndpoint.self, action: .throw(.authenticationError(.notAuthenticated))) {
            do throws(MockSimpleEndpoint.TaskError) {
                _ = try await session.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
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
