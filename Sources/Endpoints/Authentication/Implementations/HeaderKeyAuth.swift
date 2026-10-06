import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a static key in a header, such as an API key.
public struct HeaderKeyAuth: AuthenticationMethod {
    /// The key.
    public let key: String

    /// The header the key is sent in.
    public let header: Header

    /// The text before the key, such as `Bearer`. When `nil`, the key is sent alone.
    public let prefix: String?

    /// The key and prefix are immutable, so the header value is composed once.
    private let headerValue: String

    /// Creates a method that sends `key` in `header`.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - header: The header to send it in. Defaults to `Authorization`.
    ///   - prefix: The text before the key. Defaults to `Bearer`. Pass `nil` to send the key alone.
    public init(
        key: String,
        header: Header = .authorization,
        prefix: String? = "Bearer"
    ) {
        self.key = key
        self.header = header
        self.prefix = prefix
        self.headerValue = prefix.map { "\($0) \(key)" } ?? key
    }

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        var mutableRequest = request
        mutableRequest.setValue(headerValue, forHTTPHeaderField: header.name)
        return mutableRequest
    }
}
