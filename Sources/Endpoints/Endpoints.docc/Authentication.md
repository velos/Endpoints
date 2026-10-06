# Authentication

Apply credentials to requests, refresh expired tokens, and retry rejected requests.

## Overview

An ``AuthenticationMethod`` adds credentials to each request before it is sent. Methods that support refresh can also renew credentials after a rejected response, and the request is then retried. The async/await and Combine request methods handle this for you.

## Declaring authentication

A server declares the method its endpoints share with ``ServerDefinition/auth``:

```swift
struct ApiServer: ServerDefinition {
    static let auth = HeaderKeyAuth(key: "my-api-key")

    var baseUrls: [Environments: URL] { ... }
    static var defaultEnvironment: Environments { .production }
}
```

Every endpoint on the server inherits it, and requests use the usual methods:

```swift
let profile = try await URLSession.shared.response(with: ProfileEndpoint())
```

A server that declares no `auth` uses ``NoAuth``.

Declare authentication methods with `static let`. A stateful method such as ``JWTAuth`` keeps its tokens on the instance, and every request needs to see the same one. A computed `static var` creates a new instance per request and loses the tokens. Debug builds assert when an endpoint's `auth` returns a different instance each time.

### Overriding per endpoint

Set ``Endpoint/auth`` on an endpoint to opt out of its server's method, or to use a different one:

```swift
struct LoginEndpoint: Endpoint {
    typealias Server = ApiServer
    static var auth: NoAuth { NoAuth() }
    // ...
}

struct MetricsEndpoint: Endpoint {
    typealias Server = ApiServer
    static let auth = HeaderKeyAuth(key: clientKey, header: "X-Client-Key", prefix: nil)
    // ...
}
```

### Passing credentials per request

The request methods take an `auth:` argument, which defaults to the endpoint's ``Endpoint/auth``. Credentials usually belong to one environment, so an app that talks to several environments or accounts at once should pass both together:

```swift
struct ApiClient {
    let environment: ApiServer.Environments
    let auth: JWTAuth   // one instance per client, so its refreshes are shared

    func profile() async throws -> ProfileEndpoint.Response {
        try await URLSession.shared.response(with: ProfileEndpoint(), environment: environment, auth: auth)
    }
}
```

Requests from different clients don't affect each other. A server whose credentials always come from the call site doesn't need to declare `auth`.

### Completion handlers

`endpointTask(with:completion:)` returns its task synchronously, so it can't wait for an asynchronous ``AuthenticationMethod/authenticate(request:)``. It only accepts endpoints whose `auth` is ``NoAuth``. Using it with an authenticated endpoint is a compile error.

## Built-in methods

- ``HeaderKeyAuth`` sends a static key in a header. It defaults to `Authorization: Bearer <key>`. Pass `header:` and `prefix: nil` for a header like `X-API-Key: <key>`.
- ``BasicAuth`` sends HTTP Basic credentials, encoded as UTF-8.
- ``CookieAuth`` sends a static cookie, merged with any cookies already on the request.
- ``JWTAuth`` sends an access token and refreshes it with a refresh token.
- ``NoAuth`` leaves the request unchanged.

## Refreshing tokens

``JWTAuth`` holds a ``JWTAuth/TokenPair``. It refreshes in two cases:

- **After a rejection.** When a response's status code is in ``JWTAuth/Configuration/refreshTriggerStatusCodes`` (401 by default), it calls your refresh handler and retries the request once with the new tokens.
- **Before expiry.** When ``JWTAuth/TokenPair/expiresAt`` is set and the token is within ``JWTAuth/Configuration/expiryLeeway`` of expiring (30 seconds by default), it refreshes before sending the request.

Concurrent requests that need a refresh share one call to the handler. A request rejected with tokens that have already been replaced uses the new tokens without refreshing again, so single-use refresh tokens aren't wasted.

