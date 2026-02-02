import Foundation

/// Errors that can occur during authentication operations.
public enum AuthenticationError: Error, Sendable {
    /// No valid credentials are available to authenticate the request.
    case notAuthenticated

    /// No refresh token is available to perform token refresh.
    case noRefreshToken

    /// The token refresh operation failed.
    case refreshFailed(underlying: Error)

    /// Maximum retry attempts exceeded.
    case maxRetriesExceeded

    /// The authentication method does not support refresh.
    case refreshNotSupported
}

extension AuthenticationError: CustomNSError {
    public var errorUserInfo: [String: Any] {
        switch self {
        case .refreshFailed(let underlying):
            return [NSUnderlyingErrorKey: underlying]
        default:
            return [:]
        }
    }
}
