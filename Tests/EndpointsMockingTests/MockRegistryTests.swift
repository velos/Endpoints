//
//  MockRegistryTests.swift
//  Endpoints
//

import Testing
import Endpoints
import Foundation
@testable import EndpointsMocking

struct MockSecondEndpoint: Endpoint {
    typealias Server = MockTestServer

    static let definition: Definition<MockSecondEndpoint> = Definition(
        method: .get,
        path: "second"
    )

    struct Response: Codable {
        let value: Int
    }

    struct ErrorResponse: Codable, Equatable {
        let message: String
    }
}

struct MockThirdEndpoint: Endpoint {
    typealias Server = MockTestServer

    static let definition: Definition<MockThirdEndpoint> = Definition(
        method: .get,
        path: "third"
    )

    struct Response: Codable {
        let flag: Bool
    }
}

/// A server whose base URL refuses connections immediately, so pass-through
/// requests fail fast without touching the network.
struct UnroutableServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [.production: URL(string: "http://127.0.0.1:1")!]
    }

    static var defaultEnvironment: Environments { .production }
}

struct PassthroughEndpoint: Endpoint {
    typealias Server = UnroutableServer

    static let definition: Definition<PassthroughEndpoint> = Definition(
        method: .get,
        path: "passthrough"
    )

    struct Response: Codable {
        let value: String
    }
}

@Suite("Mock Registry")
struct MockRegistryTests {

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func routesEachEndpointToItsOwnMock() async throws {
        try await withMock { mocks in
            mocks.register(MockSimpleEndpoint.self, action: .return(.init(response1: "first")))
            mocks.register(MockSecondEndpoint.self, action: .fail(.init(message: "second failed")))
            mocks.register(MockThirdEndpoint.self, action: .throw(.internetConnectionOffline))
        } test: {
            let simple = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
            #expect(simple.response1 == "first")

            do throws(MockSecondEndpoint.TaskError) {
                _ = try await URLSession.shared.response(with: MockSecondEndpoint())
                Issue.record("Expected errorResponse to be thrown")
            } catch {
                guard case .errorResponse(_, let errorResponse) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(errorResponse.message == "second failed")
            }

            do throws(MockThirdEndpoint.TaskError) {
                _ = try await URLSession.shared.response(with: MockThirdEndpoint())
                Issue.record("Expected internetConnectionOffline to be thrown")
            } catch {
                guard case .internetConnectionOffline = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func nestedScopesCompose() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "outer"))) {
            try await withMock(MockSecondEndpoint.self, action: .return(.init(value: 42))) {
                // Both the outer and inner mocks are active.
                let simple = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
                #expect(simple.response1 == "outer")

                let second = try await URLSession.shared.response(with: MockSecondEndpoint())
                #expect(second.value == 42)
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func innerScopeShadowsSameEndpoint() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "outer"))) {
            try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "inner"))) {
                let response = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
                #expect(response.response1 == "inner")
            }

            // The outer mock is restored once the inner scope exits.
            let response = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
            #expect(response.response1 == "outer")
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func unmockedEndpointPassesThrough() async throws {
        try await withMock(MockSimpleEndpoint.self, action: .return(.init(response1: "mocked"))) {
            // An endpoint type with no registered mock goes to the real transport,
            // which for UnroutableServer fails with a connection error.
            do throws(PassthroughEndpoint.TaskError) {
                _ = try await URLSession.shared.response(with: PassthroughEndpoint())
                Issue.record("Expected urlLoadError to be thrown")
            } catch {
                guard case .urlLoadError = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func registeringSameEndpointTwiceKeepsTheLatest() async throws {
        try await withMock { mocks in
            mocks.register(MockSimpleEndpoint.self, action: .return(.init(response1: "first")))
            mocks.register(MockSimpleEndpoint.self, action: .return(.init(response1: "second")))
        } test: {
            let response = try await URLSession.shared.response(with: MockSimpleEndpoint(pathComponents: .init(name: "a", id: "b")))
            #expect(response.response1 == "second")
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func continuationBasedRegistrationWorks() async throws {
        try await withMock { mocks in
            mocks.register(MockSecondEndpoint.self) { continuation in
                continuation.resume(returning: .init(value: 7))
            }
        } test: {
            let response = try await URLSession.shared.response(with: MockSecondEndpoint())
            #expect(response.value == 7)
        }
    }
}
