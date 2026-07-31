//
//  MockRegistry.swift
//  Endpoints
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import Foundation

/// Collects mocks for multiple endpoint types within a single `withMock(registering:test:)` scope.
///
/// Register a mock per endpoint type — either a pre-configured ``MockAction`` or a
/// dynamic continuation-based closure. Endpoint types without a registered mock pass
/// through to the real transport. Registering the same endpoint type twice replaces
/// the earlier registration.
///
/// ```swift
/// try await withMock { mocks in
///     mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
///     mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
/// } test: {
///     let profile = try await session.response(with: ProfileEndpoint())
/// }
/// ```
public final class MockRegistry {
    var wrappers: [ObjectIdentifier: ToReturnWrapper] = [:]

    init() {}

    /// Registers a pre-configured mock action for an endpoint type.
    /// - Parameters:
    ///   - type: The endpoint type to mock
    ///   - action: The mock action to perform (return, fail, throw, or none)
    public func register<T: Endpoint>(_ type: T.Type, action: MockAction<T.Response, T.ErrorResponse>) {
        register(type) { continuation in
            continuation.resume(with: action)
        }
    }

    /// Registers a dynamic, continuation-based mock for an endpoint type.
    /// - Parameters:
    ///   - type: The endpoint type to mock
    ///   - body: A closure that receives a ``MockContinuation`` to configure the mock response
    public func register<T: Endpoint>(_ type: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void) {
        wrappers[ObjectIdentifier(type)] = ToReturnWrapper(body)
    }
}

#endif
