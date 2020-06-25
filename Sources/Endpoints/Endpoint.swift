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
    case invalidHeader(named: String, type: Any.Type)
    case invalidBody(Error)
}

public enum Parameter<T> {
    case form(key: String, value: PartialKeyPath<T>)
    case formValue(key: String, value: PathRepresentable)
    case query(key: String, value: PartialKeyPath<T>)
    case queryValue(key: String, value: PathRepresentable)
}

public enum FieldValue<T> {
    case field(value: PartialKeyPath<T>)
    case fieldValue(value: CustomStringConvertible)
}

/// A placeholder type for representing empty encodable or decodable Body values and ErrorResponse values.
public struct EmptyResponse: Codable { }

public protocol EncoderType {
    func encode<T: Encodable>(_ value: T) throws -> Data
}

extension JSONEncoder: EncoderType { }

public protocol DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

extension JSONDecoder: DecoderType { }

public protocol RequestDataType {
    associatedtype Response
    associatedtype ErrorResponse: Decodable = EmptyResponse

    associatedtype Body: Encodable = EmptyResponse
    associatedtype PathComponents = Void
    associatedtype Parameters = Void
    associatedtype Headers = Void

    associatedtype BodyEncoder: EncoderType = JSONEncoder
    associatedtype ErrorDecoder: DecoderType = JSONDecoder
    associatedtype ResponseDecoder: DecoderType = JSONDecoder

    var body: Body { get }
    var pathComponents: PathComponents { get }
    var parameters: Parameters { get }
    var headers: Headers { get }

    static var bodyEncoder: BodyEncoder { get }
    static var errorDecoder: ErrorDecoder { get }
    static var responseDecoder: ResponseDecoder { get }
}

public extension RequestDataType where Body == EmptyResponse {
    var body: Body { return EmptyResponse() }
}

public extension RequestDataType where PathComponents == Void {
    var pathComponents: PathComponents { return () }
}

public extension RequestDataType where Parameters == Void {
    var parameters: Parameters { return () }
}

public extension RequestDataType where Headers == Void {
    var headers: Headers { return () }
}

/// The HTTP Method
public enum Method {
    case options
    case get
    case head
    case post
    case put
    case patch
    case delete
    case trace
    case connect

    public var methodString: String {
        switch self {
        case .options: return "OPTIONS"
        case .get: return "GET"
        case .head: return "HEAD"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        case .trace: return "TRACE"
        case .connect: return "CONNECT"
        }
    }
}

public extension RequestDataType where ResponseDecoder == JSONDecoder {
    static var responseDecoder: ResponseDecoder {
        return JSONDecoder()
    }
}

public extension RequestDataType where ErrorDecoder == JSONDecoder {
    static var errorDecoder: ErrorDecoder {
        return JSONDecoder()
    }
}
public extension RequestDataType where BodyEncoder == JSONEncoder {
    static var bodyEncoder: BodyEncoder {
        return JSONEncoder()
    }
}

public protocol EnvironmentType {
    /// The baseUrl of the Environment
    var baseUrl: URL { get }
    /// Processes the built URLRequest right before sending in order to attach any Environment related authentication or data to the outbound request
    var requestProcessor: (URLRequest) -> URLRequest { get }
}

public extension EnvironmentType {
    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
}

public struct Endpoint<T: RequestDataType> {

    /// The HTTP method of the Endpoint
    public let method: Method
    /// A template including all elements that appear in the path
    public let path: PathTemplate<T.PathComponents>
    /// The parameters (form and query) that are included in the Endpoint
    public let parameters: [Parameter<T.Parameters>]
    /// The headers that are included in the Endpoint
    public let headers: [Headers: FieldValue<T.Headers>]

    /// Initializes an Endpoint with the given properties, defining all dynamic pieces as type-safe parameters.
    /// - Parameters:
    ///   - method: The HTTP method to use when fetching this Endpoint
    ///   - path: The path template representing the path and all path-related parameters
    ///   - parameters: The parameters passed to the endpoint. Either through query or form body.
    ///   - headers: The headers associated with this request
    public init(method: Method, path: PathTemplate<T.PathComponents>, parameters: [Parameter<T.Parameters>] = [], headers: [Headers: FieldValue<T.Headers>] = [:]) {
        self.method = method
        self.path = path
        self.parameters = parameters
        self.headers = headers
    }

    /// Generates a `URLRequest` given the associated request value. Throws an `EndpointError` if the request is invalid.
    /// - Parameters:
    ///   - environment: The environment in which to create the request
    ///   - request: The associated request value to use to fill in call-time pieces of the Endpoint
    public func request(in environment: EnvironmentType, for request: T) throws -> URLRequest {

        var components = URLComponents()
        components.path = path.path(with: request.pathComponents)

        let urlQueryItems: [URLQueryItem] = try self.parameters.compactMap { item in

            let value: Any
            let key: String
            switch item {
            case .query(let queryKey, let valuePath):
                value = request.parameters[keyPath: valuePath]
                key = queryKey
            case .queryValue(let queryKey, let queryValue):
                value = queryValue
                key = queryKey
            default:
                return nil
            }

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidQuery(named: key, type: type(of: value))
            }

            if let query = queryValue.parameterValue {
                return URLQueryItem(name: key, value: query)
            }

            return nil
        }

        let bodyFormItems: [URLQueryItem] = try self.parameters.compactMap { item in

            let value: Any
            let key: String
            switch item {
            case .form(let formKey, let valuePath):
                value = request.parameters[keyPath: valuePath]
                key = formKey
            case .formValue(let formKey, let formValue):
                value = formValue
                key = formKey
            default:
                return nil
            }

            guard let formValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidForm(named: key, type: type(of: value))
            }

            if let form = formValue.parameterValue {
                return URLQueryItem(name: key, value: form)
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

        let headerItems: [String: String] = try self.headers.reduce(into: [:]) { allHeaders, field in
            let value: Any
            let key = field.key.description

            switch field.value {
            case .field(let valuePath):
                value = request.headers[keyPath: valuePath]
            case .fieldValue(let fieldValue):
                value = fieldValue
            }

            guard let headerValue = value as? CustomStringConvertible else {
                throw EndpointError.invalidHeader(named: key, type: type(of: value))
            }

            allHeaders[key] = headerValue.description
        }

        for (key, value) in headerItems {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        urlRequest.url = url

        if !(request.body is EmptyResponse) {
            do {
                urlRequest.httpBody = try T.bodyEncoder.encode(request.body)
            } catch {
                throw EndpointError.invalidBody(error)
            }

            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if !bodyFormItems.isEmpty {
            urlRequest.httpBody = bodyFormItems.formString.data(using: .utf8)
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        urlRequest = environment.requestProcessor(urlRequest)

        return urlRequest
    }
}

extension Array where Element == URLQueryItem {

    /// Goes through each URLQueryItem element and joins them with a '&',
    /// suitable for putting into the httpBody of a request
    public var formString: String {
        return map { item in
            let name = item.name.pathSafe
            let value = item.value?.pathSafe ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }
}
