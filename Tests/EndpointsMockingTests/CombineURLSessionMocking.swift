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

final class PublisherWaiter<P: Publisher> {
    let publisher: P

    init(publisher: P) {
        self.publisher = publisher
    }

    @available(iOS 15.0, *)
    func wait() async throws -> P.Output {
        var iterator = publisher
            .assertNoFailure()
            .first()
            .values
            .makeAsyncIterator()

        guard let value = await iterator.next() else {
            throw WaiterError.noElement
        }

        return value
    }
}

@Suite("Combine URLSession Mocking")
struct CombineURLSessionMocking {

    @available(iOS 15.0, *)
    @Test(arguments: ["test", "test2"])
    func combineInline(response: String) async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: response))) {
            let simple = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let endpointResponse = try await URLSession.shared.endpointPublisher(with: simple).awaitFirst
            #expect(endpointResponse.response1 == response)
        }
    }
}
