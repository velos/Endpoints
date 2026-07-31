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

    /// Whether to merge with cookies already on the request. Defaults to true.
    /// An existing cookie with the same name is replaced.
    public let appendToExisting: Bool

    public init(
        name: String,
        value: String,
        appendToExisting: Bool = true
    ) {
        self.name = name
        self.value = value
        self.appendToExisting = appendToExisting
    }

    public func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        var mutableRequest = request
        let cookiePair = "\(name)=\(value)"

        if appendToExisting,
           let existing = request.value(forHTTPHeaderField: Header.cookie.name),
           !existing.isEmpty {
            var pairs = existing
                .components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != name && !$0.hasPrefix("\(name)=") }
            pairs.append(cookiePair)
            mutableRequest.setValue(pairs.joined(separator: "; "), forHTTPHeaderField: Header.cookie.name)
        } else {
            mutableRequest.setValue(cookiePair, forHTTPHeaderField: Header.cookie.name)
        }

        return mutableRequest
    }
}
