//
//  URLSession+Combine.swift
//  Endpoints
//
//  Created by Zac White on 6/17/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(Combine)
import Combine

/// Bridges a single-value async operation into Combine.
///
/// Holds the in-flight `Task` so that cancelling the subscription cancels the work, and
/// carries the `Future` promise across the concurrency boundary under a lock. Combine's
/// promise type is not `Sendable`, which is why this is `@unchecked` rather than a plain
/// value type.
private final class AsyncBridge<Output: Sendable, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var promise: ((Result<Output, Failure>) -> Void)?
    private var task: Task<Void, Never>?

    /// Starts `work`, delivering its result to `promise` unless the subscription is
    /// cancelled first.
    func begin(
        promise: @escaping (Result<Output, Failure>) -> Void,
        work: @escaping @Sendable () async -> Result<Output, Failure>
    ) {
        lock.lock()
        self.promise = promise
        lock.unlock()

        let task = Task { [self] in
            deliver(await work())
        }

        lock.lock()
        if self.promise == nil {
            // Cancelled between starting and storing the task.
            lock.unlock()
            task.cancel()
        } else {
            self.task = task
            lock.unlock()
        }
    }

    private func deliver(_ result: Result<Output, Failure>) {
        lock.lock()
        let promise = self.promise
        self.promise = nil
        self.task = nil
        lock.unlock()

        promise?(result)
    }

    func cancel() {
        lock.lock()
        let task = self.task
        self.promise = nil
        self.task = nil
        lock.unlock()

        task?.cancel()
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
private func endpointPublisher<Output: Sendable, Failure: Error>(
    performing work: @escaping @Sendable () async throws(Failure) -> Output
) -> AnyPublisher<Output, Failure> {
    Deferred { () -> AnyPublisher<Output, Failure> in
        let bridge = AsyncBridge<Output, Failure>()
        return Future<Output, Failure> { promise in
            bridge.begin(promise: promise) {
                do throws(Failure) {
                    return .success(try await work())
                } catch {
                    return .failure(error)
                }
            }
        }
        .handleEvents(receiveCancel: { bridge.cancel() })
        .eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
public extension URLSession {

    /// Creates a publisher and starts the request for the given ``Definition``. This function does not expect a result value from the endpoint.
    ///
    /// The endpoint's ``Endpoint/Auth`` is applied to the request, and a failed request is
    /// retried after reauthentication when the method asks for it. Cancelling the
    /// subscription cancels the underlying request.
    /// - Parameters:
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Void {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint)
        }
    }

    /// Creates a publisher and starts the request for the given ``Definition``. This function expects a result value of `Data`.
    ///
    /// The endpoint's ``Endpoint/Auth`` is applied to the request, and a failed request is
    /// retried after reauthentication when the method asks for it. Cancelling the
    /// subscription cancels the underlying request.
    /// - Parameters:
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Data {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint)
        }
    }

    /// Creates a publisher and starts the request for the given ``Definition``. This function expects a result value which is `Decodable`.
    ///
    /// The endpoint's ``Endpoint/Auth`` is applied to the request, and a failed request is
    /// retried after reauthentication when the method asks for it. Cancelling the
    /// subscription cancels the underlying request.
    /// - Parameters:
    ///   - endpoint: The request data to insert into the ``Definition``
    /// - Returns: A `Publisher` which fetches the ``Endpoint``'s contents. Any failures when creating the request are sent as errors in the `Publisher`
    func endpointPublisher<T: Endpoint>(with endpoint: T) -> AnyPublisher<T.Response, T.TaskError> where T.Response: Decodable {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint)
        }
    }
}

#endif
