# Endpoints

![CI](https://github.com/velos/Endpoints/workflows/CI/badge.svg) ![Documentation](https://github.com/velos/Endpoints/workflows/Documentation/badge.svg)

Endpoints is a small library for creating statically and strongly-typed definitions of endpoints with paths, methods, inputs and outputs.

## Purpose

The purpose of Endpoints is to, in a type-safe way, define how to create a `URLRequest` from typed properties and, additionally, define how a response for the request should be handled. The library not only includes the ability to create these requests in a type-safe way, but also includes helpers to perform the requests using `URLSession`. Endpoints does not try to wrap the URL loading system to provide features on top of it like Alamofire. Instead, Endpoints focuses on defining endpoints and associated data to produce a request as a `URLRequest` object to be plugged into vanilla `URLSession`s. However, this library could be used in conjunction with Alamofire if desired.

## Features

- **Type-safe endpoint definitions** - Define endpoints with compile-time checking of paths, parameters, and headers
- **Server definition with multiple environments** - Support for local, development, staging, and production environments with easy switching
- **Authentication with automatic token refresh** - Declare an authentication method per server or per endpoint; credentials are applied, refreshed, and retried transparently
- **Built-in mocking support** - Comprehensive testing utilities through the `EndpointsMocking` module
- **Swift 6.0 compatible** - Built with modern Swift concurrency, Sendable support and typed throws
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

`Endpoints` and `Definitions` now include server information, eliminating the need to pass environments at call time. Servers can implement a `requestProcessor`, a final synchronous hook after `URLRequest` creation for static request modification such as signing. For credentials that can expire and be refreshed, use [Authentication](#authentication) instead.

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

## Authentication

Authentication is declared on the endpoint, the same way decoders are. A server names the `AuthenticationMethod` its endpoints use, and every endpoint inherits it:

```swift
struct ApiServer: ServerDefinition {
    static let auth = HeaderKeyAuth(key: "my-api-key")

    var baseUrls: [Environments: URL] { ... }
    static var defaultEnvironment: Environments { .production }
}

struct ProfileEndpoint: Endpoint {
    typealias Server = ApiServer  // authenticated, nothing else to declare

    static let definition: Definition<ProfileEndpoint> = Definition(method: .get, path: "profile")
    struct Response: Decodable { let name: String }
}
```

Requests then go through the ordinary `URLSession` API — there is no separate session type, and credentials are applied automatically:

```swift
let response = try await URLSession.shared.response(with: ProfileEndpoint())
```

An individual endpoint can override its server's method — to opt out on a login or refresh endpoint, or to use a different scheme entirely:

```swift
struct LoginEndpoint: Endpoint {
    typealias Server = ApiServer
    static var auth: NoAuth { NoAuth() }         // unauthenticated
    ...
}

struct MetricsEndpoint: Endpoint {
    typealias Server = ApiServer
    static let auth = HeaderKeyAuth(key: clientKey, header: "X-Client-Key", prefix: nil)
    ...
}
```

Declare the method as a `static let` so all endpoints on a server share one instance. That shared instance is what allows a stateful method like `JWTAuth` to coalesce concurrent token refreshes across every endpoint — a computed `static var` would hand out a fresh instance per request, losing tokens. Debug builds assert if that happens, so the mistake surfaces in development rather than as mysterious re-authentication in production.

Servers that declare no `auth` use `NoAuth`, so existing endpoints keep working unchanged.

The async/await and Combine APIs both apply authentication, including refresh and retry. Cancelling a Combine subscription cancels the underlying request.

The closure-based `endpointTask` is the exception: it hands back a `URLSessionDataTask` synchronously, so it cannot await an asynchronous `authenticate` before returning. It is constrained to unauthenticated endpoints — calling it with an authenticated endpoint is a compile error rather than a request that silently skips its credentials. Use `response(with:)` or `endpointPublisher(with:)` for authenticated endpoints.

Built-in authentication methods:

- `HeaderKeyAuth` - A static key in a header, with an optional prefix. Defaults to `Authorization: Bearer <key>`; use `HeaderKeyAuth(key: "secret", header: "X-API-Key", prefix: nil)` for custom API-key headers.
- `BasicAuth` - HTTP Basic credentials (RFC 7617), UTF-8 encoded.
- `CookieAuth` - A static cookie, merged with any cookies already on the request.
- `JWTAuth` - Access/refresh token pairs with automatic refresh (see below).
- `NoAuth` - Passes requests through unchanged. Useful as a generic placeholder.

### Token refresh with JWTAuth

`JWTAuth` holds an access/refresh token pair. When a request fails with a status code in `refreshTriggerStatusCodes` (401 by default), your `refreshHandler` is called and the request is retried with the new tokens. Concurrent refreshes are coalesced into a single operation, and a request that fails with already-replaced tokens will not trigger a redundant refresh — important when your backend rotates single-use refresh tokens.

If you know when the access token expires, set `TokenPair.expiresAt`: tokens within `expiryLeeway` (30 seconds by default) of expiring are then refreshed *before* the request is sent, skipping the round trip that would have been rejected. Without `expiresAt`, refresh is purely reactive.

```swift
struct ApiServer: ServerDefinition {
    static let auth = JWTAuth(
        initialTokens: loadTokensFromKeychain(),
        refreshHandler: { refreshToken in
            // Exchange the refresh token for new tokens against your backend.
            let response = try await URLSession.shared.response(with: RefreshEndpoint(token: refreshToken))
            return JWTAuth.TokenPair(accessToken: response.access, refreshToken: response.refresh)
        },
        onTokensUpdated: { tokens in
            saveTokensToKeychain(tokens)
        },
        onRefreshFailed: { error in
            await logOut()
        }
    )

    var baseUrls: [Environments: URL] { ... }
    static var defaultEnvironment: Environments { .production }
}
```

> **Important:** the refresh endpoint must not be authenticated by the same `JWTAuth` — the request would wait on the very refresh that is waiting on it. Give it `static var auth: NoAuth { NoAuth() }`; it authenticates with the refresh token, not the access token. If you do hit this, the request fails with a `RefreshReentrancyError` explaining the fix rather than hanging.

After a login or logout, update the tokens with `await ApiServer.auth.setTokens(_:)` or `await ApiServer.auth.clearTokens()`.

### Custom authentication methods

Conform to `AuthenticationMethod` to implement your own scheme. Only `authenticate(request:)` is required; refreshable credentials also implement `shouldReauthenticate(for:response:)` and `reauthenticate(after:)`:

```swift
struct SignatureAuth: AuthenticationMethod {
    let secret: String

    func authenticate(request: URLRequest) async throws(AuthenticationError) -> URLRequest {
        var request = request
        request.setValue(sign(request, with: secret), forHTTPHeaderField: "X-Signature")
        return request
    }
}
```

For failures that don't fit the built-in `AuthenticationError` cases (credential storage errors, signing failures), wrap them in `AuthenticationError.custom(underlying:)`.

### Error handling

All failures — including authentication failures — surface as the endpoint's typed `EndpointTaskError`, so a single `catch` covers everything:

```swift
do {
    let response = try await URLSession.shared.response(with: MyEndpoint())
} catch {
    // error is MyEndpoint.TaskError — no casting needed
    switch error {
    case .authenticationError(.refreshFailed(let underlying)):
        // token refresh failed; underlying holds the refresh error
    case .errorResponse(_, let errorResponse):
        // typed server error response
    default:
        break
    }
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

When a flow touches several endpoints, register them together with a `MockRegistry` instead of nesting `withMock` calls:

```swift
try await withMock { mocks in
    mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
    mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac")))
} test: {
    let profile = try await session.response(with: ProfileEndpoint())
}
```

Mocks are scoped per endpoint type: endpoints without a registered mock pass through to the real transport, nested `withMock` scopes merge, and an inner mock for the same endpoint type shadows the outer one for the duration of its scope.

The mocking system supports:
- Returning successful responses
- Returning error responses
- Throwing network errors
- Dynamic response generation
- Combine publisher mocking
- Authenticated and unauthenticated endpoints alike

Note that mocks bypass authentication entirely: a mocked request never invokes the endpoint's `AuthenticationMethod`, and mock errors do not trigger the refresh/retry loop. To simulate an authentication failure, throw one directly with `.throw(.authenticationError(.notAuthenticated))`; to test the refresh flow itself, use a `URLProtocol`-based fake transport.

To find out more about the pieces of the `Endpoint`, check out [Defining a ResponseType](https://github.com/velos/Endpoints/wiki/DefiningResponseType) on the wiki.

## Examples

To browse more complex examples, make sure to check out the [Examples](https://github.com/velos/Endpoints/wiki/Examples) wiki page or the documentation in Xcode.

## Requirements

- Swift 6.0+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ to build endpoints and create `URLRequest`s
- macOS 12.0+ for the async/await and Combine request APIs (`response(with:)`, `endpointPublisher(with:)`), and therefore for authentication

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/velos/Endpoints.git", from: "0.5.0")
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
