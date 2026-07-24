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
    /// - Parameters:
    ///   - environment: The environment in which to make the request
    ///   - endpoint: The endpoint instance to be used to make the request
    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) where T.Response == Void {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result = try await loadData(for: urlRequest, endpoint: T.self)
        _ = try T.definition.response(data: result.data, response: result.response, error: nil).get()
    }

    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response where T.Response == Data {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result = try await loadData(for: urlRequest, endpoint: T.self)
        return try T.definition.response(data: result.data, response: result.response, error: nil).get()
    }

    func response<T: Endpoint>(with endpoint: T) async throws(T.TaskError) -> T.Response where T.Response: Decodable {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let mockResponse = try await Mocking.shared.handleMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result = try await loadData(for: urlRequest, endpoint: T.self)
        let data = try T.definition.response(data: result.data, response: result.response, error: nil).get()

        do {
            return try T.responseDecoder.decode(T.Response.self, from: data)
        } catch {
            throw T.TaskError.responseParseError(data: data, error: error)
        }
    }

    /// Loads data for the request, mapping `URLSession` failures into the endpoint's ``EndpointTaskError``.
    internal func loadData<T: Endpoint>(for urlRequest: URLRequest, endpoint: T.Type) async throws(T.TaskError) -> (data: Data, response: URLResponse) {
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
