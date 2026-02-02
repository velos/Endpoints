//
//  Mocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

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

/// Internal mocking system that intercepts URLSession requests.
///
/// This type manages the mock state and coordinates between the `withMock` functions
/// and the URLSession task interception. It uses TaskLocal storage to track active mocks
/// and method swizzling to intercept data task resume calls.
struct Mocking {

    static let shared = Mocking()

    @TaskLocal
    static private var current: ToReturnWrapper?

    init() {
        // Initialize URLSession swizzling on first use
        URLSessionTask.classInit
    }

    /// Handles a mock request for the specified endpoint type (async/await version).
    /// - Parameter endpointsOfType: The endpoint type being requested
    /// - Returns: The mock response, or nil if no mock is active
    func handlMock<T: Endpoint>(for endpointsOfType: T.Type) async throws -> T.Response? {
        guard let action = await actionForMock(for: T.self) else {
            return nil
        }

        switch action {
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

    /// Sets up a mock context and executes the test block within it.
    /// - Parameters:
    ///   - ofType: The endpoint type to mock
    ///   - body: Closure that configures the mock response
    ///   - test: The test code to execute with mocking enabled
    func withMock<T: Endpoint, R: Sendable>(_ ofType: T.Type, _ body: @Sendable @escaping (MockContinuation<T>) async -> Void, test: @escaping () async throws -> R) async rethrows -> R {
        try await Self.$current.withValue(ToReturnWrapper(body)) {
            try await test()
        }
    }
}

extension Mocking {
    /// Checks if a mock is currently active for the given endpoint type.
    func shouldHandleMock<T: Endpoint>(for endpointsOfType: T.Type) -> Bool {
        Self.current != nil
    }

    /// Retrieves the mock action for the specified endpoint type.
    /// - Parameter endpointsOfType: The endpoint type being requested
    /// - Returns: The configured mock action, or nil if no mock is active
    func actionForMock<T: Endpoint>(for endpointsOfType: T.Type) async -> MockAction<T.Response, T.ErrorResponse>? {
        guard let current = Self.current else {
            return nil
        }

        let continuation = MockContinuation<T>()
        await current.toReturn(for: T.self)(continuation)
        return continuation.action
    }
}

#if canImport(Combine)
@preconcurrency import Combine

extension Mocking {
    /// Handles a mock request for Combine publishers.
    /// - Parameter endpointsOfType: The endpoint type being requested
    /// - Returns: A publisher that emits the mock response or error
    func handleMock<T: Endpoint>(for endpointsOfType: T.Type) -> AnyPublisher<T.Response?, T.TaskError> {
        guard shouldHandleMock(for: T.self) else {
            return Just(nil)
                .setFailureType(to: T.TaskError.self)
                .eraseToAnyPublisher()
        }

        let subject = CurrentValueSubject<T.Response?, T.TaskError>(nil)

        Task {
            guard let action = await actionForMock(for: T.self) else {
                subject.send(nil)
                return
            }

            switch action {
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
#endif

#endif
