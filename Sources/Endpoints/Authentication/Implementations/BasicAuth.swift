import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authentication using HTTP Basic credentials ([RFC 7617](https://www.rfc-editor.org/rfc/rfc7617)).
///
/// Sends `Authorization: Basic <base64(username:password)>` with the credentials
/// encoded as UTF-8.
public struct BasicAuth: AuthenticationMethod {
    /// The username. Must not contain a colon (RFC 7617, section 2).
    public let username: String

    /// The password.
    public let password: String

    /// The credentials are immutable, so the header value is encoded once.
    private let headerValue: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
        self.headerValue = "Basic \(Data("\(username):\(password)".utf8).base64EncodedString())"
    }

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        var mutableRequest = request
        mutableRequest.setValue(headerValue, forHTTPHeaderField: Header.authorization.name)
        return mutableRequest
    }
}
