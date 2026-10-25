# Petstore plugin example

PetstoreAPI contains the specification and a static authentication extension.
PetstoreClientTests checks inherited HeaderKeyAuth authentication, request wire
values, repeated query tags, and the status union decoded with HTTPResponseJSONDecoder.

Until 3N-2 makes `<Stem>.endpoints.swift` configuration available, the plugin uses
default internal access and the tests use `@testable import PetstoreAPI`.
TODO(3N-2): add a Swift config with `accessLevel: .public`, make the auth witness
public, and restore the second-module public API check with an ordinary import.
This keeps the example on the supported plugin path without exposing the CLI's
private configuration transport.

Run from the repository root:

```sh
swift build --disable-sandbox --package-path Examples/PetstoreClient --build-tests -Xswiftc -warnings-as-errors
swift test --disable-sandbox --package-path Examples/PetstoreClient -Xswiftc -warnings-as-errors
```

Do not exclude the specification from the target: the build plugin must discover
it. SwiftPM may print an unhandled-file notice for the specification. Observed
local behavior is recorded in ../../docs/OpenAPIGenerator-Verification.md.

For an Xcode project, add the plugin to the source target and include the spec as
a target input. Remove it from Copy Bundle Resources so it is not bundled.
