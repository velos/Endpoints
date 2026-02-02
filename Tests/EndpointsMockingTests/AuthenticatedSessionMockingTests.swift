import Testing
import Foundation
import Endpoints
@testable import EndpointsMocking

@Suite("Authenticated Session Mocking")
struct AuthenticatedSessionMockingTests {
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func mockedResponseWorks() async throws {
        let auth = APIKeyAuth(key: "test")
        let session = AuthenticatedSession(auth: auth)

        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "mocked"))) {
            let endpoint = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await session.response(with: endpoint)
            #expect(response.response1 == "mocked")
        }
    }
}
