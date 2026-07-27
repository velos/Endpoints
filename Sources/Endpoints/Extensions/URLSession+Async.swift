//
//  URLSession+Async.swift
//  Endpoints
//
//  Created by Zac White on 9/29/22.
//  Copyright © 2022 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
public extension URLSession {

    /// Perform the request for the endpoint on the given environment.
    ///
    /// Use this when the response body is expected to be `Void` or empty as you would have in a 204.
    /// - Parameter endpoint: The endpoint instance to be used to make the request
    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) where T.Response == Void {
        try await performRequest(with: endpoint) { (_) throws(T.TaskError) in () }
    }

    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response where T.Response == Data {
        try await performRequest(with: endpoint) { (data) throws(T.TaskError) in data }
    }

    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response where T.Response: Decodable {
        try await performRequest(with: endpoint) { (data) throws(T.TaskError) in
            do {
                return try T.responseDecoder.decode(T.Response.self, from: data)
            } catch {
                throw T.TaskError.responseParseError(data: data, error: error)
            }
        }
    }

    /// Authenticates and performs the request, retrying after reauthentication when the
    /// endpoint's ``Endpoint/Auth`` asks for it.
    ///
    /// With the default ``NoAuth``, `authenticate` returns the request unchanged and
    /// `shouldReauthenticate` is always false, so this is a single pass through the
    /// unauthenticated request path.
    ///
    /// An active mock short-circuits here, ahead of authentication: a mocked request
    /// never applies credentials and never enters the retry loop.
    private func performRequest<T: Endpoint>(
        with endpoint: T,
        transform: (Data) throws(T.TaskError) -> T.Response
    ) async throws(T.TaskError) -> T.Response {
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        let auth = T.auth
        // The endpoint is immutable, so the unauthenticated request is identical on
        // every attempt; only the credentials applied to it change.
        let request = try createUrlRequest(for: endpoint)

        var attempt = 0
        while true {
            let authenticatedRequest: URLRequest
            do {
                authenticatedRequest = try await auth.authenticate(request: request)
            } catch {
                throw T.TaskError.authenticationError(error)
            }

            do {
                let result = try await loadData(for: authenticatedRequest, endpoint: T.self)
                let data = try T.definition.response(
                    data: result.data,
                    response: result.response,
                    error: nil
                ).get()

                return try transform(data)
            } catch {
                guard attempt < auth.retryAttempts,
                      auth.shouldReauthenticate(for: error, response: error.httpResponse) else {
                    throw error
                }

                do {
                    try await auth.reauthenticate(after: authenticatedRequest)
                } catch {
                    throw T.TaskError.authenticationError(error)
                }

                attempt += 1
            }
        }
    }

    /// Loads data for the request, mapping `URLSession` failures into the endpoint's ``EndpointTaskError``.
    private func loadData<T: Endpoint>(for urlRequest: URLRequest, endpoint: T.Type) async throws(T.TaskError) -> (data: Data, response: URLResponse) {
        do {
            return try await data(for: urlRequest)
        } catch {
            if (error as NSError).code == URLError.Code.notConnectedToInternet.rawValue {
                throw T.TaskError.internetConnectionOffline
            } else {
                throw T.TaskError.urlLoadError(error)
            }
        }
    }
}
