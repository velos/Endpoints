# OpenAPI → Endpoints Generator: Architecture and Implementation Plan (revised after review)

Repository: `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25`
Status: foundation committed as `54563a1`; runtime hooks (§6.1–6.3) and full parameter/status-response generation committed as `f0c87c7`. Path encoding fix velos/Endpoints#24 is merged; generated embedded paths use individually encoded values. Local verification is recorded in OpenAPIGenerator-RuntimeHooks-Verification.md (foundation history: OpenAPIGenerator-Verification.md). Linux execution and native Xcode verification remain owner-run checks.

**Separately owned runtime bugs:** path double encoding is fixed in velos/Endpoints#24 (merged into this branch). Optional header omission (§6.4) and empty-body `EmptyCodable` error decoding (the last part of §6.1) are still to be fixed separately, and this branch leaves their implementations untouched. Generated integration tests assert the intended behavior, using `withKnownIssue` only for those two bugs. Remove each wrapper when its fix lands.

---

## 0. Summary of decisions

| Topic | Decision | One-line reason |
|---|---|---|
| Parser | OpenAPIKit **exact `6.4.0`** (`OpenAPIKit`, `OpenAPIKit30`, `OpenAPIKitCompat`), `traits: []` | Latest 6.x; 7.0.0 needs Swift 6.2; supports OAS 3.0/3.1/3.2; opting out of `ExternalLoading` removes the external-loading path and its build cost. |
| YAML/JSON loading | Yams **exact `6.2.2`**, used for both `.yaml` and `.json` | Yams preserves key order (Foundation's `JSONDecoder.allKeys` order isn't guaranteed); an exact pin keeps the parser inside the determinism tuple. |
| swift-tools-version | **6.1**; Linux CI `swift:6.1`; a macOS job on SwiftPM ≥ 6.2 | OpenAPIKit's manifest is tools 6.1, so 6.1 is the floor regardless; 6.1 is also needed for `traits:`. |
| Package trait | **`OpenAPIGenerator`, enabled by default**, guards Core's dependencies on OpenAPIKit and Yams | Plugin users (including Xcode projects) need no opt-in; runtime-only consumers on SwiftPM ≥ 6.2 can write `traits: []` and never fetch OpenAPIKit/Yams (verified in SwiftPM source, §2.2). Adding it now, not later, breaks nobody. |
| Response contract | New additive runtime hook: `DecoderType.decode(_:from:response:)` with a default, `HTTPResponseJSONDecoder`, `CodingUserInfoKey.httpStatusCode`/`.httpHeaders` | Status-tagged `Response`/`ErrorResponse` unions dispatch on the real status, not structural guessing; `200: Pet` + `204` becomes exact. |
| Presence | Optional ↔ absent; required-nullable ↔ explicit `null` (custom Codable); optional-nullable collapses to `T?` as a permanent documented policy; required readOnly/writeOnly → optional | Exact where the wire needs it; the one collapse is deliberate and never changes a public type later. |
| Numbers | `int32` → `Int32`, `int64` → `Int64`, unformatted `integer` → `Int`; `JSONValue` keeps `.integer(Int64)` and `.number(Double)` | Changing property types after adoption is the expensive mistake. |
| Enums | **Extensible by default** (`struct X: RawRepresentable` with static members); `enums: "closed"` opt-in; covers string and int enums | New server values must not fail whole-response decoding; switching closed→open later breaks exhaustive switches. |
| Unsupported constructs | `strict: true` default (error); `strict: false` skips with warnings | Lossy generation is opt-in. |
| Naming | Pure per-name function + explicit `renames`; collisions and reserved-name hits are **errors**, never auto-suffixed; ASCII-only identifier policy; namespace = stem verbatim | Stable under spec evolution and Unicode-data changes. |
| Rendering | Hand-rolled `CodeWriter`; no SwiftSyntax/swift-format | Avoids minutes of build time per consumer and toolchain coupling. |
| Output files | Fixed per spec: `<Stem>.Server.swift`, `.Schemas.swift`, `.Endpoints.swift`, `.Support.swift`; written only when changed | Names known before parsing; stable mtimes. |
| Dates | Hand-written RFC 3339 parse/format in Support (pure Swift, `Z` output, offsets accepted) emitted only when `Date` is used | No new deployment floor (the package is macOS 10.15/iOS 13), no formatter thread-safety questions, offsets handled. |

### 0.1 Changes from review (Astra items and dispositions)

| # | Finding | Disposition | Reason / where |
|---|---|---|---|
| 1 | Determinism tuple omits stem; Yams unpinned | **Accept.** Tuple is (spec bytes, config bytes, stem, generator version); Yams `exact: "6.2.2"`. | §1. Relaxing either pin requires a revised guarantee and a generator minor bump. |
| 2 | Ordering gaps; tie-breakers; Foundation-normalised URLs; Unicode classification | **Accept.** Ordering audit moves to Phase 2 with an enumerated list of unordered sources; tie-breakers specified; URLs emitted from the spec string; identifier characters are ASCII-only by policy. Goldens are evidence, the rules are the guarantee. | §1, §5.1, §5.7, §5.8 |
| 3 | Response contract loses status/headers | **Accept.** Additive runtime hook (§6.1); status-tagged unions with HTTP reason-phrase case names; `200`+`204` handled; request media type preserved via fixed `Content-Type` header. | §5.5, §6.1 |
| 4 | Presence/nullability, readOnly/writeOnly, allOf, oneOf, strict default | **Accept with one modification.** Required-nullable gets custom Codable; optional-nullable collapses to `T?` (permanent, documented, no tri-state type); required readOnly/writeOnly → optional; conflicting `allOf` → error; untagged unions only when members are distinguishable by JSON kind, otherwise error; `strict: true` default. | §4, §5.6 |
| 5 | Naming not collision-proof/stable; `_` fallback invalid | **Accept.** No auto-suffixing: collisions and reserved names are errors; `renames` config in v1; namespace = stem verbatim (identifier-validated) so the plugin can check uniqueness; every emitted/synthesised symbol reserved; invalid names are errors, not fallbacks; algorithm frozen as a versioned contract. | §4, §5.7 |
| 6 | Path double-encoding; base-URL normalisation on the path component | **Accept as prerequisite** (separate runtime PR, coordinator-owned). Base URL: validate with `URLComponents`, reject query/fragment, append `/` to the path component, emit the original string. Encoded-value fixture in Phase 2. | §5.8, Phase 2 |
| 7 | Date helper lacks offset; deployment floor conflicts with this package's tests | **Accept, different fix.** Hand-written RFC 3339 helpers (no `ISO8601FormatStyle`, no formatter), emitted only when needed; offsets tested. Package platforms unchanged. | §7.4 |
| 8 | `Int`/`Double` bake in limits | **Accept.** `Int32`/`Int64`/`Int` policy; runtime conformances for `Int32`/`Int64`; `JSONValue.integer(Int64)`. | §5.6, §6.3 |
| 9 | Closed enums as default | **Accept.** Extensible default, closed opt-in, covers int enums. No request/response distinction (same schema often serves both). | §5.6 |
| 10 | Public output needs `public static let auth`; test from a second module; incompatible op security | **Accept.** Access-correct doc comment; Examples gains a second module; a note diagnostic when an operation's security scheme differs from the global one. | §5.9, Phase 2 |
| 11 | Support types are enduring public API; shared mutable coders | **Accept.** `JSONCoding` always internal; decoders/encoders are fresh per call via `HTTPResponseJSONDecoder` (a `Sendable` struct) and a `@Sendable` configure closure; only types appearing in witnesses take the configured access level; recursive optional coding tested. | §7.4 |
| 12 | Array-parameter precedence; semantics; header formatting | **Accept.** `ParameterRepresentable` checked first (existing conformances win); nil/empty/nil-element/query-vs-form semantics specified; header components restricted to `String`/`Int`/`Int32`/`Int64`/`Double`/`Bool` and optionals. | §6.2, §5.3 |
| 13 | Prove discovery/invalidation early; config version; write-if-changed; `--check` on bytes | **Accept.** Phase 2 acceptance includes the invalidation matrix and a native Xcode checklist; `"version": 1` in config; write-if-changed; `--check` compares regenerated bytes. | §3, Phase 2 |
| 14 | Claims about cloning, sandbox, trait union | **Accept with correction.** OpenAPIKit *is* fetched by all consumers on SwiftPM 6.1 because `targetsRequired(for: self.products)` walks every product (plugin included); on ≥ 6.2 `isTargetDependencyEnabled` drops trait-disabled dependencies before `dependencyConstraints`, so `traits: []` prunes them. Linux sandbox is a no-op → no-network comes from the generator (lint bans networking imports). Trait union can only re-enable `ExternalLoading` (harmless). | §2.2 |
| 15 | Phase 1 should test irreversible boundaries | **Accept.** Runtime foundations become Phase 1; the generator spike (Phase 2) targets ordered properties, required-nullable, `Int64`, reserved-name error, encoded path, public auth, incompatible responses, invalidation matrix, Xcode. Acceptance uses `swift test`/`--build-tests`. | §10 |
| — | Owner: package traits? | **Yes, default-on** (see trait row above and §2.2). | §2.2, §9 |

