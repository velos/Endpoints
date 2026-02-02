//
//  Server.swift
//  Endpoints
//
//  Created by Zac White on 11/27/24.
//

import Foundation

/// Thread-safe storage for server environments.
/// Maps environment types to their current values, allowing runtime switching.
enum EnvironmentStorage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var environments: [ObjectIdentifier: Any] = [:]

    static func getEnvironment<T>(for type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        let typeKey = ObjectIdentifier(type)
        return environments[typeKey] as? T
    }

    static func setEnvironment<T>(_ environment: T, for type: T.Type) {
        lock.lock()
        defer { lock.unlock() }
        let typeKey = ObjectIdentifier(type)
        environments[typeKey] = environment
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
            EnvironmentStorage.getEnvironment(for: Self.Environments.self) ?? Self.defaultEnvironment
        }
        set {
            EnvironmentStorage.setEnvironment(newValue, for: Self.Environments.self)
        }
    }
}
