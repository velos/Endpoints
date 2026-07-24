import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A session wrapper that applies authentication to requests and handles token refresh.
///
/// All errors — including authentication failures — surface as the endpoint's ``EndpointTaskError``.
/// Authentication-specific failures are wrapped in ``EndpointTaskError/authenticationError(_:)``.
public struct AuthenticatedSession<Auth: AuthenticationMethod>: Sendable {
    /// The underlying URLSession for network requests.
    public let session: URLSession

    /// The authentication method to use.
    public let auth: Auth

    /// Maximum number of retry attempts after reauthentication.
    /// Negative values are treated as 0. Defaults to 1.
    public let maxRetryAttempts: Int

    public init(
        session: URLSession = .shared,
        auth: Auth,
        maxRetryAttempts: Int = 1
    ) {
        self.session = session
        self.auth = auth
        self.maxRetryAttempts = max(0, maxRetryAttempts)
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
public extension AuthenticatedSession {

    /// Performs an authenticated request expecting a Decodable response.
    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response
    where T.Response: Decodable {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        return try await performRequest(with: endpoint) { (data) throws(T.TaskError) in
            do {
                return try T.responseDecoder.decode(T.Response.self, from: data)
            } catch {
                throw T.TaskError.responseParseError(data: data, error: error)
            }
        }
    }

    /// Performs an authenticated request expecting a Void response.
    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError)
    where T.Response == Void {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let _: T.Response = try await Mocking.shared.handleMock(for: T.self) {
            return
        }
        #endif

        _ = try await performRequest(with: endpoint) { (_) throws(T.TaskError) in () }
    }

    /// Performs an authenticated request expecting raw Data.
    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response
    where T.Response == Data {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        return try await performRequest(with: endpoint) { (data) throws(T.TaskError) in data }
    }

    private func performRequest<T: Endpoint, R>(
        with endpoint: T,
        transform: (Data) throws(T.TaskError) -> R
    ) async throws(T.TaskError) -> R {
        var attempt = 0
        while true {
            let request = try createUrlRequest(for: endpoint)

            let authenticatedRequest: URLRequest
            do {
                authenticatedRequest = try await auth.authenticate(request: request)
            } catch {
                throw T.TaskError.authenticationError(error)
            }

            do {
                let result = try await session.loadData(for: authenticatedRequest, endpoint: T.self)
                let data = try T.definition.response(
                    data: result.data,
                    response: result.response,
                    error: nil
                ).get()

                return try transform(data)
            } catch {
                guard attempt < maxRetryAttempts,
                      auth.shouldReauthenticate(for: error, response: extractHTTPResponse(from: error)) else {
                    throw error
                }

                do {
                    try await auth.reauthenticate()
                } catch {
                    throw T.TaskError.authenticationError(error)
                }

                attempt += 1
            }
        }
    }

    private func createUrlRequest<T: Endpoint>(for endpoint: T) throws(T.TaskError) -> URLRequest {
        do {
            return try endpoint.urlRequest()
        } catch {
            throw T.TaskError.endpointError(error)
        }
    }

    private func extractHTTPResponse<E: Sendable>(from error: EndpointTaskError<E>) -> HTTPURLResponse? {
        switch error {
        case .errorResponse(let httpResponse, _):
            return httpResponse
        case .unexpectedResponse(let httpResponse):
            return httpResponse
        case .errorResponseParseError(let httpResponse, _, _):
            return httpResponse
        default:
            return nil
        }
    }
}
