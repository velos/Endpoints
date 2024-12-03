//
//  File.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation
import XCTest
@testable import Endpoints

public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await MockingActor.shared.withMock(T.self, body, test: test)
}

public func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, action: MockAction<T.Response, T.ErrorResponse>, test: @Sendable @escaping () async throws -> R) async rethrows -> R {
    return try await MockingActor.shared.withMock(T.self, { continuation in
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
