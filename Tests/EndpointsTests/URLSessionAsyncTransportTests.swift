#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

/// Exercises the real (non-mocked) request paths of the async `URLSession` extension
/// through `TestURLProtocol`: response parsing, error decoding, and load-error mapping.
@Suite("Async URLSession Transport", .serialized)
struct URLSessionAsyncTransportTests {

    private static let url = URL(string: "https://api.velosmobile.com/transport/test")!

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func decodableSuccess() async throws {
        let successData = try JSONEncoder().encode(TransportEndpoint.Response(value: "ok"))
        TestURLProtocol.register(path: "/transport/test") { _ in
            (HTTPURLResponse(url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        let response = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
        #expect(response.value == "ok")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func decodeFailureSurfacesAsResponseParseError() async throws {
        let garbage = Data("not json".utf8)
        TestURLProtocol.register(path: "/transport/test") { _ in
            (HTTPURLResponse(url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!, garbage)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
            Issue.record("Expected responseParseError to be thrown")
        } catch {
            guard case .responseParseError(let data, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(data == garbage)
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func errorResponseIsDecoded() async throws {
        let errorData = try JSONEncoder().encode(TransportEndpoint.ErrorResponse(message: "unprocessable"))
        TestURLProtocol.register(path: "/transport/test") { _ in
            (HTTPURLResponse(url: Self.url, statusCode: 422, httpVersion: nil, headerFields: nil)!, errorData)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
            Issue.record("Expected errorResponse to be thrown")
        } catch {
            guard case .errorResponse(let httpResponse, let errorResponse) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(httpResponse.statusCode == 422)
            #expect(errorResponse.message == "unprocessable")
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func undecodableErrorResponseSurfacesAsErrorResponseParseError() async throws {
        let garbage = Data("<html>ise</html>".utf8)
        TestURLProtocol.register(path: "/transport/test") { _ in
            (HTTPURLResponse(url: Self.url, statusCode: 500, httpVersion: nil, headerFields: nil)!, garbage)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
            Issue.record("Expected errorResponseParseError to be thrown")
        } catch {
            guard case .errorResponseParseError(let httpResponse, let data, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(httpResponse.statusCode == 500)
            #expect(data == garbage)
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func voidResponse() async throws {
        TestURLProtocol.register(path: "/transport/void") { _ in
            (HTTPURLResponse(url: URL(string: "https://api.velosmobile.com/transport/void")!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { TestURLProtocol.unregister(path: "/transport/void") }

        try await TestURLProtocol.makeSession().response(with: TransportVoidEndpoint())
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func dataResponse() async throws {
        let payload = Data([0xca, 0xfe])
        TestURLProtocol.register(path: "/transport/data") { _ in
            (HTTPURLResponse(url: URL(string: "https://api.velosmobile.com/transport/data")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        defer { TestURLProtocol.unregister(path: "/transport/data") }

        let response = try await TestURLProtocol.makeSession().response(with: TransportDataEndpoint())
        #expect(response == payload)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func loadFailureSurfacesAsUrlLoadError() async throws {
        TestURLProtocol.register(path: "/transport/test") { _ in
            throw URLError(.timedOut)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
            Issue.record("Expected urlLoadError to be thrown")
        } catch {
            guard case .urlLoadError(let underlying) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect((underlying as NSError).code == URLError.Code.timedOut.rawValue)
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func offlineSurfacesAsInternetConnectionOffline() async throws {
        TestURLProtocol.register(path: "/transport/test") { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { TestURLProtocol.unregister(path: "/transport/test") }

        do {
            _ = try await TestURLProtocol.makeSession().response(with: TransportEndpoint())
            Issue.record("Expected internetConnectionOffline to be thrown")
        } catch {
            guard case .internetConnectionOffline = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}

struct TransportEndpoint: Endpoint {
    typealias Server = TestServer

    static let definition: Definition<TransportEndpoint> = Definition(
        method: .get,
        path: "transport/test"
    )

    struct Response: Codable, Sendable {
        let value: String
    }

    struct ErrorResponse: Codable, Sendable {
        let message: String
    }
}

struct TransportVoidEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void

    static let definition: Definition<TransportVoidEndpoint> = Definition(
        method: .post,
        path: "transport/void"
    )
}

struct TransportDataEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Data

    static let definition: Definition<TransportDataEndpoint> = Definition(
        method: .get,
        path: "transport/data"
    )
}
#endif
