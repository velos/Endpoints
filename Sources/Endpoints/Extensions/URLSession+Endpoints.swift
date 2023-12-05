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
public enum EndpointTaskError<ErrorResponseType>: Error {
    case endpointError(EndpointError)
    case responseParseError(data: Data, error: Error)

    case unexpectedResponse(httpResponse: HTTPURLResponse)

    case errorResponse(httpResponse: HTTPURLResponse, response: ErrorResponseType)
    case errorResponseParseError(httpResponse: HTTPURLResponse, data: Data, error: Error)

    case urlLoadError(Error)
    case internetConnectionOffline
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
    ///   - environment: An instance conforming to ``EnvironmentType``, which is used to build the full request.
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(in environment: EnvironmentType, with endpoint: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Void {

        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(T.definition.response(data: data, response: response, error: error).map { _ in })
        }
    }

    /// Creates a session data task using the ``Definition`` associated with the passed in request on the passed in environment.
    /// This function expects a result value of `Data`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - environment: An instance conforming to ``EnvironmentType``, which is used to build the full request.
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(in environment: EnvironmentType, with endpoint: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Data {

        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(T.definition.response(data: data, response: response, error: error))
        }
    }

    /// Creates a session data task using the ``Definition`` associated with the passed in request on the passed in environment.
    /// This function expects a result value which is `Decodable`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - environment: An instance conforming to ``EnvironmentType``, which is used to build the full request.
    ///   - endpoint: The request data to use when filling in the ``Definition``
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an ``EndpointTaskError`` of ``EndpointTaskError/endpointError(_:)`` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    func endpointTask<T: Endpoint>(in environment: EnvironmentType, with endpoint: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response: Decodable {

        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        return dataTask(with: urlRequest) { (data, response, error) in
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
    }

    func createUrlRequest<T: Endpoint>(in environment: EnvironmentType, for endpoint: T) throws -> URLRequest {
        let urlRequest: URLRequest

        do {
            urlRequest = try endpoint.urlRequest(in: environment)
        } catch {
            guard let endpointError = error as? EndpointError else {
                fatalError("Unhandled endpoint error: \(error)")
            }

            throw T.TaskError.endpointError(endpointError)
        }

        return urlRequest
    }
}
