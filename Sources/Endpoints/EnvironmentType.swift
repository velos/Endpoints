//
//  EnvironmentType.swift
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
/// Conform to this protocol to create a server definition that specifies
/// base URLs for different environments and request processing behavior.
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
    /// The environment type for this server. Defaults to ``TypicalEnvironments``.
    associatedtype Environments: Hashable = TypicalEnvironments

    /// Required initializer for creating server instances.
    init()

    /// Maps environments to their base URLs.
    var baseUrls: [Environments: URL] { get }

    /// Optional request processor to modify requests before sending.
    /// Use this to add authentication headers or signatures.
    var requestProcessor: (URLRequest) -> URLRequest { get }

    /// The default environment to use when none is explicitly set.
    static var defaultEnvironment: Environments { get }
}

public extension ServerDefinition {
    /// Default passthrough request processor that returns the request unchanged.
    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
}

struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://local-api.velos.com")!,
            .staging: URL(string: "https://staging-api.velos.com")!,
            .production: URL(string: "https://api.velos.com")!
        ]
    }

    static var defaultEnvironment: Environments {
        #if DEBUG
        .staging
        #else
        .production
        #endif
    }

    static let api = Self()
}

struct TestEndpoint: Endpoint {
    typealias Server = ApiServer
    typealias Response = Void
    static let definition: Definition<TestEndpoint> = Definition(server: ApiServer.api, method: .get, path: "/")
}

/// A generic server implementation that can be used as a default for simple endpoints.
/// Supports multiple environments (development, staging, production) with configurable base URLs.
public struct GenericServer: ServerDefinition {
    public let baseUrls: [Environments: URL]
    public let requestProcessor: @Sendable (URLRequest) -> URLRequest
    
    /// Creates a GenericServer with the given base URLs for different environments.
    /// - Parameters:
    ///   - local: URL for local development (optional)
    ///   - development: URL for development environment (optional)
    ///   - staging: URL for staging environment (optional)
    ///   - production: URL for production environment (optional)
    ///   - requestProcessor: Optional request processor for modifying requests (default: passthrough)
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
    
    /// Creates a GenericServer with a single base URL used for all environments.
    /// - Parameters:
    ///   - baseUrl: The base URL to use for all environments
    ///   - requestProcessor: Optional request processor for modifying requests (default: passthrough)
    public init(baseUrl: URL, requestProcessor: @Sendable @escaping (URLRequest) -> URLRequest = { $0 }) {
        self.baseUrls = [
            .local: baseUrl,
            .development: baseUrl,
            .staging: baseUrl,
            .production: baseUrl
        ]
        self.requestProcessor = requestProcessor
    }
    
    /// Required parameterless initializer for ServerDefinition conformance.
    /// Creates a GenericServer with no base URLs configured.
    /// Note: You must set base URLs using the `baseUrls` property or use a different initializer.
    public init() {
        self.baseUrls = [:]
        self.requestProcessor = { $0 }
    }
    
    public static var defaultEnvironment: Environments { .production }
}
