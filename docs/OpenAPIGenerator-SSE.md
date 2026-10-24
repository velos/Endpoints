# Server-Sent Events: design addendum

Status: design only. This adds to `OpenAPIGenerator-Design.md` and will be folded into it (§0, §0.1, §2, §5.10, §6.5, §8, §9, §10) when Phase 8 starts. It's kept separate for now so it doesn't collide with in-flight edits to the main doc.

---

## §0 additions: summary of decisions

| Topic | Decision | One-line reason |
|---|---|---|
| SSE runtime location | Inside the `Endpoints` module under `#if ServerSentEvents`, with `@available(*, unavailable, message:)` stubs in the `#else` branch. **No** `EndpointsServerSentEvents` product. | Generated code never imports anything new, and with the trait off the only compile errors are the stubs' friendly message. A separate module would give "no such module" instead, and splitting stubs from a real module would collide on names. |
| SSE trait | `ServerSentEvents`, **default-off**. It conditions `Endpoints`' dependency on `AsyncServerSentEvents`. | `Endpoints` stays dependency-free unless a consumer asks for streaming. Xcode's package-dependency editor can enable it, so default-off excludes nobody. |
| SSE library | `velos/AsyncServerSentEvents`, `.upToNextMinor(from: "0.3.0")`, after three small public additions (§6.5.4) | It's 0.x, and we own the library, so the additions ship before Phase 8. |
| Output files | Still four. SSE endpoints render into `<Stem>.Endpoints.swift`; there's no fifth `Streams` file. | Once no extra import is needed, nothing distinguishes them at the file level. |
| Pattern going forward | A trait when a capability adds a **dependency** to a runtime module (with unavailable stubs so the API shape is identical). A product when it's dependency-free code that only some consumers want (`EndpointsMocking`). A default-on trait only for heavy build-time dependencies (`OpenAPIGenerator`). | Traits stay additive, and "trait off" stays a compile-time error with a message rather than a missing symbol. |

## §0.1 additions: changes from review

| # | Finding | Disposition |
|---|---|---|
| 16 | Owner: SSE without the trait must fail with a message telling the user to enable it | **Accept.** Unavailable stubs in `Endpoints` (§6.5.2), plus a CI trap fixture (§8). |
| 17 | Owner correction: Xcode has a package-trait UI | **Accept.** §2.2's "Xcode offers no trait UI" is wrong; corrected text below. It doesn't flip `OpenAPIGenerator` to default-off. |

---

## §2 changes

### §2.1: manifest additions (both branches of `#if os(Linux)`)

```swift
let streamingTrait = "ServerSentEvents"

// runtimeTargets, both branches:
.target(
    name: "Endpoints",
    dependencies: [
        .product(name: "AsyncServerSentEvents", package: "AsyncServerSentEvents",
                 condition: .when(traits: [streamingTrait])),
    ]),

// Package(...):
traits: [
    .trait(name: generatorTrait, description: "Builds the OpenAPI generator and fetches OpenAPIKit and Yams."),
    .trait(name: streamingTrait, description: "Adds Server-Sent Events streaming endpoints (URLSession.events(with:)) and fetches AsyncServerSentEvents."),
    .default(enabledTraits: [generatorTrait]),          // ServerSentEvents stays off by default
],
dependencies: [
    .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", exact: "6.4.0", traits: []),
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(url: "https://github.com/velos/AsyncServerSentEvents.git", .upToNextMinor(from: "0.3.0")),
]
```

- SSE runtime sources live in `Sources/Endpoints/ServerSentEvents/`, wrapped in `#if ServerSentEvents … #else <stubs> #endif`. SE-0450 passes enabled traits as `-D<Trait>` to the declaring package's own targets (this repo's `#if OpenAPIGenerator` already relies on that). So `Endpoints` and its test targets see the define, and consumers never do. That's why the API shape must be identical in both branches.
- SSE tests go in `Tests/EndpointsTests/ServerSentEvents/` under `#if ServerSentEvents`, so plain `swift test` still passes with the trait off.
- No new products. `EndpointsMocking` is unchanged and mocks streaming endpoints through the existing `MockAction<T.Response, T.ErrorResponse>` (§6.5.3).

### §2.2: corrected and extended text

Replace "Plugin users and Xcode projects need no opt-in (Xcode offers no trait UI)" with:

