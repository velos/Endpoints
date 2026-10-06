import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Leaves requests unchanged. The default for servers that don't declare ``ServerDefinition/auth``.
public struct NoAuth: AuthenticationMethod {
    public init() {}

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        request
    }
}
