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
    case form(String, path: PartialKeyPath<T>)
    case formValue(String, value: PathRepresentable)
    case query(String, path: PartialKeyPath<T>)
    case queryValue(String, value: PathRepresentable)
}

public enum HeaderField<T> {
    case field(path: PartialKeyPath<T>)
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

/// The `Response` is an associated type which defines the response from the server. Note that this is just type information which helpers, such as the built-in `URLSession` extensions, can use to know how to handle particular types. For instance, if this type conforms to `Decodable`, then a JSON decoder is used on the data coming from the server. If it's typealiased to `Void`, then the extension can know to ignore the response. If it's `Data`, then it can deliver the response data unmodified.
/// An `ErrorResponse` type can be associated to define what value conforming to `Decodable` to use when parsing an error response from the server. This can be useful if your server returns a different JSON structure when there's an error versus a success. Often in a project, this can be defined globally and `typealias` can be used to associate this global type on all `RequestType`s.
/// 
///
///
public protocol RequestType {
    associatedtype Response
    associatedtype ErrorResponse: Decodable = EmptyResponse

    associatedtype Body: Encodable = EmptyResponse
    associatedtype PathComponents = Void
    associatedtype Parameters = Void
    associatedtype HeaderValues = Void

    associatedtype BodyEncoder: EncoderType = JSONEncoder
    associatedtype ErrorDecoder: DecoderType = JSONDecoder
    associatedtype ResponseDecoder: DecoderType = JSONDecoder

    /// The instance of the associated `Body` type. Must be `Encodable`.
    var body: Body { get }

    /// The instance of the associated `PathComponents` type. Used for filling in request data into the path template of the endpoint.
    /// If none are necessary, this can be `Void`
    var pathComponents: PathComponents { get }

    /// The instance of the associated `Parameters` type. Used for filling in request data into the query and form parameters of the endpoint.
    var parameters: Parameters { get }

    /// The instance of the associated `Headers` type. Used for filling in request data into the headers of the endpoint.
    var headerValues: HeaderValues { get }

    /// The decoder instance to use when decoding the associated `Body` type
    static var bodyEncoder: BodyEncoder { get }

    /// The decoder instance to use when decoding the associated `ErrorResponse` type
    static var errorDecoder: ErrorDecoder { get }

    /// The decoder instance to use when decoding the associated `Response` type
    static var responseDecoder: ResponseDecoder { get }

    static var endpoint: Endpoint<Self> { get }
}

extension RequestType {

    /// Generates a `URLRequest` given the associated request value.
    /// - Parameter environment: The environment in which to create the request
    /// - Throws: An `EndpointError` which describes the error filling in data to the associated `Endpoint`.
    /// - Returns: A `URLRequest` ready for requesting with all values from `self` filled in according to the associated `Endpoint`.
    public func urlRequest(in environment: EnvironmentType) throws -> URLRequest {

        var components = URLComponents()
        components.path = Self.endpoint.path.path(with: pathComponents)

        let urlQueryItems: [URLQueryItem] = try Self.endpoint.parameters.compactMap { item in

            let value: Any
            let name: String
            switch item {
            case .query(let queryName, let valuePath):
                value = parameters[keyPath: valuePath]
                name = queryName
            case .queryValue(let queryName, let queryValue):
                value = queryValue
                name = queryName
            default:
                return nil
            }

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidQuery(named: name, type: type(of: value))
            }

            if let encodedValue = queryValue.parameterValue {
                return URLQueryItem(name: name, value: encodedValue)
            }

            return nil
        }

        let bodyFormItems: [URLQueryItem] = try Self.endpoint.parameters.compactMap { item in

            let value: Any
            let name: String
            switch item {
            case .form(let formName, let valuePath):
                value = parameters[keyPath: valuePath]
                name = formName
            case .formValue(let formName, let formValue):
                value = formValue
                name = formName
            default:
                return nil
            }

            guard let formValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidForm(named: name, type: type(of: value))
            }

            if let encodedValue = formValue.parameterValue {
                return URLQueryItem(name: name, value: encodedValue)
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
        urlRequest.httpMethod = Self.endpoint.method.methodString

        let headerItems: [String: String] = try Self.endpoint.headers.reduce(into: [:]) { allHeaders, field in
            let value: Any
            let name = field.key.name

            switch field.value {
            case .field(let valuePath):
                value = headerValues[keyPath: valuePath]
            case .fieldValue(let fieldValue):
                value = fieldValue
            }

            guard let headerValue = value as? CustomStringConvertible else {
                throw EndpointError.invalidHeader(named: name, type: type(of: value))
            }

            allHeaders[name] = headerValue.description
        }

        for (name, value) in headerItems {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        urlRequest.url = url

        if !(body is EmptyResponse) {
            do {
                urlRequest.httpBody = try Self.bodyEncoder.encode(body)
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

public extension RequestType where Body == EmptyResponse {
    var body: Body { return EmptyResponse() }
}

public extension RequestType where PathComponents == Void {
    var pathComponents: PathComponents { return () }
}

public extension RequestType where Parameters == Void {
    var parameters: Parameters { return () }
}

public extension RequestType where HeaderValues == Void {
    var headerValues: HeaderValues { return () }
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

public extension RequestType where ResponseDecoder == JSONDecoder {
    static var responseDecoder: ResponseDecoder {
        return JSONDecoder()
    }
}

public extension RequestType where ErrorDecoder == JSONDecoder {
    static var errorDecoder: ErrorDecoder {
        return JSONDecoder()
    }
}
public extension RequestType where BodyEncoder == JSONEncoder {
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

public struct Endpoint<T: RequestType> {

    /// The HTTP method of the Endpoint
    public let method: Method
    /// A template including all elements that appear in the path
    public let path: PathTemplate<T.PathComponents>
    /// The parameters (form and query) that are included in the Endpoint
    public let parameters: [Parameter<T.Parameters>]
    /// The headers that are included in the Endpoint
    public let headers: [Headers: HeaderField<T.HeaderValues>]

    /// Initializes an Endpoint with the given properties, defining all dynamic pieces as type-safe parameters.
    /// - Parameters:
    ///   - method: The HTTP method to use when fetching this Endpoint
    ///   - path: The path template representing the path and all path-related parameters
    ///   - parameters: The parameters passed to the endpoint. Either through query or form body.
    ///   - headerValues: The headers associated with this request
    public init(method: Method, path: PathTemplate<T.PathComponents>, parameters: [Parameter<T.Parameters>] = [], headers: [Headers: HeaderField<T.HeaderValues>] = [:]) {
        self.method = method
        self.path = path
        self.parameters = parameters
        self.headers = headers
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