> Plugin users need no opt-in. Xcode projects can enable or disable a package dependency's traits in the project's package-dependencies editor, so a default-off trait is usable from Xcode too. Default-on still spares every plugin user an extra step. **`OpenAPIGenerator` stays default-on.** The other reasons still hold: SwiftPM 6.1 fetches the generator's dependencies regardless of traits, adding the trait after release would have broken existing users, and the plugin is the package's headline feature. The Xcode correction changes one thing: a default-off trait is now an acceptable shape for an optional runtime capability, which is what `ServerSentEvents` uses.

Add after the trait-union bullet:

> **How the two traits combine:**
> - `traits: []`: runtime only, no generator, no SSE.
> - `traits: [.defaults]`, or omitted: generator on, SSE off.
> - `traits: [.defaults, "ServerSentEvents"]`: both.
> - `traits: ["ServerSentEvents"]`: SSE without the generator, which is valid for vendored output.
>
> The member is spelled `.defaults` (`Package.Dependency.Trait.defaults`, verified in `PackageDescription`). Traits are unioned across the graph and only ever add: if one package enables `ServerSentEvents`, `Endpoints` builds with streaming for everyone, which changes no existing API. On SwiftPM 6.1, every consumer fetches `AsyncServerSentEvents` (no dependencies, about 6 files), because a product can reach it. On 6.2 and later, it's fetched only when the trait is enabled.

### §2.3: consumer usage addition

```swift
.package(url: "https://github.com/velos/Endpoints.git", from: "0.7.0", traits: [.defaults, "ServerSentEvents"]),
```

The README and the `Generating.md` DocC article describe both routes: the manifest line above, or enabling the `ServerSentEvents` trait for the Endpoints package in Xcode's package-dependencies editor.

### §2.5: CI additions (both OSes)

- `swift test --enable-all-traits` compiles and runs the SSE tests, including the local-server tests.
- Keep `swift test` with default traits, which proves the `#else` stubs and the trait-off runtime still build, and keep `swift build --disable-default-traits --product Endpoints`.
- `Examples/StreamingClient` (plugin plus an SSE spec, `traits: [.defaults, "ServerSentEvents"]`): `swift test --package-path …`.
- Trap fixture `Examples/StreamingTraitOff`: the same generated sources, vendored, with `traits: [.defaults]`. The step runs `swift build --package-path Examples/StreamingTraitOff 2>&1 | tee /tmp/trap.log; test ${PIPESTATUS[0]} -ne 0 && grep -q "Enable the ServerSentEvents trait" /tmp/trap.log`. It also asserts the log has no `no such module` and no `has no member` lines.

---

## §5.10 Streaming responses (SSE)

### 5.10.1 Detection

An operation is **streaming** when its selected success response has a `text/event-stream` entry in its content map. Selection is the same as §5.5: lowest explicit 2xx, then `2XX`, then `default`. The entry is matched with `ContentType.eventStream`, compared by `typeAndSubtype` so parameters are ignored. Streaming endpoints render into `<Stem>.Endpoints.swift`; there's no fifth file.

| Shape | Generated | Status |
|---|---|---|
| Only `text/event-stream` on the success response | `struct <Name>Endpoint: ServerSentEventsEndpoint` | supported |
| Both JSON and `text/event-stream` on the same success response (e.g. a `stream` flag) | Two types: `<Name>Endpoint` (JSON, as in §5.5) and `<Name>StreamEndpoint` (SSE), whose `PathComponents`/`ParameterComponents`/`HeaderComponents`/`Body` are typealiases to the JSON endpoint's. `StreamEndpoint` takes part in collision checks. | supported |
| `text/event-stream` on a non-success response | error ("error responses can't stream") | unsupported |
| Streaming op with `security: []`, deprecation, docs, filtering, renames | identical to §5.2 | supported |

### 5.10.2 Event typing

OpenAPI 3.2 describes each event with `itemSchema`, and OpenAPIKit 6.4.0 parses it as `Content.itemSchema: JSONSchema?`. OpenAPIKit's `StringContext` has `contentMediaType` but **no `contentSchema`**, so lowering reads `contentSchema` through a side channel:

1. The Loader already keeps the Yams root `Node`.
2. Lowering walks the response-content pointer to the `itemSchema` node and finds `properties/data/contentSchema` (per `oneOf` member when there are several).
3. It decodes that with `YAMLDecoder().decode(JSONSchema.self, from: node)` and lowers it like any other schema. `$ref`s resolve through components as usual.

