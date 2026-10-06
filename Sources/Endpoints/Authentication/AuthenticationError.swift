import Foundation

/// Errors that can occur during authentication operations.
public enum AuthenticationError: Error, Sendable {
    /// There are no credentials to authenticate the request with.
    case notAuthenticated

    /// There is no refresh token to refresh with.
    case noRefreshToken

    /// The refresh failed with the underlying error.
    case refreshFailed(underlying: Error)

    /// The authentication method can't refresh its credentials.
    case refreshNotSupported

    /// A failure in a custom ``AuthenticationMethod`` that doesn't match another case,
    /// such as a keychain or signing error.
    case custom(underlying: Error)
}

/// The underlying error when a ``JWTAuth`` refresh handler makes a request through
/// that same `JWTAuth`.
///
/// The request would wait for the refresh, which is waiting for the request, so it
/// fails instead. Give the refresh endpoint ``NoAuth``.
public struct RefreshReentrancyError: Error, CustomStringConvertible {
    let authType: Any.Type

    public var description: String {
        """
        A request authenticated by this \(authType) was made from inside its own \
        refreshHandler, which would deadlock: the request waits for the refresh that is \
        waiting for the handler. Give the refresh endpoint `static var auth: NoAuth \
        { NoAuth() }`, or perform the refresh with a plain URLSession.
        """
    }
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