---

## 1. Determinism: definition and rules

**Definition.** For a fixed tuple **(spec bytes, config bytes, stem, generator version)** — where the stem is the logical name passed on the command line and derived by the plugin from the spec file name — `endpoints-generate` writes byte-identical files on every machine, OS, locale, clock, process, and invocation order. Pinned parser versions (OpenAPIKit 6.4.0, Yams 6.2.2) are part of "generator version". Nothing else is an input: not the spec's directory, user, time, toolchain patch version, or environment.

**Rules (checked by tests in Phase 2 and Phase 6):**

1. **No unordered iteration reaches output.** Every `Dictionary`/`Set` is converted to an array sorted with `Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8))` before use. Audit list of unordered sources in OpenAPIKit 6.4.0 that the lowering touches: `OpenAPI.SecurityRequirement` (`[JSONReference<SecurityScheme>: [String]]`) → sorted by reference name; `vendorExtensions: [String: AnyCodable]` → never iterated in v1; object values inside `AnyCodable` → never iterated (only scalar `allowedValues` are read); `Document.allTags` (`Set`) → not used (tags are read from `operation.tags` arrays). Ordered and safe: paths, components, schema properties, responses, content maps, discriminator mapping, server variables, `Compat30To31` conversion (preserves order). Our own `Set`s (cycle detection, reserved names) never reach output unsorted.
2. **Ordering policy.** File-level declarations (component types, endpoints, header-dictionary entries, conformance extensions) are sorted by generated Swift name. Members with user-visible order (struct properties, enum values, union cases, memberwise-init arguments, `Definition.parameters`) keep **spec order**, with path-item-level parameters before operation-level ones (an operation parameter overrides a path-item one with the same name and location).
3. **Tie-breakers.** Media selection: fixed priority list (§5.4/§5.5), then document order. Response codes: explicit codes before ranges (`2XX`) before `default`. Schema identity: by `$ref` component name only; inline schemas are never deduplicated. Diagnostics: sorted by (file, line, column, JSON pointer, message) before printing; messages are generator-authored text, never upstream error descriptions (OpenAPIKit/Yams errors are mapped to our own codes with the upstream text appended only as a quoted detail).
4. **No varying strings.** Banned in `EndpointsGeneratorCore` and `endpoints-generate`: `Date()`, `Date.now`, `.random(`, `getenv`, `UUID()`, `ProcessInfo`, `FileManager.currentDirectoryPath`, `NSUserName`, `#file`/`#filePath`/`#function` in output, `Bundle`, `Locale`, `.capitalized`, `localized*`, `String(format:)`, `Mirror`, `Hasher`-dependent ordering, `URLSession`, `FoundationNetworking`. `URL`/`URLComponents` may validate input but never produce output text (§5.8).
5. **Identifier policy.** Only ASCII letters, digits and `_` are identifier characters; every other scalar is a separator. Names that yield no valid identifier are errors with a `renames` hint. Casing touches ASCII only. This makes names independent of the toolchain's Unicode tables.
6. **Header comment.**
   ```
   // Generated by EndpointsGenerator 0.1.0 for Petstore (Petstore.openapi). Do not edit.
   // Inputs: spec sha256 3f2a9c1d7e8b4f60, config sha256 none
   // swiftlint:disable all
   ```
   Version is the constant `GeneratorVersion.current`; SHA-256 (self-contained implementation, test vectors) of the raw spec and config bytes, 16 hex chars. The source label is always `<Stem>.openapi`; the actual basename and directory never appear in output.
7. **No network, no filesystem beyond inputs.** Local `$ref`s only; `ReferenceError.cannotLookupRemoteReference` is a hard error in both modes. Networking imports are banned (rule 4) because SwiftPM's sandbox is a no-op on Linux.
8. **Text format.** UTF-8, no BOM, `\n`, 4-space indent, no trailing whitespace, exactly one trailing `\n`, at most one consecutive blank line. `CodeWriter.finish()` asserts these; a test checks every golden.
9. **Build integration.** `.buildCommand` with `inputFiles: [spec, config?]`, the four outputs, and the executable as implicit input. Output names derive from the stem only.

**Evidence** (§8): goldens compiled and byte-compared on macOS and Linux; a cross-process test with random hash seeds; the banned-token lint; the shuffle test. These demonstrate the rules hold for the corpus; the rules themselves are the guarantee.

---

## 2. Package layout

### 2.1 Targets, products, trait

```swift
// swift-tools-version:6.1
import PackageDescription

let generatorTrait = "OpenAPIGenerator"

let generatorTargets: [Target] = [
    .target(
        name: "EndpointsGeneratorCore",
        dependencies: [
            .product(name: "OpenAPIKit", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
            .product(name: "OpenAPIKit30", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
            .product(name: "OpenAPIKitCompat", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
            .product(name: "Yams", package: "Yams", condition: .when(traits: [generatorTrait])),
        ]),
    .executableTarget(name: "endpoints-generate", dependencies: ["EndpointsGeneratorCore"]),
    .plugin(name: "EndpointsGeneratorPlugin", capability: .buildTool(), dependencies: ["endpoints-generate"]),
    .testTarget(name: "EndpointsGeneratorCoreTests", dependencies: ["EndpointsGeneratorCore"], resources: [.copy("Fixtures")]),
    .testTarget(name: "EndpointsGeneratedGoldenTests", dependencies: ["Endpoints"]),   // goldens compiled as sources
]

// Appended to BOTH branches of the existing #if os(Linux) manifest:
// products += .plugin(name: "EndpointsGeneratorPlugin", targets: ["EndpointsGeneratorPlugin"])

// Package(...):
traits: [
    .trait(name: generatorTrait, description: "Builds the OpenAPI → Endpoints generator and fetches its dependencies (OpenAPIKit, Yams)."),
    .default(enabledTraits: [generatorTrait]),
],
dependencies: [
    .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", exact: "6.4.0", traits: []),
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
]
```
- `EndpointsGeneratorCore` is not a product; tests use `@testable import`. The CLI parses its flags by hand (no swift-argument-parser: every dependency here is fetched by plugin users).
- Phase 6 adds `.plugin(name: "EndpointsGenerateCommand", capability: .command(intent: .custom(verb: "generate-endpoints", description: ...), permissions: [.writeToPackageDirectory(reason: ...)]))` for vendoring, with `--check`.
- Phase 1 verifies that `.package(url:exact:traits:)` accepts `traits:` in tools 6.1 (fallback: omit it and accept `ExternalLoading`).

### 2.2 Consumer impact and the trait decision

Verified against SwiftPM sources:
- `Manifest.dependenciesRequired(for:)` for a non-root package (tools ≥ 5.2) keeps dependencies referenced by `targetsRequired(for: self.products)` — **all products**, not the ones the consumer uses. The plugin product reaches `EndpointsGeneratorCore` → OpenAPIKit/Yams, so on SwiftPM **6.1** every consumer fetches OpenAPIKit, Yams, swift-docc-plugin and swift-docc-symbolkit (clone only; nothing is built unless the plugin is used).
- On SwiftPM **6.2 and later**, that same walk skips a target dependency when `isTargetDependencyEnabled(target:_:enabledTraits:)` returns false (all guarding traits disabled), and `SourceControlPackageContainer.loadDependencies` feeds `manifest.dependencyConstraints(productFilter:enabledTraits)` to the resolver. A dependency used only under a disabled trait is therefore **not fetched**. SE-0450's "not during resolution" text describes 6.1; the implementation moved on. No CHANGELOG entry documents it, so Phase 1 adds a CI assertion (below) rather than relying on prose.

Decision: **trait `OpenAPIGenerator`, default-on.**
- Plugin users and Xcode projects need no opt-in (Xcode offers no trait UI); adding the trait in v1 can't break anyone.
- Runtime-only consumers on ≥ 6.2 opt out: `.package(url: "https://github.com/velos/Endpoints.git", from: "0.6.0", traits: [])`. On 6.1 the opt-out is accepted but has no effect (documented).
- Trait union: another package enabling `OpenAPIGenerator` only causes the fetch; nothing is built unless the plugin product is used.
- Trait-disabled builds: Core and the CLI compile without OpenAPIKit/Yams, guarded by `#if OpenAPIGenerator`. Invoking the CLI without the trait exits non-zero with a source-formatted error asking the consumer to enable the `OpenAPIGenerator` trait. A plugin build command surfaces that same error as a build diagnostic. This guard is necessary even for root runtime-only builds: with Apple Swift 6.4, the native SwiftPM engine warns that `--product Endpoints` cannot select an automatic library, then builds default targets including the executable. The default `swiftbuild` engine selects the runtime successfully. Keep `swift build --disable-default-traits --product Endpoints` in CI; both engines must pass it. This observation supersedes the originally planned missing-import failure; it does not change generated public API.
- CI: `Examples/RuntimeOnlyClient` (`traits: []`) builds on the macOS job (SwiftPM ≥ 6.2) and a step asserts `.build/checkouts` contains neither `OpenAPIKit` nor `Yams`.

