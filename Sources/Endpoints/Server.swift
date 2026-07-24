//
//  Server.swift
//  Endpoints
//
//  Created by Zac White on 11/27/24.
//

import Foundation

/// Thread-safe storage for server environments.
/// Maps server types to their current environment values, allowing runtime switching.
///
/// Keyed by the server type — not its `Environments` type — so servers that share an
/// environment type (e.g. the default ``TypicalEnvironments``) switch independently.
enum EnvironmentStorage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var environments: [ObjectIdentifier: Any] = [:]

    static func getEnvironment<S: ServerDefinition>(for server: S.Type) -> S.Environments? {
        lock.lock()
        defer { lock.unlock() }
        let serverKey = ObjectIdentifier(server)
        return environments[serverKey] as? S.Environments
    }

    static func setEnvironment<S: ServerDefinition>(_ environment: S.Environments, for server: S.Type) {
        lock.lock()
        defer { lock.unlock() }
        let serverKey = ObjectIdentifier(server)
        environments[serverKey] = environment
    }
}

extension ServerDefinition {
    /// The current environment for this server type.
    /// 
    /// Use this property to switch environments at runtime. The value persists across
    /// all endpoints using this server type.
    ///
    /// ```swift
    /// // Switch to staging for all subsequent requests
    /// ApiServer.environment = .staging
    /// ```
    public static var environment: Self.Environments {
        get {
            EnvironmentStorage.getEnvironment(for: Self.self) ?? Self.defaultEnvironment
        }
        set {
            EnvironmentStorage.setEnvironment(newValue, for: Self.self)
        }
    }
}
