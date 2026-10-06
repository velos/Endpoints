import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Access-token authentication that refreshes the token when needed.
///
/// The token is refreshed after a response with a status code in
/// ``Configuration/refreshTriggerStatusCodes``, and the request is retried. When
/// ``TokenPair/expiresAt`` is set, a token within ``Configuration/expiryLeeway`` of
/// expiring is refreshed before the request is sent. Concurrent requests share one
/// refresh.
///
/// > Important: The ``RefreshHandler`` must not make its request through an endpoint
/// > that uses this same `JWTAuth`. That request would wait for the refresh, which is
/// > waiting for the handler. Give the refresh endpoint
/// > `static var auth: NoAuth { NoAuth() }`, since it authenticates with the refresh
/// > token. A request that does this fails with ``RefreshReentrancyError``.
public actor JWTAuth: AuthenticationMethod {

    // MARK: - Types

    /// An access token and the refresh token that renews it.
    public struct TokenPair: Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String

        /// When the access token expires, if known.
        ///
        /// When set, a request authenticated within ``Configuration/expiryLeeway`` of this
        /// date refreshes the token before it is sent. When `nil`, the token is refreshed
        /// only after a rejected response.
        public let expiresAt: Date?

        public init(accessToken: String, refreshToken: String, expiresAt: Date? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        /// Whether the access token expires within `leeway` seconds, or already has.
        /// Always `false` when ``expiresAt`` is `nil`.
        public func isExpiring(within leeway: TimeInterval) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow <= leeway
        }
    }

    /// Where the token is sent and when it is refreshed.
    public struct Configuration: Sendable {
        /// The header the access token is sent in. Defaults to `Authorization`.
        public let header: Header

        /// The text before the token, such as `Bearer`. Defaults to `Bearer`.
        /// An empty string sends the token alone.
        public let tokenPrefix: String

        /// The status codes that trigger a refresh and retry. Defaults to `[401]`.
        public let refreshTriggerStatusCodes: Set<Int>

        /// How many seconds before ``TokenPair/expiresAt`` a token is refreshed before
        /// use. Defaults to 30.
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

    /// Exchanges a refresh token for new tokens.
    ///
    /// > Important: Make the refresh request through an endpoint that doesn't use this
    /// > `JWTAuth`. See ``JWTAuth``.
    public typealias RefreshHandler = @Sendable (String) async throws -> TokenPair

    /// Receives new tokens after a refresh, for example to save them to the keychain.
    ///
    /// Called once per successful refresh, before the new tokens are used. It isn't
    /// called for a refresh replaced by ``JWTAuth/setTokens(_:)`` or
    /// ``JWTAuth/clearTokens()`` before its handler returned. A call that has already
    /// started can't be stopped, so a save can finish after a logout. If your store must
    /// not keep tokens after a logout, have it reject writes from a signed-out session.
    public typealias TokenUpdateHandler = @Sendable (TokenPair) async -> Void

    /// Receives the error when a refresh fails, for example to log the user out.
    ///
    /// It isn't called for a refresh replaced by ``JWTAuth/setTokens(_:)`` or
    /// ``JWTAuth/clearTokens()``.
    public typealias RefreshFailureHandler = @Sendable (Error) async -> Void

    // MARK: - State

    private var currentTokens: TokenPair?
    private var pendingRefresh: Task<TokenPair, Error>?

    /// Instances whose `refreshHandler` is running in the current task tree.
    ///
    /// Task-local, so requests the handler makes inherit it, which lets
    /// ``authenticate(request:)`` detect a reentrant call.
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
    /// A refresh replaced by ``setTokens(_:)`` or ``clearTokens()`` is discarded, not
    /// committed. Those tokens are newer, and a logout must not be undone by a refresh
    /// that was already running. A replaced refresh returns normally, so the request
    /// continues with the current tokens.
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
        // joined it resumes here, one at a time. The first commits and, through the
        // defer, clears `pendingRefresh`, so later callers leave the tokens alone. This
        // also covers setTokens/clearTokens, which clear `pendingRefresh`: a refresh
        // they replaced is never committed, even by a caller that resumes after a
        // logout that happened between two callers resuming.
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
                // A replaced refresh isn't a failure. The tokens were replaced or cleared
                // on purpose, so don't report it or trigger a logout.
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
    /// A refresh in progress is discarded, and requests waiting for it use these tokens.
    public func setTokens(_ tokens: TokenPair) {
        currentTokens = tokens
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// Removes the current tokens, for example after a logout.
    ///
    /// A refresh in progress is discarded, so it can't sign the user back in. Requests
    /// waiting for it fail with ``AuthenticationError/notAuthenticated``. A
    /// ``TokenUpdateHandler`` call that already started can still finish afterward.
    public func clearTokens() {
        currentTokens = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// The current tokens, or `nil` when signed out.
    public var tokens: TokenPair? {
        currentTokens
    }

    /// Whether there are tokens to authenticate with.
    public var isAuthenticated: Bool {
        currentTokens != nil
    }
}
