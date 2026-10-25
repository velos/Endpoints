> Current configuration boundary: `<Stem>.endpoints.swift` is the only user-facing
> config. 3N-2 implementation and current local measurements are recorded at the
> end of this file, followed by owner-reported Linux and sandbox-on results.
> The latest review corrections and measurements are at the end. Linux,
> sandbox-on SwiftPM and native Xcode reruns of those corrections remain owner-run.
> Earlier sidecar measurements are historical probes. JSON is private CLI/test transport.

# OpenAPI generator foundation verification (54563a1)

Historical foundation record. The subsequent runtime-hooks phase is recorded in
[OpenAPIGenerator-RuntimeHooks-Verification.md](OpenAPIGenerator-RuntimeHooks-Verification.md).

Local toolchain: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 macOS,
SwiftPM's default `swiftbuild` engine. This record covers the foundation subset
in the task brief, not the later phases of the full design. These changes were committed as `54563a1`. At that boundary,
`Sources/Endpoints` and `Sources/EndpointsMocking` were unchanged.

## Implemented boundaries

- Tools 6.1 manifest, default-on `OpenAPIGenerator` trait, guarded Core parser
  dependencies, plugin product on both platform branches. Remote tags verified:
  OpenAPIKit **6.4.0** and Yams **6.2.2** both exist. Both are pinned exactly;
  OpenAPIKit's `ExternalLoading` trait is disabled.
- Source-marked YAML/JSON loading, OpenAPI 3.0 conversion and 3.1/3.2 decoding, validation, closed
  configuration, array-only IR, ASCII naming and explicit collision errors,
  deterministic rendering and SHA-256 headers, write-if-changed CLI.
- The requested schema/operation subset, plus server configuration variants;
  unsupported constructs follow strict/lenient policy. External references,
  invalid names/collisions, invalid configuration and servers remain hard errors.
- Both build-tool plugin entry points, multi-spec discovery, duplicate checks,
  explicit command inputs/outputs and cleanup of output directories for removed
  specifications. The generator executable is an implicit build-command input.
- Compiled source goldens for Boundaries (3.0), Petstore (3.1), SchemaEdges, and DateScopes;
  reserved-Date and colliding-operationId (including absent operationId) diagnostic goldens; process determinism
  and banned-API checks; two example packages.

The collection-by-collection audit is in
`Sources/EndpointsGeneratorCore/Lowering/ORDERING.md`.

## Commands and results

Successful local Swift builds/tests used `--disable-sandbox`, including examples.
A fresh-scratch PetstoreClient build was also attempted with sandboxing enabled;
Codex blocked manifest evaluation with `sandbox-exec: sandbox_apply: Operation not
permitted`, before the plugin could run. CI now uses sandboxing for every step;
there is no `--disable-sandbox` exception in the workflow. Where the
outer Codex sandbox denied Xcode's default Clang module cache, the commands used
these environment variables (no package setting was changed):

```sh
export CLANG_MODULE_CACHE_PATH=/tmp/endpoints-module-cache
export SWIFT_MODULECACHE_PATH=/tmp/endpoints-module-cache
```

| Check | Result |
| --- | --- |
| `swift build --disable-sandbox` | Pass |
| `swift build --disable-sandbox --target endpoints-generate` | Pass |
| `swift build --disable-sandbox --build-tests -Xswiftc -warnings-as-errors` | Pass; zero warnings, including all generated golden sources |
| `swift test --disable-sandbox` | Pass: 129 tests; runtime 74, mocking 20, Core 29, compiled goldens 6 |
| `swift build --disable-sandbox --disable-default-traits --product Endpoints` | Pass with the default engine and the native engine; Core/CLI compile without parser dependencies when selected |
| Trait-disabled CLI and plugin consumer | CLI exits 1 with the enable-trait error; a plugin consumer build surfaces the same source-formatted diagnostic |
| `swift build --disable-sandbox --package-path Examples/PetstoreClient --build-tests` | Pass |
| `swift test --disable-sandbox --package-path Examples/PetstoreClient` | Pass: 1 test in a second module, including public auth witness and request assertions |
| `swift build --disable-sandbox --package-path Examples/RuntimeOnlyClient --build-tests` | Pass |
| `swift test --disable-sandbox --package-path Examples/RuntimeOnlyClient` | Pass: 1 test |
| Fresh PetstoreClient build without `--disable-sandbox` | Blocked by Codex nested sandbox restriction during manifest evaluation; not a plugin sandbox qualification |
| RuntimeOnlyClient checkout assertion | Pass; `.build/checkouts` exists and is empty on Swift 6.4 |
| `git diff --check` | Pass |
| Native Xcode project | Not run here, as requested; follow-up checklist below |
| Linux Swift 6.1 | Owner reports 81 tests passing on the preceding revision; this final follow-up was verified locally on macOS |

`UPDATE_GOLDENS=1 swift test --disable-sandbox` rewrites the expected source and
error-diagnostic files. Run a normal test build afterwards to compile updated
sources. The final normal test run compares generated bytes to checked-in source
locations without rewriting them.

The process test invokes the built CLI three times, using independent input and
output directories, unset vs enabled `SWIFT_DETERMINISTIC_HASHING`, different
locales/timezones, `YAMS_DEFAULT_ENCODING=UTF8` vs `UTF16`, and `.yaml` vs `.yml` basenames. It compares all four files.
The writer test also verifies unchanged bytes retain modification times.

## Plugin invalidation observations

A separate temporary SwiftPM consumer exercised the actual plugin and CLI using
verbose builds. Command counts below count generator invocations, not compiler
invocations. Byte hashes and nanosecond modification times were compared.

| Change | Result |
| --- | --- |
| Clean build | One generator invocation, four generated files; compiled successfully |
| Unchanged rebuild | Zero generator invocations; bytes and mtimes unchanged |
| Spec edit | One invocation; all four headers changed |
| Historical config add, edit, remove (discovery since removed) | One invocation for each change; inputs/config hashes updated |
| Add second spec | One new invocation; eight outputs; both namespaces compiled |
| Remove second spec | Four remaining outputs; removed namespace's files absent |
| Case-insensitive stem clash | Build failed with duplicate-stem diagnostic (different extensions allow testing on case-insensitive volumes) |
| Duplicate namespace in historical configuration probe (discovery since removed) | Build failed with duplicate-namespace diagnostic |
| Generator version/source change | Executable rebuilt, one generator invocation; version header changed |
| Comment-only generator edit | Source recompiled, but generation did not rerun when executable bytes were unchanged |
| Remove final spec | No commands, zero generated files; expected no-spec warning; remaining hand-written source compiled |

Swift 6.4 emitted **no unhandled-file warning** for `.openapi.yaml`,
or `.openapi.json` inputs. Do not exclude these specifications from a
target: the plugin needs to discover them. Swift 6.1's behavior remains for CI to
observe. Swift 6.4's `swiftbuild` engine did emit stale-file cleanup warnings on
spec removal (old paths outside its newly allowed output roots); the files were
absent on disk and no longer included in compilation.

## Design clarifications and runtime boundary

- Approved determinism correction: every header uses the canonical label
  `<Stem>.openapi`, never the actual basename. Section 1 rule 6 and the matching
  generated example were updated. Changing directory or extension cannot affect
  output. Raw spec/config bytes still determine their hashes.
- Approved ordering correction: environment cases retain spec order and the
  first spec server is the default. Section 1 rule 2 no longer lists environment
  cases among sorted file-level declarations. The SchemaEdges golden has Zebra
  before Alpha and asserts both CaseIterable order and the default.
- The example dependencies keep `path: "../.."` and supply the explicit package
  name `Endpoints`, because a local path package's identity otherwise comes from
  this worktree's directory name.
