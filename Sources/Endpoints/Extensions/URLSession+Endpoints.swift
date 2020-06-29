//
//  URLSession+Endpoints.swift
//  Endpoints
//
//  Created by Zac White on 5/11/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

/// A error when creating or requesting an Endpoint
public enum EndpointTaskError<ErrorResponseType>: Error {
    case endpointError(EndpointError)
    case responseParseError(Error)

    case unexpectedResponse(code: Int)

    case errorResponse(code: Int, response: ErrorResponseType)
    case errorResponseParseError(Error)

    case urlLoadError(Error)
    case internetConnectionOffline
}

extension RequestType {
    /// Shorthand for an `EndpointTaskError` with the request's generic `ErrorResponse`
    public typealias TaskError = EndpointTaskError<ErrorResponse>
}

extension Endpoint {
    func response(data: Data?, response: URLResponse?, error: Error?) -> Result<Data, T.TaskError> {
        let responseCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if let error = error {
            guard (error as NSError).code != URLError.Code.notConnectedToInternet.rawValue else {
                return .failure(.internetConnectionOffline)
            }

            return .failure(.urlLoadError(error))
        } else if responseCode == 204 {
            // handle empty response
            return .success(Data())
        } else if (200..<300).contains(responseCode), let data = data {
            return .success(data)
        } else if let data = data {
            let decoded: T.ErrorResponse
            do {
                decoded = try T.errorDecoder.decode(T.ErrorResponse.self, from: data)
            } catch {
                return .failure(.errorResponseParseError(error))
            }

            return .failure(.errorResponse(code: responseCode, response: decoded))
        } else {
            return .failure(.unexpectedResponse(code: responseCode))
        }
    }
}

extension URLSession {

    /// Creates a session data task using the given Endpoint on the passed in environment. This function does not expect a result value from the endpoint.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - environment: An instance conforming to EnvironmentType, which is used to build the full request.
    ///   - endpoint: The Endpoint to use when building the request
    ///   - request: The request data to use when filling in the Endpoint
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an `EndpointTaskError` of `.endpointError(EndpointError)` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    public func endpointTask<T: RequestType>(in environment: EnvironmentType, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Void {

        let urlRequest = try createUrlRequest(in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(T.endpoint.response(data: data, response: response, error: error).map { _ in })
        }
    }

    /// Creates a session data task using the given Endpoint on the passed in environment. This function expects a result value of `Data`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - environment: An instance conforming to EnvironmentType, which is used to build the full request.
    ///   - endpoint: The Endpoint to use when building the request
    ///   - request: The request data to use when filling in the Endpoint
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an `EndpointTaskError` of `.endpointError(EndpointError)` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    public func endpointTask<T: RequestType>(in environment: EnvironmentType, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Data {

        let urlRequest = try createUrlRequest(in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(T.endpoint.response(data: data, response: response, error: error))
        }
    }

    /// Creates a session data task using the given Endpoint on the passed in environment. This function expects a result value which is `Decodable`.
    /// Note: This does not start the request. That must be done with `resume()`.
    /// - Parameters:
    ///   - environment: An instance conforming to EnvironmentType, which is used to build the full request.
    ///   - endpoint: The Endpoint to use when building the request
    ///   - request: The request data to use when filling in the Endpoint
    ///   - completion: The completion handler to call when the load request is complete. This handler is executed on the delegate queue.
    /// - Throws: Throws an `EndpointTaskError` of `.endpointError(EndpointError)` if there is an issue constructing the request.
    /// - Returns: The new session data task.
    public func endpointTask<T: RequestType>(in environment: EnvironmentType, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response: Decodable {

        let urlRequest = try createUrlRequest(in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            let response = T.endpoint.response(data: data, response: response, error: error)
            switch response {
            case .success(let data):
                let decoded: T.Response
                do {
                    decoded = try T.responseDecoder.decode(T.Response.self, from: data)
                } catch {
                    completion(.failure(.responseParseError(error)))
                    return
                }
                completion(.success(decoded))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }

    func createUrlRequest<T: RequestType>(in environment: EnvironmentType, for request: T) throws -> URLRequest {
        let urlRequest: URLRequest

        do {
            urlRequest = try request.urlRequest(in: environment)
        } catch {
            guard let endpointError = error as? EndpointError else {
                fatalError("Unhandled endpoint error: \(error)")
            }

            throw T.TaskError.endpointError(endpointError)
        }

        return urlRequest
    }
}
