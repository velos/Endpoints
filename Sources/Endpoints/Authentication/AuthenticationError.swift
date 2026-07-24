import Foundation

/// Errors that can occur during authentication operations.
public enum AuthenticationError: Error, Sendable {
    /// No valid credentials are available to authenticate the request.
    case notAuthenticated

    /// No refresh token is available to perform token refresh.
    case noRefreshToken

    /// The token refresh operation failed.
    case refreshFailed(underlying: Error)

    /// The authentication method does not support refresh.
    case refreshNotSupported

    /// An implementation-specific authentication failure.
    ///
    /// Use this from custom ``AuthenticationMethod`` implementations for failures
    /// that don't fit the other cases (e.g. credential storage or signing errors).
    case custom(underlying: Error)
}

extension AuthenticationError: CustomNSError {
    public var errorUserInfo: [String: Any] {
        switch self {
        case .refreshFailed(let underlying), .custom(let underlying):
            return [NSUnderlyingErrorKey: underlying]
        default:
            return [:]
        }
    }
}
