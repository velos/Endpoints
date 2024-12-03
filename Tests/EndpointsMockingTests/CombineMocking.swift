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
import Combine

@Suite("Combine Mocking")
struct CombineMocking {

    @available(iOS 15.0, *)
    @Test func basicCombineInline() async throws {
        try await withMock(SimpleEndpoint.self, action: .return(.init(response1: "test"))) {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            for try await response in URLSession.shared.endpointPublisher(with: simple).values {
                #expect(response.response1 == "test")
            }
        }
    }

    @available(iOS 15.0, *)
    @Test func basicCombineInline2() async throws {
        try await withMock(SimpleEndpoint.self, action: .return(.init(response1: "test2"))) {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            for try await response in URLSession.shared.endpointPublisher(with: simple).values {
                #expect(response.response1 == "test2")
            }
        }
    }
}
