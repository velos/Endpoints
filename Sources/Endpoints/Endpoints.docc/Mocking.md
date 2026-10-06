# Mocking

The Endpoints library includes a powerful mocking system through the `EndpointsMocking` module that allows you to intercept and mock network requests during testing. This enables fast, reliable tests without making actual network calls.

## Overview

The mocking system works by:
1. Intercepting URLSession data task `resume()` calls when a mock is active
2. Providing mock responses through a continuation-based API
3. Supporting async/await, Combine, and closure-based callbacks

## Setup

Add the `EndpointsMocking` module to your test target dependencies:

```swift
// Package.swift
testTarget(
    name: "YourTests",
    dependencies: ["Endpoints", "EndpointsMocking"]
)
```

Import the mocking module in your tests:

```swift
import Testing // or XCTest
import Endpoints
import EndpointsMocking
```

## Basic Mocking

### Mocking a Successful Response

Use `withMock` to wrap your test code and provide mock responses:

```swift
import Testing
import Endpoints
import EndpointsMocking

@Test func testSuccessfulResponse() async throws {
    try await withMock(MyEndpoint.self) { continuation in
        // Provide the mock response
        continuation.resume(returning: .init(userId: "123", name: "John Doe"))
    } test: {
        // Your actual test code
        let endpoint = MyEndpoint(pathComponents: .init(userId: "123"))
        let response = try await URLSession.shared.response(with: endpoint)
        
        #expect(response.userId == "123")
        #expect(response.name == "John Doe")
    }
}
```

### Inline Mock Action

For simple cases, use the inline action syntax:

```swift
@Test func testWithInlineAction() async throws {
    try await withMock(
        MyEndpoint.self, 
        action: .return(.init(userId: "456", name: "Jane Smith"))
    ) {
        let endpoint = MyEndpoint(pathComponents: .init(userId: "456"))
        let response = try await URLSession.shared.response(with: endpoint)
        
        #expect(response.name == "Jane Smith")
    }
}
```

## Mock Actions

The `MockAction` enum provides four different actions:

### 1. Return a Success Response

```swift
continuation.resume(returning: responseObject)
// or inline:
withMock(MyEndpoint.self, action: .return(responseObject))
```

### 2. Return an Error Response

