#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A URLProtocol that routes requests to handlers registered per URL path.
///
/// Handlers are keyed by path so independent test suites can run in parallel
/// without racing on shared state, as long as they use disjoint paths. Tests
/// that reuse a path must run serialized.
final class TestURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(path: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[path] = handler
    }

    static func unregister(path: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[path] = nil
    }

    private static func handler(for request: URLRequest) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        guard let path = request.url?.path else { return nil }
        return handlers[path]
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler(for: request) else {
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

final class ResponseQueue: @unchecked Sendable {
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

final class RequestRecorder: @unchecked Sendable {
    private var requests: [URLRequest] = []
    private let lock = NSLock()

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    func all() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
#endif
