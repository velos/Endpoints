import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A session wrapper that applies authentication to requests and handles token refresh.
public struct AuthenticatedSession<Auth: AuthenticationMethod>: Sendable {
    /// The underlying URLSession for network requests.
    public let session: URLSession

    /// The authentication method to use.
    public let auth: Auth

    /// Maximum number of retry attempts after reauthentication. Defaults to 1.
    public let maxRetryAttempts: Int

    public init(
        session: URLSession = .shared,
        auth: Auth,
        maxRetryAttempts: Int = 1
    ) {
        self.session = session
        self.auth = auth
        self.maxRetryAttempts = maxRetryAttempts
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
public extension AuthenticatedSession {

    /// Performs an authenticated request expecting a Decodable response.
    func response<T: Endpoint>(with endpoint: T) async throws -> T.Response
    where T.Response: Decodable {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handlMock(for: T.self) {
            return mockResponse
        }
        #endif

        return try await performRequest(with: endpoint) { data in
            try T.responseDecoder.decode(T.Response.self, from: data)
        }
    }

    /// Performs an authenticated request expecting a Void response.
    func response<T: Endpoint>(with endpoint: T) async throws
    where T.Response == Void {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let _: T.Response = try await Mocking.shared.handlMock(for: T.self) {
            return
        }
        #endif

        _ = try await performRequest(with: endpoint) { _ in () }
    }

    /// Performs an authenticated request expecting raw Data.
    func response<T: Endpoint>(with endpoint: T) async throws -> T.Response
    where T.Response == Data {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handlMock(for: T.self) {
            return mockResponse
        }
        #endif

        return try await performRequest(with: endpoint) { $0 }
    }

    private func performRequest<T: Endpoint, R>(
        with endpoint: T,
        transform: (Data) throws -> R
    ) async throws -> R {
        for attempt in 0...maxRetryAttempts {
            do {
                let request = try createUrlRequest(for: endpoint)
                let authenticatedRequest = try await auth.authenticate(request: request)

                let result: (data: Data, response: URLResponse)
                do {
                    result = try await session.data(for: authenticatedRequest)
                } catch {
                    if (error as NSError).code == URLError.Code.notConnectedToInternet.rawValue {
                        throw T.TaskError.internetConnectionOffline
                    } else {
                        throw T.TaskError.urlLoadError(error)
                    }
                }

                let data = try T.definition.response(
                    data: result.data,
                    response: result.response,
                    error: nil
                ).get()

                do {
                    return try transform(data)
                } catch {
                    throw T.TaskError.responseParseError(data: data, error: error)
                }
            } catch let error as T.TaskError {
                let httpResponse = extractHTTPResponse(from: error)
                if auth.shouldReauthenticate(for: error, response: httpResponse),
                   attempt < maxRetryAttempts {
                    try await auth.reauthenticate()
                    continue
                }

                throw error
            }
        }

        throw AuthenticationError.maxRetriesExceeded
    }

    private func createUrlRequest<T: Endpoint>(for endpoint: T) throws -> URLRequest {
        do {
            return try endpoint.urlRequest()
        } catch {
            guard let endpointError = error as? EndpointError else {
                fatalError("Unhandled endpoint error: \(error)")
            }

            throw T.TaskError.endpointError(endpointError)
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
