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

    @Test
    func basicAuthEncodesCredentials() async throws {
        let auth = BasicAuth(username: "user", password: "pass")
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let authenticated = try await auth.authenticate(request: request)

        #expect(authenticated.value(forHTTPHeaderField: Header.authorization.name) == "Basic dXNlcjpwYXNz")
    }

    @Test
    func basicAuthEncodesUTF8AndColonsInPassword() async throws {
        let utf8Auth = BasicAuth(username: "müller", password: "pässwörd")
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let utf8Authenticated = try await utf8Auth.authenticate(request: request)
        #expect(utf8Authenticated.value(forHTTPHeaderField: Header.authorization.name) == "Basic bcO8bGxlcjpww6Rzc3fDtnJk")

        let colonAuth = BasicAuth(username: "user", password: "pa:ss")
        let colonAuthenticated = try await colonAuth.authenticate(request: request)
        #expect(colonAuthenticated.value(forHTTPHeaderField: Header.authorization.name) == "Basic dXNlcjpwYTpzcw==")
    }

    @Test
    func noAuthPassesThroughAndDoesNotSupportRefresh() async throws {
        let auth = NoAuth()
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("value", forHTTPHeaderField: "X-Existing")

        let authenticated = try await auth.authenticate(request: request)
        #expect(authenticated == request)

        // Default implementations: never reauthenticate, refresh unsupported.
        #expect(auth.shouldReauthenticate(for: URLError(.userAuthenticationRequired), response: nil) == false)

        do {
            try await auth.reauthenticate(after: request)
            Issue.record("Expected refreshNotSupported error")
        } catch {
            guard case .refreshNotSupported = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func jwtAuthTokenManagement() async throws {
        let auth = JWTAuth(initialTokens: nil) { refreshToken in
            JWTAuth.TokenPair(accessToken: "refreshed", refreshToken: refreshToken)
        }

        #expect(await auth.isAuthenticated == false)
        #expect(await auth.tokens == nil)

        let tokens = JWTAuth.TokenPair(accessToken: "access", refreshToken: "refresh")
        await auth.setTokens(tokens)
        #expect(await auth.isAuthenticated == true)
        #expect(await auth.tokens == tokens)

        let authenticated = try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        #expect(authenticated.value(forHTTPHeaderField: Header.authorization.name) == "Bearer access")

        await auth.clearTokens()
        #expect(await auth.isAuthenticated == false)
        #expect(await auth.tokens == nil)

        do {
            _ = try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected notAuthenticated error")
        } catch {
            guard case .notAuthenticated = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func jwtAuthenticateAwaitsInFlightRefresh() async throws {
        let refreshStarted = Gate()
        let releaseRefresh = Gate()

        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
            refreshHandler: { refreshToken in
                await refreshStarted.open()
                await releaseRefresh.wait()
                return JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
            }
        )

        var staleRequest = URLRequest(url: URL(string: "https://example.com")!)
        staleRequest.setValue("Bearer old", forHTTPHeaderField: Header.authorization.name)

        let refreshTask = Task { [staleRequest] in
            try await auth.reauthenticate(after: staleRequest)
        }

        await refreshStarted.wait()

        // While the refresh is still in flight, authenticate must wait for it
        // and pick up the new access token.
        async let authenticated = auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        await Task.yield()
        await releaseRefresh.open()

        let request = try await authenticated
        #expect(request.value(forHTTPHeaderField: Header.authorization.name) == "Bearer new")

        try await refreshTask.value
        #expect((await auth.tokens)?.accessToken == "new")
    }

    @Test
    func authenticationErrorExposesUnderlyingError() {
        let underlying = URLError(.timedOut)
        let bridged = AuthenticationError.refreshFailed(underlying: underlying) as NSError

        #expect((bridged.userInfo[NSUnderlyingErrorKey] as? URLError) == underlying)
        #expect((AuthenticationError.notAuthenticated as NSError).userInfo[NSUnderlyingErrorKey] == nil)
    }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
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
