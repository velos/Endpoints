#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Testing
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

@Suite("Authenticated Session")
struct AuthenticatedSessionTests {
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test
    func retriesAfterReauthentication() async throws {
        let url = URL(string: "https://api.velosmobile.com/auth/test")!
        let errorData = try JSONEncoder().encode(AuthTestEndpoint.ErrorResponse(message: "unauthorized"))
        let successData = try JSONEncoder().encode(AuthTestEndpoint.Response(value: "ok"))

        let responses = ResponseQueue([
            (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, errorData),
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, successData)
        ])

        TestURLProtocol.handler = { _ in
            try responses.next()
        }
        defer { TestURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        let auth = TestAuth()
        let session = AuthenticatedSession(session: urlSession, auth: auth, maxRetryAttempts: 1)

        let response = try await session.response(with: AuthTestEndpoint())

        #expect(response.value == "ok")

        let counts = await auth.counts()
        #expect(counts.authenticate == 2)
        #expect(counts.reauthenticate == 1)
    }
}

struct AuthTestEndpoint: Endpoint {
    typealias Server = TestServer

    static let definition: Definition<AuthTestEndpoint> = Definition(
        method: .get,
        path: "auth/test"
    )

    struct Response: Codable, Sendable {
        let value: String
    }

    struct ErrorResponse: Codable, Sendable, Equatable {
        let message: String
    }
}

actor TestAuth: AuthenticationMethod {
    private var authenticateCount = 0
    private var reauthenticateCount = 0

    func authenticate(request: URLRequest) async throws -> URLRequest {
        authenticateCount += 1
        return request
    }

    nonisolated func shouldReauthenticate(for error: any Error, response: HTTPURLResponse?) -> Bool {
        response?.statusCode == 401
    }

    func reauthenticate() async throws {
        reauthenticateCount += 1
    }

    func counts() -> (authenticate: Int, reauthenticate: Int) {
        (authenticateCount, reauthenticateCount)
    }
}

final class ResponseQueue {
    private var responses: [(HTTPURLResponse, Data)]
    private let lock = NSLock()

    init(_ responses: [(HTTPURLResponse, Data)]) {
        self.responses = responses
    }

    func next() throws -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }

        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }
}

final class TestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
#endif
