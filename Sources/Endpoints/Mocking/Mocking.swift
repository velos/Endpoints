//
//  Mocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Foundation

struct ToReturnWrapper: Sendable {
    private let toReturn: @Sendable (Any) async -> Void
    init<T: Endpoint>(_ toReturn: @Sendable @escaping (MockContinuation<T>) async -> Void) {
        self.toReturn = { value in
            await toReturn(value as! MockContinuation<T>)
        }
    }

    func toReturn<T: Endpoint>(for: T.Type) -> ((MockContinuation<T>) async -> Void) {
        return { continuation in
            await toReturn(continuation)
        }
    }
}

struct Mocking {

    static let shared = Mocking()

    @TaskLocal
    static private var current: ToReturnWrapper?

    init() {
        URLSessionTask.classInit
    }

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

extension Mocking {
    func shouldHandleMock<T: Endpoint>(for endpointsOfType: T.Type) -> Bool {
        Self.current != nil
    }

    func actionForMock<T: Endpoint>(for endpointsOfType: T.Type) async -> MockAction<T.Response, T.ErrorResponse>? {
        guard let current = Self.current else {
            return nil
        }

        let continuation = MockContinuation<T>()
        await current.toReturn(for: T.self)(continuation)
        return continuation.action
    }
}

@preconcurrency import Combine

extension Mocking {
    func handleMock<T: Endpoint>(for endpointsOfType: T.Type) -> AnyPublisher<T.Response?, T.TaskError> {
        guard let current = Self.current else {
            return Just(nil)
                .setFailureType(to: T.TaskError.self)
                .eraseToAnyPublisher()
        }

        let subject = CurrentValueSubject<T.Response?, T.TaskError>(nil)

        Task {
            let continuation = MockContinuation<T>()
            await current.toReturn(for: T.self)(continuation)
            switch continuation.action {
            case .none:
                subject.send(nil)
            case .return(let value):
                subject.send(value)
            case .fail(let errorResponse):
                subject.send(completion: .failure(T.TaskError.errorResponse(httpResponse: HTTPURLResponse(), response: errorResponse)))
            case .throw(let error):
                subject.send(completion: .failure(error))
            }
        }

        return subject
            .eraseToAnyPublisher()
    }
}