```swift
struct ApiServer: ServerDefinition {
    static let auth = JWTAuth(
        initialTokens: loadTokensFromKeychain(),
        refreshHandler: { refreshToken in
            let response = try await URLSession.shared.response(with: RefreshEndpoint(token: refreshToken))
            return JWTAuth.TokenPair(
                accessToken: response.access,
                refreshToken: response.refresh,
                expiresAt: response.expiresAt
            )
        },
        onTokensUpdated: { tokens in
            saveTokensToKeychain(tokens)
        },
        onRefreshFailed: { error in
            await logOut()
        }
    )

    // ...
}

struct RefreshEndpoint: Endpoint {
    typealias Server = ApiServer
    static var auth: NoAuth { NoAuth() }
    // ...
}
```

> Important: The refresh endpoint must not use the same ``JWTAuth``. Its request would wait for the refresh that is waiting for it. Give it ``NoAuth``, since it authenticates with the refresh token. If a refresh handler does make a request through its own `JWTAuth`, that request fails with ``RefreshReentrancyError`` instead of hanging.

### Logging in and out

Call ``JWTAuth/setTokens(_:)`` after a login and ``JWTAuth/clearTokens()`` after a logout.

Either call replaces a refresh that is still in progress. That refresh's tokens are discarded, and neither `onTokensUpdated` nor `onRefreshFailed` is called for it, so a refresh that started just before a logout can't sign the user back in. Requests waiting for that refresh use the new tokens, or fail with ``AuthenticationError/notAuthenticated`` after a logout.

An `onTokensUpdated` call that has already started can't be stopped. If a logout happens while it is saving tokens, the save can finish afterward. If your token store must never hold tokens after a logout, have it reject writes from a session that has been signed out.

### Configuration

``JWTAuth/Configuration`` sets the header, the token prefix, the status codes that trigger a refresh, and the expiry leeway:

```swift
let auth = JWTAuth(
    initialTokens: tokens,
    configuration: .init(header: "X-Access-Token", tokenPrefix: "", refreshTriggerStatusCodes: [401, 419]),
    refreshHandler: refresh
)
```

An empty prefix sends the token alone.

## Custom methods

Conform to ``AuthenticationMethod``. Only ``AuthenticationMethod/authenticate(request:)`` is required:

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

To support refresh, also implement:

- ``AuthenticationMethod/shouldReauthenticate(for:response:)``, which decides whether a failure should trigger a refresh. It usually checks the status code.
- ``AuthenticationMethod/reauthenticate(after:)``, which renews the credentials. It receives the failed request as it was sent. If your credentials have changed since then, return without refreshing. Combine concurrent calls into one refresh.
- ``AuthenticationMethod/maxRetryAttempts``, the number of retries after refreshing. It defaults to 1.

A method that stores credentials should be an actor or a `final class`, declared with `static let`.

Wrap failures that don't match a built-in ``AuthenticationError`` case in ``AuthenticationError/custom(underlying:)``.

## Errors

Authentication failures are thrown as ``EndpointTaskError/authenticationError(_:)`` on the endpoint's `TaskError`:

```swift
do {
    let profile = try await URLSession.shared.response(with: ProfileEndpoint())
} catch {
    switch error {
    case .authenticationError(.notAuthenticated):
        // No tokens. Show the login screen.
    case .authenticationError(.refreshFailed(let underlying)):
        // The refresh handler threw `underlying`.
    default:
        break
    }
}
```

If the retried request is rejected again, the error is the server's response, such as ``EndpointTaskError/errorResponse(httpResponse:response:)``, not an authentication error.

## Mocks

A mocked request skips authentication. See <doc:Mocking>.

## Topics

### Methods

- ``AuthenticationMethod``
- ``NoAuth``
- ``HeaderKeyAuth``
- ``BasicAuth``
- ``CookieAuth``
- ``JWTAuth``

### Errors

- ``AuthenticationError``
- ``RefreshReentrancyError``
