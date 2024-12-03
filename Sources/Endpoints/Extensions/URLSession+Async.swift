//
//  URLSession+Async.swift
//  Endpoints
//
//  Created by Zac White on 9/29/22.
//  Copyright © 2022 Velos Mobile LLC. All rights reserved.
//

import Foundation

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
public extension URLSession {

    /// Perform the request for the endpoint on the given environment.
    ///
    /// Use this when the response body is expected to be `Void` or empty as you would have in a 204.
    /// - Parameters:
    ///   - environment: The environment in which to make the request
    ///   - endpoint: The endpoint instance to be used to make the request
    func response<T: Endpoint>(with endpoint: T) async throws where T.Response == Void {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG
        if let mockResponse = try await Mocking.shared.handlMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            if (error as NSError).code == URLError.Code.notConnectedToInternet.rawValue {
                throw T.TaskError.internetConnectionOffline
            } else {
                throw T.TaskError.urlLoadError(error)
            }
        }

        _ = try T.definition.response(data: result.data, response: result.response, error: nil).get()
    }

    func response<T: Endpoint>(with endpoint: T) async throws -> T.Response where T.Response == Data {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG
        if let mockResponse = try await Mocking.shared.handlMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            if (error as NSError).code == URLError.Code.notConnectedToInternet.rawValue {
                throw T.TaskError.internetConnectionOffline
            } else {
                throw T.TaskError.urlLoadError(error)
            }
        }

        return try T.definition.response(data: result.data, response: result.response, error: nil).get()
    }

    func response<T: Endpoint>(with endpoint: T) async throws -> T.Response where T.Response: Decodable {
        let urlRequest = try createUrlRequest(for: endpoint)

        #if DEBUG
        if let mockResponse = try await Mocking.shared.handlMock(for: T.self) {
            return mockResponse
        }
        #endif

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            if (error as NSError).code == URLError.Code.notConnectedToInternet.rawValue {
                throw T.TaskError.internetConnectionOffline
            } else {
                throw T.TaskError.urlLoadError(error)
            }
        }

        let data = try T.definition.response(data: result.data, response: result.response, error: nil).get()

        do {
            return try T.responseDecoder.decode(T.Response.self, from: data)
        } catch {
            throw T.TaskError.responseParseError(data: data, error: error)
        }
    }
}
