import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWT-based authentication with automatic token refresh.
///
/// Tokens are refreshed reactively when a response's status code is in
/// ``Configuration/refreshTriggerStatusCodes``, and proactively when
/// ``TokenPair/expiresAt`` is set and the token is within
/// ``Configuration/expiryLeeway`` of expiring — the refresh then happens
/// *before* the request is sent, avoiding a round trip that would be rejected.
///
/// > Important: The ``RefreshHandler`` must not perform its request with an endpoint
/// > authenticated by this same `JWTAuth`: the request would wait for the in-flight
/// > refresh that is itself waiting on the handler, deadlocking the task. Give the
/// > refresh endpoint `static var auth: NoAuth { NoAuth() }` — it authenticates with
/// > the refresh token, not the access token.
public actor JWTAuth: AuthenticationMethod {

    // MARK: - Types

    /// A pair of access and refresh tokens.
    public struct TokenPair: Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String

        /// When the access token expires, if known.
        ///
        /// When set, requests authenticated within ``Configuration/expiryLeeway`` of
        /// this date proactively refresh before being sent. When nil, tokens are only
        /// refreshed reactively after a rejected response.
        public let expiresAt: Date?

        public init(accessToken: String, refreshToken: String, expiresAt: Date? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        /// Whether the access token is expired or will expire within the given leeway.
        /// Always false when ``expiresAt`` is nil.
        public func isExpiring(within leeway: TimeInterval) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow <= leeway
        }
    }

    /// Configuration for JWT authentication behavior.
    public struct Configuration: Sendable {
        /// The HTTP header for the access token. Defaults to `.authorization`.
        public let header: Header

        /// Prefix before the token (e.g., "Bearer"). Defaults to "Bearer".
        /// An empty string sends the bare token, for headers such as `X-Access-Token`.
        public let tokenPrefix: String

        /// HTTP status codes that should trigger a token refresh. Defaults to [401].
        public let refreshTriggerStatusCodes: Set<Int>

        /// How long before ``TokenPair/expiresAt`` a token is treated as expiring and
        /// proactively refreshed. Defaults to 30 seconds.
        public let expiryLeeway: TimeInterval

        public init(
            header: Header = .authorization,
            tokenPrefix: String = "Bearer",
            refreshTriggerStatusCodes: Set<Int> = [401],
            expiryLeeway: TimeInterval = 30
        ) {
            self.header = header
            self.tokenPrefix = tokenPrefix
            self.refreshTriggerStatusCodes = refreshTriggerStatusCodes
            self.expiryLeeway = expiryLeeway
        }

        public static let `default` = Configuration()
    }

    /// Closure type for performing token refresh.
    ///
    /// The closure receives the current refresh token and should return new tokens.
    ///
    /// > Important: Perform the refresh request with a plain `URLSession`, never
    /// > through a session authenticated by this `JWTAuth` — see ``JWTAuth``.
    public typealias RefreshHandler = @Sendable (String) async throws -> TokenPair

    /// Closure type for handling token updates (e.g., persisting to Keychain).
    ///
    /// Called once per successful refresh, before the new tokens are used. A refresh
    /// superseded by ``JWTAuth/setTokens(_:)`` or ``JWTAuth/clearTokens()`` before its
    /// handler returns never calls this. A call that has already started cannot be
    /// revoked, though: if a logout lands while it is still persisting, the write can
    /// complete after the logout. If that matters, have the store reject writes from a
    /// session that has since been signed out.
    public typealias TokenUpdateHandler = @Sendable (TokenPair) async -> Void

    /// Closure type for handling refresh failures (e.g., logout).
    public typealias RefreshFailureHandler = @Sendable (Error) async -> Void

    // MARK: - State

    private var currentTokens: TokenPair?
    private var pendingRefresh: Task<TokenPair, Error>?

    /// Instances whose `refreshHandler` is running in the current task tree.
    ///
    /// Task-local, so it propagates into any request the handler makes and lets
    /// ``authenticate(request:)`` recognize a reentrant call.
    @TaskLocal
    private static var refreshingInstances: Set<ObjectIdentifier> = []

    // MARK: - Configuration & Handlers

    private nonisolated let configuration: Configuration
    private let refreshHandler: RefreshHandler
    private let onTokensUpdated: TokenUpdateHandler?
    private let onRefreshFailed: RefreshFailureHandler?

    // MARK: - Initialization

    public init(
        initialTokens: TokenPair?,
        configuration: Configuration = .default,
        refreshHandler: @escaping RefreshHandler,
        onTokensUpdated: TokenUpdateHandler? = nil,
        onRefreshFailed: RefreshFailureHandler? = nil
    ) {
        self.currentTokens = initialTokens
        self.configuration = configuration
        self.refreshHandler = refreshHandler
        self.onTokensUpdated = onTokensUpdated
        self.onRefreshFailed = onRefreshFailed
    }

    // MARK: - AuthenticationMethod

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        // A request made from inside this instance's own refreshHandler would wait on
        // the very refresh that is waiting on it. Fail with a diagnosable error instead
        // of deadlocking the task.
        if Self.refreshingInstances.contains(ObjectIdentifier(self)) {
            throw .custom(underlying: RefreshReentrancyError(authType: Self.self))
        }

        if let tokens = currentTokens,
           pendingRefresh != nil || tokens.isExpiring(within: configuration.expiryLeeway) {
            // Join an in-flight refresh, or proactively refresh an expiring token
            // rather than sending a request that is likely to be rejected. If the
            // refresh fails, keep the existing (possibly expired) tokens and send the
            // request anyway; a rejection then surfaces through
            // shouldReauthenticate/reauthenticate.
            try? await refresh(with: tokens.refreshToken)
        }

        guard let accessToken = currentTokens?.accessToken else {
            throw AuthenticationError.notAuthenticated
        }

        var mutableRequest = request
        mutableRequest.setValue(headerValue(for: accessToken), forHTTPHeaderField: configuration.header.name)
        return mutableRequest
    }

    public nonisolated func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        guard let statusCode = response?.statusCode else {
            return false
        }
        return configuration.refreshTriggerStatusCodes.contains(statusCode)
    }

    public func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError) {
        // If the tokens have rotated since the failed request was authenticated, the
        // refresh that request needed has already happened. Refreshing again would
        // consume another refresh token (often single-use), so skip.
        if let accessToken = currentTokens?.accessToken,
           failedRequest.value(forHTTPHeaderField: configuration.header.name) != headerValue(for: accessToken) {
            return
        }

        guard let refreshToken = currentTokens?.refreshToken else {
            throw AuthenticationError.noRefreshToken
        }

        try await refresh(with: refreshToken)
    }

    // MARK: - Refresh

    /// Joins the in-flight refresh if one exists, otherwise starts a new one, and
    /// commits the resulting tokens.
    ///
    /// The existence check and task creation happen in one synchronous stretch of
    /// actor isolation, so concurrent callers cannot start duplicate refreshes.
    ///
    /// A refresh superseded by ``setTokens(_:)`` or ``clearTokens()`` is discarded
    /// rather than committed: the caller's tokens are the newer intent, and a logout
    /// must not be undone by a refresh that was already underway. Superseded refreshes
    /// return normally so the request proceeds with whatever tokens are current.
    private func refresh(with refreshToken: String) async throws(AuthenticationError) {
        let refreshTask = pendingRefresh ?? startRefresh(refreshToken: refreshToken)

        defer {
            if pendingRefresh == refreshTask {
                pendingRefresh = nil
            }
        }

        let newTokens: TokenPair
        do {
            newTokens = try await refreshTask.value
        } catch is CancellationError {
            return
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw .refreshFailed(underlying: error)
        }

        // Commit only while this refresh is still the pending one. Every caller that
        // joined it resumes here, one at a time; the first commits and (via the defer)
        // clears `pendingRefresh`, so later callers leave the tokens alone. That also
        // covers supersession: setTokens/clearTokens clear `pendingRefresh`, so a
        // refresh they replaced is never committed — even by a caller that resumes
        // after a logout which landed between two callers resuming.
        guard pendingRefresh == refreshTask else { return }
        currentTokens = newTokens
    }

    private func startRefresh(refreshToken: String) -> Task<TokenPair, Error> {
        let refreshHandler = self.refreshHandler
        let onTokensUpdated = self.onTokensUpdated
        let onRefreshFailed = self.onRefreshFailed
        // Captured as a value so the refresh task does not retain the actor.
        let identity = ObjectIdentifier(self)

        let refreshTask = Task<TokenPair, Error> {
            let newTokens: TokenPair
            do {
                // Marks this instance as refreshing for the duration of the handler, so a
                // request that reenters authenticate from inside it can be detected.
                newTokens = try await Self.$refreshingInstances.withValue(
                    Self.refreshingInstances.union([identity])
                ) {
                    try await refreshHandler(refreshToken)
                }
            } catch {
                // A superseded refresh is not a failure: the tokens were replaced or
                // cleared deliberately, so don't report it (and don't trigger a logout).
                try Task.checkCancellation()
                await onRefreshFailed?(error)
                throw AuthenticationError.refreshFailed(underlying: error)
            }

            // Don't persist tokens that setTokens/clearTokens already replaced while
            // the handler was running.
            try Task.checkCancellation()
            await onTokensUpdated?(newTokens)
            return newTokens
        }

        pendingRefresh = refreshTask
        return refreshTask
    }

    private nonisolated func headerValue(for accessToken: String) -> String {
        configuration.tokenPrefix.isEmpty ? accessToken : "\(configuration.tokenPrefix) \(accessToken)"
    }

    // MARK: - Public Token Management

    /// Replaces the current tokens, for example after a login.
    ///
    /// Any refresh in flight is superseded: its result is discarded rather than
    /// committed, and requests waiting on it proceed with these tokens.
    public func setTokens(_ tokens: TokenPair) {
        currentTokens = tokens
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// Removes the current tokens, for example after a logout.
    ///
    /// Any refresh in flight is superseded: its result is discarded rather than
    /// committed, so a refresh that was already underway cannot silently sign the
    /// user back in. Requests waiting on it fail with
    /// ``AuthenticationError/notAuthenticated``. See ``TokenUpdateHandler`` for the
    /// one case where a persistence callback can still finish after this returns.
    public func clearTokens() {
        currentTokens = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// The current token pair, if any.
    public var tokens: TokenPair? {
        currentTokens
    }

    public var isAuthenticated: Bool {
        currentTokens != nil
    }
}
