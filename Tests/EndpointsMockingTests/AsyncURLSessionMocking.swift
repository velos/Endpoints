//
//  AsyncURLSessionMocking.swift
//  Endpoints
//
//  Created by Zac White on 11/30/24.
//

import Testing
import Endpoints
import Foundation
@testable import EndpointsMocking

struct TestServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .production: URL(string: "https://api.velosmobile.com")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}

struct SimpleEndpoint: Endpoint {
    static let definition: Definition<SimpleEndpoint, TestServer> = Definition(
        method: .get,
        path: "user/\(path: \.name)/\(path: \.id)/profile"
    )

    struct Response: Codable {
        let response1: String
    }

    struct ErrorResponse: Codable, Equatable {
        let errorDescription: String
    }

    struct PathComponents {
        let name: String
        let id: String
    }

    let pathComponents: PathComponents
}

@Suite("Async URLSession Mocking")
struct AsyncURLSessionMocking {
    @Test func basicThrow() async throws {
        await #expect(throws: SimpleEndpoint.TaskError.self) {
            try await withMock(SimpleEndpoint.self) { continuation in
                continuation.resume(throwing: .internetConnectionOffline)
            } test: {
                let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
                _ = try await URLSession.shared.response(with: simple)
            }
        }
    }

    @Test func basicThrowInline() async throws {
        await #expect(throws: SimpleEndpoint.TaskError.self) {
            try await withMock(SimpleEndpoint.self, action: .throw(.internetConnectionOffline)) {
                let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
                _ = try await URLSession.shared.response(with: simple)
            }
        }
    }

    @Test func basicFail() async throws {
        try await withMock(SimpleEndpoint.self) { continuation in
            continuation.resume(failingWith: .init(errorDescription: "error"))
        } test: {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            do {
                _ = try await URLSession.shared.response(with: simple)
            } catch {
                let error = try #require(error as? SimpleEndpoint.TaskError)
                if case .errorResponse(_, let response) = error {
                    #expect(response.errorDescription == "error")
                } else {
                    #expect(Bool(false), "unexpected error \(error)")
                }
            }
        }
    }

    @Test func basicFailInline() async throws {
        try await withMock(SimpleEndpoint.self, action: .fail(.init(errorDescription: "error"))) {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            do {
                _ = try await URLSession.shared.response(with: simple)
            } catch {
                let error = try #require(error as? SimpleEndpoint.TaskError)
                if case .errorResponse(_, let response) = error {
                    #expect(response.errorDescription == "error")
                } else {
                    #expect(Bool(false), "unexpected error \(error)")
                }
            }
        }
    }

    @Test func basicResponse() async throws {
        try await withMock(SimpleEndpoint.self) { continuation in
            // possibly load mocks async from json
            continuation.resume(returning: .init(response1: "test"))
        } test: {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await URLSession.shared.response(with: simple)
            #expect(response.response1 == "test")
        }
    }

    @Test func basicResponseInline() async throws {
        try await withMock(SimpleEndpoint.self, action: .return(.init(response1: "test"))) {
            let simple = SimpleEndpoint(pathComponents: .init(name: "a", id: "b"))
            let response = try await URLSession.shared.response(with: simple)
            #expect(response.response1 == "test")
        }
    }
}
