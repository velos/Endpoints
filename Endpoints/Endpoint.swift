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

    var body: Body { get }
    var pathComponents: PathComponent { get }
    var parameters: Parameters { get }

    associatedtype Response: Decodable
    associatedtype Body: Encodable
    associatedtype PathComponent
    associatedtype Parameters

    init(response: Response, body: Body, pathComponents: PathComponent, parameters: Parameters)
}

extension RequestType where Body == Empty {
    var body: Body {
        return Empty()
    }
}

extension RequestType where PathComponent == Empty {
    var pathComponents: PathComponent {
        return Empty()
    }
}

extension RequestType where Parameters == Empty {
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


public protocol EnvironmentType {
    var baseUrl: URL { get }
}

public struct Endpoint<T: RequestType> {
    public let method: Method
    public let path: PathTemplate<T.PathComponent>
    public let body: T.Body
    public let parameters: [Parameter<T.Parameters>]
    public let headers: [String: PathTemplate<T.Parameters>]

    public func request(with requestModel: T, in environment: EnvironmentType) throws -> URLRequest {

        var components = URLComponents()
        components.path = path.path(with: requestModel.pathComponents)

        let urlQueryItems: [URLQueryItem] = try parameters.compactMap { item in

            guard case .query(let key, let valuePath) = item else { return nil }

            let value = requestModel.parameters[keyPath: valuePath]

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidQuery(named: key, type: type(of: value))
            }

            if let query = queryValue.parameterValue {
                return URLQueryItem(name: key, value: query)
            }

            return nil
        }

        let bodyFormItems: [URLQueryItem] = try parameters.compactMap { item in

            guard case .form(let key, let valuePath) = item else { return nil }

            let value = requestModel.parameters[keyPath: valuePath]

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
        request.timeoutInterval = TimeInterval(30)

        for header in headers {
            request.addValue(header.value.path(with: requestModel.parameters), forHTTPHeaderField: header.key)
        }


        request.url = url

        if !bodyFormItems.isEmpty {
            request.httpBody = bodyFormItems.formString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        return request
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
