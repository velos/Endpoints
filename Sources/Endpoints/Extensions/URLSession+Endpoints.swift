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

/// A error when creating or requesting an Endpoint
public enum EndpointTaskError<ErrorResponseType: Sendable>: Error, Sendable {
    case endpointError(EndpointError)
    case responseParseError(data: Data, error: Error)

    case unexpectedResponse(httpResponse: HTTPURLResponse)

    case errorResponse(httpResponse: HTTPURLResponse, response: ErrorResponseType)
    case errorResponseParseError(httpResponse: HTTPURLResponse, data: Data, error: Error)

    case urlLoadError(Error)
    case internetConnectionOffline

    /// An authentication operation failed while applying or refreshing the
    /// endpoint's ``Endpoint/Auth`` credentials.
    case authenticationError(AuthenticationError)
}

public extension EndpointTaskError {
    /// The HTTP response associated with this error, when the failure came from a
    /// response the server actually returned.
    ///
    /// `nil` for failures that happened before or instead of a response, such as
    /// request construction, transport errors, and being offline.
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
    /// Shorthand for an ``EndpointTaskError`` with the request's generic ``Endpoint/ErrorResponse``
    typealias TaskError = EndpointTaskError<ErrorResponse>
}

public extension URLSession {

    /// Creates a session data task using the ``Definition`` associated with the passed in request on the passed in environment.
    /// This function does not expect a result value from the endpoint.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(with endpoint: T, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response == Void, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint)

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

    /// Creates a session data task using the ``Definition`` associated with the passed in request on the passed in environment.
    /// This function expects a result value of `Data`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(with endpoint: T, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response == Data, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint)

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

    /// Creates a session data task using the ``Definition`` associated with the passed in request on the passed in environment.
    /// This function expects a result value which is `Decodable`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(with endpoint: T, completion: @escaping @Sendable (Result<T.Response, T.TaskError>) -> Void) throws(T.TaskError) -> URLSessionDataTask where T.Response: Decodable, T.Auth == NoAuth {

        let urlRequest = try createUrlRequest(for: endpoint)

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

    func createUrlRequest<T: Endpoint>(for endpoint: T) throws(T.TaskError) -> URLRequest {
        do {
            return try endpoint.urlRequest()
        } catch {
            throw T.TaskError.endpointError(error)
        }
    }
}
