import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authentication using a static API key.
public struct APIKeyAuth: AuthenticationMethod {
    /// The API key value.
    public let key: String

    /// The HTTP header to use. Defaults to `.authorization`.
    public let header: Header

    /// Optional prefix before the key (e.g., "Bearer", "ApiKey").
    /// Set to nil for no prefix.
    public let prefix: String?

    /// Creates an API key authentication method.
    ///
    /// - Parameters:
    ///   - key: The API key value.
    ///   - header: The HTTP header to use. Defaults to `.authorization`.
    ///   - prefix: Optional prefix (e.g., "Bearer"). Defaults to "Bearer".
    public init(
        key: String,
        header: Header = .authorization,
        prefix: String? = "Bearer"
    ) {
        self.key = key
        self.header = header
        self.prefix = prefix
    }

    public func authenticate(request: URLRequest) async throws -> URLRequest {
        var mutableRequest = request
        let headerValue = prefix.map { "\($0) \(key)" } ?? key
        mutableRequest.setValue(headerValue, forHTTPHeaderField: header.name)
        return mutableRequest
    }

    public func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        false
    }

    public func reauthenticate() async throws {
        throw AuthenticationError.refreshNotSupported
    }
}