Effective minimum toolchain for all consumers: **Swift 6.1** (our manifest). README "Requirements" updated.

### 2.3 Consumer usage
```swift
.package(url: "https://github.com/velos/Endpoints.git", from: "0.6.0"),
.target(name: "App",
        dependencies: [.product(name: "Endpoints", package: "Endpoints")],
        plugins: [.plugin(name: "EndpointsGeneratorPlugin", package: "Endpoints")])
```
`Sources/App/Petstore.openapi.yaml` plus optional `Sources/App/Petstore.endpoints.swift` starting in 3N-2 (the only user-facing config). Phase 2 records whether SwiftPM 6.1 warns about the `.yaml` as an unhandled file; if so the README calls it benign (it must not be `exclude`d).

### 2.4 Xcode projects
`Plugins/EndpointsGeneratorPlugin/Plugin.swift` implements `BuildToolPlugin` and, under `#if canImport(XcodeProjectPlugin)`, `XcodeBuildToolPlugin` (`target.inputFiles`, `context.pluginWorkDirectoryURL`), both calling one `makeCommands(specs:toolURL:workDirectory:)`. Phase 2 includes a manual checklist against a real `.xcodeproj` (not the package opened in Xcode): discovery, regeneration on spec edit, issue-navigator diagnostics, Copy Bundle Resources guidance.

### 2.5 CI
Linux container `swift:6.1`; macOS `macos-latest`. Steps added: `swift test` (goldens, determinism, lint, runtime), `swift build --package-path Examples/PetstoreClient --build-tests && swift test --package-path Examples/PetstoreClient`, the `RuntimeOnlyClient` fetch assertion (macOS), and `swift build --disable-default-traits --product Endpoints` (runtime builds without the trait). `.spi.yml` unchanged.

---

## 3. Plugin UX

### 3.1 Discovery
- Spec: `<Stem>.openapi.{json,yaml,yml}` where `Stem` matches `[A-Za-z_][A-Za-z0-9_]*`; the literal `openapi.{json,yaml,yml}` is accepted with stem `API`. Any other `*.openapi.*` name → `Diagnostics.error` ("rename the file; the stem becomes the Swift namespace").
- Config: only `<Stem>.endpoints.swift` beside the spec, available from 3N-2. Phase 3N-1 uses defaults and discovers no configuration files.
- Namespace = configured namespace if set (3N-2), else the stem verbatim. The plugin rejects duplicate stems and stems that differ only by ASCII case. Configured namespace clashes are diagnosed by the consumer compiler; the plugin does not evaluate configs while planning.
- Zero specs → `Diagnostics.warning`, no commands. Several specs → one command and four files each.

### 3.2 Command
```
endpoints-generate generate --spec <path> --stem <Stem> --output-dir <dir> [--check]
```
Outputs under `pluginWorkDirectoryURL/GeneratedSources/<Stem>/`. All four files are always produced (a file with nothing to declare gets the header and a one-line comment). Files are written only when their bytes differ. `--check` (CLI available from 3N-2; vendoring command plugin in Phase 6) regenerates into memory and exits 1 if any existing file's bytes differ.

### 3.3 Diagnostics
`path:line:column: error|warning|note: message [#/json/pointer]` on stderr (Xcode and SwiftPM render these). Positions come from the composed Yams mapping key at the JSON pointer (array entries use their node mark); missing keys fall back to the closest authored parent, then `path:1:1`. References carry the final component source pointer. OpenAPI decoding errors are wrapped with `OpenAPI.Error(from:)` to recover their coding path; parse, decode and validation summaries append the upstream reason as a quoted detail. Exit 1 on any error. `strict: true` (default) makes every *unsupported-construct* finding an error; `strict: false` downgrades those to warnings and skips the construct (operation, parameter, or property). Collisions, reserved names, conflicting `allOf`, ambiguous unions, external refs, and invalid servers are errors in both modes. OpenAPIKit decoding errors and `validate()` failures are errors; OpenAPIKit's non-fatal warnings are not surfaced.

---

## 4. Typed Swift configuration (available from 3N-2)

The only user-facing configuration is `<Stem>.endpoints.swift` beside the spec
(`API.endpoints.swift` for bare `openapi.yaml`). It imports the dependency-free
`EndpointsGeneratorConfig` product and declares the typed configuration described
in [OpenAPIGenerator-Naming.md §4.1](OpenAPIGenerator-Naming.md).
That document supersedes this design's original configuration and naming rules.
Phase 3N-1 provides the library, naming algorithm and in-process Core support;
the plugin evaluates Swift config files starting in 3N-2. Until then the plugin
uses defaults, including internal access. There is no user-facing JSON sidecar.

```swift
// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let petstoreConfiguration = EndpointsConfiguration(
    accessLevel: .public,
    renames: [.type("Date"): "CalendarDate"]
)
```

JSON remains private serialization of the declarative settings for the future
config program and test fixtures. Core owns its reader and pointer diagnostics;
its vocabulary is not public API and carries no compatibility promise. The
plugin neither discovers nor passes JSON configuration. Public configuration
instructions cover Swift only; see Naming §4.2 for the internal boundary.

---

## 5. Generator pipeline and mapping

### 5.1 Pipeline
```
Inputs(spec bytes, config bytes, stem)
  → Loader     : Yams compose (marks) + Yams decode; version sniff → OpenAPIKit30 + convert(to: .v3_1_1) | OpenAPIKit; 2.0 → error
  → Validator  : document.validate(); external-ref scan (error); operation filter; config validation
  → Lowering   : OpenAPI.Document → IR via components.lookup(_:) with an explicit visited set (never locallyDereferenced(): it drops $ref names)
  → Naming     : NameAllocator per scope; renames; reserved-name and collision checks (errors)
  → Rendering  : CodeWriter → 4 GeneratedFile(name, bytes)
  → Diagnostics: collected, sorted, printed by the CLI
```
IR (arrays only, no dictionaries; local lookup/memoization tables do not cross this boundary): `Module { namespace, access, server: ServerDecl, schemas: [TypeDecl], endpoints: [EndpointDecl], support: SupportNeeds }`; `TypeRef` (`string, int, int32, int64, double, bool, date, data, uuid, url, jsonValue, array, dictionary, optional, named(path)`); `TypeDecl` (`structure | openEnum | closedEnum | union | alias`); `StructDecl.Property { swiftName, wireName, type, docs, deprecated, presence: .optional | .requiredNullable | .required, boxed }`; `UnionDecl { cases: [(name, payload: TypeRef?, match: .discriminator(String) | .kind(JSONKind) | .status(Int|range|default))], indirect }`; `EndpointDecl { name, docs, method, path: [PathSegment], pathParams, queryParams, headerParams, formParams, body: BodyDecl?, response: ResponseDecl, errorResponse: ResponseDecl?, auth: .inherit | .none, fixedHeaders, deprecated, nested }`.

### 5.2 Operations
| OpenAPI | Generated | Status |
|---|---|---|
| `operationId: listPets` | `struct ListPetsEndpoint: Endpoint` | supported |
| no `operationId` | `<Method><Segments>Endpoint`, `{x}` → `By<X>` (`GetPetsByPetIdPhotosEndpoint`) | supported |
| `tags` | doc-comment line only | by design |
| `summary`/`description` | `///` summary, blank, description, blank, `` `GET /pets/{petId}` `` | supported |
| operation `deprecated` | `@available(*, deprecated)` on the endpoint; schema-level deprecation uses documentation only (§5.6) | supported |
| `security: []` | `static var auth: NoAuth { NoAuth() }` | supported |
| operation `security` naming a scheme other than the document's | inherits server auth + **note** diagnostic | degraded (credentials are runtime state) |
| op/path-level `servers` | error (strict) / skip op with warning | unsupported |
| `callbacks`, `links`, webhooks | ignored silently (not client surface) | n/a |

### 5.3 Parameters
Scalar path and header parameters use `simple` serialization; `explode` has no effect on scalars and either value is accepted. Query scalars use `form` (either `explode` value), while query arrays require `form` plus `explode: true`. Other styles are unsupported.

