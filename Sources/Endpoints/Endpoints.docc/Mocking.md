# Mocking

Replace endpoint responses in tests without making network requests.

## Overview

The `EndpointsMocking` module provides `withMock`, which replaces the response for an endpoint type while a block of test code runs. Requests for that type return the mock instead of reaching the network. Requests for other types make real requests.

Mocking works with the async/await, Combine, and completion-handler request methods. It is available in DEBUG builds on Apple platforms.

## Setup

Add `EndpointsMocking` to your test target:

```swift
.testTarget(
    name: "YourAppTests",
    dependencies: [
        .product(name: "Endpoints", package: "Endpoints"),
        .product(name: "EndpointsMocking", package: "Endpoints")
    ]
)
```

Then import it in your tests:

```swift
import Testing
import Endpoints
import EndpointsMocking
```

## Mocking a response

Pass a ``MockAction`` for simple cases:

```swift
@Test func loadsProfile() async throws {
    try await withMock(ProfileEndpoint.self, action: .return(.init(name: "Zac"))) {
        let profile = try await URLSession.shared.response(with: ProfileEndpoint())
        #expect(profile.name == "Zac")
    }
}
```

Or pass a closure that receives a ``MockContinuation``. The closure runs once per request, and it can be `async`:

```swift
try await withMock(ProfileEndpoint.self) { continuation in
    continuation.resume(returning: .init(name: "Zac"))
} test: {
    let profile = try await URLSession.shared.response(with: ProfileEndpoint())
    #expect(profile.name == "Zac")
}
```

### Actions

| Action | Continuation method | Result |
|---|---|---|
| `.return(value)` | `resume(returning:)` | The request returns `value`. |
| `.fail(errorResponse)` | `resume(failingWith:)` | The request throws ``EndpointTaskError/errorResponse(httpResponse:response:)`` with your ``Endpoint/ErrorResponse`` value. |
| `.throw(error)` | `resume(throwing:)` | The request throws `error`, such as `.internetConnectionOffline`. |
| `.none` | Don't call a resume method. | The request is sent to the network. |

The `httpResponse` in a `.fail` error is a placeholder with status code 200. Assert on the error response value, not on the status code. To test status-code handling, use a fake transport. See <doc:Mocking#Testing-the-refresh-flow>.

> Note: With the completion-handler method `endpointTask(with:completion:)`, a `.none` mock doesn't send the request, and the completion handler isn't called. Return a value or an error instead.

## Mocking several endpoints

Register several endpoint types in one scope instead of nesting `withMock` calls:

```swift
try await withMock { mocks in
    mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
    mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
} test: {
    let profile = try await URLSession.shared.response(with: ProfileEndpoint())
    #expect(profile.name == "Zac")
}
```

Nested scopes combine. An inner mock for the same endpoint type replaces the outer one until the inner scope ends.

## Dynamic responses

The continuation doesn't include the endpoint instance, so a dynamic mock decides from state you control. The closure is `@Sendable`, so keep that state in an actor:

```swift
actor CallCounter {
    private(set) var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

@Test func returnsDifferentProfiles() async throws {
    let calls = CallCounter()

    try await withMock(ProfileEndpoint.self) { continuation in
        let call = await calls.next()
        continuation.resume(returning: .init(name: "User \(call)"))
    } test: {
        let first = try await URLSession.shared.response(with: ProfileEndpoint())
        let second = try await URLSession.shared.response(with: ProfileEndpoint())

        #expect(first.name == "User 1")
        #expect(second.name == "User 2")
        #expect(await calls.count == 2)
    }
}
```

To load a fixture file, catch errors inside the closure, since it can't throw:

```swift
try await withMock(ProfileEndpoint.self) { continuation in
    do {
        let url = Bundle.module.url(forResource: "profile", withExtension: "json")!
        let data = try Data(contentsOf: url)
        continuation.resume(returning: try JSONDecoder().decode(ProfileEndpoint.Response.self, from: data))
    } catch {
        continuation.resume(throwing: .urlLoadError(error))
    }
} test: {
    // ...
}
```

