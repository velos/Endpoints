# ``Endpoints``

Describe HTTP endpoints as Swift types, and send them with `URLSession`.

## Overview

An ``Endpoint`` describes a request: its server, method, path, parameters, headers, body, and response type. Endpoints builds a `URLRequest` from it and decodes the response, using plain `URLSession` rather than its own networking layer.

```swift
struct ProfileEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<ProfileEndpoint> = Definition(
        method: .get,
        path: "users/\(path: \.userId)/profile"
    )

    struct Response: Decodable {
        let name: String
    }

    struct PathComponents {
        let userId: String
    }

    let pathComponents: PathComponents
}

let profile = try await URLSession.shared.response(with: ProfileEndpoint(pathComponents: .init(userId: "42")))
```

Start with <doc:Examples> for servers, environments, and common request shapes. Then read <doc:Authentication> to attach credentials, and <doc:Mocking> to test.

## Topics

### Essentials

- <doc:Examples>
- ``Endpoint``
- ``Definition``
- ``ServerDefinition``

### Servers and Environments

- ``GenericServer``
- ``TypicalEnvironments``

### Building Requests

- ``Method``
- ``PathTemplate``
- ``PathRepresentable``
- ``Parameter``
- ``ParameterRepresentable``
- ``QueryEncodingStrategy``
- ``Header``
- ``HeaderField``
- ``HeaderCategory``

### Encoding and Decoding

- ``EncoderType``
- ``DecoderType``
- ``EmptyCodable``
- ``MultipartFormEncoder``
- ``MultipartFormFile``
- ``MultipartFormJSON``

### Authentication

- <doc:Authentication>
- ``AuthenticationMethod``
- ``AuthenticationError``
- ``RefreshReentrancyError``
- ``NoAuth``
- ``HeaderKeyAuth``
- ``BasicAuth``
- ``CookieAuth``
- ``JWTAuth``

### Sending Requests and Handling Errors

- ``Foundation/URLSession``
- ``EndpointTaskError``
- ``EndpointError``

### Testing

- <doc:Mocking>
- ``MockRegistry``
- ``MockContinuation``
- ``MockAction``