- Build-mechanics correction to §2.2: on Swift 6.4 the native engine warns that
  `--product Endpoints` cannot select an automatic library, then builds default
  targets, including the CLI. Before the guard this failed on `import Yams`; the
  default `swiftbuild` engine passed. Core and the CLI now use
  `#if OpenAPIGenerator`, so both engines pass the unchanged CI command. When the
  trait is off, invoking the CLI exits 1 and asks the user to enable the trait;
  an actual plugin consumer probe confirmed that error appears as a build
  diagnostic. Enabled output and generated public API are unchanged.
- CoreTests depends on the internal executable target as well as Core, ensuring
  process tests always exercise a freshly built CLI. It is not an extra product.
- Support uses fresh `JSONDecoder`/`JSONEncoder` values, rather than the absent
  response-aware runtime decoder. No status unions, optional headers, array query
  parameters, or new parameter/path conformances are generated.
- Namespace-level array aliases with inline object items emit sibling item types
  (for example `Shapes` and `ShapesItem`); Swift cannot nest declarations in a
  typealias. These generated names participate in collision checks.
- Embedded path placeholders such as `/files/{fileId}.json` originally used a
  fileprivate computed raw String on PathComponents. After runtime fix
  velos/Endpoints#24 merged, this was replaced with an internal `EncodedPath`
  wrapper: literals retain separators and each parameter contributes `.pathSafe`.
  Full-segment placeholders still use the hand-written endpoint style directly.
  The post-merge regression checks cover embedded spaces, `/`, `?`, `#`, `%`,
  pre-escaped-looking values and Unicode; see the runtime-hooks verification record.
