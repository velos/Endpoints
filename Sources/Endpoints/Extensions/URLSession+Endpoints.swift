//
//  URLSession+Endpoints.swift
//  Endpoints
//
//  Created by Zac White on 5/11/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

public enum EndpointTaskError<ErrorResponseType>: Error {
    case endpointError(EndpointError)
    case responseParseError(Error)

    case unexpectedResponse(code: Int)

    case errorResponse(code: Int, response: ErrorResponseType)
    case errorResponseParseError(Error)

    case urlLoadError(Error)
    case internetConnectionOffline
}

extension RequestDataType {
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

    public func endpointTask<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Void {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(endpoint.response(data: data, response: response, error: error).map { _ in })
        }
    }

    public func endpointTask<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response == Data {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            completion(endpoint.response(data: data, response: response, error: error))
        }
    }

    public func endpointTask<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<T.Response, T.TaskError>) -> Void) throws -> URLSessionDataTask where T.Response: Decodable {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            let response = endpoint.response(data: data, response: response, error: error)
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

    func createUrlRequest<T: RequestDataType>(for endpoint: Endpoint<T>, in environment: EnvironmentType, for request: T) throws -> URLRequest {
        let urlRequest: URLRequest

        do {
            urlRequest = try endpoint.request(in: environment, for: request)
        } catch {
            guard let endpointError = error as? EndpointError else {
                fatalError("Unhandled endpoint error: \(error)")
            }

            throw T.TaskError.endpointError(endpointError)
        }

        return urlRequest
    }
}