## Testing errors

```swift
@Test func showsServerError() async throws {
    try await withMock(ArticleEndpoint.self, action: .fail(.init(code: 500, message: "Server error"))) {
        do {
            _ = try await URLSession.shared.response(with: ArticleEndpoint())
            Issue.record("Expected an error")
        } catch let error as ArticleEndpoint.TaskError {
            guard case .errorResponse(_, let serverError) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(serverError.message == "Server error")
        }
    }
}

@Test func handlesOffline() async {
    await #expect(throws: ArticleEndpoint.TaskError.self) {
        try await withMock(ArticleEndpoint.self, action: .throw(.internetConnectionOffline)) {
            try await URLSession.shared.response(with: ArticleEndpoint())
        }
    }
}
```

The `test` closure's thrown errors are untyped, so cast to the endpoint's `TaskError` before matching its cases.

## Combine

Publishers from `endpointPublisher(with:)` return mocks too:

```swift
@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
@Test func loadsProfileWithCombine() async throws {
    try await withMock(ProfileEndpoint.self, action: .return(.init(name: "Zac"))) {
        let profile = try await URLSession.shared
            .endpointPublisher(with: ProfileEndpoint())
            .firstValue()
        #expect(profile.name == "Zac")
    }
}

@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
extension Publisher where Output: Sendable {
    func firstValue() async throws -> Output {
        for try await value in values {
            return value
        }
        throw CancellationError()
    }
}
```

Subscribe inside the `withMock` block. Mocks apply to work started there.

## Authentication

A mocked request skips authentication. The endpoint's ``AuthenticationMethod`` isn't called, and a mocked error doesn't start a refresh or a retry. To test how your code handles an authentication failure, throw one:

```swift
await #expect(throws: ProfileEndpoint.TaskError.self) {
    try await withMock(ProfileEndpoint.self, action: .throw(.authenticationError(.notAuthenticated))) {
        try await URLSession.shared.response(with: ProfileEndpoint())
    }
}
```

### Testing the refresh flow

To test refresh and retry, send real requests through a `URLSession` whose `URLProtocol` returns canned responses:

```swift
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct RefreshTests {
    @Test func retriesWithRefreshedToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)

        StubProtocol.requests = []
        StubProtocol.responses = [
            (401, Data(#"{}"#.utf8)),
            (200, Data(#"{"name":"Zac"}"#.utf8))
        ]

        let auth = JWTAuth(initialTokens: .init(accessToken: "old", refreshToken: "refresh")) { refreshToken in
            .init(accessToken: "new", refreshToken: refreshToken)
        }

        let profile = try await session.response(with: ProfileEndpoint(), auth: auth)

        #expect(profile.name == "Zac")
        #expect(StubProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer new"])
    }
}
```

The stub's static state is shared, so run these tests serially.

## Testing request construction

To check the URL, headers, or body an endpoint produces, build the request without sending it:

```swift
@Test func searchQuery() throws {
    let request = try SearchEndpoint(parameterComponents: .init(query: "swift", page: 2))
        .urlRequest(in: .staging)

    #expect(request.url?.absoluteString == "https://staging-api.example.com/search?q=swift&page=2&format=compact")
}
```

``Endpoint/urlRequest(in:)`` doesn't apply authentication, so the request has no credentials.

## How it works

`withMock` stores mocks in task-local values. They apply to requests made inside the `test` closure and in child tasks, and don't affect tests running in parallel. A request made from `Task.detached` doesn't see them.

The async/await and Combine methods check for a mock before building the request. `endpointTask(with:completion:)` returns its task before it can check, so in DEBUG builds the library swizzles `URLSessionTask.resume()` to deliver the mock when the task starts.

## Topics

- ``MockRegistry``
- ``MockContinuation``
- ``MockAction``
