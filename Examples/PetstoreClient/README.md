# Petstore plugin example

PetstoreAPI contains the spec, public config, and a public static auth extension.
PetstoreClientTests is a second module, importing the public generated API and
checking that Server.Auth and inherited endpoint authentication are HeaderKeyAuth.

Run from the repository root:

```sh
swift build --disable-sandbox --package-path Examples/PetstoreClient --build-tests
swift test --disable-sandbox --package-path Examples/PetstoreClient
```

Do not exclude the spec or sidecar from the target: the build plugin must discover
them. SwiftPM may print benign unhandled-file warnings for these inputs; observed
local behavior and the invalidation matrix are recorded in
../../docs/OpenAPIGenerator-Verification.md.

For an Xcode project, add the plugin to the source target and include the spec and
sidecar as target inputs. Remove those files from Copy Bundle Resources so the
spec is not bundled. Native Xcode project verification is a manual follow-up.
