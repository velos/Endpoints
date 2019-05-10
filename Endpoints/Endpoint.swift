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

public struct Empty: Codable { }

public enum Parameter<T> {
    case form(key: String, value: PartialKeyPath<T>)
    case query(key: String, value: PartialKeyPath<T>)
}

public protocol RequestType {
    associatedtype Response: Decodable
    associatedtype Body: Encodable
    associatedtype PathComponent
    associatedtype Parameters
}

public extension RequestType {
    typealias Response = Empty
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


public protocol EnvironmentType {
    var baseUrl: URL { get }
}

public struct Endpoint<T: RequestType> {
    public let method: Method
    public let path: PathTemplate<T.PathComponent>
    public let body: T.Body
    public let parameters: [Parameter<T.Parameters>]
    public let headers: [String: PathTemplate<T.Parameters>]

    public func request(in environment: EnvironmentType, pathComponents: T.PathComponent, body: T.Body, parameters: T.Parameters) throws -> URLRequest {

        var components = URLComponents()
        components.path = path.path(with: pathComponents)

        let urlQueryItems: [URLQueryItem] = try self.parameters.compactMap { item in

            guard case .query(let key, let valuePath) = item else { return nil }

            let value = parameters[keyPath: valuePath]

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

            let value = parameters[keyPath: valuePath]

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

        var request = URLRequest(url: url)
        request.httpMethod = method.methodString

        for header in headers {
            request.addValue(header.value.path(with: parameters), forHTTPHeaderField: header.key)
        }


        request.url = url

        if !(body is Empty) {

            let encoder: JSONEncoder
            if let bodyType = body as? JSONEncoderProvider {
                encoder = type(of: bodyType).jsonEncoder
            } else {
                encoder = JSONEncoder()
            }

            request.httpBody = try encoder.encode(body)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if !bodyFormItems.isEmpty {
            request.httpBody = bodyFormItems.formString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        return request
    }
}

extension Endpoint where T.Body == Empty {
    public func request(in environment: EnvironmentType, pathComponents: T.PathComponent, parameters: T.Parameters) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: pathComponents, body: Empty(), parameters: parameters)
    }
}

extension Endpoint where T.Parameters == Empty {
    public func request(in environment: EnvironmentType, pathComponents: T.PathComponent, body: T.Body) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: pathComponents, body: body, parameters: Empty())
    }
}

extension Endpoint where T.Parameters == Empty, T.Body == Empty {
    public func request(in environment: EnvironmentType, pathComponents: T.PathComponent) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: pathComponents, body: Empty(), parameters: Empty())
    }
}

extension Endpoint where T.Body == Empty, T.PathComponent == Empty {
    public func request(in environment: EnvironmentType, parameters: T.Parameters) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: Empty(), body: Empty(), parameters: parameters)
    }
}

extension Endpoint where T.Parameters == Empty, T.PathComponent == Empty {
    public func request(in environment: EnvironmentType, body: T.Body) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: Empty(), body: body, parameters: Empty())
    }
}

extension Endpoint where T.Parameters == Empty, T.Body == Empty, T.PathComponent == Empty {
    public func request(in environment: EnvironmentType) throws -> URLRequest {
        return try self.request(in: environment, pathComponents: Empty(), body: Empty(), parameters: Empty())
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
    init(method: Method, path: PathTemplate<T.PathComponent>, parameters: [Parameter<T.Parameters>] = [], headers: [String: PathTemplate<T.Parameters>] = [:]) {
        self.method = method
        self.path = path
        self.body = Empty()
        self.parameters = parameters
        self.headers = headers
    }
}
