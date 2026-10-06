//
//  MockContinuation.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import Foundation

/// How a mocked request responds.
///
/// - `.return(value)`: The request returns `value`.
/// - `.fail(errorResponse)`: The request throws ``EndpointTaskError/errorResponse(httpResponse:response:)``.
/// - `.throw(error)`: The request throws `error`.
/// - `.none`: The request is sent to the network. With `endpointTask(with:completion:)`,
///   the request isn't sent and the completion handler isn't called.
public enum MockAction<Value: Sendable, ErrorResponse: Sendable>: Sendable {
    case none
    case `return`(Value)
    case fail(ErrorResponse)
    case `throw`(EndpointTaskError<ErrorResponse>)
}

/// Sets the response for one mocked request.
///
/// `withMock` passes a continuation to your closure for each request. Call one of the
/// `resume` methods. If you call none, the mock acts as ``MockAction/none``.
///
/// ```swift
/// try await withMock(MyEndpoint.self) { continuation in
///     continuation.resume(returning: .init(name: "Zac"))
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

    /// Returns `value` from the request.
    /// - Parameter value: The response to return.
    public func resume(returning value: T.Response) {
        action = .return(value)
    }

    /// Throws ``EndpointTaskError/errorResponse(httpResponse:response:)`` with `error`.
    ///
    /// The error's `httpResponse` is a placeholder with status code 200.
    /// - Parameter error: The decoded error response.
    public func resume(failingWith error: T.ErrorResponse) {
        action = .fail(error)
    }

    /// Throws `error` from the request, such as ``EndpointTaskError/internetConnectionOffline``.
    /// - Parameter error: The error to throw.
    public func resume(throwing error: EndpointTaskError<T.ErrorResponse>) where T.ErrorResponse: Sendable {
        action = .throw(error)
    }

    /// Responds with `action`.
    /// - Parameter action: The action to perform.
    public func resume(with action: MockAction<T.Response, T.ErrorResponse>) {
        self.action = action
    }
}

#endif
