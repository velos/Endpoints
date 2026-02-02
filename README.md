# Endpoints

![CI](https://github.com/velos/Endpoints/workflows/CI/badge.svg) ![Documentation](https://github.com/velos/Endpoints/workflows/Documentation/badge.svg)

Endpoints is a small library for creating statically and strongly-typed definitions of endpoints with paths, methods, inputs and outputs.

## Purpose

The purpose of Endpoints is to, in a type-safe way, define how to create a `URLRequest` from typed properties and, additionally, define how a response for the request should be handled. The library not only includes the ability to create these requests in a type-safe way, but also includes helpers to perform the requests using `URLSession`. Endpoints does not try to wrap the URL loading system to provide features on top of it like Alamofire. Instead, Endpoints focuses on defining endpoints and associated data to produce a request as a `URLRequest` object to be plugged into vanilla `URLSession`s. However, this library could be used in conjunction with Alamofire if desired.

## Features

- **Type-safe endpoint definitions** - Define endpoints with compile-time checking of paths, parameters, and headers
- **Server definition with multiple environments** - Support for local, development, staging, and production environments with easy switching
- **Built-in mocking support** - Comprehensive testing utilities through the `EndpointsMocking` module
- **Swift 6.0 compatible** - Built with modern Swift concurrency and Sendable support
- **Combine and async/await support** - Use either reactive or async patterns

## Getting Started

The basic process for defining an Endpoint starts with defining a value conforming to `Endpoint`. With the `Endpoint` protocol, you are encapsulating the definition of the endpoint, all the properties that are plugged into the definition and the types for parsing the response. Within the `Endpoint`, the `definition` static var serves as an immutable definition of the server's endpoint and how the variable pieces of the `Endpoint` should fit together when making the full request.

### Defining a Server

First, define a server that conforms to `ServerDefinition`. This encapsulates your base URLs for different environments:

```swift
import Endpoints
import Foundation

struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://local-api.example.com")!,
            .staging: URL(string: "https://staging-api.example.com")!,
            .production: URL(string: "https://api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}
```

To get started, first create a type (struct or class) conforming to `Endpoint`. There are only two required elements to conform: defining the `Response` and creating the `Definition`.

`Endpoints` and `Definitions` now include server information, eliminating the need to pass environments at call time. Servers implement a `requestProcessor` which has a final hook before `URLRequest` creation to modify the `URLRequest` to attach authentication or signatures.

### Basic Endpoint Example

```Swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource"
    )

    struct Response: Decodable {
        let resourceId: String
        let resourceName: String
    }
}
```

This includes a `Response` associated type (can be typealiased to a more complex existing type) which defines how the response will come back from the request. The server is specified via `typealias Server = ApiServer`.

Then usage can employ the `URLSession` extensions:

#### Usage
```Swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

Notice that the API no longer requires passing an environment - it's handled automatically by the server definition.

### Async/Await

```swift
do {
    let response = try await URLSession.shared.response(with: MyEndpoint())
    // handle response
} catch {
    // handle error
}
```

## Testing with EndpointsMocking

Endpoints includes a comprehensive mocking system through the `EndpointsMocking` module:

```swift
import Testing
import Endpoints
import EndpointsMocking

@Test func testMyEndpoint() async throws {
    try await withMock(MyEndpoint.self, action: .return(.init(resourceId: "123", resourceName: "Test"))) {
        let response = try await URLSession.shared.response(with: MyEndpoint())
        #expect(response.resourceId == "123")
    }
}
```

The mocking system supports:
- Returning successful responses
- Returning error responses
- Throwing network errors
- Dynamic response generation
- Combine publisher mocking

To find out more about the pieces of the `Endpoint`, check out [Defining a ResponseType](https://github.com/velos/Endpoints/wiki/DefiningResponseType) on the wiki.

## Examples

To browse more complex examples, make sure to check out the [Examples](https://github.com/velos/Endpoints/wiki/Examples) wiki page or the documentation in Xcode.

## Requirements

- Swift 6.0+
- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/velos/Endpoints.git", from: "2.0.0")
]
```

For testing, also add:

```swift
testTarget(
    name: "YourTests",
    dependencies: ["Endpoints", "EndpointsMocking"]
)
```

## Documentation

Full documentation is available in Xcode (Product > Build Documentation) and includes:
- API reference for all types
- Comprehensive examples
- Mocking guide
- Best practices

## Migration from 0.4.0

If you're upgrading from version 0.4.0 or earlier, the main changes are:

1. **ServerDefinition replaces EnvironmentType** - Define your environments in a `ServerDefinition` conforming type
2. **No more environment parameter** - Remove `in: .production` from all API calls
3. **Add Server typealias** - Add `typealias Server = YourServer` to your endpoints
4. **Swift 6.0 required** - Update your Swift toolchain

See the [Migration Guide](https://github.com/velos/Endpoints/wiki/Migration) for detailed instructions.

## License

Endpoints is released under the MIT license. See LICENSE for details.
