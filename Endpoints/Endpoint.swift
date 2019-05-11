//
//  Endpoint.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

public enum EndpointError: Error {
    case invalid(components: URLComponents, relativeTo: URL)
    case invalidQuery(named: String, type: Any.Type)
    case invalidForm(named: String, type: Any.Type)
    case invalidBodyParameter
}

public enum Parameter<T> {
    case form(key: String, value: PartialKeyPath<T>)
    case query(key: String, value: PartialKeyPath<T>)
}

public struct Empty: Codable { }

public protocol RequestType: JSONDecoderProvider {
    associatedtype Response: Decodable = Empty
    associatedtype Body: Encodable = Empty
    associatedtype PathComponents = Empty
    associatedtype Parameters = Empty

    var body: Body { get }
    var pathComponents: PathComponents { get }
    var parameters: Parameters { get }
}

public extension RequestType where Body == Empty {
    var body: Body {
        return Empty()
    }
}

public extension RequestType where PathComponents == Empty {
    var pathComponents: PathComponents {
        return Empty()
    }
}

public extension RequestType where Parameters == Empty {
    var parameters: Parameters {
        return Empty()
    }
}

public enum Method {
    case get
    case post

    var methodString: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        }
    }
}

public protocol JSONEncoderProvider {
    static var jsonEncoder: JSONEncoder { get }
}

extension JSONEncoderProvider {
    public static var jsonEncoder: JSONEncoder {
        return JSONEncoder()
    }
}

public protocol JSONDecoderProvider {
    static var jsonDecoder: JSONDecoder { get }
}

extension JSONDecoderProvider {
    public static var jsonDecoder: JSONDecoder {
        return JSONDecoder()
    }
}

extension RequestType where Self: JSONDecoderProvider {
    static func decode(data: Data) throws -> Self.Response {
        return try jsonDecoder.decode(Response.self, from: data)
    }
}

public protocol EnvironmentType {
    var baseUrl: URL { get }
}

public struct Endpoint<T: RequestType> {
    public let method: Method
    public let path: PathTemplate<T.PathComponents>
    public let body: T.Body
    public let parameters: [Parameter<T.Parameters>]
    public let headers: [String: PathTemplate<T.Parameters>]

    public func request(in environment: EnvironmentType, for request: T) throws -> URLRequest {

        var components = URLComponents()
        components.path = path.path(with: request.pathComponents)

        let urlQueryItems: [URLQueryItem] = try self.parameters.compactMap { item in

            guard case .query(let key, let valuePath) = item else { return nil }

            let value = request.parameters[keyPath: valuePath]

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidQuery(named: key, type: type(of: value))
            }

            if let query = queryValue.parameterValue {
                return URLQueryItem(name: key, value: query)
            }

            return nil
        }

        let bodyFormItems: [URLQueryItem] = try self.parameters.compactMap { item in

            guard case .form(let key, let valuePath) = item else { return nil }

            let value = request.parameters[keyPath: valuePath]

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidForm(named: key, type: type(of: value))
            }

            if let query = queryValue.parameterValue {
                return URLQueryItem(name: key, value: query)
            }

            return nil
        }

        if !urlQueryItems.isEmpty {
            components.queryItems = urlQueryItems
        }

        let baseUrl = environment.baseUrl
        guard let url = components.url(relativeTo: baseUrl) else {
            throw EndpointError.invalid(components: components, relativeTo: baseUrl)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.methodString

        for header in headers {
            urlRequest.addValue(header.value.path(with: request.parameters), forHTTPHeaderField: header.key)
        }


        urlRequest.url = url

        if !(body is Empty) {

            let encoder: JSONEncoder
            if let bodyType = body as? JSONEncoderProvider {
                encoder = type(of: bodyType).jsonEncoder
            } else {
                encoder = JSONEncoder()
            }

            urlRequest.httpBody = try encoder.encode(body)
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if !bodyFormItems.isEmpty {
            urlRequest.httpBody = bodyFormItems.formString.data(using: .utf8)
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        return urlRequest
    }
}

extension Array where Element == URLQueryItem {

    /// Goes through each URLQueryItem element and joins them with a '&',
    /// suitable for putting into the httpBody of a request
    var formString: String {
        return map { $0.description }.joined(separator: "&")
    }
}

extension Endpoint where T.Body == Empty {
    init(method: Method, path: PathTemplate<T.PathComponents>, parameters: [Parameter<T.Parameters>] = [], headers: [String: PathTemplate<T.Parameters>] = [:]) {
        self.method = method
        self.path = path
        self.body = Empty()
        self.parameters = parameters
        self.headers = headers
    }
}
