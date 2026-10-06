# Endpoints

![CI](https://github.com/velos/Endpoints/workflows/CI/badge.svg)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelos%2FEndpoints%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/velos/Endpoints)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelos%2FEndpoints%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/velos/Endpoints)

Endpoints describes HTTP endpoints as Swift types: the path, method, parameters, headers, body, and response. From that description it builds a `URLRequest` and decodes the response, using plain `URLSession`. It doesn't replace the URL loading system the way Alamofire does, and the requests it builds work with Alamofire if you prefer that.

- **Typed endpoints.** Paths, query and form parameters, and headers are checked at compile time.
- **Servers and environments.** Each server lists a base URL per environment, and every request can pick its environment.
- **Authentication.** Declare an authentication method per server or per endpoint. Credentials are applied to each request, and refreshable tokens are refreshed and the request retried when needed.
- **Mocking.** The `EndpointsMocking` module replaces responses per endpoint type in tests.
- **Swift 6.** Built for strict concurrency, with `Sendable` types and typed throws.
- **async/await and Combine.** Plus a completion-handler API for unauthenticated endpoints.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/velos/Endpoints.git", from: "0.5.1")
]
```

Add `Endpoints` to your app target, and `EndpointsMocking` to your test target:

```swift
.testTarget(
    name: "YourAppTests",
    dependencies: [
        .product(name: "Endpoints", package: "Endpoints"),
        .product(name: "EndpointsMocking", package: "Endpoints")
    ]
)
```

## Getting Started

### Define a server

A server lists its base URL for each environment and names the environment requests use by default:

```swift
import Endpoints
import Foundation

struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        [
            .local: URL(string: "https://local-api.example.com")!,
            .staging: URL(string: "https://staging-api.example.com")!,
            .production: URL(string: "https://api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}
```

`Environments` defaults to `TypicalEnvironments` (`local`, `development`, `staging`, `production`). To use your own cases, declare `typealias Environments = MyEnvironments` with any `Hashable & Sendable` type.

### Define an endpoint

An endpoint names its server, its `Definition`, and its `Response` type:

```swift
struct ProfileEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<ProfileEndpoint> = Definition(
        method: .get,
        path: "users/\(path: \.userId)/profile",
        parameters: [
            .query("fields", path: \.fields)
        ]
    )

    struct Response: Decodable {
        let name: String
        let email: String
    }

    struct PathComponents {
        let userId: String
    }

    struct ParameterComponents {
        let fields: String?
    }

    let pathComponents: PathComponents
    let parameterComponents: ParameterComponents
}
```

A `Decodable` response is decoded with `JSONDecoder` by default. Use `Data` to receive the raw body, or `Void` to ignore it. `nil` query and form values are left out of the request. See the [Examples](Sources/Endpoints/Endpoints.docc/Examples.md) guide for headers, request bodies, form parameters, multipart uploads, custom encoders and decoders, and typed error responses.

### Make a request

```swift
let endpoint = ProfileEndpoint(
    pathComponents: .init(userId: "42"),
    parameterComponents: .init(fields: nil)
)

let profile = try await URLSession.shared.response(with: endpoint)
```

With Combine:

```swift
URLSession.shared.endpointPublisher(with: endpoint)
    .sink { completion in
        if case .failure(let error) = completion {
            // handle ProfileEndpoint.TaskError
        }
    } receiveValue: { profile in
        // handle ProfileEndpoint.Response
    }
    .store(in: &cancellables)
```

Canceling the subscription cancels the request. For unauthenticated endpoints, `endpointTask(with:completion:)` returns a `URLSessionDataTask` that you start with `resume()`.

To build the request without sending it, call `endpoint.urlRequest()`.

## Environments

Every request method takes an `environment:` argument, which defaults to the server's `defaultEnvironment`:

```swift
let profile = try await URLSession.shared.response(with: endpoint, environment: .staging)
```

The environment is a per-request value, not global state, so different parts of an app can use different environments at the same time.

A server can also provide a `requestProcessor`, a synchronous hook that runs on every request after it is built. Use it for static changes such as adding a build-number header. Use authentication for credentials.

## Authentication

A server declares the authentication method its endpoints use, and every endpoint on that server inherits it:

```swift
struct ApiServer: ServerDefinition {
    static let auth = HeaderKeyAuth(key: "my-api-key")

    var baseUrls: [Environments: URL] { ... }
    static var defaultEnvironment: Environments { .production }
}
```

Requests then use the same `URLSession` methods, and credentials are applied automatically. A server that declares no `auth` uses `NoAuth`.

An endpoint can override its server's method, either to opt out or to use a different scheme:

```swift
struct LoginEndpoint: Endpoint {
    typealias Server = ApiServer
    static var auth: NoAuth { NoAuth() }
    ...
}

struct MetricsEndpoint: Endpoint {
    typealias Server = ApiServer
    static let auth = HeaderKeyAuth(key: clientKey, header: "X-Client-Key", prefix: nil)
    ...
}
```

Declare authentication methods with `static let`, so every request shares one instance. A stateful method like `JWTAuth` keeps its tokens on that instance and relies on it to combine concurrent refreshes. A computed `static var` creates a new instance on every request and loses the tokens. Debug builds assert when this happens.

The async/await and Combine APIs apply authentication, including refresh and retry. `endpointTask(with:completion:)` returns its task synchronously, so it can't wait for authentication. It only accepts endpoints whose `auth` is `NoAuth`, and using it with an authenticated endpoint is a compile error.

### Built-in methods

| Method | Sends |
|---|---|
| `HeaderKeyAuth` | A static key in a header. Defaults to `Authorization: Bearer <key>`. Pass `header:` and `prefix: nil` for headers like `X-API-Key: <key>`. |
| `BasicAuth` | HTTP Basic credentials ([RFC 7617](https://www.rfc-editor.org/rfc/rfc7617)), UTF-8 encoded. |
| `CookieAuth` | A static cookie, merged with any cookies already on the request. |
| `JWTAuth` | An access token, refreshed with a refresh token when it expires or is rejected. |
| `NoAuth` | Nothing. The request passes through unchanged. |

### Refreshing tokens with JWTAuth

`JWTAuth` holds an access token and a refresh token. When a response has a status code in `refreshTriggerStatusCodes` (401 by default), it calls your `refreshHandler` and retries the request with the new tokens. Concurrent requests that need a refresh share one call to the handler. A request rejected with tokens that have already been replaced doesn't trigger another refresh, which matters when your backend issues single-use refresh tokens.

If you know when the access token expires, set `TokenPair.expiresAt`. A token within `expiryLeeway` (30 seconds by default) of expiring is then refreshed before the request is sent, which saves a rejected round trip.

```swift
struct ApiServer: ServerDefinition {
    static let auth = JWTAuth(
        initialTokens: loadTokensFromKeychain(),
        refreshHandler: { refreshToken in
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

> **Important:** Give the refresh endpoint `static var auth: NoAuth { NoAuth() }`. It authenticates with the refresh token, and a request authenticated by the same `JWTAuth` would wait for the refresh that is waiting for it. If that happens, the request fails with a `RefreshReentrancyError` instead of hanging.

After a login or logout, call `await ApiServer.auth.setTokens(_:)` or `await ApiServer.auth.clearTokens()`. Either call replaces a refresh that is still in progress. That refresh's tokens are discarded, so a refresh that started just before a logout can't sign the user back in. Requests that were waiting for it use the new tokens, or fail with `.notAuthenticated` after a logout.

`onTokensUpdated` isn't called for a discarded refresh, but a call that has already started can't be stopped. If your token store must never hold tokens after a logout, have it reject writes from a session that has since been signed out.

To send the token in a different header or without a prefix, pass a configuration such as `JWTAuth.Configuration(header: "X-Access-Token", tokenPrefix: "")`.

### Credentials and environments

Credentials usually belong to one environment: a token issued by staging isn't valid against production. A server-wide `static let auth` fits an app that talks to one environment at a time.

An app that talks to several environments or accounts at once should pass the environment and credentials together on each request:

```swift
struct ApiClient {
    let environment: ApiServer.Environments
    let auth: JWTAuth   // one instance per client, so its refreshes are shared

    func profile(_ endpoint: ProfileEndpoint) async throws -> ProfileEndpoint.Response {
        try await URLSession.shared.response(with: endpoint, environment: environment, auth: auth)
    }
}
```

`auth:` accepts any `AuthenticationMethod` and defaults to the endpoint's `auth`. Two clients like this can make requests concurrently without affecting each other. A server whose credentials always come from the call site doesn't need to declare `auth`.

### Custom methods

Conform to `AuthenticationMethod`. Only `authenticate(request:)` is required:

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

Credentials that can be refreshed also implement `shouldReauthenticate(for:response:)` and `reauthenticate(after:)`, and can set `maxRetryAttempts`. Wrap failures that don't match a built-in `AuthenticationError` case, such as a keychain error, in `AuthenticationError.custom(underlying:)`.

## Error Handling

Every failure, including authentication failures, is thrown as the endpoint's `TaskError`, so a `catch` needs no casting:

```swift
do {
    let profile = try await URLSession.shared.response(with: endpoint)
} catch {
    switch error {
    case .errorResponse(let httpResponse, let errorResponse):
        // The server returned an error, decoded as the endpoint's ErrorResponse type.
    case .authenticationError(.refreshFailed(let underlying)):
        // The token refresh failed.
    case .internetConnectionOffline:
        // The device is offline.
    default:
        break
    }
}
```

## Testing

`withMock` from `EndpointsMocking` replaces the response for an endpoint type inside a test:

```swift
import Testing
import Endpoints
import EndpointsMocking

@Test func loadsProfile() async throws {
    try await withMock(ProfileEndpoint.self, action: .return(.init(name: "Zac", email: "zac@example.com"))) {
        let profile = try await URLSession.shared.response(with: endpoint)
        #expect(profile.name == "Zac")
    }
}
```

To mock several endpoint types at once, register them together:

```swift
try await withMock { mocks in
    mocks.register(RefreshEndpoint.self, action: .return(.init(access: "new", refresh: "next")))
    mocks.register(ProfileEndpoint.self, action: .return(.init(name: "Zac", email: "zac@example.com")))
} test: {
    let profile = try await URLSession.shared.response(with: endpoint)
}
```

Endpoint types without a mock make real requests. Mocked requests skip authentication. See the [Mocking](Sources/Endpoints/Endpoints.docc/Mocking.md) guide for errors, dynamic responses, and testing the refresh flow.

## Requirements

- Swift 6.0 or later
- iOS 13, macOS 10.15, tvOS 13, or watchOS 6 to define endpoints and build requests
- macOS 12 for the async/await and Combine request methods, and so for authentication. Other platforms have no additional requirement.
- `EndpointsMocking` is available on Apple platforms only. Linux builds include `Endpoints`.

## Documentation

The [API documentation](https://swiftpackageindex.com/velos/Endpoints/documentation) is hosted on the Swift Package Index and updated with each release, for both `Endpoints` and `EndpointsMocking`. You can also build it in Xcode with Product > Build Documentation. The [Examples](Sources/Endpoints/Endpoints.docc/Examples.md), [Authentication](Sources/Endpoints/Endpoints.docc/Authentication.md), and [Mocking](Sources/Endpoints/Endpoints.docc/Mocking.md) guides are readable on GitHub.

## Migrating from 0.4

- **Replace `EnvironmentType` with a `ServerDefinition`.** List each environment's base URL in `baseUrls`, and move any `requestProcessor` onto the server.
- **Name the server on each endpoint** with `typealias Server = ApiServer`.
- **Drop the `in:` argument.** `response(in: environment, with: endpoint)` becomes `response(with: endpoint)`, which uses the server's default environment, or `response(with: endpoint, environment: .staging)`. The same applies to `endpointPublisher` and `endpointTask`. `urlRequest(in:)` now takes one of the server's environments.
- **Move credentials to `auth`.** Credentials set in a `requestProcessor` keep working, but declaring them with `static let auth` adds refresh and retry.
- **Remove error casts.** Request methods use typed throws, so the error in a `catch` is already the endpoint's `TaskError`.
- **Update to Swift 6.0.**

## License

Endpoints is released under the MIT license. See [LICENSE](LICENSE) for details.
