//
//  MockingActor.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation

struct ToReturnWrapper: Sendable {
    private let toReturn: @Sendable (Any) async -> Void
    init<T: Endpoint>(_ toReturn: @Sendable @escaping (MockContinuation<T>) async -> Void) {
        self.toReturn = { @Sendable (value) in
            await toReturn(value as! MockContinuation<T>)
        }
    }

    func toReturn<T: Endpoint>(for: T.Type) -> ((MockContinuation<T>) async -> Void) {
        return { continuation in
            await toReturn(continuation)
        }
    }
}

actor MockingActor: Sendable {

    static let shared = MockingActor()

    @TaskLocal
    static private var current: ToReturnWrapper?

    func handlMock<T: Endpoint>(for endpointsOfType: T.Type) async throws -> T.Response? {
        guard let current = Self.current else { return .none }
        let continuation = MockContinuation<T>()
        await current.toReturn(for: T.self)(continuation)
        switch continuation.action {
        case .none:
            return nil
        case .return(let value):
            return value
        case .fail(let errorResponse):
            throw T.TaskError.errorResponse(httpResponse: HTTPURLResponse(), response: errorResponse)
        case .throw(let error):
            throw error
        }
    }

    func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void, test: @escaping () async throws -> R) async rethrows -> R {
        try await Self.$current.withValue(ToReturnWrapper(body)) {
            try await test()
        }
    }
}
