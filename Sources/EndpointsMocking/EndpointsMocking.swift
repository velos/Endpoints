//
//  EndpointsMocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation
@testable import Endpoints

/// Runs `test` with requests of an endpoint type answered by a closure.
///
/// `body` runs once per request of `ofType` made inside `test`, including from child
/// tasks. Requests of other endpoint types make real requests.
///
/// ```swift
/// try await withMock(MyEndpoint.self) { continuation in
///     continuation.resume(returning: .init(name: "Zac"))
/// } test: {
///     let response = try await URLSession.shared.response(with: MyEndpoint())
///     #expect(response.name == "Zac")
/// }
/// ```
///
/// - Parameters:
///   - ofType: The endpoint type to mock.
///   - body: A closure that sets the response on the `MockContinuation` it receives.
///   - test: The code to run with the mock in place.
/// - Returns: The value `test` returns.
public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await Mocking.shared.withMock(T.self, body, test: test)
}

/// Runs `test` with every request of an endpoint type answered by `action`.
///
/// ```swift
/// try await withMock(MyEndpoint.self, action: .return(.init(name: "Zac"))) {
///     let response = try await URLSession.shared.response(with: MyEndpoint())
///     #expect(response.name == "Zac")
/// }
/// ```
///
/// - Parameters:
///   - ofType: The endpoint type to mock.
///   - action: How the requests respond.
///   - test: The code to run with the mock in place.
/// - Returns: The value `test` returns.
public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, action: MockAction<T.Response, T.ErrorResponse>, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await Mocking.shared.withMock(T.self, { continuation in
        continuation.resume(with: action)
    }, test: test)
}

/// Runs `test` with mocks for several endpoint types.
///
/// Use this instead of nesting `withMock` calls when a flow uses several endpoints,
/// such as a request whose token refresh calls a second endpoint. Endpoint types
/// without a mock make real requests. Nested scopes combine, and an inner mock for the
/// same endpoint type replaces the outer one until the inner scope ends.
///
/// ```swift
/// try await withMock { mocks in
///     mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
///     mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
/// } test: {
///     let profile = try await URLSession.shared.response(with: ProfileEndpoint())
///     #expect(profile.name == "Zac")
/// }
/// ```
///
/// - Parameters:
///   - registering: A closure that registers mocks on the `MockRegistry` it receives.
///   - test: The code to run with the mocks in place.
/// - Returns: The value `test` returns.
public func withMock<R: Sendable>(registering: (MockRegistry) -> Void, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await Mocking.shared.withMock(registering: registering, test: test)
}
