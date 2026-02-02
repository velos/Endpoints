import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWT-based authentication with automatic token refresh.
public actor JWTAuth: AuthenticationMethod {

    // MARK: - Types

    /// A pair of access and refresh tokens.
    public struct TokenPair: Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String

        public init(accessToken: String, refreshToken: String) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
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

        public init(
            header: Header = .authorization,
            tokenPrefix: String = "Bearer",
            refreshTriggerStatusCodes: Set<Int> = [401]
        ) {
            self.header = header
            self.tokenPrefix = tokenPrefix
            self.refreshTriggerStatusCodes = refreshTriggerStatusCodes
        }

        public static let `default` = Configuration()
    }

    /// Closure type for performing token refresh.
    ///
    /// The closure receives the current refresh token and should return new tokens.
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

    public func authenticate(request: URLRequest) async throws -> URLRequest {
        if let pendingRefresh {
            do {
                currentTokens = try await pendingRefresh.value
            } catch {
                // Refresh failed - fall through to notAuthenticated if no token is available.
            }
        }

        guard let accessToken = currentTokens?.accessToken else {
            throw AuthenticationError.notAuthenticated
        }

        var mutableRequest = request
        let headerValue = "\(configuration.tokenPrefix) \(accessToken)"
        mutableRequest.setValue(headerValue, forHTTPHeaderField: configuration.header.name)
        return mutableRequest
    }

    public nonisolated func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        guard let statusCode = response?.statusCode else {
            return false
        }
        return configuration.refreshTriggerStatusCodes.contains(statusCode)
    }

    public func reauthenticate() async throws {
        if let existingRefresh = pendingRefresh {
            currentTokens = try await existingRefresh.value
            return
        }

        guard let refreshToken = currentTokens?.refreshToken else {
            throw AuthenticationError.noRefreshToken
        }

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

        do {
            currentTokens = try await refreshTask.value
            pendingRefresh = nil
        } catch {
            pendingRefresh = nil
            throw error
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

    public func getTokens() -> TokenPair? {
        currentTokens
    }

    public var isAuthenticated: Bool {
        currentTokens != nil
    }
}
