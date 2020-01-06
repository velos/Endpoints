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
    case errorRresponseParseError(Error)

    case urlLoadError(Error)
}

extension URLSession {

    public func task<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<Void, EndpointTaskError<T.ErrorResponse>>) -> Void) throws -> URLSessionDataTask where T.Response == Void {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in
            let responseCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let error = error {
                completion(.failure(.urlLoadError(error)))
            } else if responseCode == 204 {
                completion(.success(()))
            } else if !(200..<300).contains(responseCode), let data = data {
                let decoded: T.ErrorResponse
                do {
                    decoded = try T.errorDecoder.decode(T.ErrorResponse.self, from: data)
                } catch {
                    completion(.failure(.errorRresponseParseError(error)))
                    return
                }

                completion(.failure(.errorResponse(code: responseCode, response: decoded)))
            } else {
                completion(.failure(.unexpectedResponse(code: responseCode)))
            }
        }
    }

    public func task<T: RequestDataType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<T.Response, EndpointTaskError<T.ErrorResponse>>) -> Void) throws -> URLSessionDataTask where T.Response: Decodable {

        let urlRequest = try createUrlRequest(for: endpoint, in: environment, for: request)

        return dataTask(with: urlRequest) { (data, response, error) in

            let responseCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let error = error {
                completion(.failure(.urlLoadError(error)))
            } else if (200..<300).contains(responseCode), let data = data {
                let decoded: T.Response
                do {
                    decoded = try T.responseDecoder.decode(T.Response.self, from: data)
                } catch {
                    completion(.failure(.responseParseError(error)))
                    return
                }

                completion(.success(decoded))
            } else if let data = data {
                let decoded: T.ErrorResponse
                do {
                    decoded = try T.errorDecoder.decode(T.ErrorResponse.self, from: data)
                } catch {
                    completion(.failure(.errorRresponseParseError(error)))
                    return
                }

                completion(.failure(.errorResponse(code: responseCode, response: decoded)))
            }
        }
    }

    private func createUrlRequest<T: RequestDataType>(for endpoint: Endpoint<T>, in environment: EnvironmentType, for request: T) throws -> URLRequest {
        let urlRequest: URLRequest

        do {
            urlRequest = try endpoint.request(in: environment, for: request)
        } catch {
            guard let endpointError = error as? EndpointError else {
                fatalError("Unhandled endpoint error: \(error)")
            }

            throw EndpointTaskError<T.ErrorResponse>.endpointError(endpointError)
        }

        return urlRequest
    }
}