- Date support is derived from retained IR, so skipped date-valued constructs
  cannot emit an unused RFC 3339 helper. The date tests include the UTC and offset
  leap-second examples from [RFC 3339 sections 5.7–5.8](https://www.rfc-editor.org/rfc/rfc3339).
  The implementation checks the UTC month-end slot without an external leap
  table, and normalizes leap seconds to the following second in Foundation Date.
  Encoding rejects non-finite dates and rounded dates outside years 0000–9999
  with EncodingError rather than trapping during integer conversion.
- Empty error outcomes inherit the existing EmptyCodable default. The separate
  runtime branch owns lenient decoding of genuinely empty error bodies.

## Foundation review revisions

| Review item | Change and verification |
| --- | --- |
| 1. Namespace shadowing | Reserve the namespace in namespace, struct-nested and endpoint-nested type allocators, retaining rename hints. Mapping tests cover a component, a nested object and an inline request body. |
| 2. Auth documentation | One paragraph, contiguous indented extension and contiguous per-scheme list. The first document requirement selects the example (its AND keys are byte-sorted); otherwise the first sorted scheme does. Header key, bearer, basic, cookie, OAuth2/OpenID and session/query guidance reflect the actual scheme and configured access. Bearer regression and Petstore golden pass. |
| 3. Cycle complexity | ComponentGraph computes Tarjan SCCs once, traversing references in arrays and inline schemas without expanding targets. References use recursive-membership checks. The 20-level × 3-ref SharedDAG fixture generated in 34–101 ms locally, with a one-second test budget. Date traversal is memoized too. SCCs remain available for later boxing. |
| 4. Fallback identity | Absent operationId uses `GET /pets/{petId}`-style originals for diagnostics and rename lookup. `By` exists only in Swift name derivation. NoOperationId collision diagnostic golden and successful rename test pass. |
| 5. Decode/validation details | Wrap decoding errors with OpenAPI.Error(from:), recover the pointer and key mark, and append a quoted upstream description. Validation errors include their quoted reason. Tests assert `/info/version` at 4:3 and a response reference failure at 12:15. |
| 6. CI sandbox | Removed `--disable-sandbox` everywhere in CI. Local enabled attempt was blocked by Codex as described above. |
| 7. Maintainability | One statement per line, wrapped long lines and descriptive locals in lowering/rendering/config. AccessLevel and HTTPMethod enums; named Rename, ConfiguredEnvironment, FixedHeader and component/location values. Lowering chooses EndpointPath.template vs .computed; rendering only spells it. |
| 8. Layout | Initializer line threshold is 100 bytes including indentation; boundary tests cover 100 vs 101. Stored lets, coder overrides and open-enum static lets are grouped. Matching closed-enum raw values are omitted. All source goldens regenerated and compiled. |
| 9. Coder scope | Independently follow each endpoint body/success/error type through referenced and inline schemas for Date. Emit only the corresponding override. DateScopes covers aliases and arrays, all three Date payload kinds, and a plain endpoint in the same module; real body bytes and offset-date decoding pass. Date-free body requests inherit runtime JSON encoding, so the Petstore multi-key body test compares JSON semantics; Date body tests retain exact byte assertions. |
| 10. RFC helper | ASCII punctuation constants, descriptive civil-date/offset/era names, and arithmetic-step comments. Existing RFC vectors and behavior retained, including offset dates, leap-second normalization and encoding bounds. |

Smaller findings are also covered: marks use mapping keys (reserved Date is now
7:5); duplicate scans, rename/parameter identities and component lookups compare
UTF-8 bytes; content references carry their final response/requestBody/media
source pointers; explicit `properties: {}` is accepted; dependent-removal warnings
use the removed declaration's own pointer. The design status and details are
updated, and lint additionally bans `Date.now`, `.random(` and `getenv`.

Parser details discovered during the byte-matching checks:

- Compose and decode explicitly select UTF-8. Yams' default encoding can otherwise
  consult `YAMS_DEFAULT_ENCODING`; its Options initialization may still print an
  informational default-encoding message when that variable is set. The process
  test varies it and confirms identical generated files; stdout is not generated
  source. Decode uses Yams' normal string decoder because its merge-only resolver
  differs from compose's resolver (notably for numeric response-code keys).
- Pinned Yams 6.2.2 itself rejects canonically equivalent mapping keys during
  compose, before the generator duplicate scan can run. This upstream restriction
  remains; generator-level wire comparisons use bytes and never silently resolve
  a differently encoded reference or rename. No parser fork or dependency change
  was introduced.

## Second review revisions

- **A — Linux invalid-date error payload.** The generated date strategy now throws
  `EncodingError.invalidValue(date.timeIntervalSince1970, ...)`, never embedding
  the Date. The original generated payload failed the new regression six times
  before regeneration. Tests now explicitly catch and inspect the payload before
  describing the actual error, and cover NaN, both infinities, a huge finite value,
  and finite values outside the encoding bounds. They do not pass an invalid Date,
  a containing record, or an unchecked error to Swift Testing. RFC assertions use
  numeric intervals, formatted strings and boolean acceptance results; the other
  date-array assertion also compares intervals. The generated Support audit found
  no other Date description/interpolation in an error path: decoder errors contain
  a fixed string, and formatting runs only after the encoder's finite/range guard.
  This is local macOS proof plus source reasoning; the owner's Swift 6.1 Linux
  container rerun is still required and is not claimed here.
- **B — Readability.** Plugin statements/calls are expanded and wrapped; ASCII
  checks and case shifts use named constants and descriptive byte variables.
  The CLI uses a named Option value. Generator uses namespace, named input hashes,
  three joined header lines and a direct GeneratedFile array. Naming, URL checks,
  loader and diagnostics use descriptive locals/comparator arguments. The three
  requested test files follow the same formatter style. All B-listed files have
  no lines over 120 columns; SHA-256's standard notation is unchanged. Golden and
  determinism checks confirm that these mechanical changes preserve output.
- **C — Deprecation.** Deprecated properties retain their public name, type, mutable
  getter/setter and initializer label. Schemas use private backing storage and
  explicit Codable; encoding/decoding and initialization reference that storage.
  Parameter-component backing storage is fileprivate so the enclosing endpoint
  can form key paths without referencing deprecated public members. Colliding
  backing names produce a rename diagnostic. SchemaEdges now compiles deprecated
  path/query/header parameters and verifies their requests, plus required/optional
  deprecated-property JSON round trips. `--build-tests -Xswiftc -warnings-as-errors`
  passes with zero warnings across the package and goldens.
- **C — Hints and details.** Schema/operation/property hints preserve escaped wire
  identities and nested owners. Phase 3N-1 supersedes these original hint spellings
  with typed Swift syntax. Tests validate all categories and escaped keys; diagnostic
  goldens were regenerated. YAML parse errors append the quoted YamlError description.
- **C — Remaining cleanup.** Operation identity is computed once and passed into
  lowering. The namespace allocator is constructed once in lower(), including
  the configured server root. RFC guard continuations use four spaces. Bearer
  docs use `HeaderKeyAuth(key: token)` and the regression expects that form.

All four source goldens and all three diagnostic goldens match the final generator.
The canonical header label and spec-ordered Environment cases/default are retained.

## Final review follow-up

- Schema-level deprecation now emits only
  `/// - Important: Deprecated by the OpenAPI document.`, for all rendered schema
  kinds. Properties, parameters and operations retain their deprecation attributes.
  SchemaEdges marks LegacyRecord deprecated and references it from Container.legacy
  and GetLegacyEndpoint.Response. The original renderer failed the new fixture's
  warnings-as-errors build; the regenerated golden shows the doc marker and builds
  cleanly. Tests decode both live reference paths.
- One claimDeprecatedBackingStorage helper now serves schema fields and all three
  parameter locations, using Property.storageName throughout.
- Renderer and emitted Support encoder both explain why invalidValue carries seconds
  rather than Date. The reserved-name documentation covers deprecated backing fields;
  invalid-stem wording matches the review; diagnostic replacement calls are separate
  lines. Design schema/operation rows and §7.3 distinguish their deprecation policy.
- Final local root suite: 129 tests with warnings treated as errors, zero warnings.
  Both example packages also build and test with warnings treated as errors.
  Source/diagnostic goldens and process determinism pass; runtime sources are unchanged.

The owner separately reported all 81 tests passing in the Swift 6.1 Linux container
before this final doc-marker/helper/comment follow-up. That reported result is
recorded separately from local macOS verification; Linux was not rerun here.

## Remaining platform verification

Linux CI is configured for `swift:6.1` with the package and both example checks.
No local result here establishes Linux or remote CI success. The macOS no-fetch
assertion is intentionally separate from the Linux build: SwiftPM 6.1 may fetch
trait-disabled dependencies even though they are not built.

Manual checklist for a native `.xcodeproj` (not opening Package.swift in Xcode):

- Attach EndpointsGeneratorPlugin to the source target and include spec/config
  target inputs; keep them out of Copy Bundle Resources.
- Confirm all four outputs compile, including a public auth extension used from
  another module.
- Edit the spec and verify regeneration. Starting in 3N-2, also edit/add/remove the Swift config and verify regeneration.
- Confirm source-marked diagnostics appear in the issue navigator.
- Add/remove a second spec and exercise duplicate stem/namespace errors.

No unresolved implementation question remains for the requested slice. Linux,
native Xcode, and the separately owned runtime fixes remain distinct verification
boundaries.

## Phase 3N-1: naming v2 (uncommitted, 2026-10-25)

Implemented the approved `OpenAPIGenerator-Naming.md` §10 scope: the dependency-free
`EndpointsGeneratorConfig` product on both platforms, the full typed configuration
API, shared reference algorithm, structured identities, inventory/resolution/single
lowering, typed structured renames, private transport diagnostics, and spec naming extensions.
The Swift-file compiler, runner, transport, and cache belong to 3N-2.

### Identifier review and wire preservation

**Every identifier changed in the five existing source goldens: none.**

| Existing fixture | Identifier changes |
| --- | --- |
| Boundaries | None; only all four config-hash headers changed; the redundant owner_id rename is now removed, exercising default ownerId generation |
| Petstore | None |
| SchemaEdges | None |
| DateScopes | None |
| Operations | None |

All 20 existing generated file bodies (excluding the three header lines) were
byte-compared against a copy saved before implementation and are identical. This
also establishes that their CodingKeys, enum raw values, query parameter names,
and header names are byte-identical before and after. Diagnostic goldens now use
Swift rename hints and list both colliding identities. The additional `NamingConfigured` fixture exercises names absent from the
older corpus: snake case, screaming enum values, acronym/digit boundaries,
non-ASCII names repaired by renames, distinct located parameters, independent
inline names, integer enums, and both spec extensions. Compiled tests round-trip
its JSON and assert the exact enum raw values and HTTP request names; an additional
Core test compares wire bytes across all three declarative strategies.

### Implementation choices where the design left details open

- `ServerEnvironment` is a typed enum of the existing `local`, `development`,
  `staging`, and `production` cases; `.environments` defaults to `.production`.
  `OperationFilter` has stored `include`/`exclude` arrays. Any corresponding
  JSON vocabulary belongs only to the private transport.
- Acronym defaults are empty. Public default arguments inline `[]`; the internal
  default constant and algorithm/keyword/reserved helpers have package visibility.
  Core owns scope allocation and diagnostics.
- Identity equality/hashing compares UTF-8 bytes, preserving the existing rule
  that canonically equivalent Unicode wire strings are distinct. No hash-table
  traversal determines output order. Inventory request IDs are unique targets.
- A digit followed by uppercase then lowercase starts a new token before the
  capital. This preserves `HTTP2Status`, `UTF8String` and `v2Beta` while keeping
  `2FA` one token. The executable, rule text and pseudocode use the same condition.
- The expanded table governs the wholly non-ASCII `.verbatim` case: it has no
  candidate, rather than inventing an underscore-only name. ASCII punctuation
  still maps one scalar to one underscore (`---` becomes `___`).
- `NameContext` offers both an initializer that computes spelling candidates and
  a memberwise initializer for the documented fields. Core prepares integer enum
  candidates (`value42`/`valueMinus1`) explicitly, preserving the actual decimal
  wire name and distinguishing integer enums from numeric string enums.
- Inline defaults come from their wire origin, independently of member renames.
  Array-item identities nest `.items(of:)`; status-union payloads retain their
  `.response`/`.errorResponse` status identities and default to `Option<N>`.
  Composite schema support is unchanged. Status-union payloads retain their actual
  `.response`/`.errorResponse` identities; no unused union-member case is public.
- The private fixture serialization currently encodes the remaining inline origins as `{"items": <type>}`,
  `{"parameter": <wire>, "location": <location>, "operation": <operation>}`,
  `{"body": <operation>}`, `{"response": <operation>, "status": <status>}`,
  and `{"errorResponse": <operation>, "status": <status>}`.
- Route aliases normalize recursively, including located parameters and inline
  owners. Supplying both route and ID aliases for one target is ambiguous.
  Unused renames warn regardless of `strict`. Operation rename values exclude
  `Endpoint`; namespace reservation applies to the emitted suffixed name.
- Naming diagnostics provide copyable Swift hints. The plugin uses defaults;
  Swift config evaluation starts in 3N-2. JSON is private CLI/test transport only.

### Local verification

Apple Swift 6.4, arm64 macOS, default Swift Build engine; all local SwiftPM
commands use `--disable-sandbox` and `-Xswiftc -warnings-as-errors`.

- Full `swift test`: passes, including all six compiled source goldens, the
  expanded reference table, request-order shuffle, rename/extension diagnostics,
  byte-exact identities, and cross-process determinism. Exactly two known issues
  remain: optional headers and empty-body `EmptyCodable` error decoding.
- `swift test --package-path Examples/PetstoreClient`: passes (2 tests).
- `swift test --package-path Examples/RuntimeOnlyClient`: passes (1 test).
- `swift build --disable-default-traits --product Endpoints`: passes.
- `git diff --check`: passes.

Linux `swift:6.1` execution is owner-run; it was not run locally. No Foundation or
platform module is imported by the new config library. No config-program process
spawning or Swift-file execution has been added.


### 3N-1 revision: Swift config only (2026-10-25)

- Removed JSON discovery and configuration inputs from both plugin entry points.
  The only planned user config is `<Stem>.endpoints.swift`, starting in 3N-2.
  Defaults are used until then. Naming diagnostics now show only Swift rename hints.
- Renamed the CLI transport flag to `--configuration-json`, omitted from public
  usage, README and DocC. Core retains its private reader and pointer diagnostics;
  there is no vocabulary compatibility promise or legacy-map migration diagnostic.
- Core generation tests now construct `EndpointsConfiguration` in process where
  practical. A direct adapter retains custom closures and uses the same semantic
  validation as the transport reader. Rename dictionaries are sorted by structured
  identity before resolution; diagnostics and output do not depend on traversal order.
  In-process calls may supply authored source bytes for the header fingerprint;
  without source bytes the fingerprint is `none` (not a hash of closure identity).
- Renamed the configured naming fixture to `NamingConfigured` and fixture transport
  files to `<Stem>.configuration.json`. Strategy/rename and exact-wire coverage is
  retained. All 20 existing generated file bodies remain byte-identical to the saved
  pre-3N-1 snapshot; none of their identifiers or wire values changed.
- Removed PetstoreClient's JSON file. Its auth witness is temporarily internal and
  its tests use `@testable import`; a 3N-2 TODO restores public access through a Swift
  config and an ordinary second-module import. This keeps the example exercising
  the real plugin, requests, authentication and decoding without using private CLI
  transport as an example interface.

Local verification on Apple Swift 6.4 / macOS, with `--disable-sandbox` and
`-Xswiftc -warnings-as-errors`: all 189 package tests pass, exactly two known issues
remain (optional headers and empty-body `EmptyCodable`); both examples pass (2 and
1 tests); the runtime builds with the generator trait disabled. Zero compiler or
build warnings. A separate temporary Petstore consumer also passes with deliberately
malformed `Petstore.endpoints.json` beside its spec, excluded from SwiftPM inputs:
the plugin ignores it, whereas the former direct filesystem discovery would have
read it. Cross-process determinism and private-flag fixture tests pass in the full
suite. `git diff --check` passes. Linux `swift:6.1` execution remains owner-run.


### 3N-1 review revisions (2026-10-25)

1. **Unsupported parameters.** Lowering checks the shared supported-location mapping
   before schema or name resolution. Cookie/querystring locations return nil rather
   than borrowing query identity. Regression tests cover strict errors and lenient
   warnings, with and without a same-named query and with an inline cookie enum.
2. **Public surface.** Algorithm/ASCII helpers, `NameError`, acronym defaults, strategy
   dispatch, target role helpers and the prepared-candidate initializer are package-only.
   Core no longer re-exports `Naming`/`NameError`. The ordinary context initializer and
   context spelling helpers remain deliberate public helpers. 3N-2 must pass the same
   `-package-name EndpointsConfigProgram` to both swiftc steps; the design commands now
   include that flag. No config-program execution was added.
3. **Developer documentation.** All public source declarations have doc comments,
   including candidate nil/empty rules, enum styles, environments, glob semantics,
   acronym validation, rename precedence and byte-exact identities. `NameTarget.owner`
   returns the target itself for `.type`, as documented. Removed the unused
   `InlineOrigin.unionMember` API and its private encoding; status-union payloads keep
   `.response`/`.errorResponse` identities and their `Option<N>` default candidates.
4. **Digit boundary.** A digit splits before an uppercase letter only when followed
   by lowercase. The algorithm, prose, pseudocode and table agree; precision rows
   include `_2fa`, `oAuth2Token`/`OAuth2Token`, and `v2Beta`/`V2Beta`.
5. **Collision diagnostics.** Nested type allocators describe originals with Swift
   identities, never the private JSON representation. An exact diagnostic test pins
   the `tags`/`tagsItem` collision and its failing property pointer.
6. **Invalid-name diagnostics.** Library messages contain no rename suggestion.
   Core suggests a rename for strategy failures; invalid explicit values are labelled
   `Invalid rename value`. Exact messages are asserted through typed and private
   transport entry points, without doubled hints.
7. **Shared walk decisions.** `OperationInputs.swift` owns media selection, response
   partitions/ignored statuses, payload identities/default numbering, HEAD/204 skips,
   and supported parameter locations. Both inventory and lowering call these helpers.
8. **Precision/default tests.** Restored the deleted precision cases, including `_`
   rejection, type keywords and reserved `init`. Every declarative default is checked
   for both initializer forms, with all six strategies exercised through `name(for:)`.
   Table contexts use real environment, header, query and path roles.

Additional cleanup: Boundaries has no owner_id rename and now proves default
`ownerId` generation. Core stores one `EndpointsConfiguration` value; other settings
are projections, with separate diagnostic-location metadata. Allocator failure
pointers use `NameTarget` rather than matching name/hint strings. Unrelated formatter
reflows in IR and both lowering files were restored to their original spelling.
Semantic diagnostic advice uses Swift labels. The private JSON path reuses its
composed source rather than composing YAML twice.

An inline-object property's `x-swift-name` supplies the naming input for **both**
the property and its independently resolved inline type. For example, `wire_key`
with `x-swift-name: better_key` defaults to property `betterKey` and type `BetterKey`;
a property rename alone does not rename that type. Existing integration coverage
exercises this shared extension behavior.

Verification on Apple Swift 6.4/macOS, using `--disable-sandbox` and warnings-as-errors:
all 194 package tests pass (including 55 naming table rows); both examples pass (2
and 1 tests); the runtime builds with the generator trait disabled. Exactly two
known issues remain: optional headers and empty-body `EmptyCodable`. Final build/test
logs contain no compiler/build warnings. The cookie, nested collision and hint tests
failed against the pre-fix code before the repair. A separate temporary compilation
of the former digit rule reproduces `_2Fa`; the repaired reference table asserts
`_2fa`. A compiler-generated public symbol graph contains only the intended 14
public types and no undocumented source declarations or package helper leaks.
All 20 existing golden bodies remain byte-identical to the saved pre-3N-1 snapshot,
including wire values; only Boundaries' config fingerprint changed after removing
the redundant rename. Cross-process determinism and `git diff --check` pass.
Linux `swift:6.1` passed the owner’s preceding review run (136 tests, two known issues);
this revision's Linux execution remains owner-run and was not repeated locally.


### 3N-1 second review revisions (2026-10-25)

- Restored `public` to the keyword set after an overbroad access-modifier edit
  changed that string literal to a duplicate `package`. Added property/enum/type
  table rows and an independent frozen-set assertion covering every keyword.
  The supplied `probe3/K.openapi.yaml` generates escaped `public` members and enum
  constants, and its four generated files type-check with warnings-as-errors.
- Nil strategies now report `The naming strategy returned no name` when the
  naming input has tokens. Tokenless inputs retain the `no ASCII identifier`
  explanation. Typed generation tests pin both exact messages and source pointers.
- Removed dead `suggested:` and `owner:` arguments from lowering and parameter
  type lowering. Deleted the pass-through payload helper and call `type` directly.
  Inventory alone chooses candidates; lowering uses resolved identities.
- Renames sort by their UTF-8 Swift hint spelling. Removed the JSON emitters used
  only for sorting; the remaining hint test independently pins Swift escaping.
  The private JSON reader remains unchanged as a transport boundary.
- Both inventory and lowering call `jsonRequestBody`, which requires a required
  body, selected JSON media and a schema. Typed tests cover JSON and vendor JSON,
  optional bodies, multipart and form bodies. Renames targeting skipped bodies now
  warn as unused, while supported bodies emit their renamed types.
- Namespace diagnostics use the complete requested Swift advice. Server targets
  are bound once, and server naming failures no longer produce a misleading
  missing-URL follow-up. Exact diagnostics are covered at the generator boundary.
- Simplified the `user_IDs` table row. The public configuration type doc describes
  the value declared by `<Stem>.endpoints.swift`; the public context initializer
  explicitly treats numeric input as strings (`"5"` becomes `_5`), unlike prepared
  integer enum contexts. A public-initializer test asserts this distinction.

All new regression checks failed on the preceding implementation before fixes.
Final local verification: Apple Swift 6.4/macOS, `--disable-sandbox` and
`-Xswiftc -warnings-as-errors`; 199 package tests pass, including 58 naming-table
rows, with exactly the two known issues (optional headers and empty-body
`EmptyCodable`). Both examples pass (2 and 1 tests), and the runtime builds with
its generator trait disabled. No compiler/build warnings. All 20 existing golden
bodies remain byte-identical to the saved baseline, including wire spellings;
no golden regeneration was needed. Cross-process determinism and
`git diff --check` pass. Linux `swift:6.1` passed the owner’s preceding revision
(141 tests, two known issues); this revision was not rerun on Linux locally.


### 3N-2 Swift config program (2026-10-25, uncommitted)

Implemented from 88cff79. Only `<Stem>.endpoints.swift` is discovered. It remains
an ordinary target source, starts with the version-1 header and declares the
stem-derived global configuration constant. Both plugin APIs obtain `swiftc`
through `context.tool(named:)` and pass the Swift file as a build input. SwiftPM
checks the configuration-library dependency. Native Xcode skips that check because
its plugin dependency metadata omits package products; the target compiler
diagnoses a missing import instead (see the qualification follow-up below). The CLI fallback is Darwin `xcrun --find`
then PATH; Darwin compilations explicitly select the macOS SDK through `xcrun`,
never SDKROOT. The DSL and config program both use Swift 6, `-Onone`,
`-package-name EndpointsConfigProgram`. The DSL-library compile remains strict;
user-file warnings are forwarded without failing generation under the subsequent
owner decision recorded below. No public DSL types
or members were added; strategy-kind metadata is package-only.

The byte lexer checks comments (including nested block comments), ordinary,
multiline and raw strings, and executable interpolation. It rejects imports,
conditional compilation, other directives/literals, underscored attributes and
the listed nondeterministic identifiers before launching anything. Added `Clock`, `Task`, `async` and `await` to the identifier ban, plus
`@unchecked` conformances: concurrency APIs are implicitly available even without
an explicit import. A real CLI probe accepted a Task.detached closure racing an
unchecked shared object before this repair; it is now rejected before compiling.
The lexical regression cases also failed before the repair. A second real CLI
probe called the underscored standard-library OS-version hook without imports.
The lexer now rejects underscored implementation identifiers, except the `_`
placeholder; helper declarations must use ordinary names. That case also failed
before the repair. A third real CLI probe used String.withCString and inferred pointer types to
produce different identifier bytes on two cached executions. The lexer also
rejects unmanaged/pointer/address APIs, pointer-lending CString/UTF8/contiguous/
varargs helpers and Mirror. These additional source restrictions close measured
gaps in the original ban list; the public DSL API is unchanged. Comments/whitespace between `@` and an underscored attribute
are also checked. Regression cases for that gap failed before repair. The
compiler import-list check is a second layer. Entry diagnostics use lexer token
positions, including when comments mention the symbol; that regression also
failed before repair. Compiler diagnostics retain the original user path/text.
Naming diagnostics use the design's quoted-wire-name line heuristic. A bad
route rename is tested end to end at its Swift line; structural JSON method and
location labels are excluded from the wire-string search.

Core collects one inventory, evaluates one batch using two separate program
executions with matching responses, filters the existing inventory and its diagnostics against the returned settings, then resolves and
lowers once. Excluded operations do not run their closures. The private
Foundation-free transport returns declarative JSON and ordered candidates through
a UTF-8 file protocol with escaped fields, counts, IDs, trailer and DSL/transport/
protocol fingerprint. User stdout is captured separately. Embedded payloads are
regenerated from the authoritative DSL and transport sources; the equality test
and UPDATE_EMBEDDED path guard drift. The new compiled `Naming` golden uses a
real Swift config with custom strategies, renames and acronyms, and matches the
corresponding typed configuration byte for byte. `NamingErrors` pins lexical
errors. All 24 pre-existing generated golden files remain unchanged from HEAD;
there are no wire-name changes.

`ConfigProcessRunner` uses Foundation.Process, separate per-execution FileHandles,
no pipes, null stdin, fixed program arguments and exactly
`SWIFT_DETERMINISTIC_HASHING=1` in the program environment. Compiler/SDK probes
inherit their environment. A termination handler plus bounded semaphore wait
avoids `waitUntilExit()`, kills on timeout, and bounds the final notification wait.
Failures report exit/signal/timeout and a bounded stderr tail. The 50-iteration
`processRunnerDoesNotHangOnLinux` initially passed locally on macOS, and the owner
has since reported it passing on Linux `swift:6.1`. Foundation.Process stays;
no posix_spawn replacement is needed. Additional tests cover null stdin, the exact
child environment, argv, timeout, exit status, signals and bounded stderr.

Cache entries use full length-prefixed SHA-256 keys over all specified sources,
entry/stem, flags and toolchain/SDK/generator identities. A compile lock also
protects the shared module cache. Atomic publication follows executable integrity
checks; intermediate files are discarded. Immutable entries have separate usage
metadata and shared execution leases. Eviction requires an exclusive nonblocking
lease. Restored, truncated, concurrent and abandoned-work cases are tested.
Module-cache identity includes its physical root, compiler, SDK, DSL/transport
fingerprint and compile settings, so relocation or payload/toolchain changes reset
it on the next use.

**Recorded implementation decisions:** cache paths in the key are normalized so
a restored executable can hit in a new scratch directory. The selected compiler
symlink is preserved for execution (resolving `swiftc` to `swift-frontend` broke
the initial probe). The transport uses narrow, file-private fixed-arity C ABI
stdio declarations on the supported 64-bit hosts, avoiding a platform-module
import and its multi-megabyte cache. Linker dead-code/symbol removal preserves
`-Onone`. The original unconditional ten-minute cache grace period retained
3.19 MB after ten edits, missing the design's 2 MB acceptance target. The grace
period now yields to a 2 MB budget, while the two newest entries and active leases
always remain protected; large programs/active leases may exceed that budget.
This internal retention adjustment is reflected in §5.10.

Local qualification: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 macOS,
default Swift Build engine. Every local SwiftPM command used `--disable-sandbox`.
218 package tests pass (19 new program tests), exactly two known issues remain:
optional headers and empty-body `EmptyCodable`. Both examples pass (2 and 1 tests);
PetstoreClient now uses a Swift config, public access, a custom strategy and an
ordinary second-module import. The config type-checks as a consumer-module source
in Swift 5, Swift 6 and Swift 6/MainActor default isolation. The latter flag is
unavailable on Swift 6.1, so that variant is compiled on the current macOS job.
The runtime builds with its generator trait disabled. No compiler/build warnings.

Measured with the actual Foundation-free transport and restricted environment:

| Measurement | Local result |
| --- | --- |
| Fresh-cache Naming CLI, complete wall time including compiler/SDK probes | 1.036 s |
| Same CLI cache hit, complete wall time | 0.213 s |
| Ten consecutive authored config edits, complete CLI wall time each | 0.973–1.089 s |
| Cache after initial compilation plus ten edits | 1,894,239 logical bytes; 1,920 KiB allocated; seven retained entries |
| Full-suite instrumented cold compile / config execution | 1.011 s / 0.130 s |
| Full-suite instrumented hit compile / execution | 0 s / 0.0040 s |
| Petstore unchanged build | SwiftPM 0.30 s; 0.95 s wall; same executable and usage timestamps |
| Petstore spec-only edit | SwiftPM 0.84 s; 1.50 s wall; same executable entry |
| Petstore config edit | SwiftPM 1.68 s; 2.41 s wall; new executable entry |
| Petstore restored authored files | SwiftPM 0.81 s; 1.50 s wall; cached original entry |
| Final Petstore no-change test run | SwiftPM 0.29 s; 1.03 s wall; usage metadata unchanged (program not evaluated) |

The edit probes restored the exact original bytes and rebuilt afterwards. These
are local measurements, **not CI timing or sandbox proof**. Representative logs
are in `/private/tmp/3n2-finished-suite.log`, `3n2-plugin-measurements.json`,
`3n2-plugin-nochange.json`, and
`3n2-release-measurement-n6s0qc7m/measurements.json`.

CI now runs the Linux 6.1 launcher regression separately with a job-step timeout,
the complete suite, and both examples with sandboxing enabled. macOS includes
latest Xcode and macos-15/Xcode 16.4 (Swift 6.1); the selected installation is in
the [official macos-15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
CI and native Xcode have not been run here. Xcode Cloud, custom toolchains and
cross-compilation remain unqualified as recorded in the design.

**Owner-run checks (from the repository root; no `--disable-sandbox`):**

1. In Linux `swift:6.1`, use a fresh scratch directory (do not reuse a macOS
   `.build`). Build first so the external hang deadline covers only execution:

   ```sh
   swift build --scratch-path /tmp/endpoints-3n2-linux --build-tests -Xswiftc -warnings-as-errors
   timeout 120 swift test --scratch-path /tmp/endpoints-3n2-linux --skip-build --filter processRunnerDoesNotHangOnLinux
   swift test --scratch-path /tmp/endpoints-3n2-linux --skip-build
   swift test --package-path Examples/PetstoreClient --scratch-path /tmp/petstore-3n2-linux -Xswiftc -warnings-as-errors
   swift test --package-path Examples/RuntimeOnlyClient --scratch-path /tmp/runtime-3n2-linux -Xswiftc -warnings-as-errors
   ```

2. On macOS, test a fresh sandbox-on example build, on the current Xcode and
   Xcode 16.4 (CI covers both). A fresh path forces the config compile/run to occur:

   ```sh
   petstore_sandbox_build="$(mktemp -d)"
   swift test --package-path Examples/PetstoreClient --scratch-path "$petstore_sandbox_build" -Xswiftc -warnings-as-errors
   runtime_sandbox_build="$(mktemp -d)"
   swift test --package-path Examples/RuntimeOnlyClient --scratch-path "$runtime_sandbox_build" -Xswiftc -warnings-as-errors
   ```

3. Native **`.xcodeproj`**, macOS target and iOS simulator target: link Endpoints
   and EndpointsGeneratorConfig, attach EndpointsGeneratorPlugin, include the
   specification and Swift config as target inputs, keep the config in Compile
   Sources and remove the spec from Copy Bundle Resources. Build both with
   `ENABLE_USER_SCRIPT_SANDBOXING=YES`; confirm the sandbox wrapper in the log.
   An iOS build must compile the config program against the host macOS SDK.
   Check a no-change rebuild, a config edit, a compiler type error, and a lexical
   violation (`#filePath`) at its authored file/line in the issue navigator;
   restore the config and rebuild. Use the actual project/scheme names:

   ```sh
   xcodebuild -project Consumer.xcodeproj -scheme MacConsumer -destination 'platform=macOS' ENABLE_USER_SCRIPT_SANDBOXING=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Consumer.xcodeproj -scheme IOSConsumer -destination 'generic/platform=iOS Simulator' ENABLE_USER_SCRIPT_SANDBOXING=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES CODE_SIGNING_ALLOWED=NO build
   ```

   These are now the actual project/scheme names in the owner's native consumer
   (see the qualification follow-up below). No native project was created, edited
   or built here. This checklist remains the 3N-2 qualification gate.


### 3N-2 owner qualification follow-up (2026-10-25)

**Owner-reported results, distinct from local validation:**

- Linux `swift:6.1`: the 50-iteration `processRunnerDoesNotHangOnLinux` passes,
  so Foundation.Process remains the launcher. Both examples pass on Linux.
- Fresh sandbox-on macOS builds of both examples pass. A fresh Petstore build
  takes **13.9 s**. RuntimeOnlyClient fetches no parser checkouts.
- Native Xcode 27.1 with `ENABLE_USER_SCRIPT_SANDBOXING=YES`: the macOS target
  initially failed in the plugin's dependency check, despite linking both
  Endpoints and EndpointsGeneratorConfig. The Linux suite also exposed a flawed
  shell-based signal test. Neither complete Linux-suite success nor native
  Xcode success is claimed for the revised code until the owner reruns them.

**Native Xcode correction.** The owner's `project.yml` and `mac1.log` confirm the
package products are linked and the plugin rejects the correctly configured
`MacConsumer`. `XcodeTarget.dependencies` does not supply these package products.
The Xcode entry point now passes unavailable dependency metadata, skipping only
that check; SwiftPM retains its actionable missing-product error. Xcode's target
compiler reports a missing module when the product really is absent. The source
membership check and explicit Swift config build input remain in both APIs.
The native project under `scratchpad/native/` was read only, never modified;
`xcodebuild` was not run here.

**Signal-test correction; launcher unchanged.** Swift 6.1
[corelibs Foundation Process](https://github.com/swiftlang/swift-corelibs-foundation/blob/swift-6.1-RELEASE/Sources/Foundation/Process.swift#L747-L762)
correctly distinguishes `WIFSIGNALED` from normal exit and reports `WTERMSIG`.
Its spawn attributes do not reset the caller's signal mask. Linux dispatch
[workers](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/swift-6.1-RELEASE/src/queue.c#L6214-L6217)
[block SIGTERM](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/swift-6.1-RELEASE/src/init.c#L90-L110).
Consequently, a shell can inherit blocked SIGTERM, queue its self-signal and
exit normally. A controlled local POSIX probe reproduced the test's weakness:
`/bin/sh -c 'kill -TERM $$'` died by signal 15 with SIGTERM unblocked, but exited
0 with SIGTERM blocked. This mechanism is consistent with the owner's Linux
failure; the original Linux child's mask was not captured directly.

`timeoutExitSignalAndBoundedStderr` now compiles a tiny Swift helper using the
host compiler and macOS SDK selection already used by the config program.
It restores SIGTERM's default disposition, explicitly blocks then unblocks it
and signals its own PID. Reaching the following `exit` is a failure. Separate
helper modes exit normally with 15 and 143; both must remain normal exits,
preventing numeric heuristics from masking a broken signal classification.
The runner still uses `.uncaughtSignal`, with no inferred signal status and no
unsupported Linux limitation asserted. The existing timeout and bounded-stderr
checks remain, as does the unchanged 50-iteration hang regression.

**Local validation after the corrections:** macOS, always `--disable-sandbox`
and `-Xswiftc -warnings-as-errors`: all 218 package tests pass with exactly two
known issues (optional headers and empty-body `EmptyCodable`). Both examples
pass (Petstore: 2 tests; RuntimeOnly: 1). The focused launcher suite passes all
3 tests in 0.548 s, including the compiled signal helper; the full run passes
all 19 config-program tests in 3.668 s. No build/compiler warnings, and
`git diff --check` passes. Logs: `/private/tmp/3n2-owner-fixes-runner.log`,
`3n2-owner-fixes-suite.log`, `3n2-owner-fixes-petstore.log` and
`3n2-owner-fixes-runtime.log`. These are local unsandboxed results; neither
Linux nor native Xcode was run here.

**Rerun after these corrections:** in Linux `swift:6.1`, rebuild and run
`swift test -Xswiftc -warnings-as-errors --filter timeoutExitSignalAndBoundedStderr`,
then the full suite (exactly the two known issues). Rebuild the owner's
`Consumer.xcodeproj`, schemes `MacConsumer` and `IOSConsumer`, with user-script
sandboxing enabled, following the native checklist above. Sandbox-on SwiftPM
example checks already passed on the owner's machine; they are not evidence of
native Xcode success.


### 3N-2 REVISE corrections (2026-10-25, uncommitted)

All six required items and the accompanying nits are implemented. This entry
supersedes the original warnings policy and native-Xcode no-change assumption.
The supplied `scratchpad/review/` probes and native logs were read only.

1. **Compiler diagnostics.** Each of the three checked compiler steps parses
   stderr into blocks starting at `path:line:column: severity:`. Authored config
   blocks retain their original headers, excerpts and continuation lines.
   Generated main/transport blocks are suppressed; their errors become one
   entry error at the lexical declaration position, using the exact same wording
   as missing/duplicate lexical entries. The source-excerpt substring heuristic
   is gone. An exit/signal/timeout error is emitted once only when no located
   error is available. Located type errors, an unclosed parenthesis, `= 42` and
   a private entry are tested end to end. These tests reproduced the old failures
   before repair; deleted temporary paths and redundant status errors are absent.
2. **Warnings.** The user-file compile and import check omit warnings-as-errors;
   the authoritative DSL-library compile retains it. Successful warnings are
   forwarded verbatim. Immutable `diagnostics.json` entry metadata retains warning
   blocks and normalizes only their header paths for replay at the current config
   location. A real deprecated helper succeeds and emits the same warning on a
   cold compile, a cache hit and a relocated config/cache hit. The app target
   still applies its own compiler warning policy to this ordinary source file.
3. **Regexes.** Code-state slashes follow the requested conservative rule:
   reject non-comment `/` followed by a non-whitespace byte, except `/=` followed
   by whitespace. Spaced division remains allowed. An invalid regex-looking line
   is skipped after the error so its quotes or comment-looking bytes cannot hide
   subsequent code. `/"/`, `/x\//` and `/[/*]/` are regression cases; NamingErrors
   includes the located regex error.
4. **Key paths.** Every code-state `\` produces the key-path diagnostic. Strings
   and comments remain opaque. The computed-key-path hash escape is therefore
   rejected before compilation; NamingErrors and lexer tests pin its location.
5. **Address and identity families.** The gate rejects the requested identity,
   layout, reflection, hashing and argv identifier tokens, unsafe-prefix families,
   `hash(into:` (including escaped labels), class/actor declarations (including escaped/Unicode names) and `===`/`!==`,
   while retaining all previous bans. Tests cover every requested token/operator,
   literal/comment immunity, and allowed structs, enums, functions, closures and
   spaced arithmetic. The lexical gate blocks cheap, known channels before
   compiling. The dual run added in the second-review correction below is the
   runtime guard for user configs. CI's macOS+Linux `--check` covers only this
   repository's fixtures, not users' configs. It does not prove arbitrary Swift
   code deterministic or detect stable cross-host capacity/Unicode differences. The design records the
   legitimate uses excluded by the bans: regexes, key-path mapping conveniences,
   reference-type helpers, manual hashing and some benign helper names matching
   the pre-existing substring rules. Ordinary String/Array/Dictionary/Set
   operations and value-type naming helpers remain available.
6. **Native Xcode rebuilds and identity probes.** Xcode re-applies the plugin and
   changes a time-based script GUID in llbuild's command key. A plugin cannot
   preserve that command key. `review/native/b1.log`, `b2.log` and `b3.log` all
   succeed and execute the phase with different `Script-…sh` paths:
   `11CE3C3C308EA21400A3E20B`, `11B53B0F308EA22400C22BFE`, and
   `118665DE308EA2260016BDA7`. The spike already showed the same behavior:
   `ios1.log` executes `1132AFA6308E65FB00424DFB`, while `ios2.log` executes
   `118377E3308E66A600A62D78`. The earlier “no-change Xcode build skips generation”
   claim is corrected. SwiftPM must still skip unchanged commands; native Xcode
   runs the cached command (about 0.2 s observed by the reviewer) and preserves
   unchanged output mtimes by comparing bytes before writing.

   The three identity probes now use a separately locked, atomically published
   cache keyed by swiftc path/realpath, file size, mtime and `DEVELOPER_DIR`.
   Darwin also notices xcode-select and SDK-directory/symlink changes. Missing
   SDKs or malformed cached identities trigger new probes. A counting swiftc
   wrapper verifies reuse, restored reuse, size/mtime invalidation and independent
   CLI executions with different valid `DEVELOPER_DIR` spellings. The identity
   helper receives the environment value from ConfigProgram; the ambient-API
   lint's environment-read exception remains confined to ConfigProgram. Literal
   ban-list mentions of Mirror/Hasher are ignored by the lint, while actual calls
   remain forbidden.

**Nits:** both flock declarations use the imported Darwin/Glibc function directly
([TSCBasic FileLock](https://github.com/swiftlang/swift-tools-support-core/blob/main/Sources/TSCBasic/Lock.swift) uses the same call; local Darwin compilation passes,
Linux awaits the owner). Timeout kills the child's process group, falling back to the direct
child if the group is unavailable. A descendant-marker regression failed
with direct-child-only killing and now passes. `swiftc` tool lookup is lazy in both
plugin APIs; Xcode source-membership advice says “add it to the target's Compile
Sources.” CLI usage includes `--config-cache`. An explicit glob table checks
transport and Core against the same expected results, including empty patterns,
retries, case sensitivity, Unicode bytes and literal `?`/brackets. That table also
found both matchers treating the pattern's `*` as a literal when the input value
contained `*`; both now prioritize wildcard semantics. The added rows failed
before the shared repair, and the transport payload was regenerated through
`UPDATE_EMBEDDED`. Program-failure
stderr tail lines are formatted as located `note:` diagnostics. The four requested
files now have no lines over 100 columns; operation-source tuples are a struct,
Swift diagnostic-line lookup is named, and private generation accepts one optional
prepared-generation value instead of three coupled optional/defaulted arguments.

The CLI byte-comparing `--check` was brought forward from the later vendoring phase
so both current CI platforms run it against the Swift-config Naming golden.
Vendoring's command plugin remains later scope. A process test proves `--check`
succeeds for matching bytes, detects a changed file and leaves that file unchanged.
These CI steps are configured but remote CI has not been run here.

**Measured locally after the corrections** (Apple Swift 6.4, arm64 macOS, direct
CLI with explicit host swiftc; these are wall times, not native-Xcode timings):

| Measurement | Result |
| --- | --- |
| Fresh-cache Naming generation, including identity probes and compile | 1.014 s |
| Five cached invocations, including config execution and byte comparison | 0.128–0.137 s; median 0.129 s |
| Same executable cache with identity metadata deliberately removed before each invocation | 0.210–0.247 s; median 0.227 s |
| All four output file mtimes across the cached invocations | Unchanged |
| CLI `--check` against the Naming golden bytes | Pass |

Raw final timings are in
`/private/tmp/3n2-revise-final-timings-emgiyj4e/measurements.json`. These are local
samples, sensitive to machine load. The counting-compiler test independently
establishes that cache hits eliminate the identity probes. The fresh wall
measurement includes module-cache startup; it is not a CI timing result.

**Final local validation:** all **224** package tests pass, including 25 config-
program tests, with exactly the two known issues: optional headers and empty-body
`EmptyCodable`. PetstoreClient passes 2 tests and RuntimeOnlyClient passes 1.
All local SwiftPM builds/tests use `--disable-sandbox` and
`-Xswiftc -warnings-as-errors`; no project compiler/build warnings. The explicit CI-style
CLI golden `--check` passes locally. `git diff --check` passes. Logs:
`/private/tmp/3n2-revise-done-suite.log`, `3n2-revise-done-petstore.log`,
`3n2-revise-done-runtime.log`, and `3n2-revise-ci-check.log`.
The generated golden bytes remain unchanged by this review revision.

**Owner reruns still needed:** Linux `swift:6.1` full suite, including the imported
flock call, signal/hang and descendant-timeout regressions; a fresh sandbox-on
SwiftPM Petstore build; and native macOS/iOS builds with user-script sandboxing.
On native Xcode, expect the phase to run again, preserve unchanged output mtimes
and reuse `ToolchainIdentity.json`. Check a config warning, located type error,
wrong/private entry, and a regex/key-path violation in the issue navigator.
Neither Linux nor native Xcode nor plugin sandboxing was run by Codex.


### 3N-2 second-review corrections (2026-10-25, uncommitted)

The supplied `scratchpad/r2/` scripts were read only. Focused regression tests
first reproduced the shuffle/contextual-token gaps, ASLR-dependent names,
foreign compiler notes (including replayed cached notes), and wrong rename lines.

1. **Shuffle:** the lowercase substring gate now includes `shuffle`, covering
   `.shuffle()` and `.shuffled()` and their seeded variants. Code/literal/comment
   cases and a located NamingErrors row cover the change. The conservative slash
   diagnostic now adds “put spaces around '/' for division.” Class/actor scanning
   skips contextual uses after `for`, `case`, `.`, `let` or `var`, ignoring escape
   backticks when finding the preceding token. Loops, enum cases and member uses
   are regression cases alongside actual class/actor declarations.
2. **Runtime guard:** one collected inventory now drives two separate executions
   for every successful Swift-config evaluation, including executable cache hits.
   They share identical request bytes, have separate request/response/log files,
   and hold the executable lease across both runs. Each response is validated;
   raw response bytes must then match before Core resolves or lowers anything.
   Failure uses the requested error and a note naming the first differing target
   with the shared Swift target formatter. A difference confined to declarative
   settings gets a settings note rather than inventing a name target. An execution
   or malformed-protocol failure aborts generation immediately. No successful
   check is memoized for later generations.

   The implicit array descriptions of a function-local struct and a top-level
   private struct are rejected on both cold and cached evaluations. A third
   case changes only the declarative namespace and is also rejected. Tests pin
   the error/note and assert that both processes ran even on cache hits. The
   owner's Naming example still matches the typed configuration and golden
   bytes, with two executions. The target formatter's access is now `package`
   so Core hints and CLI mismatch diagnostics use one spelling; the public
   configuration-library API is unchanged.
3. **Scope:** the lexical gate blocks cheap, known channels before compiling.
   The dual run is the runtime guard for user configs. CI's macOS+Linux `--check`
   covers only this repository's fixtures, not users' configs. These statements
   replace the earlier claim to close every known channel. `Array.capacity` and
   `ManagedBuffer.capacity` can observe allocator size classes (`malloc_size`
   and platform equivalents), differing between macOS and Linux while stable
   across repeated runs on one host. Standard-library Unicode properties can
   change between toolchain versions. Those observations are outside the portable
   naming contract; two equal executions do not establish cross-host portability
   or prove arbitrary Swift code deterministic.
4. **Compiler notes:** only blocks whose standardized/resolved path is the config
   are forwarded. Foreign notes, including temporary embedded-DSL declaration
   notes, are dropped. Foreign errors retain the existing entry-error mapping
   when no authored error is present. Cache publication normalizes the actual
   compiler header path even when `/tmp` and `/private/tmp` differ. Cache reads
   filter again, so old/restored metadata cannot replay deleted DSL paths. An
   end-to-end NameContext missing-argument case has no `.tmp-` diagnostics. The
   warning replay test restores an aliased legitimate config header plus a stale
   foreign note; the warning survives, the foreign note does not, and executable
   mtime proves the test hit the cache. Compilation failures are not cached.
5. **Rename positions:** prefer a line containing all quoted target wire values,
   then its leading wire value, then any value, then line 1. Method/location enum
   spellings break ties between otherwise identical query/header targets. A test
   runs the Naming config against the example Petstore spec and pins all eight
   rename warnings individually to authored lines 10 through 17, including the
   inline type, enum case and both parameter locations.


**Measured runtime cost** (local Apple Swift 6.4, arm64 macOS; no native Xcode run):

| Measurement | Result |
| --- | --- |
| Isolated warm first + verification process | 8.940 ms total |
| Added verification process in that pair | 4.027 ms |
| Fresh Naming CLI, including probes, compilation and both executions | 1.797 s wall |
| Five cached Naming CLI calls, including both executions | 0.164–0.222 s wall; median 0.201 s |
| Generated-file mtimes across those calls | Unchanged |
| CLI `--check` against Naming golden bytes | Pass |
| Supplied `r2/owner.swift`, copied to a separate temporary config and run against the supplied Petstore spec | Pass |

The extra process is roughly 4 ms in the isolated sample, compared with the
reviewer's earlier roughly 0.2 s native-Xcode cached phase. That is a scale
comparison, **not a measured native-Xcode delta**; wall timings vary with machine
load and the owner must remeasure native builds. The paired-run bookkeeping
measures process launch/wait and redirected I/O; full CLI timings also include
request/response file handling, loading, resolution and rendering. Raw results:
`/private/tmp/3n2-r2-isolated-timing.log` and
`/private/tmp/3n2-r2-timings-t096rj3l/measurements.json`.

**Local validation:** all **226** package tests pass, including 27 config-program
tests, with exactly the two known issues (optional headers and empty-body
`EmptyCodable`). Both examples pass (Petstore: 2; RuntimeOnly: 1). Project builds
and tests use `--disable-sandbox -Xswiftc -warnings-as-errors`, with zero project
compiler warnings. The diagnostic and runtime-guard regressions failed before
the repair. Generated golden Swift bytes are unchanged; NamingErrors gains the
shuffle diagnostic and the revised slash message. `git diff --check` passes.
Logs: `/private/tmp/3n2-r2-baseline.log`, `3n2-r2-program.log`,
`3n2-r2-suite.log`, `3n2-r2-petstore.log` and `3n2-r2-runtime.log`.

Linux `swift:6.1`, fresh sandbox-on SwiftPM and native Xcode reruns remain
owner-run. Native Xcode should still re-run its phase, perform both executions
on a cached program and preserve unchanged output mtimes. Confirm source-located
compiler errors, no temporary DSL notes on a cache hit, the runtime mismatch
error/target note, and acceptance of the owner's config. No owner probe or native
project was edited, and no Linux, native Xcode or plugin-sandbox success is
claimed from these local checks. The changes remain uncommitted.
