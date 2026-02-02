import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A protocol that defines how to authenticate requests and handle token refresh.
public protocol AuthenticationMethod: Sendable {

    /// Applies authentication credentials to a request.
    ///
    /// - Parameter request: The URLRequest to authenticate.
    /// - Returns: The authenticated URLRequest.
    /// - Throws: `AuthenticationError.notAuthenticated` if no valid credentials are available.
    func authenticate(request: URLRequest) async throws -> URLRequest

    /// Determines whether a failed request should trigger reauthentication.
    ///
    /// - Parameters:
    ///   - error: The error that occurred.
    ///   - response: The HTTP response, if available.
    /// - Returns: `true` if reauthentication should be attempted.
    func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool

    /// Performs reauthentication (e.g., token refresh).
    ///
    /// Implementations should coalesce concurrent calls into a single refresh operation.
    func reauthenticate() async throws
}
