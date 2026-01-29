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
    static var contentType: String? { get }
    func encode<T: Encodable>(_ value: T) throws -> Data
}

public extension EncoderType {
    static var contentType: String? { nil }
}

extension JSONEncoder: EncoderType { }

extension JSONEncoder {
    public static var contentType: String? { "application/json" }
}

public protocol DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

extension JSONDecoder: DecoderType { }

public protocol Endpoint {

    /// The response type received from the server.
    ///
    /// This conveys type information which helpers, such as the built-in ``Foundation/URLSession`` extensions,
    /// can use to know how to handle particular types. For instance, if this type conforms to `Decodable`, then a JSON decoder is used
    /// on the data coming from the server. If it's typealiased to `Void`, then the extension can know to ignore the response. If it's `Data`, then it can deliver the
    /// response data unmodified.
    associatedtype Response

    /// The type representing the `Decodable` error response from the server. Defaults to an empty `Decodable` struct, ``EmptyCodable``.
    ///
    /// This can be useful if your server returns a different JSON structure when there's an error versus a success. Often in a project, this can be defined globally
    /// and `typealias` can be used to associate this global type on all ``Endpoint``s.
    associatedtype ErrorResponse: Decodable = EmptyCodable

    /// The body type conforming to `Encodable`. Defaults to ``EmptyCodable``.
    associatedtype Body: Encodable = EmptyCodable

    /// The values needed to fill the ``Definition``'s path.
    ///
    /// If a ``Endpoint/PathComponents`` type is associated, properties of that type can be utilized in the `path` of the ``Endpoint`` using a path string interpolation syntax:
    ///
    /// ```swift
    /// struct DeleteEndpoint: Endpoint {
    ///     static let definition: Definition<DeleteEndpoint> = Definition(
    ///         method: .delete,
    ///         path: "calendar/v3/calendars/\(path: \.calendarId)/events\(path: \.eventId)"
    ///     )
    ///
    ///     typealias Response = Void
    ///
    ///     struct PathComponents {
    ///         let calendarId: String
    ///         let eventId: String
    ///     }
    ///
    ///     let pathComponents: PathComponents
    /// }
    /// ```
    associatedtype PathComponents = Void

    /// The values needed to fill the ``Definition``'s parameters.
    ///
    /// A ``Endpoint/ParameterComponents`` type, in a similar way to ``Endpoint/PathComponents``, holds properties that can be referenced in the ``Endpoint`` via ``Parameter`` values  in order to define form parameters used in the body or query parameters attached to the URL. The enum type is defined as:
    ///
    /// ```swift
    /// public enum Parameter<T> {
    ///     case form(String, path: PartialKeyPath<T>)
    ///     case formValue(String, value: PathRepresentable)
    ///     case query(String, path: PartialKeyPath<T>)
    ///     case queryValue(String, value: PathRepresentable)
    /// }
    /// ```
    ///
    /// With this enum, either hard-coded values can be injected into the ``Endpoint`` (with ``Parameter/formValue(_:value:)`` or ``Parameter/queryValue(_:value:)``) or key paths can define which reference properties in the ``Endpoint/ParameterComponents`` associated type to define a form or query parameter that is needed at the time of the request.
    associatedtype ParameterComponents = Void

    /// The values needed to fill the ``Definition``'s headers.
    associatedtype HeaderComponents = Void

    /// The ``EncoderType`` to use when encoding the body of the request. Defaults to `JSONEncoder`.
    associatedtype BodyEncoder: EncoderType = JSONEncoder
    /// The ``DecoderType`` to use when decoding the body of the request. Defaults to `JSONDecoder`.
    associatedtype ErrorDecoder: DecoderType = JSONDecoder
    /// The ``DecoderType`` to use when decoding the response. Defaults to `JSONDecoder`.
    associatedtype ResponseDecoder: DecoderType = JSONDecoder

    /// A ``Definition`` which pieces together all the components defined in the endpoint.
    static var definition: Definition<Self> { get }

    /// The instance of the associated `Body` type. Must be `Encodable`.
    var body: Body { get }

    /// The instance of the associated ``Endpoint/PathComponents`` type. Used for filling in request data into the path template of the endpoint.
    /// If none are necessary, this can be `Void`
    var pathComponents: PathComponents { get }

    /// The instance of the associated ``Endpoint/ParameterComponents`` type. Used for filling in request data into the query and form parameters of the endpoint.
    var parameterComponents: ParameterComponents { get }

    /// The instance of the associated ``Endpoint/HeaderComponents`` type. Used for filling in request data into the headers of the endpoint.
    var headerComponents: HeaderComponents { get }

    /// The decoder instance to use when decoding the associated ``Endpoint/Body`` type
    static var bodyEncoder: BodyEncoder { get }

    /// The decoder instance to use when decoding the associated ``Endpoint/ErrorResponse`` type
    static var errorDecoder: ErrorDecoder { get }

    /// The decoder instance to use when decoding the associated ``Endpoint/Response`` type
    static var responseDecoder: ResponseDecoder { get }

    /// A strategy for encoding query parameters. Defaults to `QueryEncodingStrategy.default`
    static var queryEncodingStrategy: QueryEncodingStrategy { get }
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

public extension Endpoint {
    static var queryEncodingStrategy: QueryEncodingStrategy {
        return .default
    }
}

public enum QueryEncodingStrategy {
    case `default`
    case custom((URLQueryItem) -> (String, String?)?)
}

public struct Definition<T: Endpoint> {

    /// The HTTP method of the ``Endpoint``
    public let method: Method
    /// A template including all elements that appear in the path
    public let path: PathTemplate<T.PathComponents>
    /// The parameters (form and query) that are included in the ``Definition``
    public let parameters: [Parameter<T.ParameterComponents>]
    /// The headers that are included in the ``Definition``
    public let headers: [Header: HeaderField<T.HeaderComponents>]

    /// Initializes a ``Definition`` with the given properties, defining all dynamic pieces as type-safe parameters.
    /// - Parameters:
    ///   - method: The HTTP method to use when fetching the owning ``Endpoint``
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