Header parameter override identities compare names case-insensitively with ASCII folding; other wire names compare UTF-8 bytes. Dropped explicit 3xx statuses and 1XX/3XX ranges produce source-marked note diagnostics.

Properties of `PathComponents`/`ParameterComponents`/`HeaderComponents` (declared `Sendable`, explicit `init`, optionals default `nil`). Headers dictionary entries sorted by header name.

Full-segment placeholders use ordinary `PathTemplate` key-path interpolation. Embedded placeholders (prefixes, suffixes such as `.json`, or multiple parameters within a segment) use a fileprivate `_endpointPath` returning the internal `<Namespace>.EncodedPath: PathRepresentable` from Support. It concatenates literal template text with each parameter's `.pathSafe`, including enums through their RawRepresentable conformance. Literal `/` stays a separator; `/`, `?`, `#`, `%`, spaces and Unicode inside values are percent-encoded once. The runtime normalizer preserves those escapes before assigning `percentEncodedPath`. The helper is emitted only when an embedded path is retained; no generated public signature uses it.

Ordinary interpolation cannot replace this strategy with the current runtime: `"files/\(path: \.name).json"` produces `files/42/.json`; setting `includesSlash: false` produces `files42.json`. A local probe also covered prefixed and two-parameter segments. Keeping computed paths avoids changing runtime slash semantics while protecting parameter boundaries.

| Construct | Generated | Status |
|---|---|---|
| path string/int/int32/int64/uuid | `String`/`Int`/`Int32`/`Int64`/`UUID` (runtime conformances §6.3), `PathRepresentable.pathSafe` encodes each value once; template separators are preserved | supported |
| path enum (inline/ref) | enum type + `extension X: PathRepresentable, ParameterRepresentable {}` | supported |
| path bool/double/other | unsupported (error / skip op) | unsupported |
| query scalar required/optional | `T` / `T?` | supported |
| query `date-time`/`date`/`uri` | `String` (`Date.parameterValue` is a local-time day; not used for params) | degraded, documented |
| query array, `form`+`explode: true` (default) | `[T]` / `[T]?` → repeated keys (§6.2) | supported |
| query array other styles, objects, `deepObject`, `content:` | unsupported (error / skip param) | unsupported |
| header `String`/`Int`/`Int32`/`Int64`/`Double`/`Bool` and optionals | `HeaderComponents` property (optional needs §6.4) | supported |
| header enum/other | unsupported (error / skip param) | unsupported |
| cookie params | unsupported (error / skip param) | unsupported |
| `deprecated` | `@available(*, deprecated)` on the public property; generated uses go through non-deprecated backing storage | supported |

### 5.4 Request bodies
Priority: `application/json` → any `*+json` → `application/x-www-form-urlencoded` → `multipart/form-data` → others (raw). Ties: document order. When the chosen media type isn't exactly `application/json`, the generator pins it with `headers: [.contentType: .fieldValue(value: "<media type>")]` (the runtime does not add the encoder's type when one is set).

| Content type | Generated | Status |
|---|---|---|
| JSON `$ref` / inline object / array / primitive | `typealias Body = …` or nested `struct Body`; `static var bodyEncoder: JSONEncoder { PetstoreAPI.JSONCoding.makeEncoder() }` only when a `Date` is involved | supported |
| form, object of scalars | `.form("name", path: \.name)` in `ParameterComponents` | supported |
| form with nested fields | unsupported (error / skip op) | unsupported |
| multipart | nested `struct Body: Encodable, Sendable`; `binary` → `MultipartFormFile`, object → `MultipartFormJSON<T>`; `static var bodyEncoder: MultipartFormEncoder { MultipartFormEncoder() }` | supported |
| octet-stream / image / other binary | `typealias Body = Data`; `static var bodyEncoder: PetstoreAPI.RawBodyEncoder { .init() }`; media type via fixed header | supported |
| `text/plain`, XML | treated as raw `Data` + note | degraded |
| `required: false` body | unsupported (error / generate non-optional with warning) | unsupported |

