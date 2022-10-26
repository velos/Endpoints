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

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: request)
        } catch {
            return Fail(outputType: T.Response.self, failure: error as! EndpointTaskError)
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
                let data = try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
                do {
                    return try T.responseDecoder.decode(T.Response.self, from: data)
                } catch {
                    throw T.TaskError.responseParseError(data: data, error: error)
                }
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }
}