Phase 8 verifies that OpenAPIKit tolerates the unknown `contentSchema` key when it decodes the document. If it rejects the key, the Loader decodes the document from the Yams node with those keys removed, instead of from the string.

| `itemSchema` | `Event` | `decodeEvent` | Status |
|---|---|---|---|
| object with `event: {const: "created"}` and a `data` whose `contentMediaType` is `application/json` or `*+json`, with a `contentSchema` | `enum Event { case created(Payload); case other(ServerSentEvent) }` | `switch event.type` on the const; payload via `JSONCoding.makeDecoder().decode(Payload.self, from: Data(event.data.utf8))` | supported |
| `oneOf` of such objects | one case per member in spec order, plus `other` last | same | supported |
| member without an `event` const (at most one) | `case message(Payload)` (the spec's default type) | matches `event.type == "message"` | supported |
| two members without a const, or duplicate consts | error | unsupported |
| `data` string without a JSON `contentMediaType`, or JSON without `contentSchema` | `case <name>(String)` (raw `data`), plus a note | degraded |
| `data` typed `object` directly (common outside 3.2) | treated as a JSON payload of that schema, plus a note | degraded |
| `id`, `retry` properties | ignored for typing; available on `ServerSentEvent` through `.other` and on `EventStream.lastEventId` | n/a |
| no `itemSchema` (3.0/3.1 `schema: {type: string}`, or none) | `typealias Event = ServerSentEvent`; `decodeEvent` returns the event unchanged; note: "describe events with OpenAPI 3.2 `itemSchema` for typed events" | degraded |

`Event` and `decodeEvent` join the endpoint-scope reserved names (§5.7). The `other` case name is reserved within the event enum, so a const literally named `other` is an error with a rename hint. Case names are the const in lowerCamel (`pet-created` → `petCreated`). Inline `contentSchema` objects get nested `<CaseName>Payload` type names.

Determinism: case order is `oneOf` order with `other` last, consts match by exact string, and no new inputs join the determinism tuple.

### 5.10.3 Generated example

```swift
extension Petstore {

    /// Watch pet changes.
    ///
    /// `GET /pets/watch` (text/event-stream)
    public struct WatchPetsEndpoint: ServerSentEventsEndpoint {
        public typealias Server = Petstore.Server
        public typealias Response = EventStream<Event>
        public typealias ErrorResponse = Petstore.Problem

        public static let definition: Definition<WatchPetsEndpoint> = Definition(
            method: .get,
            path: "pets/watch",
            parameters: [
                .query("since", path: \.since)
            ]
        )

        public enum Event: Hashable, Sendable {
            /// `event: created`
            case created(Petstore.Pet)
            /// `event: deleted`
            case deleted(Petstore.PetDeleted)
            /// An event type the specification doesn't list.
            case other(ServerSentEvent)
        }

        public static func decodeEvent(_ event: ServerSentEvent) throws -> Event? {
            let decoder = Petstore.JSONCoding.makeDecoder()
            switch event.type {
            case "created":
                return .created(try decoder.decode(Petstore.Pet.self, from: Data(event.data.utf8)))
            case "deleted":
                return .deleted(try decoder.decode(Petstore.PetDeleted.self, from: Data(event.data.utf8)))
            default:
                return .other(event)
            }
        }

        public struct ParameterComponents: Sendable {
            public var since: String?

            public init(since: String? = nil) {
                self.since = since
            }
        }

        public let parameterComponents: ParameterComponents

        public init(parameterComponents: ParameterComponents = ParameterComponents()) {
            self.parameterComponents = parameterComponents
        }

        public static var errorDecoder: HTTPResponseJSONDecoder { Petstore.JSONCoding.makeDecoder() }
    }
}
```

Usage: `for try await event in try await URLSession.shared.events(with: Petstore.WatchPetsEndpoint()) { … }`. With the trait off, this struct produces exactly one kind of compile error (§6.5.2).

---

## §6.5 Server-Sent Events runtime (trait `ServerSentEvents`)

### 6.5.1 API (real branch, `#if ServerSentEvents`)

```swift
import AsyncServerSentEvents

/// A server-sent event. Alias so generated code needs no second import.
public typealias ServerSentEvent = AsyncServerSentEvents.ServerSentEvent

/// An endpoint whose success response is a `text/event-stream`.
///
/// `Response` is the stream itself, so the body-returning `response(with:)` overloads don't
/// apply; open it with `URLSession.events(with:)`.
public protocol ServerSentEventsEndpoint: Endpoint where Response == EventStream<Event> {
    associatedtype Event: Sendable
    /// Decodes one event. Return `nil` to skip it.
    static func decodeEvent(_ event: ServerSentEvent) throws -> Event?
}

/// The decoded events of a streaming endpoint. Single-pass; dropping it or cancelling the
/// consuming task closes the connection.
public struct EventStream<Event: Sendable>: AsyncSequence, Sendable {
    public typealias Element = Event
    /// A finished stream of known events, for mocks and tests.
    public init(_ events: [Event])
    /// The most recent event ID committed by the server, for resuming by hand.
    public var lastEventId: String? { get async }
    public func makeAsyncIterator() -> AsyncIterator          // next() throws any Error
}

public enum ReconnectionPolicy: Sendable {
    /// One connection; the sequence ends when the server closes it. Default.
    case never
    /// Reconnect after clean closes and transport errors, as `EventSource` does: waits the
    /// server's `retry` interval (or `retryInterval` ms until one is seen), resends
    /// `Last-Event-ID`, re-applies authentication on every connect, ends on HTTP 204.
    case automatic(retryInterval: Int = 3000, lastEventId: String? = nil)
}

public extension URLSession {
    /// Opens the endpoint's event stream.
    ///
    /// Builds the request, applies `auth`, and connects. A non-2xx response body is decoded as
    /// `ErrorResponse` and thrown as `.errorResponse`; when `auth.shouldReauthenticate` agrees
    /// (401 for `JWTAuth`), the credentials are refreshed and the connection retried before
    /// any event is delivered. 204 returns an empty stream.
    func events<T: ServerSentEventsEndpoint>(
        with endpoint: T,
        environment: T.Server.Environments = T.Server.defaultEnvironment,
        auth: any AuthenticationMethod = T.auth,
        reconnection: ReconnectionPolicy = .never
    ) async throws(T.TaskError) -> T.Response
}
```

What `events(with:)` does, in order:

1. In `DEBUG`, checks for a mock through the module-internal `Mocking.shared.handleMock(for: T.self)`, which returns the mocked `EventStream` or throws.
2. Builds the request with `endpoint.urlRequest(in:)`, then calls `request.preparedForServerSentEvents(lastEventId:)` (library, §6.5.4), so `Accept`, `Cache-Control`, and `Last-Event-ID` are set **before** authentication.
3. Runs the same authenticate → send → `shouldReauthenticate` → `reauthenticate` loop as `performRequest`, bounded by `auth.retryAttempts`. Here "send" is `serverSentEventsConnection(for:)`, which returns `(SSEByteStream, URLResponse)` without validation.
4. Handles the response:
   - 200 with `text/event-stream`: wraps `bytes.sse()`.
   - 204: returns `EventStream([])`.
   - Any other non-2xx: reads the body to the end, decodes it with `T.errorDecoder.decode(T.ErrorResponse.self, from: body, response:)`, and throws `.errorResponse(httpResponse:response:)`, or `.errorResponseParseError` if decoding fails.
   - Any other 2xx, or the wrong content type: throws `.urlLoadError(SSEError.unacceptableStatusCode)` or `.urlLoadError(SSEError.unacceptableContentType)`. There's no new `EndpointTaskError` case, because adding one breaks exhaustive switches.

**Iteration.** Each raw event goes through `T.decodeEvent`, and `nil` skips the event. A throw from `decodeEvent` surfaces as `T.TaskError.responseParseError(data: Data(event.data.utf8), error:)`, and transport errors surface as `.urlLoadError`. `next()` throws both as `any Error`, because a typed `AsyncSequence.Failure` needs newer OS availability.

**Reconnection.** With `.automatic`, the iterator re-runs step 3 after a clean close or a transport error, after sleeping the current retry interval. Typed error responses aren't retried, apart from the auth refresh.

**Cancellation.** Cancelling the consuming task, or dropping the sequence, cancels the data task (`SSEByteStream` termination).

**Not supported:** Combine (an `AsyncSequence` is the natural shape; bridge it if you need to) and `endpointTask(with:completion:)`.

### 6.5.2 Stubs (`#else` branch) and the trap

Every symbol generated code names exists in both branches with the same shape. In the `#else` branch each one is marked unavailable, with one shared message:

```
Server-Sent Events support is off. Enable the ServerSentEvents trait on the Endpoints package:
in Package.swift use .package(url: "https://github.com/velos/Endpoints.git", from: "0.7.0",
traits: [.defaults, "ServerSentEvents"]), or enable it for the Endpoints package in Xcode's
package dependencies.
```

Swift requires a string literal in the attribute, so the source repeats the string; keep it all in one `#else` file.

```swift
@available(*, unavailable, message: "<message>")
public protocol ServerSentEventsEndpoint: Endpoint where Response == EventStream<Event> {
    associatedtype Event: Sendable
    static func decodeEvent(_ event: ServerSentEvent) throws -> Event?
}

@available(*, unavailable, message: "<message>")
public struct EventStream<Event: Sendable>: Sendable {
    public init(_ events: [Event])
}

@available(*, unavailable, message: "<message>")
public struct ServerSentEvent: Hashable, Sendable {
    public var id: String?
    public var name: String?
    public var data: String
    public var lastEventId: String?
    public var type: String { "" }
}

@available(*, unavailable, message: "<message>")
public enum ReconnectionPolicy: Sendable { case never }

public extension URLSession {
    @available(*, unavailable, message: "<message>")
    func events<T: ServerSentEventsEndpoint>(with endpoint: T) async throws -> T.Response
}
```

Why every symbol needs a stub: the generated struct references `ServerSentEventsEndpoint` (its conformance), `EventStream<Event>` (a typealias), `ServerSentEvent` (a parameter type and the `.other` payload), and `event.type`/`event.data` (members). Each reference to an unavailable type reports the same message at that line. Because the stubs also declare the members generated code uses, there's no "has no member" or "no such module" noise. The user's own call sites (`URLSession.events(with:)`) get the same message.

`ServerSentEvent` is a stub struct here and a typealias in the real branch. Both spell the same name, so generated code is byte-identical either way.

### 6.5.3 Mocking

`T.Response == EventStream<T.Event>`, so the existing API covers streams with no new surface: `withMock(Petstore.WatchPetsEndpoint.self, action: .return(EventStream([.created(pet), .deleted(gone)])))`, `.fail(problem)`, `.throw(.internetConnectionOffline)`, and the closure form all work. `events(with:)` can consult `Mocking.shared` because it lives in the same module, which is the second reason SSE belongs inside `Endpoints`. Mock availability is the same as today's: Apple platforms, `DEBUG` builds.

### 6.5.4 Minimal additions to `AsyncServerSentEvents` (ship as 0.3.0 first)

1. `public extension URLSession { func serverSentEventsConnection(for request: URLRequest) async throws -> (SSEByteStream, URLResponse) }`. It opens the connection with **no** header injection and **no** status or content-type validation, so the caller can read an error body and decode a typed error. Today `serverSentEvents(for:)` throws `SSEError.unacceptableStatusCode` and cancels the task, dropping the body.
2. `public extension URLRequest { func preparedForServerSentEvents(lastEventId: String? = nil) -> URLRequest }`. It exposes `SSERequest.prepared`, so Endpoints can add the SSE headers before authentication runs.
3. `public extension URLResponse { func validateServerSentEvents() throws }`. It exposes `SSERequest.validate`, so the 200/`text/event-stream` check isn't duplicated.

Nothing else in the library changes. `EventSource` stays as the reference for the reconnect loop, which Endpoints re-implements because it needs auth and typed errors that `EventSource` can't provide.

### 6.5.5 Runtime tests (`Tests/EndpointsTests/ServerSentEvents/`, `#if ServerSentEvents`, both OSes)

A small POSIX-socket HTTP/1.1 test server of about 100 lines, modelled on the library's MIT-licensed `TestHTTPServer.swift`, scripted per test:

- 200 stream with `id`, `retry`, and multi-line `data` → decoded events and `lastEventId`.
- 401 then 200 → the `JWTAuth` refresh handler is called once, and the second request carries the new token and `Last-Event-ID`.
- 404 with a JSON body → `.errorResponse` with the decoded `Problem`.
- 204 → an empty stream.
- 200 with `text/plain` → `.urlLoadError(SSEError.unacceptableContentType)`.
- Cancellation → the server observes the disconnect within a timeout.
- `.automatic` → a clean close triggers a reconnect with `Last-Event-ID` and the server-provided `retry`.
- `decodeEvent` throws → `.responseParseError` with the event's data.
- Unknown event name → `.other`.
- `withMock` returning `EventStream([...])` → bypasses the network (Apple only).

---

## §8 additions (testing)

- **Unit:** event case naming, const and default-type rules, `contentSchema` side-channel extraction (including a `$ref` inside `contentSchema`), splitting dual JSON+SSE operations, and the reserved `Event`/`decodeEvent`/`other` names.
- **Goldens:**
  - `Streams`: 3.2 `oneOf` events, a single typed event, a raw 3.1 stream, and a dual JSON+SSE operation. Compiled in `EndpointsGeneratedGoldenTests` under `#if ServerSentEvents`, with decoding tests that feed `ServerSentEvent` values to `decodeEvent`.
  - `StreamsErrors`: two default-type members, a const named `other`, and a stream on an error response, checked as `diagnostics.txt`.
- **End-to-end:** `Examples/StreamingClient` (plugin, SSE spec, trait on, a mocked-stream test), and the `Examples/StreamingTraitOff` trap fixture from §2.5, asserting the exact message and no `no such module`/`has no member` lines.

---

## §9 additions (owner decisions)

**Accepted by the owner on 2026-10-24: items 9–13 as recommended.**

9. **SSE inside `Endpoints` behind a default-off `ServerSentEvents` trait**, which adds a conditional dependency on `AsyncServerSentEvents` to the runtime target. All consumers fetch it on SwiftPM 6.1; on 6.2 and later, only when the trait is enabled. Recommend **yes**: it's the only shape where generated code is identical and the trait-off failure is the friendly message, and the runtime stays dependency-free by default.
10. **`AsyncServerSentEvents` 0.3.0 additions**: the raw connection, public request preparation, and public response validation. Recommend **yes**: three small public functions, with no behaviour change for existing callers.
11. **Reconnection is opt-in** (`.never` by default). Recommend **yes**: an infinite sequence by default would surprise callers and hide server closes.
12. **Generated event enums always have a `case other(ServerSentEvent)`.** Recommend **yes**: it mirrors open enums, so new server event types never fail the stream.
13. **Dual JSON+SSE operations become two endpoint types** (`…Endpoint` and `…StreamEndpoint`). Recommend **yes**: one `Response` per endpoint is the library's contract, and the caller picks by type.

---

## §10 addition

### Phase 8: Streaming responses (SSE)

**Prerequisite:** `AsyncServerSentEvents` 0.3.0 published, with the §6.5.4 additions.

**Scope:**
- The manifest trait and conditional dependency (§2).
- Runtime §6.5.1–6.5.3, including the `#else` stubs.
- Local-server runtime tests (§6.5.5).
- Generator §5.10, including the `contentSchema` side channel and the dual-operation split.
- Reserved names.
- The `Streams` and `StreamsErrors` goldens.
- `Examples/StreamingClient` and `Examples/StreamingTraitOff`.
- README and `Generating.md` sections describing both ways to enable the trait.
- The CI steps from §2.5.

**Acceptance:**
- `swift test` (default traits) and `swift test --enable-all-traits` pass on macOS and Linux.
- The trap step fails the build with the exact message and no other kinds of error.
- `StreamingClient` tests pass with a mocked stream.
- The local-server tests cover every row of §6.5.5.
- Goldens stay byte-identical across the cross-process determinism test.
- OpenAPIKit's handling of the unknown `contentSchema` key is recorded in `docs/OpenAPIGenerator-Verification.md`.

---

## Coordinator review notes (to verify in Phase 8)

- **Name collisions with a direct import.** An app that imports both `Endpoints` and `AsyncServerSentEvents` may hit an ambiguous `ServerSentEvent` lookup. With the trait off, the stub is a distinct type; with it on, it's a typealias to the library's type. Check both cases. If the lookup is ambiguous, rename the Endpoints-side symbol, for example `EndpointServerSentEvent`, or document that callers should qualify it.
- **Version in the trap message.** The message hard-codes `from: "0.7.0"`, which will drift. Either keep it in sync at release time (a test can assert it matches the README) or drop the version from the snippet.
