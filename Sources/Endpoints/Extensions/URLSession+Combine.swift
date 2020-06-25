//
//  URLSession+Combine.swift
//  Endpoints
//
//  Created by Zac White on 6/17/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine
#endif

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension URLSession {

    /// Creates a publisher to fetch the given endpoint with the request.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The Endpoint to use when creating the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Void {
        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }
        

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .map { _ in }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher to fetch the given endpoint with the request.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The Endpoint to use when creating the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Data {

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result -> T.Response in
                try endpoint.response(data: result.data, response: result.response, error: nil).get()
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher to fetch the given endpoint with the request.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The Endpoint to use when creating the request
    ///   - request: The request data to insert into the Endpoint
    /// - Returns: A Publisher which fetches the Endpoints contents. Any failures when creating the request are sent as errors in the Publisher
    public func endpointPublisher<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response: Decodable {

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: T.TaskError.endpointError(error as! EndpointError))
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = endpoint.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result -> T.Response in
                let data = try endpoint.response(data: result.data, response: result.response, error: nil).get()
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
}
