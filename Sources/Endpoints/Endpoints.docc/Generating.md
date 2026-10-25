# Generating Endpoints from OpenAPI

Generate a server, models, and endpoints from an OpenAPI document when you build.

## Overview

Add `Petstore.openapi.yaml` to a target and apply the `EndpointsGeneratorPlugin` build tool plugin. Every build then generates a `Petstore` namespace containing a ``ServerDefinition``, a model for each schema, and an ``Endpoint`` for each operation. The generated code is ordinary Endpoints code: you send requests with `URLSession`, attach credentials with ``ServerDefinition/auth``, and mock endpoints in tests as described in <doc:Mocking>.

The generator reads OpenAPI 3.0, 3.1, and 3.2 documents in YAML or JSON. Generated files aren't added to your source tree. They live in the build directory and are compiled into the target.

The output is deterministic. The same specification, configuration file, and generator version produce byte-identical files on every machine, so generated code doesn't change between developers or between a laptop and CI.

## Setup

### Swift packages

Add the package, apply the plugin to the target that contains the specification, and depend on `Endpoints`:

```swift
dependencies: [
    .package(url: "https://github.com/velos/Endpoints.git", from: "0.6.0")
],
targets: [
    .target(
        name: "PetstoreAPI",
        dependencies: [
            .product(name: "Endpoints", package: "Endpoints")
        ],
        plugins: [
            .plugin(name: "EndpointsGeneratorPlugin", package: "Endpoints")
        ]
    )
]
```

