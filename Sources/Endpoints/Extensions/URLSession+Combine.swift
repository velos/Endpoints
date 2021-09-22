//
//  URLSession+Combine.swift
//  Endpoints
//
//  Created by Zac White on 6/17/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
import Combine

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension URLSession {

    /// Creates a publisher and starts the request for the given Endpoint. This function does not expect a result value from the endpoint.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestType>(in environment: EnvironmentType, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Void {
        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result in
                _ = try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher and starts the request for the given Endpoint. This function expects a result value of `Data`.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestType>(in environment: EnvironmentType, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Data {

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result -> T.Response in
                try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher and starts the request for the given Endpoint. This function expects a result value which is `Decodable`.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestType>(in environment: EnvironmentType, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response: Decodable {

        let shouldCache = (request as? CacheableRequestType)?.isCacheable ?? false

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .tryCatch { error -> AnyPublisher<URLSession.DataTaskPublisher.Output, URLSession.DataTaskPublisher.Failure> in
                guard shouldCache, let urlCache = URLSession.shared.configuration.urlCache else {
                    throw error
                }

                switch error.code {
                case .notConnectedToInternet,
                     .networkConnectionLost,
                     .timedOut,
                     .dataNotAllowed:
                    guard let cachedResponse = urlCache.cachedResponse(for: urlRequest) else {
                        throw error // not found in cache
                    }
                    return Just((data: cachedResponse.data, response: cachedResponse.response))
                        .setFailureType(to: URLSession.DataTaskPublisher.Failure.self)
                        .eraseToAnyPublisher()

                default:
                    throw error
                }
            }
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .handleEvents(receiveOutput: {
                guard shouldCache, let urlCache = URLSession.shared.configuration.urlCache else { return }

                // Check whether manual caching is necessary:
                let previousCachedResponse = urlCache.cachedResponse(for: urlRequest)
                guard !Self.compareHeadersAsStringDictionaries(response1: previousCachedResponse?.response, response2: $0.response) else {
                    // Unchanged headers indicate this was already cached
                    return
                }

                let cachedResponse = CachedURLResponse(response: $0.response, data: $0.data)
                urlCache.storeCachedResponse(cachedResponse, for: urlRequest)
            })
            .tryMap { result -> T.Response in
                let data = try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
                do {
                    return try T.responseDecoder.decode(T.Response.self, from: data)
                } catch {
                    throw T.TaskError.responseParseError(error)
                }
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    private static func compareHeadersAsStringDictionaries(response1: URLResponse?, response2: URLResponse?) -> Bool {
        guard let fields1 = (response1 as? HTTPURLResponse)?.allHeaderFields as? [String: String],
              let fields2 = (response2 as? HTTPURLResponse)?.allHeaderFields as? [String: String]
        else { return false }
        return fields1 == fields2
    }
}

