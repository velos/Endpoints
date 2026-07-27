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
    public typealias TokenUpdateHandler = @Sendable (TokenPair) async -> Void

    /// Closure type for handling refresh failures (e.g., logout).
    public typealias RefreshFailureHandler = @Sendable (Error) async -> Void

    // MARK: - State

    private var currentTokens: TokenPair?
    private var pendingRefresh: Task<TokenPair, Error>?

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
        if let tokens = currentTokens,
           pendingRefresh != nil || tokens.isExpiring(within: configuration.expiryLeeway) {
            do {
                // Join an in-flight refresh, or proactively refresh an expiring token
                // rather than sending a request that is likely to be rejected.
                currentTokens = try await refresh(with: tokens.refreshToken)
            } catch {
                // The refresh failed. Keep the existing (possibly expired) tokens and
                // send the request anyway; if it is rejected, the failure surfaces
                // through shouldReauthenticate/reauthenticate.
            }
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

        currentTokens = try await refresh(with: refreshToken)
    }

    // MARK: - Refresh

    /// Joins the in-flight refresh if one exists, otherwise starts a new one.
    ///
    /// The existence check and task creation happen in one synchronous stretch of
    /// actor isolation, so concurrent callers cannot start duplicate refreshes.
    private func refresh(with refreshToken: String) async throws(AuthenticationError) -> TokenPair {
        let refreshTask: Task<TokenPair, Error>
        if let pendingRefresh {
            refreshTask = pendingRefresh
        } else {
            refreshTask = startRefresh(refreshToken: refreshToken)
        }

        defer {
            if pendingRefresh == refreshTask {
                pendingRefresh = nil
            }
        }

        return try await awaitRefresh(refreshTask)
    }

    private func startRefresh(refreshToken: String) -> Task<TokenPair, Error> {
        let refreshHandler = self.refreshHandler
        let onTokensUpdated = self.onTokensUpdated
        let onRefreshFailed = self.onRefreshFailed

        let refreshTask = Task<TokenPair, Error> {
            do {
                let newTokens = try await refreshHandler(refreshToken)
                await onTokensUpdated?(newTokens)
                return newTokens
            } catch {
                await onRefreshFailed?(error)
                throw AuthenticationError.refreshFailed(underlying: error)
            }
        }

        pendingRefresh = refreshTask
        return refreshTask
    }

    private nonisolated func headerValue(for accessToken: String) -> String {
        "\(configuration.tokenPrefix) \(accessToken)"
    }

    /// Awaits a refresh task, mapping its untyped failure back to ``AuthenticationError``.
    private func awaitRefresh(_ task: Task<TokenPair, Error>) async throws(AuthenticationError) -> TokenPair {
        do {
            return try await task.value
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw .refreshFailed(underlying: error)
        }
    }

    // MARK: - Public Token Management

    public func setTokens(_ tokens: TokenPair) {
        currentTokens = tokens
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

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