Use this when the server returns a structured error (matching your endpoint's `ErrorResponse` type):

```swift
continuation.resume(failingWith: ErrorResponse(code: 404, message: "Not found"))
// or inline:
withMock(MyEndpoint.self, action: .fail(errorResponse))
```

### 3. Throw a Task Error

Use this to simulate network or parsing errors:

```swift
continuation.resume(throwing: .internetConnectionOffline)
// or inline:
withMock(MyEndpoint.self, action: .throw(.internetConnectionOffline))
```

### 4. Do Nothing

For cases where you want the mock to not interfere (rarely used):

```swift
// Just don't call any resume method, or:
withMock(MyEndpoint.self, action: .none)
```

## Advanced Mocking

### Dynamic Responses

The mock closure runs once per request, so it can vary its response over time. The
continuation does not receive the endpoint instance, so decide based on state you
control rather than on the request's components. Because the closure is `@Sendable`,
keep that state in an actor:

```swift
actor ResponseSequence {
    private var names = ["Administrator", "Regular User"]

    func next() -> String {
        names.isEmpty ? "Guest" : names.removeFirst()
    }
}

@Test func testDynamicResponse() async throws {
    let sequence = ResponseSequence()

    try await withMock(MyEndpoint.self) { continuation in
        continuation.resume(returning: .init(userId: "1", name: await sequence.next()))
    } test: {
        let first = try await URLSession.shared.response(with: MyEndpoint(pathComponents: .init(userId: "1")))
        let second = try await URLSession.shared.response(with: MyEndpoint(pathComponents: .init(userId: "2")))

        #expect(first.name == "Administrator")
        #expect(second.name == "Regular User")
    }
}
```

### Async Mock Data Loading

You can load mock data asynchronously from files or other sources:

```swift
@Test func testWithAsyncMockLoading() async throws {
    try await withMock(MyEndpoint.self) { continuation in
        // Load mock from JSON file
        let mockData = try await loadMockData(filename: "user_response.json")
        let decoder = JSONDecoder()
        let response = try decoder.decode(MyEndpoint.Response.self, from: mockData)
        
        continuation.resume(returning: response)
    } test: {
        let endpoint = MyEndpoint(pathComponents: .init(userId: "123"))
        let response = try await URLSession.shared.response(with: endpoint)
        
        #expect(response.userId == "123")
    }
}

func loadMockData(filename: String) async throws -> Data {
    let url = Bundle.module.url(forResource: filename, withExtension: nil)!
    return try Data(contentsOf: url)
}
```

### Multiple Requests in One Mock Block

The mock applies to all requests of the specified endpoint type within the test block:

```swift
@Test func testMultipleRequests() async throws {
    let calls = CallCounter()

    try await withMock(MyEndpoint.self) { continuation in
        let count = await calls.increment()
        continuation.resume(returning: .init(userId: "\(count)", name: "User \(count)"))
    } test: {
        let response1 = try await URLSession.shared.response(with: MyEndpoint(pathComponents: .init(userId: "1")))
        let response2 = try await URLSession.shared.response(with: MyEndpoint(pathComponents: .init(userId: "2")))

        #expect(await calls.value == 2)
        #expect(response1.name == "User 1")
        #expect(response2.name == "User 2")
    }
}

actor CallCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
```

### Mocking Several Endpoints at Once

When a flow touches more than one endpoint, register them together instead of nesting
`withMock` calls. Endpoint types without a registered mock pass through to the real
transport, nested scopes merge, and an inner mock for the same endpoint type shadows
the outer one for the duration of its scope:

```swift
@Test func testProfileAfterRefresh() async throws {
    try await withMock { mocks in
        mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
        mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
    } test: {
        let profile = try await URLSession.shared.response(with: ProfileEndpoint())
        #expect(profile.name == "Zac")
    }
}
```

## Combine Support

Mocking works seamlessly with Combine publishers:

```swift
import Testing
import Endpoints
import EndpointsMocking
@preconcurrency import Combine

@Suite("Combine Mocking")
@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
struct CombineMockingTests {
    
    @Test func testCombinePublisher() async throws {
        try await withMock(MyEndpoint.self, action: .return(.init(userId: "123", name: "Test"))) {
            let endpoint = MyEndpoint(pathComponents: .init(userId: "123"))
            
            let response = try await URLSession.shared
                .endpointPublisher(with: endpoint)
                .awaitFirst()
            
            #expect(response.name == "Test")
        }
    }
}

// Helper to await the first value of a publisher.
// `Publisher.values` needs iOS 15 / macOS 12, so annotate it for older deployment targets.
@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
extension Publisher where Output: Sendable {
    func awaitFirst() async throws -> Output {
        for try await value in values {
            return value
        }
        throw CancellationError()
    }
}
```

## Testing Errors

### Testing Error Responses

```swift
@Test func testErrorResponse() async throws {
    struct ServerError: Codable, Equatable {
        let code: Int
        let message: String
    }
    
    struct ErrorEndpoint: Endpoint {
        typealias Server = ApiServer
        typealias ErrorResponse = ServerError
        
        static let definition: Definition<ErrorEndpoint> = Definition(
            method: .get,
            path: "error"
        )
        
        struct Response: Decodable {
            let value: String
        }
    }
    
    try await withMock(ErrorEndpoint.self) { continuation in
        continuation.resume(failingWith: ServerError(code: 500, message: "Server Error"))
    } test: {
        do {
            _ = try await URLSession.shared.response(with: ErrorEndpoint())
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            guard case .errorResponse(_, let errorResponse) = error as? ErrorEndpoint.TaskError else {
                #expect(Bool(false), "Wrong error type")
                return
            }
            #expect(errorResponse.code == 500)
            #expect(errorResponse.message == "Server Error")
        }
    }
}
```

### Testing Thrown Errors

```swift
@Test func testThrownError() async throws {
    await #expect(throws: MyEndpoint.TaskError.self) {
        try await withMock(MyEndpoint.self) { continuation in
            continuation.resume(throwing: .internetConnectionOffline)
        } test: {
            _ = try await URLSession.shared.response(with: MyEndpoint())
        }
    }
}
```

## Best Practices

### 1. Mock at the Endpoint Type

Mocks are keyed by endpoint type, so one `withMock(MyEndpoint.self)` covers every
request of that type inside the block regardless of the instance's path, query, or body
values. Keep endpoint types focused so a mock does not have to answer for unrelated
requests.

### 2. Organize Mock Data

Create helper functions or extensions for common mock scenarios:

```swift
extension MyEndpoint {
    static func mockSuccess(userId: String, name: String) -> MockAction<Response, ErrorResponse> {
        .return(.init(userId: userId, name: name))
    }
    
    static func mockNotFound() -> MockAction<Response, ErrorResponse> {
        .fail(.init(code: 404, message: "User not found"))
    }
}

// Usage
try await withMock(MyEndpoint.self, action: .mockSuccess(userId: "123", name: "Test")) {
    // test code
}
```

### 3. Test Error Cases

Always test both success and failure paths:

```swift
@Suite("User Endpoint Tests")
struct UserEndpointTests {
    
    @Test func successCase() async throws { ... }
    
    @Test func notFoundCase() async throws { ... }
    
    @Test func networkErrorCase() async throws { ... }
    
    @Test func decodingErrorCase() async throws { ... }
}
```

### 4. Select the Environment Per Request

The environment is a per-request value, so tests never need to save and restore global
state — pass the one you want and nothing leaks into other tests:

```swift
@Test func testStagingEnvironment() async throws {
    let response = try await URLSession.shared.response(
        with: MyEndpoint(),
        environment: .staging
    )

    // Test code...
}
```

## Authentication and Mocks

A mocked request short-circuits before authentication: the endpoint's
``AuthenticationMethod`` is never invoked, no credentials are applied, and a mock error
does not enter the refresh/retry loop. To simulate an authentication failure, throw one
directly:

```swift
try await withMock(ProfileEndpoint.self, action: .throw(.authenticationError(.notAuthenticated))) {
    await #expect(throws: ProfileEndpoint.TaskError.self) {
        try await URLSession.shared.response(with: ProfileEndpoint())
    }
}
```

To exercise the refresh flow itself — credentials applied, a 401, a refresh, a retry —
use a `URLProtocol`-based fake transport on a dedicated `URLSession` instead of a mock.

## Limitations

- Mocking only works in DEBUG builds and on Apple platforms; the `EndpointsMocking`
  module is not built on Linux.
- A mock applies to every request of its endpoint type within the block. To vary the
  response between requests, use a dynamic mock as shown above.
- Mocks bypass authentication entirely (see above).

## How It Works

`withMock` stores the registered mocks in task-local state, so they are visible to
every request made from within the `test` closure — including from child tasks — and
invisible to anything running concurrently outside it. The async/await and Combine
request methods consult that state before building a request. The closure-based
`endpointTask` cannot, because it returns a `URLSessionDataTask` synchronously; for that
path the library swizzles `URLSessionTask.resume()` in DEBUG builds so the task delivers
the mock instead of hitting the network.