If the target has a configuration file (see <doc:Generating#Configuring-the-generator>), it also needs the `EndpointsGeneratorConfig` product:

```swift
dependencies: [
    .product(name: "Endpoints", package: "Endpoints"),
    .product(name: "EndpointsGeneratorConfig", package: "Endpoints")
],
```

Without it, the plugin reports `Petstore.endpoints.swift requires the EndpointsGeneratorConfig product as a dependency of target 'PetstoreAPI'`. `EndpointsGeneratorConfig` has no dependencies of its own, and the configuration adds a single constant to your module.

### Xcode projects

1. Add the Endpoints package to the project, and add the `Endpoints` library to your target. If you use a configuration file, add `EndpointsGeneratorConfig` too.
2. In the target's Build Phases, add `EndpointsGeneratorPlugin` under Run Build Tool Plug-ins.
3. Add the specification to the target.
4. Remove the specification from Copy Bundle Resources. Xcode adds `.yaml` and `.json` files there by default, which would copy the file into your app.

A configuration file is a Swift file, so Xcode adds it to Compile Sources. Leave it there.

### Package traits

The generator depends on OpenAPIKit and Yams. Both sit behind the `OpenAPIGenerator` package trait, which is on by default, so the plugin works without any opt-in.

An app that only uses the runtime can turn the trait off:

```swift
.package(url: "https://github.com/velos/Endpoints.git", from: "0.6.0", traits: [])
```

On SwiftPM 6.2 and later, OpenAPIKit and Yams are then not fetched. On SwiftPM 6.1 they're fetched but not built. In Xcode, turn the trait off in the package dependency's editor. If you use the plugin with the trait off, the build fails and asks you to enable the `OpenAPIGenerator` trait.

### Naming the specification

The plugin looks for files named `<Stem>.openapi.yaml`, `<Stem>.openapi.yml`, or `<Stem>.openapi.json`. The stem becomes the Swift namespace, so it must be a valid Swift identifier: `Petstore.openapi.yaml` generates `Petstore`. A file named just `openapi.yaml` uses the stem `API`.

A target can contain several specifications. Each one generates its own namespace. Two stems that differ only by case are an error.

Don't exclude the specification from the target in `Package.swift`. The plugin only sees files that belong to the target.

## What gets generated

Each specification produces four files, named after the stem: `Petstore.Server.swift`, `Petstore.Schemas.swift`, `Petstore.Endpoints.swift`, and `Petstore.Support.swift`. A file is only rewritten when its contents change, so an unchanged specification doesn't cause recompilation.

The examples in this section come from this specification:

```yaml
openapi: 3.1.0
info:
  title: Petstore
  version: 1.0.0
servers:
  - url: https://petstore.example.com/v1
    description: Production
  - url: https://staging.petstore.example.com/v1
    description: Staging
security:
  - api_key: []
paths:
  /pets/{petId}:
    get:
      operationId: getPet
      summary: Get a pet.
      parameters:
        - name: petId
          in: path
          required: true
          schema: {type: integer, format: int64}
        - name: X-Request-ID
          in: header
          required: true
          schema: {type: string}
      responses:
        '200':
          description: The pet.
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet'}
        '404':
          description: No pet has this ID.
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Problem'}
  /pets:
    get:
      operationId: searchPets
      parameters:
        - name: tags
          in: query
          required: true
          schema: {type: array, items: {type: string}}
      responses:
        '200':
          description: Matching pets.
          content:
            application/json:
              schema: {type: array, items: {$ref: '#/components/schemas/Pet'}}
        '204':
          description: No pets match.
components:
  securitySchemes:
    api_key: {type: apiKey, in: header, name: api_key}
  schemas:
    Pet:
      type: object
      required: [id, name, owner_name]
      properties:
        id: {type: integer, format: int64}
        name: {type: string}
        owner_name: {type: [string, 'null']}
        status: {type: string, enum: [available, pending, sold]}
    Problem:
      type: object
      required: [code, message]
      properties:
        code: {type: integer}
        message: {type: string}
```

### Endpoints

Each operation becomes an endpoint named after its `operationId`. Path, query, and header parameters become `PathComponents`, `ParameterComponents`, and `HeaderComponents`:

```swift
extension Petstore {
    /// Get a pet.
    ///
    /// `GET /pets/{petId}`
    struct GetPetEndpoint: Endpoint {
        typealias Server = Petstore.Server
        typealias Response = Petstore.Pet
        typealias ErrorResponse = Petstore.Problem

        static let definition: Definition<GetPetEndpoint> = Definition(
            method: .get,
            path: "pets/\(path: \.petId)",
            headers: [
                "X-Request-ID": .field(path: \.xRequestID)
            ]
        )

        struct PathComponents: Sendable {
            var petId: Int64

            init(petId: Int64) {
                self.petId = petId
            }
        }

        struct HeaderComponents: Sendable {
            var xRequestID: String

            init(xRequestID: String) {
                self.xRequestID = xRequestID
            }
        }

        let pathComponents: PathComponents
        let headerComponents: HeaderComponents

        init(pathComponents: PathComponents, headerComponents: HeaderComponents) {
            self.pathComponents = pathComponents
            self.headerComponents = headerComponents
        }
    }
}
```

Optional parameters are optionals that default to `nil`. A query array is sent as repeated keys, such as `tags=cat&tags=small`. An operation with `security: []` declares `static var auth: NoAuth { NoAuth() }`, so it skips the server's authentication.

### Models

Each object schema in `components.schemas` becomes a `Codable`, `Hashable`, and `Sendable` struct. Enum schemas become enums, described below, and other schemas, such as a plain string, become a `typealias`.

The `Pet` schema generates:

```swift
extension Petstore {
    struct Pet: Codable, Hashable, Sendable {
        var id: Int64
        var name: String
        var ownerName: String?
        var status: Petstore.Pet.Status?

        // Status, shown below

        init(id: Int64, name: String, ownerName: String?, status: Petstore.Pet.Status? = nil) {
            self.id = id
            self.name = name
            self.ownerName = ownerName
            self.status = status
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case ownerName = "owner_name"
            case status
        }

        // init(from:) and encode(to:)
    }
}
```

Properties that aren't required are optional, left out of the JSON when `nil`, and default to `nil` in the initializer. `owner_name` is required but allows `null`, so it's a `String?` that must be present in the JSON and is encoded as `null` when it's `nil`. A property that is optional and also allows `null` is a plain optional: a missing key and `null` both decode as `nil`.

Inline objects and enums become nested types, such as `Pet.Status`. Formats map to these types:

| Schema | Swift |
|---|---|
| `string` | `String` |
| `string`, `format: date-time` | `Date` |
| `string`, `format: uuid` | `UUID` |
| `string`, `format: uri` | `URL` |
| `string`, `format: byte` or `binary` | `Data` |
| `integer` | `Int` |
| `integer`, `format: int32` or `int64` | `Int32` or `Int64` |
| `number` | `Double` |
| `boolean` | `Bool` |
| `array` | `[Element]` |

Other string formats, including `date`, are `String`. Query parameters with `date`, `date-time`, or `uri` formats are `String` too, so you control their formatting.

### Enums

String and integer enums are extensible by default. A value the specification doesn't list still decodes, so a server that adds a value doesn't break decoding for the whole response:

```swift
struct Status: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let available = Status(rawValue: "available")
    static let pending = Status(rawValue: "pending")
    static let sold = Status(rawValue: "sold")
    static let knownValues: [Status] = [.available, .pending, .sold]
}
```

Match the known values and handle the rest:

```swift
switch pet.status {
case .available?:
    showAvailable()
case let status?:
    showUnavailable(reason: status.rawValue)
case nil:
    break
}
```

To generate Swift enums that reject unknown values instead, set `enums: .closed` in the configuration.

### Responses with several status codes

When an operation has one success response, `Response` is its type, as with `GetPetEndpoint`. A `204` or a response without content is `Void`, and a non-JSON body is `Data`.

When an operation has several success responses, `Response` is an enum with a case per status code. It decodes from the actual HTTP status:

```swift
enum Response: Decodable, Hashable, Sendable {
    /// `200`: Matching pets.
    case ok([Petstore.Pet])
    /// `204`: No pets match.
    case noContent

    // init(from:) switches on the status code
}
```

Case names come from the HTTP reason phrase: `ok`, `created`, `noContent`, `notFound`, and so on. `2XX`, `4XX`, and `5XX` ranges become `success`, `clientError`, and `serverError`, and `default` becomes `defaultResponse`. A code without a registered phrase becomes `status<code>`.

Error responses follow the same rules. One error schema becomes the endpoint's ``Endpoint/ErrorResponse``, as `Problem` does for `GetPetEndpoint`. Several become an `ErrorResponse` enum with a case per status code. Status-tagged types decode with ``HTTPResponseJSONDecoder``, which the generated endpoint selects for you.

### Sending requests

Generated endpoints use the same request methods as hand-written ones:

```swift
let endpoint = Petstore.GetPetEndpoint(
    pathComponents: .init(petId: 42),
    headerComponents: .init(xRequestID: UUID().uuidString)
)

let pet = try await URLSession.shared.response(with: endpoint)
```

A status-tagged response is an enum to switch on:

```swift
let search = Petstore.SearchPetsEndpoint(parameterComponents: .init(tags: ["cat", "small"]))

switch try await URLSession.shared.response(with: search) {
case .ok(let pets):
    show(pets)
case .noContent:
    showEmptyState()
}
```

Errors are thrown as the endpoint's `TaskError`, with the decoded error response:

```swift
do {
    let pet = try await URLSession.shared.response(with: endpoint)
} catch {
    if case .errorResponse(_, let problem) = error {
        // problem is a Petstore.Problem
    }
}
```

### Servers and environments

Each entry in `servers` becomes a case of `Petstore.Environment`, named after its `description`, and the first is the default. A server without a description is named `server1`, `server2`, and so on.

```swift
let pet = try await URLSession.shared.response(with: endpoint, environment: .staging)
```

To use `TypicalEnvironments` with your own URLs, or a server type you already have, set `server` in the configuration.

### Authentication

Credentials are runtime state, so the generator doesn't create them. It documents the specification's security schemes on `Petstore.Server`, along with the declaration to add. Declare `auth` in an extension in the same target as the generated code:

```swift
import Endpoints

extension Petstore.Server {
    static let auth = HeaderKeyAuth(key: apiKey, header: "api_key", prefix: nil)
}
```

Every generated endpoint inherits the server's `auth`. If you generate public declarations, declare it `public static let auth`. The extension must be in the same module because it completes `Server`'s conformance to ``ServerDefinition``. See <doc:Authentication> for the available methods.

## Naming

Generated names follow Swift conventions by default. Types and endpoints are upper camel case, and properties, parameters, enum cases, and environments are lower camel case:

| In the specification | Generated |
|---|---|
| Schema `pet_record` | `PetRecord` |
| Property `owner_name` | `ownerName` |
| Property `user_id` | `userId` |
| Property `HTTP2Status` | `http2Status` |
| Property `class` | `class`, escaped with backticks |
| Header `X-Request-ID` | `xRequestID` |
| Enum value `IN_PROGRESS` | `inProgress` |
| Enum value `on-hold` | `onHold` |
| Enum value `2fa_required` | `_2faRequired` |
| Enum value `""` | `empty` |
| Integer enum values `-1`, `42` | `valueMinus1`, `value42` |
| `operationId: list_orders` | `ListOrdersEndpoint` |
| `GET /pets/{pet_id}` without an `operationId` | `GetPetsByPetIdEndpoint` |
| Server description `Production US` | `productionUS` |

Wire names never change. `CodingKeys`, parameter names, header names, and enum raw values keep the server's spelling, as in `case ownerName = "owner_name"`.

Only ASCII letters, digits, and underscores are used in names. Every other character separates words, so naming doesn't depend on Unicode tables. A name with no ASCII letters or digits, such as a schema named `東京`, is an error until you rename it.

The generator never adds a suffix to make names unique. Two names that collide, or a name that clashes with a type the generated code uses, such as a schema named `Date`, are errors. The error suggests a rename to add to your configuration.

A specification can also choose names with `x-swift-name` on a schema, property, parameter, operation, or server, and with `x-enum-varnames` on an enum. These replace the wire name as the input to the naming strategy, so `x-enum-varnames: [READY]` becomes `ready` with the default strategy. Use `.verbatim` for enum cases to keep them exactly as written.

## Configuring the generator

To change the generated code, add `<Stem>.endpoints.swift` to the same directory and target as the specification, such as `Petstore.endpoints.swift`. Without one, the generator uses the defaults described above.

```swift
// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let petstoreConfiguration = EndpointsConfiguration(
    namespace: "PetStore",
    accessLevel: .public,
    acronyms: ["ID"]
)
```

The first line must be exactly `// endpoints-configuration-version: 1`. The file must declare one `let` named after the stem in lower camel case, followed by `Configuration`: `petstoreConfiguration` for `Petstore`, and `apiConfiguration` in `API.endpoints.swift` for a bare `openapi.yaml`.

The file is part of your target, so the compiler checks it like any other source. The generator also compiles and runs it during the build to read the settings. The first build after a change takes about a second longer.

You can also start from the defaults and change only what you need:

```swift
let petstoreConfiguration = EndpointsConfiguration { configuration in
    configuration.accessLevel = .public
    configuration.enums = .closed
}
```

### Settings

| Setting | Default | Effect |
|---|---|---|
| `namespace` | The stem | The name of the generated namespace. |
| `accessLevel` | `.internal` | The access level of generated declarations: `.internal`, `.package`, or `.public`. |
| `server` | `.fromSpec` | Where the server comes from. See below. |
| `operations` | `.all` | Which operations to generate. See below. |
| `enums` | `.extensible` | `.closed` generates Swift enums that fail to decode unknown values. |
| `strict` | `true` | When `false`, unsupported constructs are warnings and are skipped. See <doc:Generating#Unsupported-constructs>. |

`server` takes one of three values:

- `.fromSpec` generates `Server` and an `Environment` enum from the specification's `servers`.
- `.environments([.production: "https://api.example.com"], default: .production)` generates a `Server` that uses ``TypicalEnvironments`` with the URLs you give. The default environment must have a URL.
- `.type("ApiServer")` uses an existing ``ServerDefinition`` with an `init()`, and generates no server. Declare `auth` on that type.

`operations` takes an `OperationFilter`. Each pattern matches an `operationId` or a `METHOD /path` string such as `DELETE /pets/{petId}`. Patterns are case-sensitive, and `*` matches any characters, including `/`. Exclusions win over inclusions:

```swift
operations: OperationFilter(exclude: ["admin*", "DELETE *"])
```

### Naming strategies

Six properties set the strategy for each kind of name:

| Property | Names | Default |
|---|---|---|
| `typeNamingStrategy` | Schemas and nested types | `.upperCamelCase` |
| `propertyNamingStrategy` | Model properties | `.camelCase` |
| `parameterNamingStrategy` | Path, query, and header parameters | `.camelCase` |
| `enumCaseNamingStrategy` | Enum cases and extensible enum values | `.camelCase` |
| `operationNamingStrategy` | Endpoints, before the `Endpoint` suffix | `.upperCamelCase` |
| `environmentNamingStrategy` | Environment cases | `.camelCase` |

Each takes one of these strategies:

- `.camelCase` and `.upperCamelCase` produce the names in the table above.
- `.verbatim` keeps the server's spelling, changed only where Swift requires it. Each character that isn't an ASCII letter, digit, or underscore becomes `_`, and a leading digit gets a `_` prefix. `IN_PROGRESS` stays `IN_PROGRESS`, `on-hold` becomes `on_hold`, and `X-Request-ID` becomes `X_Request_ID`.
- `.custom { context in … }` computes the name in a closure.

A custom closure receives a `NameContext` and returns a name, or `nil`. The context provides:

- `target`, which identifies the name. Its `owner` is the type that declares a property or enum case.
- `wireName`, the server's spelling, and `specName`, the `x-swift-name` or `x-enum-varnames` value if there is one.
- `camelCased`, `upperCamelCased`, and `verbatim`, the results of the built-in strategies.
- `removingPrefix(_:)`, `removingSuffix(_:)`, and `replacing(_:)`, which return a context with a different input and recomputed candidates. Prefixes and suffixes are case-sensitive and removed once. If nothing matches, or nothing would be left, the context is returned unchanged.
- `lowercasedASCII(_:)` and `uppercasedASCII(_:)`, which change the case of ASCII letters only.

```swift
operationNamingStrategy: .custom { $0.removingPrefix("legacy_").upperCamelCased }
```

Returning `nil` is an error unless a rename supplies the name. The generator checks every name the strategy returns. Member names that are Swift keywords are escaped with backticks. Type names that are keywords, and names that aren't valid identifiers, are errors.

### Acronyms

`acronyms` lists words to spell exactly as given in camel-case names:

```swift
acronyms: ["ID", "URL"]
```

With this list, `user_id` becomes `userID`, `image_url` becomes `imageURL`, and `GET /pets/{pet_id}` becomes `GetPetsByPetIDEndpoint`. Acronyms only replace whole words, and the first word of a lower camel-case name stays lowercase: `id_token` becomes `idToken`. Entries can only contain ASCII letters and digits.

### Renames

`renames` sets the exact Swift name for one item. Each key identifies the item by its original names in the specification, so a rename keeps working when you change a strategy:

```swift
renames: [
    .type("Date"): "CalendarDate",
    .property("owner_name", in: "Pet"): "owner",
    .type(.inline(.property("status", in: "Order"))): "OrderStatus",
    .enumCase("IN_PROGRESS", in: .inline(.property("status", in: "Order"))): "working",
    .operation("listPets"): "FetchPets",
    .operation(.route(method: .get, path: "/pets/{pet_id}")): "FetchPet",
    .parameter("id", in: .query, of: "listPets"): "identifier",
    .environment("Production US"): "production",
]
```

The targets are:

- `.type(_:)` for a schema. A string names a schema in `components.schemas`. `.inline(_:)` names a nested type by where it's declared: `.property(_:in:)`, `.items(of:)`, `.parameter(_:in:of:)`, `.body(_:)`, `.response(_:status:)`, or `.errorResponse(_:status:)`.
- `.property(_:in:)` for a property of a type.
- `.parameter(_:in:of:)` for a parameter. The location, `.path`, `.query`, or `.header`, tells apart parameters that share a name.
- `.enumCase(_:in:)` for an enum value, by its raw value. Integer values are written as strings, such as `"-1"`.
- `.operation(_:)` for an endpoint, without the `Endpoint` suffix. A string is an `operationId`. Use `.route(method:path:)` for an operation without one.
- `.environment(_:)` for a server, by its description, or by `server1`, `server2`, and so on.

A rename must be an ASCII identifier, and it's still checked for keywords, reserved names, and collisions.

### Precedence

Each name is resolved in three steps:

1. The input is the `x-swift-name` or `x-enum-varnames` value if there is one, and the wire name otherwise.
2. The strategy for that kind of name turns the input into a candidate.
3. A rename, if there is one, replaces the candidate.

A rename that doesn't match anything in the specification is a warning, so you notice when a schema or operation is renamed or removed on the server. An operation renamed both by its `operationId` and by its route is an error.

### Examples

Keep the server's spelling for one enum, either with a rename per value:

```swift
renames: [
    .enumCase("IN_PROGRESS", in: .inline(.property("status", in: "Order"))): "IN_PROGRESS",
]
```

Or with a strategy that checks which type the case belongs to:

```swift
enumCaseNamingStrategy: .custom { context in
    context.target.owner == .inline(.property("status", in: "Order"))
        ? context.verbatim
        : context.camelCased
}
```

Strip an `Api` prefix from every schema, so `ApiUser` becomes `User`:

```swift
typeNamingStrategy: .custom { $0.removingPrefix("Api").upperCamelCased }
```

Use `PetStore` as the namespace for `Petstore.openapi.yaml`, and publish the generated API from its own module:

```swift
// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let petstoreConfiguration = EndpointsConfiguration(
    namespace: "PetStore",
    accessLevel: .public,
    acronyms: ["ID"],
    renames: [
        .property("class", in: "Pet"): "kind",
        .parameter("X-Request-ID", in: .header, of: "getPet"): "requestID",
    ]
)
```

Leave out administrative operations, use your own server type, and generate closed enums:

```swift
let petstoreConfiguration = EndpointsConfiguration(
    server: .type("ApiServer"),
    operations: OperationFilter(exclude: ["admin*"]),
    enums: .closed
)
```

Share logic between strategies with a function. The file can declare other constants and functions:

```swift
let legacyPrefixes = ["v1_", "legacy_"]

func modernName(_ context: NameContext) -> String? {
    for prefix in legacyPrefixes {
        let trimmed = context.removingPrefix(prefix)
        if trimmed.wireName != context.wireName {
            return trimmed.upperCamelCased
        }
    }
    return context.upperCamelCased
}

let petstoreConfiguration = EndpointsConfiguration(
    typeNamingStrategy: .custom(modernName),
    operationNamingStrategy: .custom(modernName)
)
```

## Rules for configuration files

The configuration file is compiled into your target and is also compiled and run by the generator, in Swift 6 language mode, while you build. It must produce the same names on every machine, so it has to be self-contained and can only compute names from its inputs.

The generator checks the file before compiling it, and reports each violation at its line and column:

- The only import allowed is `import EndpointsGeneratorConfig`.
- No conditional compilation, such as `#if`, and no other `#` directives or literals, such as `#filePath`.
- No regular expression literals. Put spaces around `/` when you divide.
- No key-path expressions. Write `map { $0.name }` instead of `map(\.name)`.
- No classes, actors, `@unchecked` conformances, `@_` attributes, or identifiers that start with an underscore.
- No randomness, shuffling, clocks, durations, sleeping, tasks, `async`, or `await`.
- No identity operators (`===` or `!==`), or address, reflection, or hashing APIs, such as `ObjectIdentifier`, unsafe pointers, `withUnsafe…`, `withCString`, `withUTF8`, `withContiguousStorageIfAvailable`, `withContiguousMutableStorageIfAvailable`, `withVaList`, `getVaList`, `Unmanaged`, `Hasher`, `hashValue`, `Mirror`, `MemoryLayout`, or `capacity`.
- No `CommandLine` or `readLine`.

The API checks match identifier tokens exactly and are case-sensitive, so helper names like `randomPrefix` and `taskName` are fine. The prefixes `unsafe`, `Unsafe`, and `withUnsafe` are also rejected when followed by an uppercase letter or the end of the token: `unsafeLabel` is rejected, but `unsafety` is fine.

After compiling the file, the generator runs it twice, in separate processes, and fails with "configuration program is not deterministic" if the two runs produce different results.

Swift's own Unicode operations, such as `lowercased()` and `uppercased()`, use Unicode tables that can change between toolchain and OS versions. For non-ASCII input they could produce different names on different machines, and neither the checks nor the second run can detect that. Use `lowercasedASCII(_:)` and `uppercasedASCII(_:)` instead. The built-in strategies only use ASCII.

## Diagnostics

Errors and warnings appear in the build log and, in Xcode, in the issue navigator at the file and line that caused them. A problem in the specification points to its line and column, followed by its JSON pointer:

```
Petstore.openapi.yaml:61:5: error: Reserved name 'Date' for 'Date'; use renames: [.type("Date"): "NewName"] [#/components/schemas/Date]
Petstore.openapi.yaml:28:5: error: Unsupported: oneOf/anyOf schemas [#/components/schemas/Shape]
```

A problem in the configuration file points to the line in that file. Compiler errors in it are reported as the compiler wrote them:

```
Petstore.endpoints.swift:3:1: error: configuration files may only import EndpointsGeneratorConfig
Petstore.endpoints.swift:1:1: error: configuration must declare exactly one 'let petstoreConfiguration: EndpointsConfiguration'
Petstore.endpoints.swift:9:1: warning: Unused rename target .type("Missing")
```

The plugin itself reports specification files with invalid names, stems that clash, and a configuration file that isn't part of the target. A target that applies the plugin but contains no specification gets a warning.

## Platforms and limitations

The generator runs on macOS, in SwiftPM and Xcode, and on Linux. The code it generates has the same requirements as the rest of Endpoints. For iOS, tvOS, and watchOS builds, the configuration file is compiled for the Mac that runs the build.

SwiftPM skips the generate step when the specification and configuration haven't changed. Xcode runs it on every build. That run reuses the compiled configuration, takes a fraction of a second, and leaves the generated files untouched, so nothing is recompiled.

The generator hasn't yet been verified with Xcode Cloud, custom toolchains, or cross-compilation.

### Unsupported constructs

A construct the generator doesn't support yet is reported as "Unsupported". By default that's an error. With `strict: false`, it's a warning, and the generator skips the construct, which is a property, a parameter, or an operation, along with anything that depends on it.

The generator doesn't support these yet:

- `oneOf`, `anyOf`, and `allOf`. The exception is a `oneOf` or `anyOf` of one type and `null`, which becomes an optional.
- Recursive schemas, including recursion through arrays.
- `additionalProperties`, and objects without `properties`.
- Enums whose values aren't strings or integers.
- Request bodies other than a required JSON body, including form, multipart, and binary bodies.
- Cookie parameters, `querystring` parameters, and parameters that use `content`.
- Object parameters, and query arrays that aren't exploded `form` style.
- `OPTIONS`, `TRACE`, and `QUERY` operations.
- `servers` declared on an operation or path.
- Operations without a success or `default` response.

Some problems are errors even with `strict: false`: OpenAPI 2.0 documents, references to other files, invalid or relative server URLs, and naming errors such as collisions.

Response headers aren't generated. Redirect responses (`3xx`) are ignored with a note.

### Known issues

- An optional header parameter generates a property that fails with ``EndpointError/invalidHeader(named:type:)`` when the request is built. Required header parameters work.
- When an endpoint declares no error responses and the server returns an error with an empty body, the request fails with ``EndpointTaskError/errorResponseParseError(httpResponse:data:error:)`` rather than ``EndpointTaskError/errorResponse(httpResponse:response:)``.
