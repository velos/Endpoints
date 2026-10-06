//
//  Endpoint.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An error building a `URLRequest` from an ``Endpoint``.
public enum EndpointError: Error, Sendable {
    /// The path and query didn't form a valid URL relative to the base URL.
    case invalid(components: URLComponents, relativeTo: URL)
    /// A query parameter's value doesn't conform to ``ParameterRepresentable``.
    case invalidQuery(named: String, type: Any.Type)
    /// A form parameter's value doesn't conform to ``ParameterRepresentable``.
    case invalidForm(named: String, type: Any.Type)
    /// A header's value doesn't conform to `CustomStringConvertible`.
    case invalidHeader(named: String, type: Any.Type)
    /// The body encoder threw this error.
    case invalidBody(Error)
    /// The server has no base URL for the requested environment.
    case misconfiguredServer(server: any ServerDefinition)
}

/// A query or form parameter in a ``Definition``.
///
/// `T` is the endpoint's ``Endpoint/ParameterComponents`` type.
public enum Parameter<T>: Sendable {
    /// A form body parameter read from a property of the parameter components.
    case form(String, path: PartialKeyPath<T> & Sendable)
    /// A form body parameter with a fixed value.
    case formValue(String, value: PathRepresentable)
    /// A query parameter read from a property of the parameter components.
    case query(String, path: PartialKeyPath<T> & Sendable)
    /// A query parameter with a fixed value.
    case queryValue(String, value: PathRepresentable)
}

/// The value of a header in a ``Definition``.
///
/// `T` is the endpoint's ``Endpoint/HeaderComponents`` type.
public enum HeaderField<T>: Sendable {
    /// A value read from a property of the header components.
    case field(path: PartialKeyPath<T> & Sendable)
    /// A fixed value.
    case fieldValue(value: CustomStringConvertible & Sendable)
}

/// An empty value, used as the default ``Endpoint/Body`` and ``Endpoint/ErrorResponse``.
public struct EmptyCodable: Codable, Sendable { }

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

public protocol Endpoint: Sendable {

    associatedtype Server: ServerDefinition = GenericServer

    /// The type of a successful response.
    ///
    /// The `URLSession` methods decode a `Decodable` type with ``responseDecoder``,
    /// return the body unchanged for `Data`, and ignore the body for `Void`.
    associatedtype Response: Sendable

    /// The type of an error response body. Defaults to ``EmptyCodable``.
    ///
    /// A response with a status code outside 200–299 is decoded as this type with
    /// ``errorDecoder`` and thrown as ``EndpointTaskError/errorResponse(httpResponse:response:)``.
    /// If your endpoints share an error format, define the type once and refer to it
    /// with a `typealias` on each endpoint.
    associatedtype ErrorResponse: Decodable & Sendable = EmptyCodable

    /// The type of the request body, encoded with ``bodyEncoder``. Defaults to ``EmptyCodable``, which sends no body.
    associatedtype Body: Encodable = EmptyCodable

    /// The values that fill in the ``Definition``'s path. Defaults to `Void`.
    ///
    /// Refer to its properties in the path with `\(path:)` interpolation:
    ///
    /// ```swift
    /// struct DeleteEventEndpoint: Endpoint {
    ///     static let definition: Definition<DeleteEventEndpoint> = Definition(
    ///         method: .delete,
    ///         path: "calendars/\(path: \.calendarId)/events/\(path: \.eventId)"
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
    associatedtype PathComponents: Sendable = Void

    /// The values that fill in the ``Definition``'s query and form parameters. Defaults to `Void`.
    ///
    /// ``Parameter/query(_:path:)`` and ``Parameter/form(_:path:)`` read a property of
    /// this type. ``Parameter/queryValue(_:value:)`` and ``Parameter/formValue(_:value:)``
    /// send a fixed value instead. Properties must conform to ``ParameterRepresentable``,
    /// and `nil` values are left out of the request.
    associatedtype ParameterComponents: Sendable = Void

    /// The values that fill in the ``Definition``'s headers. Defaults to `Void`.
    associatedtype HeaderComponents: Sendable = Void

