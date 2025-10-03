//
//  MockContinuation.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation

public enum MockAction<Value: Sendable, ErrorResponse: Sendable>: Sendable {
    case none
    case `return`(Value)
    case fail(ErrorResponse)
    case `throw`(EndpointTaskError<ErrorResponse>)
}

public class MockContinuation<T: Endpoint> where T.Response: Sendable {
    var action: MockAction<T.Response, T.ErrorResponse>

    init(_ type: T.Type) {
        self.action = .none
    }

    init(action: MockAction<T.Response, T.ErrorResponse> = .none) {
        self.action = action
    }

    public func resume(returning value: T.Response) {
        action = .return(value)
    }

    public func resume(failingWith error: T.ErrorResponse) {
        action = .fail(error)
    }

    public func resume(throwing error: EndpointTaskError<T.ErrorResponse>) where T.ErrorResponse: Sendable {
        action = .throw(error)
    }
}
