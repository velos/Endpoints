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

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockedAuthenticationErrorSurfacesTyped() async throws {
        let session = AuthenticatedSession(auth: HeaderKeyAuth(key: "test"))

        try await withMock(MockSimpleEndpoint.self, action: .throw(.authenticationError(.notAuthenticated))) {
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