### 5.5 Responses (one `Response`, one `ErrorResponse`, exact status dispatch)
Response media selection: `application/json` → `*+json` → none/other. A non-JSON success body → `Data`.
- **Response.** Collect success outcomes: explicit 2xx codes, then `2XX`, then `default` (only if no 2xx exists). If exactly one outcome → `typealias Response = T`, or `Void` (204, no content, `HEAD`), or `Data`. If several outcomes → nested `enum Response: Decodable, Hashable, Sendable` with one case per outcome, dispatched on `decoder.userInfo[.httpStatusCode]` (§6.1): `case ok(PetstoreAPI.Pet)`, `case noContent`, `case created(PetstoreAPI.Order)`, `case success(…)` for `2XX`, `case defaultResponse(…)`. Case names come from a fixed [IANA reason-phrase table](https://www.iana.org/assignments/http-status-codes); unknown codes use `status<code>`. The decoder override `static var responseDecoder: HTTPResponseJSONDecoder { PetstoreAPI.JSONCoding.makeDecoder() }` is emitted whenever a union or a `Date` is involved.
- **ErrorResponse** (`Decodable & Sendable`). Collect 4xx/5xx explicit codes, `4XX`/`5XX`, and `default` (when a 2xx exists). None → protocol default `EmptyCodable`. One outcome → `typealias ErrorResponse = PetstoreAPI.Problem` / nested `struct ErrorResponse`. Several → nested `enum ErrorResponse` with status-dispatched cases (`badRequest`, `notFound`, `clientError`, `serverError`, `defaultResponse`); a status with no matching case and no `default` throws `DecodingError`, which the runtime reports as `errorResponseParseError`. `static var errorDecoder: HTTPResponseJSONDecoder` is emitted for a status union, a payload involving `Date`, or a raw `Data` error payload. `bodyEncoder` is emitted only for a body involving `Date`; `responseDecoder` is emitted for a status union or a response involving `Date`. Date usage follows referenced and inline schemas. Other payloads inherit runtime defaults.
- Exact status matches precede range matches, then `default`, regardless of map order. At least one success or default outcome is required; error-only operations produce an unsupported diagnostic. Enum cases retain the authored response-map order within their success/error category. Inline union payloads are nested `Option1`, `Option2`, etc. (§5.6), numbered by that category's authored outcome order, including body-less outcomes.
- **Raw union bodies:** JSONDecoder normally parses the whole input before invoking a status enum, so it cannot dispatch arbitrary binary bytes. `HTTPResponseJSONDecoder` therefore has an opt-in `isRawDataStatus: @Sendable (_ statusCode: Int) -> Bool` selector. The JSON-only initializer selects no raw statuses; the selector initializer requires that argument. Selected bodies, including empty data, become a JSON base64 string before decoding; `.base64` is forced after configuration so custom data strategies cannot break raw decoding. Body-less union outcomes also select raw decoding, ignoring arbitrary bytes just as a single Void response does. Explicit 204 arms are always omitted: `Definition.responseWithMetadata` discards every 204 body and supplies `Data()` before decoding. Unions without a default treat unmatched statuses as raw, allowing their decoder to report the unexpected status code even for HTML or text bodies. The enum's `singleValueContainer().decode(Data.self)` receives the original bytes. Payloads decode through a single-value container to preserve JSONDecoder's Data/Date strategies; calling `Data(from:)` or `Date(from:)` directly bypasses those strategies. Generated overrides use the same exact/range/default precedence for this selector. An arm is omitted when its result equals the next matching lower-precedence result; pure code predicates are emitted as comparisons. Support omits empty configure closures, and `configure` is the last initializer parameter for trailing-closure use. Selection follows the spec's media priority, independent of the actual Content-Type header. Single raw successes retain the runtime's direct `Data` path; raw error payloads also use the selector. Invalid JSON on JSON statuses still throws.
- The frozen reason-phrase table is checked into `Lowering/Operations.swift` (including `contentTooLarge` for 413 and `unprocessableContent` for 422); unassigned or unused codes such as 299 and 418 use `status<code>`. No platform HTTP phrase lookup participates in naming.
- Response headers are not modelled (available to hand-written code via `.httpHeaders`).

### 5.6 Component schemas → Swift types
Models are `Codable, Hashable, Sendable`, properties `var`, explicit memberwise `init` (optionals default `nil`). Type references are fully qualified from the namespace root.

| Schema | Swift | Status |
|---|---|---|
| object with `properties` | `struct` | supported |
| not required, not nullable | `T?`; absent ↔ `nil`; synthesized Codable | supported, exact |
| required + nullable (3.0 `nullable`, 3.1 `[T, "null"]`, `oneOf [T, null]`, `enum [..., null]`) | `T?`; struct gets explicit `init(from:)`/`encode(to:)`: `decode(T?.self, forKey:)` (missing key throws, `null` → nil) and `encode(_:forKey:)` (nil → `null`) | supported, exact |
| optional + nullable | `T?`; absent and `null` both → `nil`; encoding omits. **Permanent policy**, documented in Generating.md (no tri-state type) | degraded by design |
| required + `readOnly`/`writeOnly` | `T?` (required doesn't apply in the other direction) | supported |
| string enum / int enum | `enums: "open"` (default): `struct Status: RawRepresentable, Codable, Hashable, Sendable { let rawValue; init(rawValue:); static let available = …; static let knownValues: [Status] }`; `"closed"`: `enum Status: String|Int|Int32|Int64, Codable, Hashable, Sendable, CaseIterable` (integer formats retain their width) | supported |
| enum of other types | error | unsupported |
| `string` formats | `date-time` → `Date`; `uuid` → `UUID`; `uri` → `URL`; `byte` → `Data` (base64); `binary` → `Data` (JSON) / `MultipartFormFile` (multipart); `date` and all others → `String` | supported |
| `integer` | no format → `Int`; `int32` → `Int32`; `int64` → `Int64` | supported |
| `number` | `Double` (any format) | supported |
| `boolean` | `Bool` | supported |
| `array` | `[T]`; no `items` → `[JSONValue]` | supported |
| object with only `additionalProperties` / free-form | `[String: T]` / `[String: JSONValue]` | supported |
| `properties` **and** `additionalProperties` | error (strict) / drop extras with warning | unsupported |
| `{}`, `fragment`, `not`, lone `null` | `JSONValue` + note | degraded |
| `allOf` of objects/refs | flattened `struct`; same wire name in two members must resolve to the identical `TypeRef`, else **error**; required = union of members' required | supported |
| `allOf` with non-object member | error | unsupported |
| `oneOf` + `discriminator` | `enum` with a case per member; `init(from:)` reads the discriminator key and switches on `mapping` values (default: component name); payload decoded with the same decoder; `encode(to:)` forwards | supported |
| `oneOf`/`anyOf` without discriminator | untagged `enum` **only if** members are pairwise distinguishable by JSON kind (null, bool, number, string, array, object — each at most once); dispatch inspects the kind via `singleValueContainer` probes in that fixed order; otherwise **error** "add a discriminator" | supported / unsupported |
| `discriminator` on an `allOf` base | base stays a struct; note | degraded |
| recursive schemas | dependency graph; edges through `array`/`dictionary` need no boxing; every other edge inside a strongly connected component gets `@Indirect` (Support); unions in a cycle are `indirect enum` | supported |
| inline object in property `owner` | nested `Pet.Owner` | supported |
| inline object as array item of `tags` | nested `Pet.TagsItem` | supported |
| inline enum in property/parameter | nested `Pet.Status` / `ListPetsEndpoint.Status` | supported |
| inline object in a union | nested `Option1`, `Option2` | supported |
| wire name not a valid identifier | sanitised name + `private enum CodingKeys` listing all properties (only when any differs) | supported |
| `description`/`title` → doc comments; schema-level `deprecated` → `/// - Important: Deprecated by the OpenAPI document.` | Schema types never receive `@available(*, deprecated)`, so live generated references remain warning-free. Properties and parameters keep the attribute. | supported |
| `default`, `pattern`, `min*`/`max*`, `example(s)`, `xml`, `externalDocs` | ignored | n/a |

### 5.7 Naming (frozen contract; changes require a generator major bump)
1. Apply `renames` first; a renamed value must already be a valid identifier.
2. Tokenise: split on any non-`[A-Za-z0-9_]` scalar, on lower→Upper boundaries, and before the last capital of an uppercase run followed by lowercase (`HTTPStatus` → `HTTP`,`Status`).
3. PascalCase: uppercase the first ASCII letter of each token, keep the rest. lowerCamel: first token lowercased entirely if all-uppercase ASCII, else first letter only; other tokens Pascal.
4. Leading digit → prefix `_`. No tokens → **error**.
5. Members that are Swift keywords → backticks. Types equal to a keyword or `Type`/`Protocol`/`Self`/`Any` → **error**.
6. Reserved (→ **error** with rename hint). The namespace name itself is reserved in namespace, struct-nested, and endpoint-nested type scopes, preventing qualified references from resolving to a shadowing nested type. Namespace scope: `Server`, `Environment`, `JSONCoding`, `JSONValue`, `Indirect`, `RawBodyEncoder`, `EncodedPath`, and every unqualified library type the generated code references (`String, Int, Int32, Int64, Double, Bool, Date, Data, UUID, URL, Optional, Array, Dictionary, Decodable, Encodable, Codable, Hashable, Sendable, CaseIterable, RawRepresentable, Decoder, Encoder, DecodingError, EncodingError, KeyedDecodingContainer, KeyedEncodingContainer, Endpoint, Definition, Header, HeaderField, Parameter, PathTemplate, Method, NoAuth, EmptyCodable, JSONEncoder, JSONDecoder, HTTPResponseJSONDecoder, MultipartFormEncoder, MultipartFormFile, MultipartFormJSON, EncoderType, DecoderType, ParameterRepresentable, PathRepresentable, ServerDefinition, TypicalEnvironments`). Endpoint scope: `Server, Response, ErrorResponse, Body, PathComponents, ParameterComponents, HeaderComponents, Auth, TaskError, BodyEncoder, ErrorDecoder, ResponseDecoder, definition, body, pathComponents, parameterComponents, headerComponents, auth, bodyEncoder, errorDecoder, responseDecoder, queryEncodingStrategy`. Struct scope: `CodingKeys`, `init`, `hashValue`, `rawValue`, `allCases`, `knownValues`, `wrappedValue`, and `_<name>` for every boxed or deprecated property. Union scope: `DiscriminatorKeys`, case names of the status/kind tables.
7. Naming and renames are superseded by Naming §4.1/§5.7. Rename hints use Swift syntax, e.g. `renames: [.operation(.route(method: .get, path: "/pets/{petId}")): "FetchPet"]`. Collisions within a scope (two originals → one Swift name; a query and a form field with one name; endpoint names from `operationId` vs method+path) → **error** naming both originals and the `renames` key to use.
8. Enum member names: lowerCamel of the raw value; `""` → `empty`; ints → `value<N>` / `valueMinus<N>`; collisions → error.
9. Environment case names: from `servers[].description` (lowerCamel), fallback `server<index>`; collisions → error.

### 5.8 Servers and environments
- `server.type` → `typealias Server = <Type>` everywhere; nothing generated.
- `server.environments` → `struct Server: ServerDefinition` with `TypicalEnvironments`, URLs from config.
- Otherwise `enum Environment: String, Hashable, Sendable, CaseIterable` from spec `servers` (spec order; doc comment = URL + description); default = first server.
- Variables substituted with `default`; note lists variables and enum alternatives. Relative URLs, URLs with query or fragment, and zero servers without config → **error**.
- URL handling: parse with `URLComponents` to validate; if the path is non-empty and lacks a trailing `/`, insert `/` at the end of the path in the **original string** (query/fragment are rejected, so this is a suffix insertion); emit the string verbatim (never `URL.absoluteString`). Operation paths lose their leading `/`. Verified: `https://h/api/v3` + `pet/x` → `https://h/api/pet/x`; with trailing slash → `https://h/api/v3/pet/x`; a leading `/` on the path discards the base path.
- `requestProcessor` is not generated.

### 5.9 Security schemes → `Auth`
1. `Server` is emitted without `auth`; `Auth` defaults to `NoAuth` via the associated-type default and the `where Auth == NoAuth` extension.
2. A doc comment on `Server` lists each scheme with the matching Endpoints type (`http bearer` → `HeaderKeyAuth`/`JWTAuth`; `http basic` → `BasicAuth`; `apiKey header` → `HeaderKeyAuth(key:header:prefix: nil)`; `apiKey cookie` → `CookieAuth`; `apiKey query` → "not supported; use `requestProcessor`"; `oauth2`/`openIdConnect` → `JWTAuth`; `mutualTLS` → URLSession) and the exact extension to write, **with the configured access level** (`public static let auth = …` for public output).
3. The user's same-module extension witness determines `Auth` (confirmed by review); endpoints inherit via `Auth = Server.Auth`. From another module this cannot work (documented).
4. `security: []` → `NoAuth` override. An operation whose security differs from the document's → note.

---

## 6. Runtime changes to `Endpoints` (Phase 1; additive, dependency-free)

### 6.1 Response-aware decoding (the response hook)
```swift
public protocol DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
    /// Decodes a response body with access to the HTTP response. Defaults to `decode(_:from:)`.
    func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T
}
public extension DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T { try decode(type, from: data) }
}

public extension CodingUserInfoKey {
    /// `Int`: the status code of the response being decoded.
    static let httpStatusCode = CodingUserInfoKey(rawValue: "com.velos.endpoints.httpStatusCode")!
    /// `[String: String]`: the response headers, names as received.
    static let httpHeaders = CodingUserInfoKey(rawValue: "com.velos.endpoints.httpHeaders")!
}

/// A JSON decoder that exposes the HTTP status and headers through `Decoder.userInfo`
/// and decodes an empty body as JSON `null`, so a response type can represent body-less statuses.
public struct HTTPResponseJSONDecoder: DecoderType, Sendable {
    public var configure: @Sendable (JSONDecoder) -> Void
    public var isRawDataStatus: @Sendable (_ statusCode: Int) -> Bool
    public init(configure: @Sendable @escaping (JSONDecoder) -> Void = { _ in })
    public init(
        isRawDataStatus: @Sendable @escaping (_ statusCode: Int) -> Bool,
        configure: @Sendable @escaping (JSONDecoder) -> Void = { _ in }
    )
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T                 // fresh JSONDecoder, configure, decode
    public func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T
    // fresh JSONDecoder; configure; userInfo[.httpStatusCode] = response.statusCode; userInfo[.httpHeaders] = …;
    // decode(type, from: data.isEmpty ? Data("null".utf8) : data)
}
```
The initializers are disjoint: `init(configure:)` creates a JSON decoder with no raw-data statuses, while `init(isRawDataStatus:configure:)` requires a selector and also decodes its selected statuses as Data. A trailing closure after `isRawDataStatus:` binds to `configure`. Only the response-aware overload sets the HTTP userInfo keys or invokes `isRawDataStatus`; raw decoding forces `.base64` after configuration.

Call sites switch to the three-argument form: `URLSession+Async.performRequest` (its `transform` gains the `HTTPURLResponse`), the three `endpointTask` overloads, `URLSession+Combine`, and the error path in `Definition+URLResponse.swift`. `Definition.response(data:response:error:)` keeps its public signature; a new internal variant returns the `HTTPURLResponse` alongside the data. Existing `JSONDecoder` users are untouched (default method). The `EmptyCodable.init(from:)` empty-body behavior is intentionally deferred to `claude/endpoints-runtime-fixes`; the public response helper otherwise preserves its existing status/data/error behavior. Combine delegates to the async implementation, so metadata forwarding there covers its publishers too.

### 6.2 Repeated query/form parameters
```swift
public protocol MultiValueParameterRepresentable { var parameterValues: [String] { get } }
extension Array: MultiValueParameterRepresentable where Element: ParameterRepresentable { … compactMap(\.parameterValue) }
extension Optional: MultiValueParameterRepresentable where Wrapped: MultiValueParameterRepresentable { … nil → [] }
```
In `urlRequest(in:)` the existing `ParameterRepresentable` check runs **first** (existing custom conformances keep their behaviour); only values that aren't `ParameterRepresentable` are then checked for `MultiValueParameterRepresentable` and appended one `URLQueryItem` per value. Semantics: `nil` array → omitted; empty array → omitted; `nil` elements → omitted; identical for `.query` and `.form`; fixed values unchanged.

### 6.3 Conformances
`extension ParameterRepresentable where Self: RawRepresentable, RawValue: ParameterRepresentable` and the `PathRepresentable` twin (default implementations); `Int32`, `Int64`, `UUID`: `ParameterRepresentable` and `PathRepresentable`.

### 6.4 Optional headers (separate bug-fix branch)
`Optional<String>` isn't `CustomStringConvertible`, so optional header components currently throw `invalidHeader`. An internal `OptionalHeaderValue` protocol (`extension Optional where Wrapped: CustomStringConvertible`) makes `nil` omit the header and `.some` use the wrapped `description`. Behaviour change limited to a case that previously always threw.

---

## 7. Generated code examples (valid against the API above)

Generated layout: an initializer signature stays on one line if the complete line, including its indentation and opening brace, is at most 100 UTF-8 bytes; otherwise use one parameter per line. Consecutive stored `let`s, coder overrides, and open-enum static members form uninterrupted groups. Closed string-enum cases omit raw values when the identifier already equals the wire value.

### 7.1 `Petstore.Server.swift`
```swift
// Generated by EndpointsGenerator 0.1.0 for Petstore (Petstore.openapi). Do not edit.
// Inputs: spec sha256 3f2a9c1d7e8b4f60, config sha256 9b1e0c44d2a7f315
// swiftlint:disable all

import Endpoints
import Foundation

/// Swagger Petstore (1.0.0)
public enum Petstore {

    /// Security schemes declared by the spec. Credentials are runtime state, so attach them
    /// in your own file in this module:
    ///
    ///     extension Petstore.Server {
    ///         public static let auth = HeaderKeyAuth(key: apiKey, header: "api_key", prefix: nil)
    ///     }
    ///
    /// - `api_key`: apiKey in header `api_key`
    /// - `petstore_auth`: oauth2 (consider `JWTAuth`)
    public struct Server: ServerDefinition {
        public typealias Environments = Petstore.Environment

        public init() {}

        public var baseUrls: [Environments: URL] {
            [
                .server1: URL(string: "https://petstore3.swagger.io/api/v3/")!
            ]
        }

        public static var defaultEnvironment: Environments { .server1 }
    }

    public enum Environment: String, Hashable, Sendable, CaseIterable {
        /// https://petstore3.swagger.io/api/v3
        case server1
    }
}
```

### 7.2 `Petstore.Endpoints.swift` — path + query + header + JSON body, status-tagged response, typed error
```swift
extension Petstore {

    /// Place an order.
    ///
    /// `POST /stores/{storeId}/orders`
    public struct PlaceOrderEndpoint: Endpoint {
        public typealias Server = Petstore.Server
        public typealias Body = Petstore.OrderRequest
        public typealias ErrorResponse = Petstore.Problem

        public static let definition: Definition<PlaceOrderEndpoint> = Definition(
            method: .post,
            path: "stores/\(path: \.storeId)/orders",
            parameters: [
                .query("dryRun", path: \.dryRun),
                .query("tags", path: \.tags)
            ],
            headers: [
                "Idempotency-Key": .field(path: \.idempotencyKey)
            ]
        )

        /// `201`: the created order. `202`: the order was queued and has no body.
        public enum Response: Decodable, Hashable, Sendable {
            case created(Petstore.Order)
            case accepted

            public init(from decoder: any Decoder) throws {
                guard let statusCode = decoder.userInfo[.httpStatusCode] as? Int else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Petstore response requires the HTTP status code; decode with `HTTPResponseJSONDecoder.decode(_:from:response:)`."
                    ))
                }
                switch statusCode {
                case 201:
                    self = .created(try decoder.singleValueContainer().decode(Petstore.Order.self))
                case 202:
                    self = .accepted
                default:
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unexpected status code \(statusCode)."
                    ))
                }
            }
        }

        public struct PathComponents: Sendable {
            public var storeId: Int64

            public init(storeId: Int64) {
                self.storeId = storeId
            }
        }

        public struct ParameterComponents: Sendable {
            /// Validate the order without placing it.
            public var dryRun: Bool?
            /// Sent as repeated `tags=` items.
            public var tags: [String]?

            public init(dryRun: Bool? = nil, tags: [String]? = nil) {
                self.dryRun = dryRun
                self.tags = tags
            }
        }

        public struct HeaderComponents: Sendable {
            public var idempotencyKey: String?

            public init(idempotencyKey: String? = nil) {
                self.idempotencyKey = idempotencyKey
            }
        }

        public let pathComponents: PathComponents
        public let parameterComponents: ParameterComponents
        public let headerComponents: HeaderComponents
        public let body: Body

        public init(
            pathComponents: PathComponents,
            parameterComponents: ParameterComponents = ParameterComponents(),
            headerComponents: HeaderComponents = HeaderComponents(),
            body: Body
        ) {
            self.pathComponents = pathComponents
            self.parameterComponents = parameterComponents
            self.headerComponents = headerComponents
            self.body = body
        }

        public static var bodyEncoder: JSONEncoder { Petstore.JSONCoding.makeEncoder() }
        public static var responseDecoder: HTTPResponseJSONDecoder {
            Petstore.JSONCoding.makeDecoder(isRawDataStatus: { $0 != 201 })
        }
        public static var errorDecoder: HTTPResponseJSONDecoder { Petstore.JSONCoding.makeDecoder() }
    }

    /// Logs user into the system.
    ///
    /// `GET /user/login`
    public struct LoginUserEndpoint: Endpoint {
        public typealias Server = Petstore.Server
        public typealias Response = String

        public static var auth: NoAuth { NoAuth() }

        public static let definition: Definition<LoginUserEndpoint> = Definition(
            method: .get,
            path: "user/login",
            parameters: [
                .query("username", path: \.username),
                .query("password", path: \.password)
            ]
        )

        public struct ParameterComponents: Sendable {
            public var username: String?
            public var password: String?

            public init(username: String? = nil, password: String? = nil) {
                self.username = username
                self.password = password
            }
        }

        public let parameterComponents: ParameterComponents

        public init(parameterComponents: ParameterComponents = ParameterComponents()) {
            self.parameterComponents = parameterComponents
        }
    }
}
```
Checks: `Definition.init` uses `T.Server()` (generated `public init() {}`); `\(path: \.storeId)` needs `Int64: PathRepresentable` (§6.3); `[String]?` needs §6.2; `String?` header needs §6.4; `Response: Sendable` holds; the union is `Decodable` only, which satisfies `where T.Response: Decodable`; `ErrorResponse: Decodable & Sendable` holds; `HTTPResponseJSONDecoder` conforms to `DecoderType`, so `ResponseDecoder`/`ErrorDecoder` infer.

### 7.3 `Petstore.Schemas.swift` — extensible enum, required-nullable, CodingKeys, discriminated and kind-dispatched unions
```swift
extension Petstore {

    /// A pet for sale in the pet store
    public struct Pet: Codable, Hashable, Sendable {
        public var id: Int64?
        public var name: String
        /// Required; `null` when the pet has no owner.
        public var ownerId: Int64?
        public var photoUrls: [String]
        public var tags: [Petstore.Tag]?
        /// pet status in the store
        public var status: Petstore.Pet.Status?
        public var shipDate: Date?
        private var _legacyName: String?
        @available(*, deprecated)
        public var legacyName: String? {
            get { _legacyName }
            set { _legacyName = newValue }
        }

        /// pet status in the store
        public struct Status: RawRepresentable, Codable, Hashable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public static let available = Status(rawValue: "available")
            public static let pending = Status(rawValue: "pending")
            public static let sold = Status(rawValue: "sold")

            public static let knownValues: [Status] = [.available, .pending, .sold]
        }

        public init(
            id: Int64? = nil,
            name: String,
            ownerId: Int64?,
            photoUrls: [String],
            tags: [Petstore.Tag]? = nil,
            status: Petstore.Pet.Status? = nil,
            shipDate: Date? = nil,
            legacyName: String? = nil
        ) {
            self.id = id
            self.name = name
            self.ownerId = ownerId
            self.photoUrls = photoUrls
            self.tags = tags
            self.status = status
            self.shipDate = shipDate
            self._legacyName = legacyName
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case ownerId = "owner_id"
            case photoUrls
            case tags
            case status
            case shipDate
            case legacyName = "legacy-name"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
            self.name = try container.decode(String.self, forKey: .name)
            self.ownerId = try container.decode(Int64?.self, forKey: .ownerId)
            self.photoUrls = try container.decode([String].self, forKey: .photoUrls)
            self.tags = try container.decodeIfPresent([Petstore.Tag].self, forKey: .tags)
            self.status = try container.decodeIfPresent(Petstore.Pet.Status.self, forKey: .status)
            self.shipDate = try container.decodeIfPresent(Date.self, forKey: .shipDate)
            self._legacyName = try container.decodeIfPresent(String.self, forKey: .legacyName)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(ownerId, forKey: .ownerId)
            try container.encode(photoUrls, forKey: .photoUrls)
            try container.encodeIfPresent(tags, forKey: .tags)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(shipDate, forKey: .shipDate)
            try container.encodeIfPresent(_legacyName, forKey: .legacyName)
        }
    }

    public enum Animal: Codable, Hashable, Sendable {
        case cat(Petstore.Cat)
        case dog(Petstore.Dog)

        private enum DiscriminatorKeys: String, CodingKey {
            case petType
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
            let discriminator = try container.decode(String.self, forKey: .petType)
            switch discriminator {
            case "cat":
                self = .cat(try Petstore.Cat(from: decoder))
            case "dog":
                self = .dog(try Petstore.Dog(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .petType, in: container, debugDescription: "Unknown petType '\(discriminator)'.")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            switch self {
            case .cat(let value):
                try value.encode(to: encoder)
            case .dog(let value):
                try value.encode(to: encoder)
            }
        }
    }

    public enum IdOrName: Codable, Hashable, Sendable {
        case int64(Int64)
        case string(String)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int64.self) {
                self = .int64(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                throw DecodingError.typeMismatch(Petstore.IdOrName.self, DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "No oneOf member of IdOrName matched."))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int64(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            }
        }
    }
}

extension Petstore.Pet.Status: ParameterRepresentable, PathRepresentable {}
```
Schema-level deprecation is always the doc line `/// - Important: Deprecated by the OpenAPI document.`, including component and inline schema types; it never emits a deprecation attribute on a type. Property, parameter and operation deprecation retains `@available(*, deprecated)`.

The explicit `init(from:)`/`encode(to:)` on `Pet` appears for required-nullable or deprecated properties. Deprecated fields retain their public names, types and initializer labels, with private backing storage used by generated initialization and coding so consumer builds do not warn. Parameter components use fileprivate backing storage for endpoint key paths. Structs without either requirement use synthesized Codable. The untagged `IdOrName` is allowed because its members are distinguishable by JSON kind (number vs string).

### 7.4 `Petstore.Support.swift` (each part emitted only when used; `JSONCoding` whenever a decoder/encoder override exists)
For APIs with embedded path parameters, Support also emits an internal wrapper (see §5.3):
```swift
extension Petstore {
    /// A path assembled from literal text and individually encoded parameter values.
    struct EncodedPath: PathRepresentable {
        let pathSafe: String
    }
}
```

```swift
extension Petstore {

    enum JSONCoding {
        static func makeDecoder(
            isRawDataStatus: @Sendable @escaping (_ statusCode: Int) -> Bool = { _ in false }
        ) -> HTTPResponseJSONDecoder {
            HTTPResponseJSONDecoder(isRawDataStatus: isRawDataStatus) { decoder in
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let string = try container.decode(String.self)
                    guard let date = RFC3339.parse(string) else {
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Expected an RFC 3339 date-time."
                        )
                    }
                    return date
                }
            }
        }

        static func makeEncoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(RFC3339.format(date))
            }
            return encoder
        }
    }

    /// RFC 3339 date-time parsing and formatting. Accepts fractional seconds and numeric offsets;
    /// formats in UTC with millisecond precision (`2024-01-05T10:00:00.123Z`).
    enum RFC3339 {
        static func parse(_ string: String) -> Date? { /* manual scan of yyyy-MM-ddTHH:mm:ss(.fff)?(Z|±HH:MM); days-from-civil arithmetic; no Calendar/Formatter */ }
        static func format(_ date: Date) -> String { /* civil-from-days arithmetic; zero-padded fields */ }
    }

    /// Any JSON value, used where the spec leaves a schema open.
    public indirect enum JSONValue: Codable, Hashable, Sendable {
        case null
        case bool(Bool)
        case integer(Int64)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])
        // custom Codable: integers are tried before doubles; objects encode with sorted keys
    }

    /// Boxes a recursive property so a struct can contain its own type.
    @propertyWrapper
    public indirect enum Indirect<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        case value(Value)
        // wrappedValue get/set; Codable passthrough via singleValueContainer;
        // KeyedDecodingContainer.decode(Indirect<T?>.Type, forKey:) treats a missing key as nil;
        // KeyedEncodingContainer.encode(Indirect<T?>, forKey:) omits nil
    }

    /// Sends a `Data` body unchanged.
    public struct RawBodyEncoder: EncoderType {
        public init() {}
        public static var contentType: String? { "application/octet-stream" }
        public func encode<T: Encodable>(_ value: T) throws -> Data {
            guard let data = value as? Data else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "RawBodyEncoder only encodes Data."))
            }
            return data
        }
    }
}
```
`JSONCoding` and `RFC3339` are always internal (referenced only from bodies). `JSONValue`, `Indirect` and `RawBodyEncoder` take the configured access level because they can appear in public signatures; they are documented as part of the generated API.

---

## 8. Testing strategy (macOS and Linux)

1. **Unit** (`EndpointsGeneratorCoreTests`): tokeniser/casing tables (`HTTPStatus`, `first-name`, `123abc`, keywords, empty → error, non-ASCII → error), rename application, reserved/collision errors, cycle detection and boxing, presence classification, allOf conflict detection, union admissibility, response/error outcome selection and case naming, media priority, URL normalisation (path-only insertion, rejections), doc-comment sanitisation, config decoding (version, unknown keys, exclusivity), SHA-256 vectors, `CodeWriter` invariants, RFC 3339 vectors (fractional, offsets, leap day, `Z`).
2. **Goldens**: fixtures under `Tests/EndpointsGeneratorCoreTests/Fixtures/<Stem>/` (`<Stem>.openapi.yaml`, optional private `<Stem>.configuration.json` fixture, `diagnostics.txt`); expected output committed as sources of `Tests/EndpointsGeneratedGoldenTests/<Stem>/`. The test generates in-process and compares bytes and diagnostics; `UPDATE_GOLDENS=1 swift test --filter Golden` rewrites. Because the goldens compile as a test target, `swift build --build-tests` proves they build against `Endpoints`; hand-written `@Test`s build requests and assert URL/query/headers/body bytes, and decode JSON fixtures (status unions incl. 204 → `.noContent`, required-nullable round trips, missing-vs-null for `@Indirect`, discriminators, kind unions, open enums with unknown values, dates with offsets).
   Corpus: `Boundaries` (Phase 2: ordered properties, required-nullable, `Int64`, encoded path values, status union, reserved-name and collision *error* variants), `Petstore` (petstore3 3.0.x → conversion), `Petstore31`, `KitchenSinkSchemas`, `Operations`, `Lenient` (same as Operations with `strict: false`), `Servers`, `Naming`.
3. **Determinism**: in-process double run; `ProcessDeterminismTests` runs the built `endpoints-generate` three times per fixture with `SWIFT_DETERMINISTIC_HASHING` removed and once with `=1`, in different working directories and with different `--spec` directory paths for the same stem, asserting identical bytes and diagnostics; `BannedAPITests` scans Core and CLI sources for §1 rule 4 tokens; a shuffle test reorders top-level `paths`/`components` keys and asserts identical output; goldens on both CI OSes.
4. **End-to-end**: `Examples/PetstoreClient` (plugin applied, two modules: `App` with the generated code and `public static let auth` extension, `Client` asserting `Petstore.Server.Auth.self == HeaderKeyAuth.self` and exercising a request through `TestTransport`-style mocking) with `swift test`; `Examples/RuntimeOnlyClient` (`traits: []`) with the checkout assertion on macOS.
5. **Runtime** (`Tests/EndpointsTests`): §6.1 (status/headers in userInfo, empty body → null, default `JSONDecoder` path unchanged, `EmptyCodable` from empty body), §6.2 semantics table, §6.3 conformances, §6.4 optional headers.

---

## 9. Owner decisions (each with recommendation)

1. **Default-on trait `OpenAPIGenerator`** so runtime-only consumers on SwiftPM ≥ 6.2 can opt out of fetching OpenAPIKit/Yams. Recommend **yes**: zero cost for plugin and Xcode users, adding it later would be the breaking move.
2. **Response hook** (`DecoderType.decode(_:from:response:)`, `HTTPResponseJSONDecoder`, userInfo keys, `EmptyCodable` accepting empty bodies). Recommend **yes**: additive, and it is what makes multi-status responses exact rather than guessed.
3. **`strict: true` default.** Recommend **yes**; the lenient mode remains one key away.
4. **Extensible enums by default** (`enums: "open"`). Recommend **yes**; exhaustive switching is available via `enums: "closed"` for specs the team controls.
5. **`int32`/`int64` → `Int32`/`Int64`, unformatted → `Int`.** Recommend **yes**; the alternative changes public types later.
6. **Optional-nullable collapses to `T?` permanently** (no tri-state type). Recommend **yes**; JSON Merge Patch users can hand-write the few endpoints that need explicit `null` on optional fields.
7. **Exact pins** (OpenAPIKit 6.4.0, Yams 6.2.2) can conflict for consumers who also depend on those packages — but only plugin users resolve them. Recommend **keep exact**; relax to `.upToNextMinor` only on a concrete report.
8. **Swift 6.1 floor** for all consumers (forced by tools-version/OpenAPIKit). Recommend **accept**.

---

## 10. Phased implementation plan

### Phase 1 — Runtime foundations (after the path-encoding prerequisite PR)
Scope: §6.1–6.4 in `Sources/Endpoints` with tests; `EmptyCodable` lenient decoding; no generator code. Also: manifest bump to tools 6.1 with the trait, dependency pins and empty generator targets (compiling stubs), CI image bump, `Examples/RuntimeOnlyClient` with the checkout assertion, and the `--disable-default-traits --product Endpoints` build.
Acceptance: `swift test` green on both OSes; runtime tests cover each §6 item including the semantics table; existing tests unchanged except where optional headers previously asserted a throw; `RuntimeOnlyClient` on macOS resolves without `OpenAPIKit`/`Yams` checkouts (or, if SwiftPM there is 6.1, the step is marked informational and the result recorded in the README); `.package(url:exact:traits:)` confirmed to compile.

### Phase 2 — Boundary spike: plugin → CLI → Core on the irreversible decisions
Scope: Loader (Yams, version sniff, conversion), Validator, minimal lowering and renderer sufficient for the `Boundaries` fixture: a spec with two operations and three schemas exercising ordered properties, a required-nullable property, an `Int64` id, an encoded path value (space, `%`, `/`, non-ASCII), a `200`+`204` status union, a typed error, public access with the `public static let auth` extension, plus two deliberately failing variants (reserved name `Date`, two operationIds colliding) whose diagnostics are golden-tested; `CodeWriter`; header/hash; CLI; `BuildToolPlugin` + `XcodeBuildToolPlugin`; `Examples/PetstoreClient` with two modules; ordering audit of every OpenAPIKit collection the lowering touches (documented in `Sources/EndpointsGeneratorCore/Lowering/ORDERING.md`).
Acceptance: `Boundaries` golden compiles and its request/decoding assertions pass on both OSes; `ProcessDeterminismTests` passes; invalidation matrix verified and recorded (clean build; unchanged rebuild doesn't rerun; spec edit; Swift config edit/add/remove (3N-2); second spec; spec removal leaves no stale outputs; generator source change reruns; case-insensitive stem clash errors); native Xcode project checklist completed manually and recorded; `swift test --package-path Examples/PetstoreClient` passes; unhandled-file warning behaviour recorded.

### Phase 3 — Schemas and naming
Scope: every row of §5.6 and §5.7, `renames`, `enums`, `@Indirect`, `JSONValue`, kind-dispatched unions, allOf conflict detection, doc comments, deprecated.
Acceptance: goldens `KitchenSinkSchemas`, `Petstore31`, `Naming` committed and compiling; decode round-trip tests for every presence class, discriminators, kind unions, recursion (missing vs null), open enums with unknown values; naming unit table complete; all expected diagnostics match.

### Phase 4 — Operations, parameters, bodies, responses
Scope: §5.2–5.5 fully; `strict`/lenient behaviour; include/exclude; media-type pinning; reason-phrase table.
Acceptance: goldens `Petstore` (full petstore3), `Operations`, `Lenient`; request assertions for repeated query items, omitted optional headers, form body bytes, multipart part names, raw body with pinned `Content-Type`; status-union decoding incl. `default`; README/Examples.md updated for array parameters and optional headers.

### Phase 5 — Servers, environments, auth, multi-spec UX
Scope: §5.8, §5.9, plugin behaviours for zero/multiple specs and namespace/stem clashes, security notes.
Acceptance: golden `Servers` with the three config variants and the error variants (relative URL, zero servers, URL with query); `PetstoreClient` gains a second spec showing two namespaces coexisting; operation-security note diagnostic golden-tested.

### Phase 6 — Hardening, docs, command plugin
Scope: `BannedAPITests`, shuffle test, performance check on a large real spec (target < 5 s), DocC article `Generating.md` (naming contract, presence policy, enum policy, trait opt-out, Xcode steps), README section, `EndpointsGenerateCommand` with byte-comparing `--check`, `Examples/PetstoreClientVendored`.
Acceptance: lint and shuffle tests green; docs reviewed; vendored example's `--check` passes in CI and fails when a golden byte is changed.

### Phase 7 — Release
Scope: `GeneratorVersion.current`, CHANGELOG (runtime additions, Swift 6.1 floor, trait), tag.
Acceptance: fresh clones of both Examples against the tag build and test on both OSes.

---

### Critical Files for Implementation
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Package.swift` — tools 6.1, trait, pins, generator targets in both `#if os(Linux)` branches
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/Endpoints/Endpoint.swift` — `DecoderType` hook, `EmptyCodable`, the protocol every generated endpoint satisfies
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/Endpoints/Endpoint+URLRequest.swift` — repeated parameters, optional headers, single-encoding path contract
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/Endpoints/Extensions/URLSession+Async.swift` (with `URLSession+Endpoints.swift`, `URLSession+Combine.swift`, `Definition+URLResponse.swift`) — pass the `HTTPURLResponse` into decoding
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/Endpoints/ParameterRepresentable.swift` and `PathTemplate.swift` — `MultiValueParameterRepresentable`, RawRepresentable defaults, `Int32`/`Int64`/`UUID`
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/.github/workflows/ci.yml` — `swift:6.1`, Examples steps, trait checks