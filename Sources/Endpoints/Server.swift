//
//  Server.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Standard environment types used by most servers.
///
/// Use these as a starting point, or define your own environment enum.
public enum TypicalEnvironments: String, CaseIterable, Sendable {
    case local
    case development
    case staging
    case production
}

/// Defines the server configuration for endpoints.
///
/// A server lists a base URL for each environment, the authentication method its
/// endpoints share, and an optional request processor.
///
/// Each request chooses its environment with the `environment:` argument of the
/// `URLSession` methods or ``Endpoint/urlRequest(in:)``. The environment isn't global
/// state, so concurrent requests can use different environments.
/// ``defaultEnvironment`` is used when a request doesn't choose one.
///
/// Credentials usually belong to one environment: a token issued by staging isn't
/// valid against production. A server-wide ``auth`` fits an app that talks to one
/// environment at a time. An app that switches environments should pass matching
/// credentials with each request's `auth:` argument, and doesn't need to declare
/// ``auth``.
///
/// ```swift
/// struct ApiServer: ServerDefinition {
///     var baseUrls: [Environments: URL] {
///         return [
///             .staging: URL(string: "https://staging-api.example.com")!,
///             .production: URL(string: "https://api.example.com")!
///         ]
///     }
///
///     static var defaultEnvironment: Environments { .production }
/// }
/// ```
public protocol ServerDefinition: Sendable {
    /// The server's environments. Defaults to ``TypicalEnvironments``.
    associatedtype Environments: Hashable & Sendable = TypicalEnvironments

    /// The type of ``auth``. Defaults to ``NoAuth``.
    associatedtype Auth: AuthenticationMethod = NoAuth

    /// Creates the server. ``Definition`` uses this when an endpoint doesn't pass a server.
    init()

    /// The base URL for each environment. A request for an environment with no entry
    /// fails with ``EndpointError/misconfiguredServer(server:)``.
    var baseUrls: [Environments: URL] { get }

    /// Changes each request after it is built. Defaults to returning the request unchanged.
    ///
    /// Use it for static changes, such as adding a build-number header. Use ``auth``
    /// for credentials.
    var requestProcessor: @Sendable (URLRequest) -> URLRequest { get }

    /// The authentication method shared by all endpoints on this server.
    ///
    /// Declare it with `static let`, so every endpoint uses the same instance. A stateful
    /// method such as ``JWTAuth`` needs that to keep its tokens and to combine concurrent
    /// refreshes.
    ///
    /// ```swift
    /// struct ApiServer: ServerDefinition {
    ///     static let auth = JWTAuth(initialTokens: loadTokens(), refreshHandler: refresh)
    ///     ...
    /// }
    /// ```
    static var auth: Auth { get }

    /// The environment a request uses when it doesn't choose one.
    static var defaultEnvironment: Environments { get }
}

public extension ServerDefinition {
    /// Returns the request unchanged.
    var requestProcessor: @Sendable (URLRequest) -> URLRequest { return { $0 } }
}

public extension ServerDefinition where Auth == NoAuth {
    /// Servers are unauthenticated unless they declare an authentication method.
    static var auth: NoAuth { return NoAuth() }
}

/// A server configured with base URLs at runtime.
///
/// Endpoints that don't name a server use this type. Pass a configured instance to
/// ``Definition/init(server:method:path:parameters:headers:)``.
public struct GenericServer: ServerDefinition {
    public let baseUrls: [Environments: URL]
    public let requestProcessor: @Sendable (URLRequest) -> URLRequest

    /// Creates a server with a base URL for each environment you pass.
    /// - Parameters:
    ///   - local: The base URL for ``TypicalEnvironments/local``.
    ///   - development: The base URL for ``TypicalEnvironments/development``.
    ///   - staging: The base URL for ``TypicalEnvironments/staging``.
    ///   - production: The base URL for ``TypicalEnvironments/production``.
    ///   - requestProcessor: Changes each request after it is built.
    public init(
        local: URL? = nil,
        development: URL? = nil,
        staging: URL? = nil,
        production: URL? = nil,
        requestProcessor: @Sendable @escaping (URLRequest) -> URLRequest = { $0 }
    ) {
        var urls: [Environments: URL] = [:]
        if let local { urls[.local] = local }
        if let development { urls[.development] = development }
        if let staging { urls[.staging] = staging }
        if let production { urls[.production] = production }
        self.baseUrls = urls
        self.requestProcessor = requestProcessor
    }

    /// Creates a server that uses one base URL for every environment.
    /// - Parameters:
    ///   - baseUrl: The base URL.
    ///   - requestProcessor: Changes each request after it is built.
    public init(baseUrl: URL, requestProcessor: @Sendable @escaping (URLRequest) -> URLRequest = { $0 }) {
        self.baseUrls = [
            .local: baseUrl,
            .development: baseUrl,
            .staging: baseUrl,
            .production: baseUrl
        ]
        self.requestProcessor = requestProcessor
    }

    /// Creates a server with no base URLs.
    ///
    /// Every request built against it fails with
    /// ``EndpointError/misconfiguredServer(server:)``. Use one of the other initializers.
    public init() {
        self.baseUrls = [:]
        self.requestProcessor = { @Sendable in $0 }
    }

    public static var defaultEnvironment: Environments { .production }
}
