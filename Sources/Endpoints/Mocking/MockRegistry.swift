//
//  MockRegistry.swift
//  Endpoints
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import Foundation

/// Collects mocks for several endpoint types in one `withMock(registering:test:)` scope.
///
/// Register a ``MockAction`` or a closure for each endpoint type. Endpoint types
/// without a mock make real requests. Registering a type again replaces its mock.
///
/// ```swift
/// try await withMock { mocks in
///     mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
///     mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
/// } test: {
///     let profile = try await URLSession.shared.response(with: ProfileEndpoint())
/// }
/// ```
public final class MockRegistry {
    var wrappers: [ObjectIdentifier: ToReturnWrapper] = [:]

    init() {}

    /// Mocks every request of `type` with `action`.
    /// - Parameters:
    ///   - type: The endpoint type to mock.
    ///   - action: How the requests respond.
    public func register<T: Endpoint>(_ type: T.Type, action: MockAction<T.Response, T.ErrorResponse>) {
        register(type) { continuation in
            continuation.resume(with: action)
        }
    }

    /// Mocks every request of `type` with a closure that runs once per request.
    /// - Parameters:
    ///   - type: The endpoint type to mock.
    ///   - body: A closure that sets the response on the ``MockContinuation`` it receives.
    public func register<T: Endpoint>(_ type: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void) {
        wrappers[ObjectIdentifier(type)] = ToReturnWrapper(body)
    }
}

#endif
