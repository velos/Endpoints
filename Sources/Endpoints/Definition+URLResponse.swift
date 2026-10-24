//
//  Definition+URLResponse.swift
//  Endpoints
//
//  Created by Zac White on 9/29/22.
//  Copyright © 2022 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension Definition {

    /// Converts the result of a data task into the response body or the endpoint's `TaskError`.
    ///
    /// A 2xx response returns its body, and a 204 returns empty data. Any other status
    /// code is decoded as the endpoint's ``Endpoint/ErrorResponse``.
    /// - Parameters:
    ///   - data: The response body.
    ///   - response: The response.
    ///   - error: The error the data task reported, if any.
    /// - Returns: The response body, or the error to throw.
    func response(data: Data?, response: URLResponse?, error: Error?) -> Result<Data, T.TaskError> {
        responseWithMetadata(data: data, response: response, error: error).map(\.data)
    }
}

extension Definition {
    /// Returns the successful response body and HTTP response, or the endpoint's `TaskError`.
    func responseWithMetadata(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Result<(data: Data, response: HTTPURLResponse), T.TaskError> {
        if let error = error {
            guard (error as NSError).code != URLError.Code.notConnectedToInternet.rawValue else {
                return .failure(.internetConnectionOffline)
            }

            return .failure(.urlLoadError(error))
        }

        // if we don't have an `error`, we must have an `HTTPURLResponse`
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.urlLoadError(URLError(.badServerResponse)))
        }

        if httpResponse.statusCode == 204 {
            // handle empty response
            return .success((Data(), httpResponse))
        } else if (200..<300).contains(httpResponse.statusCode), let data = data {
            return .success((data, httpResponse))
        } else if let data = data {
            let decoded: T.ErrorResponse
            do {
                decoded = try T.errorDecoder.decode(
                    T.ErrorResponse.self, from: data, response: httpResponse)
            } catch {
                return .failure(.errorResponseParseError(httpResponse: httpResponse, data: data, error: error))
            }

            return .failure(.errorResponse(httpResponse: httpResponse, response: decoded))
        } else {
            return .failure(.unexpectedResponse(httpResponse: httpResponse))
        }
    }
}
