# ``EndpointsMocking``

Replace endpoint responses in tests without making network requests.

## Overview

`withMock` replaces the response for an endpoint type while a block of test code runs:

```swift
import Testing
import Endpoints
import EndpointsMocking

@Test func loadsProfile() async throws {
    try await withMock(ProfileEndpoint.self, action: .return(.init(name: "Zac"))) {
        let profile = try await URLSession.shared.response(with: ProfileEndpoint())
        #expect(profile.name == "Zac")
    }
}
```

The types you use inside a mock, `MockAction`, `MockContinuation`, and `MockRegistry`, are part of the Endpoints module. The Mocking article in the Endpoints documentation covers errors, dynamic responses, mocking several endpoints, and testing the token refresh flow.

Mocking is available in DEBUG builds on Apple platforms.

## Topics

### Mocking Endpoints

- ``withMock(_:action:test:)``
- ``withMock(_:_:test:)``
- ``withMock(registering:test:)``
