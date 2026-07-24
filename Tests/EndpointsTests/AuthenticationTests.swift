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
        let auth = HeaderKeyAuth(key: "test-key")
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test
    func apiKeyAuthSupportsCustomHeaderAndNoPrefix() async throws {
        let auth = HeaderKeyAuth(key: "secret", header: Header(name: "X-API-Key"), prefix: nil)
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

        var failedRequest = URLRequest(url: URL(string: "https://example.com")!)
        failedRequest.setValue("Bearer old", forHTTPHeaderField: Header.authorization.name)

        await withTaskGroup(of: Void.self) { [failedRequest] group in
            for _ in 0..<5 {
                group.addTask {
                    try? await auth.reauthenticate(after: failedRequest)
                }
            }
        }

        #expect(await counter.value() == 1)
        #expect((await auth.tokens)?.accessToken == "new")
    }

    @Test
    func jwtAuthSkipsRefreshWhenTokensAlreadyRotated() async throws {
        let counter = RefreshCounter()
        let auth = JWTAuth(
            initialTokens: .init(accessToken: "new", refreshToken: "refresh"),
            refreshHandler: { refreshToken in
                await counter.increment()
                return JWTAuth.TokenPair(accessToken: "newer", refreshToken: refreshToken)
            }
        )

        // A request authenticated with credentials that have since been replaced.
        var staleRequest = URLRequest(url: URL(string: "https://example.com")!)
        staleRequest.setValue("Bearer old", forHTTPHeaderField: Header.authorization.name)

        try await auth.reauthenticate(after: staleRequest)

        #expect(await counter.value() == 0)
        #expect((await auth.tokens)?.accessToken == "new")
    }

    @Test
    func cookieAuthSetsCookieHeader() async throws {
        let auth = CookieAuth(name: "session", value: "abc123")
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: Header.cookie.name) == "session=abc123")
    }

    @Test
    func cookieAuthAppendsToExistingCookies() async throws {
        let auth = CookieAuth(name: "session", value: "abc123")
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("theme=dark", forHTTPHeaderField: Header.cookie.name)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: Header.cookie.name) == "theme=dark; session=abc123")
    }

    @Test
    func cookieAuthReplacesExistingSameNameCookie() async throws {
        let auth = CookieAuth(name: "session", value: "new")
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("session=old; theme=dark", forHTTPHeaderField: Header.cookie.name)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: Header.cookie.name) == "theme=dark; session=new")
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
