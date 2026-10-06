//
//  URLSession+Endpoints.swift
//  Endpoints
//
//  Created by Zac White on 5/11/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An error building, sending, or decoding an endpoint's request.
public enum EndpointTaskError<ErrorResponseType: Sendable>: Error, Sendable {
    /// The request couldn't be built.
    case endpointError(EndpointError)
    /// A successful response's body couldn't be decoded as the endpoint's ``Endpoint/Response``.
    case responseParseError(data: Data, error: Error)

    /// The response had no body, and its status code wasn't 204.
    case unexpectedResponse(httpResponse: HTTPURLResponse)

    /// The server returned an error status code, and its body was decoded as the
    /// endpoint's ``Endpoint/ErrorResponse``.
    case errorResponse(httpResponse: HTTPURLResponse, response: ErrorResponseType)
    /// The server returned an error status code, and its body couldn't be decoded as
    /// the endpoint's ``Endpoint/ErrorResponse``.
    case errorResponseParseError(httpResponse: HTTPURLResponse, data: Data, error: Error)

    /// `URLSession` failed to load the request.
    case urlLoadError(Error)
    /// The device isn't connected to the internet.
    case internetConnectionOffline

    /// An authentication operation failed while applying or refreshing the
    /// endpoint's ``Endpoint/Auth`` credentials.
    case authenticationError(AuthenticationError)
}

public extension EndpointTaskError {
    /// The HTTP response the server returned, if the error came from one.
    ///
    /// `nil` when the request failed before a response arrived, such as when it couldn't
    /// be built, the connection failed, or the device was offline.
    var httpResponse: HTTPURLResponse? {
        switch self {
        case .errorResponse(let httpResponse, _),
             .unexpectedResponse(let httpResponse),
             .errorResponseParseError(let httpResponse, _, _):
            return httpResponse
        case .endpointError, .responseParseError, .urlLoadError, .internetConnectionOffline, .authenticationError:
            return nil
        }
    }
}

public extension Endpoint {
    /// The ``EndpointTaskError`` thrown by this endpoint's requests.
    typealias TaskError = EndpointTaskError<ErrorResponse>
}

public extension URLSession {

    /// Creates a data task for an endpoint whose response body is ignored.
    ///
    /// Only accepts endpoints whose ``Endpoint/auth`` is ``NoAuth``, because the task is
    /// returned before an asynchronous authentication method could run. Use
    /// `response(with:environment:auth:)` for authenticated endpoints.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - completion: Called with the result on the session's delegate queue.
    /// - Throws: ``EndpointTaskError/endpointError(_:)`` if the request can't be built.
    /// - Returns: A data task. Call `resume()` to start it.
    func endpointTask<T: Endpoint>(with endpoint: T, environment: T.Server.Environments = T.Server.defaultEnvironment, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response == Void, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment)

        let task = dataTask(with: urlRequest) { (data, response, error) in
            completion(T.definition.response(data: data, response: response, error: error).map { _ in })
        }

        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if Mocking.shared.shouldHandleMock(for: T.self) {
            task.resumeOverride = {
                Task {
                    let action = await Mocking.shared.actionForMock(for: T.self)!
                    switch action {
                    case .none:
                        break
                    case .return(let value):
                        completion(.success(value))
                    case .fail(let errorResponse):
                        completion(.failure(T.TaskError.errorResponse(httpResponse: HTTPURLResponse(), response: errorResponse)))
                    case .throw(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        #endif

        return task
    }

    /// Creates a data task for an endpoint that returns the raw response body.
    ///
    /// Only accepts endpoints whose ``Endpoint/auth`` is ``NoAuth``, because the task is
    /// returned before an asynchronous authentication method could run. Use
    /// `response(with:environment:auth:)` for authenticated endpoints.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - completion: Called with the result on the session's delegate queue.
    /// - Throws: ``EndpointTaskError/endpointError(_:)`` if the request can't be built.
    /// - Returns: A data task. Call `resume()` to start it.
    func endpointTask<T: Endpoint>(with endpoint: T, environment: T.Server.Environments = T.Server.defaultEnvironment, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response == Data, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment)

        let task = dataTask(with: urlRequest) { (data, response, error) in
            completion(T.definition.response(data: data, response: response, error: error))
        }
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if Mocking.shared.shouldHandleMock(for: T.self) {
            task.resumeOverride = {
                Task {
                    let action = await Mocking.shared.actionForMock(for: T.self)!
                    switch action {
                    case .none:
                        break
                    case .return(let value):
                        completion(.success(value))
                    case .fail(let errorResponse):
                        completion(.failure(T.TaskError.errorResponse(httpResponse: HTTPURLResponse(), response: errorResponse)))
                    case .throw(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        #endif
        return task
    }

    /// Creates a data task for an endpoint whose response is decoded.
    ///
    /// Only accepts endpoints whose ``Endpoint/auth`` is ``NoAuth``, because the task is
    /// returned before an asynchronous authentication method could run. Use
    /// `response(with:environment:auth:)` for authenticated endpoints.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - completion: Called with the result on the session's delegate queue.
    /// - Throws: ``EndpointTaskError/endpointError(_:)`` if the request can't be built.
    /// - Returns: A data task. Call `resume()` to start it.
    func endpointTask<T: Endpoint>(with endpoint: T, environment: T.Server.Environments = T.Server.defaultEnvironment, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response: Decodable, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment)

        let task = dataTask(with: urlRequest) { (data, response, error) in
            let response = T.definition.response(data: data, response: response, error: error)
            switch response {
            case .success(let data):
                let decoded: T.Response
                do {
                    decoded = try T.responseDecoder.decode(T.Response.self, from: data)
                } catch {
                    completion(.failure(.responseParseError(data: data, error: error)))
                    return
                }
                completion(.success(decoded))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
        #if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if Mocking.shared.shouldHandleMock(for: T.self) {
            task.resumeOverride = {
                Task {
                    let action = await Mocking.shared.actionForMock(for: T.self)!
                    switch action {
                    case .none:
                        break
                    case .return(let value):
                        completion(.success(value))
                    case .fail(let errorResponse):
                        completion(.failure(T.TaskError.errorResponse(httpResponse: HTTPURLResponse(), response: errorResponse)))
                    case .throw(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        #endif
        return task
    }

    func createUrlRequest<T: Endpoint>(
        for endpoint: T,
        in environment: T.Server.Environments = T.Server.defaultEnvironment
    ) throws(T.TaskError) -> URLRequest {
        do {
            return try endpoint.urlRequest(in: environment)
        } catch {
            throw T.TaskError.endpointError(error)
        }
    }
}
