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

@Suite("Closure URLSession Mocking")
struct ClosureURLSessionMocking {

    @Test func inline() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "test"))) {
            try await wait { continuation in
                let simple = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
                let task = try URLSession.shared.endpointTask(with: simple) { result in
                    #expect(throws: Never.self) {
                        let response = try result.get()
                        #expect(response.response1 == "test")
                    }
                    continuation.resume()
                }
                task.resume()
            }
        }
    }

    @Test func inline2() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "test2"))) {
            try await wait { continuation in
                let simple = MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
                let task = try URLSession.shared.endpointTask(with: simple) { result in
                    #expect(throws: Never.self) {
                        let response = try result.get()
                        #expect(response.response1 == "test2")
                    }
                    continuation.resume()
                }
                task.resume()
            }
        }
    }
}
