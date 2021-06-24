//
//  Definition.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
public struct EmptyCodable: Codable { }

public protocol EncoderType {
    func encode<T: Encodable>(_ value: T) throws -> Data
}

extension JSONEncoder: EncoderType { }

public protocol DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

extension JSONDecoder: DecoderType { }

/// The `Response` is an associated type which defines the response from the server. Note that this is just type information which helpers, such as the built-in
/// `URLSession` extensions, can use to know how to handle particular types. For instance, if this type conforms to `Decodable`, then a JSON decoder is used
/// on the data coming from the server. If it's typealiased to `Void`, then the extension can know to ignore the response. If it's `Data`, then it can deliver the
/// response data unmodified.
///
/// An `ErrorResponse` type can be associated to define what value conforming to `Decodable` to use when parsing an error response from the server.
/// This can be useful if your server returns a different JSON structure when there's an error versus a success. Often in a project, this can be defined globally
/// and `typealias` can be used to associate this global type on all `Endpoint`s.
public protocol Endpoint {
    associatedtype Response
    associatedtype ErrorResponse: Decodable = EmptyCodable

    associatedtype Body: Encodable = EmptyCodable
    associatedtype PathComponents = Void
    associatedtype ParameterComponents = Void
    associatedtype HeaderComponents = Void

    associatedtype BodyEncoder: EncoderType = JSONEncoder
    associatedtype ErrorDecoder: DecoderType = JSONDecoder
    associatedtype ResponseDecoder: DecoderType = JSONDecoder

    /// A `Definition` which pieces together all the components defined in the endpoint.
    static var definition: Definition<Self> { get }

    /// The instance of the associated `Body` type. Must be `Encodable`.
    var body: Body { get }

    /// The instance of the associated `PathComponents` type. Used for filling in request data into the path template of the endpoint.
    /// If none are necessary, this can be `Void`
    var pathComponents: PathComponents { get }

    /// The instance of the associated `ParameterComponents` type. Used for filling in request data into the query and form parameters of the endpoint.
    var parameterComponents: ParameterComponents { get }

    /// The instance of the associated `HeaderComponents` type. Used for filling in request data into the headers of the endpoint.
    var headerComponents: HeaderComponents { get }

    /// The decoder instance to use when decoding the associated `Body` type
    static var bodyEncoder: BodyEncoder { get }

    /// The decoder instance to use when decoding the associated `ErrorResponse` type
    static var errorDecoder: ErrorDecoder { get }

    /// The decoder instance to use when decoding the associated `Response` type
    static var responseDecoder: ResponseDecoder { get }
}

public extension Endpoint where Body == EmptyCodable {
    var body: Body { return EmptyCodable() }
}

public extension Endpoint where PathComponents == Void {
    var pathComponents: PathComponents { return () }
}

public extension Endpoint where ParameterComponents == Void {
    var parameterComponents: ParameterComponents { return () }
}

public extension Endpoint where HeaderComponents == Void {
    var headerComponents: HeaderComponents { return () }
}

public extension Endpoint where ResponseDecoder == JSONDecoder {
    static var responseDecoder: ResponseDecoder {
        return JSONDecoder()
    }
}

public extension Endpoint where ErrorDecoder == JSONDecoder {
    static var errorDecoder: ErrorDecoder {
        return JSONDecoder()
    }
}
public extension Endpoint where BodyEncoder == JSONEncoder {
    static var bodyEncoder: BodyEncoder {
        return JSONEncoder()
    }
}

public struct Definition<T: Endpoint> {

    /// The HTTP method of the Endpoint
    public let method: Method
    /// A template including all elements that appear in the path
    public let path: PathTemplate<T.PathComponents>
    /// The parameters (form and query) that are included in the Definition
    public let parameters: [Parameter<T.ParameterComponents>]
    /// The headers that are included in the Definition
    public let headers: [Header: HeaderField<T.HeaderComponents>]

    /// Initializes a Definition with the given properties, defining all dynamic pieces as type-safe parameters.
    /// - Parameters:
    ///   - method: The HTTP method to use when fetching the owning Endpoint
    ///   - path: The path template representing the path and all path-related parameters
    ///   - parameters: The parameters passed to the endpoint. Either through query or form body.
    ///   - headerValues: The headers associated with this request
    public init(method: Method,
                path: PathTemplate<T.PathComponents>,
                parameters: [Parameter<T.ParameterComponents>] = [],
                headers: [Header: HeaderField<T.HeaderComponents>] = [:]) {
        self.method = method
        self.path = path
        self.parameters = parameters
        self.headers = headers
    }
}
