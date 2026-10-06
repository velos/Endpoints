import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adds credentials to requests, and optionally refreshes them after a rejected response.
public protocol AuthenticationMethod: Sendable {

    /// Returns the request with credentials added.
    ///
    /// Called before every attempt, including retries.
    /// - Parameter request: The request to authenticate.
    /// - Returns: The authenticated request.
    /// - Throws: ``AuthenticationError/notAuthenticated`` if there are no credentials.
    func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest

    /// Returns whether a failed request should be retried after ``reauthenticate(after:)``.
    ///
    /// Defaults to `false`.
    /// - Parameters:
    ///   - error: The error the request failed with.
    ///   - response: The HTTP response, if the server returned one.
    /// - Returns: `true` to refresh the credentials and retry.
    func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool

    /// Refreshes the credentials after a failed request.
    ///
    /// Combine concurrent calls into one refresh. If the failed request's credentials no
    /// longer match the current ones, another request already refreshed them, so return
    /// without refreshing again. Refreshing twice can waste a single-use refresh token.
    ///
    /// Throws ``AuthenticationError/refreshNotSupported`` by default.
    /// - Parameter failedRequest: The failed request, as returned by ``authenticate(request:)``.
    func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError)

    /// How many times a request can be retried after reauthenticating. Defaults to 1.
    ///
    /// This limit stops a server that keeps rejecting credentials from causing an
    /// endless cycle of requests and refreshes.
    var maxRetryAttempts: Int { get }
}

public extension AuthenticationMethod {

    /// Returns `false`, so failed requests are never retried.
    func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        false
    }

    /// Throws ``AuthenticationError/refreshNotSupported``.
    func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError) {
        throw AuthenticationError.refreshNotSupported
    }

    /// Retries a request once.
    var maxRetryAttempts: Int { 1 }

    /// ``maxRetryAttempts``, with negative values treated as 0.
    var retryAttempts: Int { max(0, maxRetryAttempts) }
}
