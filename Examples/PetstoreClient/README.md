# Petstore plugin example

PetstoreAPI contains the specification, `Petstore.endpoints.swift`, and a public
static authentication extension. The Swift config selects public access and a
custom parameter naming strategy. The target links `EndpointsGeneratorConfig`;
the config remains an ordinary Swift source and a build-command input.

PetstoreClientTests imports the generated public API from a second module and
checks inherited HeaderKeyAuth authentication, request wire values, repeated query
tags, and status-union decoding with HTTPResponseJSONDecoder.

Run from the repository root (the plugin sandbox is enabled by default):

```sh
swift build --package-path Examples/PetstoreClient --build-tests -Xswiftc -warnings-as-errors
swift test --package-path Examples/PetstoreClient -Xswiftc -warnings-as-errors
```

Do not exclude the specification or Swift config from the target. No lock file
or manual config compilation is needed. Keep the config's version header and
`petstoreConfiguration` entry constant; imports and other nondeterministic channels
are checked before it is compiled and evaluated by the build tool.

For an Xcode project, link `EndpointsGeneratorConfig`, add the plugin to the source
target, and include the spec and Swift config as target inputs. Keep the config
in Compile Sources and remove the spec from Copy Bundle Resources. Native Xcode
and sandbox qualification is recorded separately in
../../docs/OpenAPIGenerator-Verification.md.
