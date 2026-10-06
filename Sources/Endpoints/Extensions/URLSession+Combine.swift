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
/// Holds the in-flight `Task` so that canceling the subscription cancels the work, and
/// carries the `Future` promise across the concurrency boundary under a lock. Combine's
/// promise type is not `Sendable`, which is why this is `@unchecked` rather than a plain
/// value type.
private final class AsyncBridge<Output: Sendable, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var promise: ((Result<Output, Failure>) -> Void)?
    private var task: Task<Void, Never>?

    /// Starts `work`, delivering its result to `promise` unless the subscription is
    /// canceled first.
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
            // Canceled between starting and storing the task.
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

    /// Creates a publisher that sends the endpoint's request and ignores the response body.
    ///
    /// The request is sent when the publisher is subscribed to. The endpoint's credentials
    /// are applied, and the request is retried after a refresh when the authentication
    /// method asks for one. Canceling the subscription cancels the request.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - auth: The credentials to authenticate with. Defaults to the endpoint's
    ///     declared ``Endpoint/auth``.
    /// - Returns: A publisher that emits one value or fails with the endpoint's `TaskError`.
    func endpointPublisher<T: Endpoint>(
        with endpoint: T,
        environment: T.Server.Environments = T.Server.defaultEnvironment,
        auth: any AuthenticationMethod = T.auth
    ) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Void {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint, environment: environment, auth: auth)
        }
    }

    /// Creates a publisher that sends the endpoint's request and returns the response body without decoding it.
    ///
    /// The request is sent when the publisher is subscribed to. The endpoint's credentials
    /// are applied, and the request is retried after a refresh when the authentication
    /// method asks for one. Canceling the subscription cancels the request.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - auth: The credentials to authenticate with. Defaults to the endpoint's
    ///     declared ``Endpoint/auth``.
    /// - Returns: A publisher that emits one value or fails with the endpoint's `TaskError`.
    func endpointPublisher<T: Endpoint>(
        with endpoint: T,
        environment: T.Server.Environments = T.Server.defaultEnvironment,
        auth: any AuthenticationMethod = T.auth
    ) -> AnyPublisher<T.Response, T.TaskError> where T.Response == Data {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint, environment: environment, auth: auth)
        }
    }

    /// Creates a publisher that sends the endpoint's request and decodes the response with its ``Endpoint/responseDecoder``.
    ///
    /// The request is sent when the publisher is subscribed to. The endpoint's credentials
    /// are applied, and the request is retried after a refresh when the authentication
    /// method asks for one. Canceling the subscription cancels the request.
    /// - Parameters:
    ///   - endpoint: The endpoint to request.
    ///   - environment: The environment to resolve the base URL against. Defaults to the
    ///     server's ``ServerDefinition/defaultEnvironment``.
    ///   - auth: The credentials to authenticate with. Defaults to the endpoint's
    ///     declared ``Endpoint/auth``.
    /// - Returns: A publisher that emits one value or fails with the endpoint's `TaskError`.
    func endpointPublisher<T: Endpoint>(
        with endpoint: T,
        environment: T.Server.Environments = T.Server.defaultEnvironment,
        auth: any AuthenticationMethod = T.auth
    ) -> AnyPublisher<T.Response, T.TaskError> where T.Response: Decodable {
        Endpoints.endpointPublisher { () throws(T.TaskError) in
            try await self.response(with: endpoint, environment: environment, auth: auth)
        }
    }
}

#endif
