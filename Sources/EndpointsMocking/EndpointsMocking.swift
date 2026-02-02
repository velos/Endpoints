//
//  EndpointsMocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation
@testable import Endpoints

/// Executes a test block with mocking enabled for the specified endpoint type.
///
/// Use this function to intercept network requests and provide mock responses instead of
/// making actual network calls. The mock applies to all requests of the specified endpoint
/// type within the test block.
///
/// ```swift
/// try await withMock(MyEndpoint.self) { continuation in
///     continuation.resume(returning: .init(userId: "123", name: "Test"))
/// } test: {
///     let response = try await URLSession.shared.response(with: MyEndpoint())
///     #expect(response.userId == "123")
/// }
/// ```
///
/// - Parameters:
///   - ofType: The endpoint type to mock
///   - body: A closure that receives a ``MockContinuation`` to configure the mock response
///   - test: The test code that will execute with mocking enabled
/// - Returns: The value returned by the test block
public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await Mocking.shared.withMock(T.self, body, test: test)
}

/// Executes a test block with a pre-configured mock action.
///
/// This is a convenience variant that accepts a ``MockAction`` directly instead of a closure.
/// Use this for simple cases where you don't need dynamic response generation.
///
/// ```swift
/// try await withMock(MyEndpoint.self, action: .return(.init(userId: "123", name: "Test"))) {
///     let response = try await URLSession.shared.response(with: MyEndpoint())
///     #expect(response.name == "Test")
/// }
/// ```
///
/// - Parameters:
///   - ofType: The endpoint type to mock
///   - action: The mock action to perform (return, fail, throw, or none)
///   - test: The test code that will execute with mocking enabled
/// - Returns: The value returned by the test block
public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, action: MockAction<T.Response, T.ErrorResponse>, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await Mocking.shared.withMock(T.self, { continuation in
        switch action {
        case .none:
            return
        case .fail(let errorResponse):
            continuation.resume(failingWith: errorResponse)
        case .return(let value):
            continuation.resume(returning: value)
        case .throw(let error):
            continuation.resume(throwing: error)
        }
    }, test: test)
}
