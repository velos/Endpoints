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

    /// Converts data, response and error into a Result type by processing data and throwing errors based on response codes and response data.
    /// - Parameters:
    ///   - data: The raw data fetched in the response
    ///   - response: The response object
    ///   - error: Any error encountered by the fetch
    /// - Returns: A Result value with either the Data or the T.TaskError
    func response(data: Data?, response: URLResponse?, error: Error?) -> Result<Data, T.TaskError> {
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
            return .success(Data())
        } else if (200..<300).contains(httpResponse.statusCode), let data = data {
            return .success(data)
        } else if let data = data {
            let decoded: T.ErrorResponse
            do {
                decoded = try T.errorDecoder.decode(T.ErrorResponse.self, from: data)
            } catch {
                return .failure(.errorResponseParseError(httpResponse: httpResponse, data: data, error: error))
            }

            return .failure(.errorResponse(httpResponse: httpResponse, response: decoded))
        } else {
            return .failure(.unexpectedResponse(httpResponse: httpResponse))
        }
    }
}
