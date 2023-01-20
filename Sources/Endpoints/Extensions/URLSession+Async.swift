//
//  URLSession+Async.swift
//  RequestTypes
//
//  Created by Zac White on 9/29/22.
//  Copyright © 2022 Velos Mobile LLC. All rights reserved.
//

import Foundation

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
extension URLSession {
    public func response<T: RequestType>(in environment: EnvironmentType, with endpoint: T) async throws where T.Response == Void {
        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            throw T.TaskError.urlLoadError(error)
        }

        _ = try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
    }

    public func response<T: RequestType>(in environment: EnvironmentType, with endpoint: T) async throws -> T.Response where T.Response == Data {
        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            throw T.TaskError.urlLoadError(error)
        }

        return try T.endpoint.response(data: result.data, response: result.response, error: nil).get()
    }

    public func response<T: RequestType>(in environment: EnvironmentType, with endpoint: T) async throws -> T.Response where T.Response: Decodable {
        let urlRequest = try createUrlRequest(in: environment, for: endpoint)

        let result: (data: Data, response: URLResponse)
        do {
            result = try await data(for: urlRequest)
        } catch {
            throw T.TaskError.urlLoadError(error)
        }

        let data = try T.endpoint.response(data: result.data, response: result.response, error: nil).get()

        do {
            return try T.responseDecoder.decode(T.Response.self, from: data)
        } catch {
            throw T.TaskError.responseParseError(data: data, error: error)
        }
    }
}
