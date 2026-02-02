import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authentication using a static HTTP cookie.
public struct CookieAuth: AuthenticationMethod {
    /// The cookie name.
    public let name: String

    /// The cookie value.
    public let value: String

    /// The HTTP header to use. Defaults to `.cookie`.
    public let header: Header

    /// Whether to append to an existing Cookie header. Defaults to true.
    public let appendToExisting: Bool

    public init(
        name: String,
        value: String,
        header: Header = .cookie,
        appendToExisting: Bool = true
    ) {
        self.name = name
        self.value = value
        self.header = header
        self.appendToExisting = appendToExisting
    }

    public func authenticate(request: URLRequest) async throws -> URLRequest {
        var mutableRequest = request
        let cookiePair = "\(name)=\(value)"

        if appendToExisting,
           let existing = request.value(forHTTPHeaderField: header.name),
           !existing.isEmpty {
            mutableRequest.setValue("\(existing); \(cookiePair)", forHTTPHeaderField: header.name)
        } else {
            mutableRequest.setValue(cookiePair, forHTTPHeaderField: header.name)
        }

        return mutableRequest
    }

    public func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        false
    }

    public func reauthenticate() async throws {
        throw AuthenticationError.refreshNotSupported
    }
}
