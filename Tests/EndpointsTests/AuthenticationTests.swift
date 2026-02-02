import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

@Suite("Authentication")
struct AuthenticationTests {
    @Test
    func apiKeyAuthAddsAuthorizationHeader() async throws {
        let auth = APIKeyAuth(key: "test-key")
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test
    func apiKeyAuthSupportsCustomHeaderAndNoPrefix() async throws {
        let auth = APIKeyAuth(key: "secret", header: Header(name: "X-API-Key"), prefix: nil)
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: "X-API-Key") == "secret")
        #expect(authenticated.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func jwtAuthRequiresTokens() async throws {
        let auth = JWTAuth(initialTokens: nil) { _ in
            JWTAuth.TokenPair(accessToken: "new", refreshToken: "refresh")
        }

        do {
            _ = try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected notAuthenticated error")
        } catch {
            guard case AuthenticationError.notAuthenticated = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func jwtAuthCoalescesRefreshRequests() async throws {
        let counter = RefreshCounter()
        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
            refreshHandler: { refreshToken in
                await counter.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
            }
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await auth.reauthenticate()
                }
            }
        }

        #expect(await counter.value() == 1)
        #expect((await auth.getTokens())?.accessToken == "new")
    }
}

actor RefreshCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
