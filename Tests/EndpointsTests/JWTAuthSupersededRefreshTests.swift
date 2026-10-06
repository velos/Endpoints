import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

/// `setTokens`/`clearTokens` are the caller's newer intent: a refresh that was already
/// in flight when they were called must not overwrite (or persist over) that intent.
@Suite("JWTAuth superseded refresh")
struct JWTAuthSupersededRefreshTests {

    private static func staleRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("Bearer old", forHTTPHeaderField: Header.authorization.name)
        return request
    }

    @Test
    func clearingTokensDuringRefreshDoesNotResurrectThem() async throws {
        let refreshStarted = Gate()
        let releaseRefresh = Gate()
        let persisted = PersistedTokens()
        let failures = RefreshCounter()

        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
            refreshHandler: { refreshToken in
                await refreshStarted.open()
                await releaseRefresh.wait()
                return JWTAuth.TokenPair(accessToken: "refreshed", refreshToken: refreshToken)
            },
            onTokensUpdated: { await persisted.set($0) },
            onRefreshFailed: { _ in await failures.increment() }
        )

        let refreshTask = Task { try await auth.reauthenticate(after: Self.staleRequest()) }
        await refreshStarted.wait()

        // The user logs out while the refresh is in flight.
        await auth.clearTokens()
        await releaseRefresh.open()
        try await refreshTask.value

        #expect(await auth.tokens == nil)
        #expect(await persisted.value == nil)
        // Being superseded is not a refresh failure, so no logout handler fires.
        #expect(await failures.value() == 0)
    }

    @Test
    func settingTokensDuringRefreshWins() async throws {
        let refreshStarted = Gate()
        let releaseRefresh = Gate()
        let persisted = PersistedTokens()

        let auth = JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
            refreshHandler: { refreshToken in
                await refreshStarted.open()
                await releaseRefresh.wait()
                return JWTAuth.TokenPair(accessToken: "refreshed", refreshToken: refreshToken)
            },
            onTokensUpdated: { await persisted.set($0) }
        )

        let refreshTask = Task { try await auth.reauthenticate(after: Self.staleRequest()) }
        await refreshStarted.wait()

        // A fresh login lands while the refresh is in flight.
        let loginTokens = JWTAuth.TokenPair(accessToken: "login", refreshToken: "login-refresh")
        await auth.setTokens(loginTokens)
        await releaseRefresh.open()
        try await refreshTask.value

        #expect(await auth.tokens == loginTokens)
        #expect(await persisted.value == nil)
    }

    /// An expired token makes `authenticate` start the refresh itself, so once the
    /// handler is running the request is known to be suspended on it.
    private static func expiringAuth(refreshStarted: Gate, releaseRefresh: Gate) -> JWTAuth {
        JWTAuth(
            initialTokens: .init(accessToken: "old", refreshToken: "refresh", expiresAt: Date(timeIntervalSinceNow: -60)),
            refreshHandler: { refreshToken in
                await refreshStarted.open()
                await releaseRefresh.wait()
                return JWTAuth.TokenPair(accessToken: "refreshed", refreshToken: refreshToken)
            }
        )
    }

    @Test
    func requestWaitingOnSupersededRefreshUsesTheNewTokens() async throws {
        let refreshStarted = Gate()
        let releaseRefresh = Gate()
        let auth = Self.expiringAuth(refreshStarted: refreshStarted, releaseRefresh: releaseRefresh)

        let authenticated = Task {
            try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        }
        await refreshStarted.wait()

        // A login lands while the request is waiting on the refresh.
        let loginTokens = JWTAuth.TokenPair(accessToken: "login", refreshToken: "login-refresh")
        await auth.setTokens(loginTokens)
        await releaseRefresh.open()

        let request = try await authenticated.value
        #expect(request.value(forHTTPHeaderField: Header.authorization.name) == "Bearer login")
        #expect(await auth.tokens == loginTokens)
    }

    @Test
    func requestWaitingOnRefreshFailsAfterLogout() async throws {
        let refreshStarted = Gate()
        let releaseRefresh = Gate()
        let auth = Self.expiringAuth(refreshStarted: refreshStarted, releaseRefresh: releaseRefresh)

        let authenticated = Task {
            try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        }
        await refreshStarted.wait()

        // The user logs out while the request is waiting on the refresh.
        await auth.clearTokens()
        await releaseRefresh.open()

        do {
            _ = try await authenticated.value
            Issue.record("Expected notAuthenticated error")
        } catch {
            guard case AuthenticationError.notAuthenticated = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(await auth.tokens == nil)
    }

    /// Several requests share one refresh. Only one of them may commit its result:
    /// otherwise a logout that lands after the first waiter resumes is undone when a
    /// later waiter resumes and commits the same tokens again.
    ///
    /// The interleaving can't be forced from outside the actor, so the later waiter
    /// runs at background priority to make it resume last, and the scenario repeats.
    @Test
    func laterWaiterDoesNotUndoLogoutAfterSharedRefresh() async throws {
        for _ in 0..<100 {
            let refreshStarted = Gate()
            let releaseRefresh = Gate()

            let auth = JWTAuth(
                initialTokens: .init(accessToken: "old", refreshToken: "refresh"),
                refreshHandler: { refreshToken in
                    await refreshStarted.open()
                    await releaseRefresh.wait()
                    return JWTAuth.TokenPair(accessToken: "refreshed", refreshToken: refreshToken)
                }
            )

            let first = Task(priority: .high) { try await auth.reauthenticate(after: Self.staleRequest()) }
            await refreshStarted.wait()
            let later = Task(priority: .background) { try? await auth.reauthenticate(after: Self.staleRequest()) }
            // Let the later waiter reach the in-flight refresh.
            try await Task.sleep(nanoseconds: 1_000_000)

            await releaseRefresh.open()
            try await first.value
            await auth.clearTokens()
            await later.value

            #expect(await auth.tokens == nil)
        }
    }

    @Test
    func emptyTokenPrefixSendsBareToken() async throws {
        let auth = JWTAuth(
            initialTokens: .init(accessToken: "token", refreshToken: "refresh"),
            configuration: .init(header: "X-Access-Token", tokenPrefix: ""),
            refreshHandler: { refreshToken in
                JWTAuth.TokenPair(accessToken: "new", refreshToken: refreshToken)
            }
        )

        let authenticated = try await auth.authenticate(request: URLRequest(url: URL(string: "https://example.com")!))
        #expect(authenticated.value(forHTTPHeaderField: "X-Access-Token") == "token")

        // The staleness check must agree with what was sent, so a bare-token 401
        // still refreshes.
        try await auth.reauthenticate(after: authenticated)
        #expect(await auth.tokens?.accessToken == "new")
    }
}

actor PersistedTokens {
    private(set) var value: JWTAuth.TokenPair?
    func set(_ tokens: JWTAuth.TokenPair) { value = tokens }
}