    /// The ``EncoderType`` to use when encoding the body of the request. Defaults to `JSONEncoder`.
    associatedtype BodyEncoder: EncoderType = JSONEncoder
    /// The ``DecoderType`` to use when decoding ``ErrorResponse``. Defaults to `JSONDecoder`.
    associatedtype ErrorDecoder: DecoderType = JSONDecoder
    /// The ``DecoderType`` to use when decoding the response. Defaults to `JSONDecoder`.
    associatedtype ResponseDecoder: DecoderType = JSONDecoder

    /// The ``AuthenticationMethod`` used to authenticate requests for this endpoint.
    ///
    /// Defaults to the server's method, which defaults to ``NoAuth``. Override it to opt
    /// out of the server's authentication, as on a login endpoint, or to use a different
    /// method:
    ///
    /// ```swift
    /// struct LoginEndpoint: Endpoint {
    ///     typealias Server = ApiServer
    ///     static var auth: NoAuth { NoAuth() }
    /// }
    /// ```
    associatedtype Auth: AuthenticationMethod = Server.Auth

    /// A ``Definition`` which pieces together all the components defined in the endpoint.
    static var definition: Definition<Self> { get }

    /// The request body.
    var body: Body { get }

    /// The values that fill in the path.
    var pathComponents: PathComponents { get }

    /// The values that fill in the query and form parameters.
    var parameterComponents: ParameterComponents { get }

    /// The values that fill in the headers.
    var headerComponents: HeaderComponents { get }

    /// The encoder for ``Body``.
    static var bodyEncoder: BodyEncoder { get }

    /// The decoder for ``ErrorResponse``.
    static var errorDecoder: ErrorDecoder { get }

    /// The decoder for ``Response``.
    static var responseDecoder: ResponseDecoder { get }

    /// The authentication method that authenticates requests for this endpoint.
    ///
    /// Defaults to ``ServerDefinition/auth``, so all endpoints on a server share one
    /// instance. A stateful method such as ``JWTAuth`` needs that shared instance to keep
    /// its tokens and to combine concurrent refreshes. Declare an override with `static let`.
    static var auth: Auth { get }

    /// How query parameters are percent-encoded. Defaults to ``QueryEncodingStrategy/default``.
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

public extension Endpoint where Auth == Server.Auth {
    /// Endpoints inherit their server's authentication method instance by default.
    static var auth: Auth {
        return Server.auth
    }
}

public extension Endpoint {
    static var queryEncodingStrategy: QueryEncodingStrategy {
        return .default
    }
}

/// How an endpoint percent-encodes its query parameters.
public enum QueryEncodingStrategy {
    /// The encoding `URLComponents` applies to `queryItems`.
    case `default`
    /// Encodes each query item with a closure that returns the percent-encoded name and
    /// value. Returning `nil`, or a `nil` value, leaves the item out.
    case custom((URLQueryItem) -> (String, String?)?)
}

public struct Definition<T: Endpoint>: Sendable {

    /// The server whose base URLs the endpoint's requests are built against.
    public let server: T.Server
    /// The HTTP method.
    public let method: Method
    /// The path, relative to the server's base URL.
    public let path: PathTemplate<T.PathComponents>
    /// The query and form parameters.
    public let parameters: [Parameter<T.ParameterComponents>]
    /// The headers.
    public let headers: [Header: HeaderField<T.HeaderComponents>]

    /// Creates a definition.
    /// - Parameters:
    ///   - server: The server to build requests against. Defaults to `T.Server()`.
    ///   - method: The HTTP method.
    ///   - path: The path, relative to the server's base URL.
    ///   - parameters: The query and form parameters.
    ///   - headers: The headers.
    public init(server: T.Server = T.Server(),
                method: Method,
                path: PathTemplate<T.PathComponents>,
                parameters: [Parameter<T.ParameterComponents>] = [],
                headers: [Header: HeaderField<T.HeaderComponents>] = [:]) {
        self.server = server
        self.method = method
        self.path = path
        self.parameters = parameters
        self.headers = headers
    }
}
