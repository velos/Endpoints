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

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public extension URLSession {

    /// Creates a publisher and starts the request for the given ``Definition``. This function does not expect a result value from the endpoint.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(in environment: EnvironmentType, with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Void {
        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: endpoint)
        } catch {
            return Fail(outputType: T.Response.self, failure: error as! T.TaskError)
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.definition.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result in
                _ = try T.definition.response(data: result.data, response: result.response, error: nil).get()
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher and starts the request for the given ``Definition``. This function expects a result value of `Data`.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(in environment: EnvironmentType, with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Data {

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: endpoint)
        } catch {
            return Fail(outputType: T.Response.self, failure: error as! T.TaskError)
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.definition.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result -> T.Response in
                try T.definition.response(data: result.data, response: result.response, error: nil).get()
            }
            // swiftlint:disable:next force_cast
            .mapError { $0 as! T.TaskError }
            .eraseToAnyPublisher()
    }

    /// Creates a publisher and starts the request for the given ``Definition``. This function expects a result value which is `Decodable`.
    /// - Parameters:
    ///   - environment: The environment with which to make the request
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(in environment: EnvironmentType, with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response: Decodable {

        let urlRequest: URLRequest
        do {
            urlRequest = try createUrlRequest(in: environment, for: endpoint)
        } catch {
            return Fail(outputType: T.Response.self, failure: error as! T.TaskError)
                .eraseToAnyPublisher()
        }

        return dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .mapError { error -> T.TaskError in
                guard case let .failure(responseError) = T.definition.response(data: nil, response: nil, error: error) else {
                    fatalError("Unhandled error")
                }

                return responseError
            }
            .tryMap { result -> T.Response in
                let data = try T.definition.response(data: result.data, response: result.response, error: nil).get()
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

#endif
