import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A no-op authentication method that passes requests through unchanged.
public struct NoAuth: AuthenticationMethod {
    public init() {}

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        request
    }

    public func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        false
    }

    public func reauthenticate(after failedRequest: URLRequest) async throws(AuthenticationError) {
        throw AuthenticationError.refreshNotSupported
    }
}
