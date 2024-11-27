//
//  Server.swift
//  Endpoints
//
//  Created by Zac White on 11/27/24.
//

import Foundation

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
    public static var environment: Self.Environments {
        get {
            EnvironmentStorage.getEnvironment(for: Self.Environments.self) ?? Self.defaultEnvironment
        }
        set {
            EnvironmentStorage.setEnvironment(newValue, for: Self.Environments.self)
        }
    }
}
