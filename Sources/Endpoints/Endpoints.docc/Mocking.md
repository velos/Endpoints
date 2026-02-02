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

### Dynamic Responses Based on Request

The continuation closure receives the endpoint instance, allowing dynamic responses:

```swift
@Test func testDynamicResponse() async throws {
    try await withMock(MyEndpoint.self) { continuation in
        // Access the endpoint being requested
        let endpoint = continuation.endpoint
        
        // Return different responses based on the request
        if endpoint.pathComponents.userId == "admin" {
            continuation.resume(returning: .init(userId: "admin", name: "Administrator"))
        } else {
            continuation.resume(returning: .init(userId: "user", name: "Regular User"))
        }
    } test: {
        let adminEndpoint = MyEndpoint(pathComponents: .init(userId: "admin"))
        let adminResponse = try await URLSession.shared.response(with: adminEndpoint)
        #expect(adminResponse.name == "Administrator")
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
    var callCount = 0
    
    try await withMock(MyEndpoint.self) { continuation in
        callCount += 1
        continuation.resume(returning: .init(userId: "\(callCount)", name: "User \(callCount)"))
    } test: {
        let endpoint1 = MyEndpoint(pathComponents: .init(userId: "1"))
        let response1 = try await URLSession.shared.response(with: endpoint1)
        
        let endpoint2 = MyEndpoint(pathComponents: .init(userId: "2"))
        let response2 = try await URLSession.shared.response(with: endpoint2)
        
        #expect(callCount == 2)
        #expect(response1.name == "User 1")
        #expect(response2.name == "User 2")
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

// Helper to await publisher values
@available(iOS 15.0, *)
extension AnyPublisher where Output: Sendable {
    var awaitFirst: Output {
        get async throws {
            try await self.first().asyncThrowing()
        }
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

### 1. Use Type-Specific Mocks

Always specify the endpoint type explicitly to ensure type safety:

```swift
// Good
withMock(MySpecificEndpoint.self) { ... }

// Avoid (if possible)
withMock(endpoint) { ... }
```

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

### 4. Reset Environment After Tests

If your tests change the server environment, reset it afterward:

```swift
@Test func testStagingEnvironment() async throws {
    let originalEnvironment = ApiServer.environment
    ApiServer.environment = .staging
    
    defer {
        ApiServer.environment = originalEnvironment
    }
    
    // Test code...
}
```

## Limitations

- Mocking only works in DEBUG builds (disabled in release builds)
- Mocking applies to all instances of an endpoint type within the test block
- You cannot selectively mock some requests and not others within the same block

## Migration from Old Mocking

If you were previously using a different mocking approach, the new `withMock` API offers several advantages:

1. **No URLSession swizzling needed** - Clean, Swift-native approach
2. **Type-safe** - Mock responses are checked at compile time
3. **Async-native** - Built for Swift's async/await
4. **Combine support** - Works with both async and Combine APIs

Replace manual URLProtocol mocking or stubbing with `withMock` for cleaner, more maintainable tests.
