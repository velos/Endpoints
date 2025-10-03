//
//  BasicMocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Testing
import Endpoints
import Foundation
@testable import EndpointsMocking
@preconcurrency import Combine

//extension AnyPublisher where Output: Sendable {
//    var awaitFirst: Output {
//        get async throws {
//            try await withCheckedThrowingContinuation { continuation in
//                Task {
//                    let cancellable = first()
//                        .print("first")
//                        .sink { completion in
//                            switch completion {
//                            case .failure(let error):
//                                continuation.resume(throwing: error)
//                            case .finished:
//                                continuation.resume(throwing: CancellationError())
//                            }
//                        } receiveValue: { value in
//                            continuation.resume(returning: value)
//                        }
//
//                    // Hold reference to cancellable until task is cancelled or value received
//                    await Task.yield()
//                    _ = cancellable
//                }
//            }
//        }
//    }
//}

@available(iOS 15.0, *)
extension AnyPublisher where Output: Sendable {
    var awaitFirst: Output {
        get async throws {
            let waiter = PublisherWaiter(publisher: self)
            return try await waiter.wait()
        }
    }
}


enum WaiterError: Error {
    case noElement
}

import SwiftUI
final class PublisherWaiter<P: Publisher> {
    let publisher: P
    @Published var value: P.Output?

    init(publisher: P) {
        self.publisher = publisher
    }

    @available(iOS 15.0, *)
    func wait() async throws -> P.Output {
        publisher
            .assertNoFailure()
            .first()
            .map { $0 }
            .print("asdf")
            .assign(to: &$value)

        for await value in $value.values.dropFirst() {
            return value!
        }

        throw WaiterError.noElement
    }
}

@Suite("Combine URLSession Mocking")
struct CombineURLSessionMocking {

    @available(iOS 15.0, *)
    @Test(arguments: ["test", "test2"])
    func combineInline(response: String) async throws {
        try await withMock(SimpleEndpoint.self, action: .return(.init(response1: response))) {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await URLSession.shared.endpointPublisher(with: simple).awaitFirst
            #expect(response.response1 == "test")
        }
    }
}
