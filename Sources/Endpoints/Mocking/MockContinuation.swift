//
//  MockContinuation.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import Foundation

/// Actions that can be performed by a mock response.
///
/// Use these actions in the `withMock` closure to specify how the mock should respond:
/// - `.return(value)`: Return a successful response
/// - `.fail(errorResponse)`: Return a server error response
/// - `.throw(error)`: Throw a network or task error
/// - `.none`: Perform no action (pass through to actual request)
public enum MockAction<Value: Sendable, ErrorResponse: Sendable>: Sendable {
    case none
    case `return`(Value)
    case fail(ErrorResponse)
    case `throw`(EndpointTaskError<ErrorResponse>)
}

/// A continuation passed to the `withMock` closure to configure mock responses.
///
/// The continuation provides methods to specify what response or error should be returned
/// when the endpoint is requested. Call one of the `resume` methods to configure the mock.
///
/// ```swift
/// try await withMock(MyEndpoint.self) { continuation in
///     continuation.resume(returning: .init(userId: "123", name: "Test"))
/// } test: {
///     let response = try await URLSession.shared.response(with: MyEndpoint())
/// }
/// ```
public class MockContinuation<T: Endpoint> where T.Response: Sendable {
    var action: MockAction<T.Response, T.ErrorResponse>

    init(_ type: T.Type) {
        self.action = .none
    }

    init(action: MockAction<T.Response, T.ErrorResponse> = .none) {
        self.action = action
    }

    /// Resumes the mock with a successful response value.
    /// - Parameter value: The response value to return
    public func resume(returning value: T.Response) {
        action = .return(value)
    }

    /// Resumes the mock with an error response.
    /// Use this when the server returns a structured error.
    /// - Parameter error: The error response from the server
    public func resume(failingWith error: T.ErrorResponse) {
        action = .fail(error)
    }

    /// Resumes the mock by throwing a task error.
    /// Use this to simulate network failures or other request errors.
    /// - Parameter error: The error to throw
    public func resume(throwing error: EndpointTaskError<T.ErrorResponse>) where T.ErrorResponse: Sendable {
        action = .throw(error)
    }
}

#endif
