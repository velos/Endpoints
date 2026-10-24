# Runtime hooks and status/parameter generation verification

Base: foundation commit `54563a1`. This phase is uncommitted. Local toolchain:
Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 macOS, SwiftPM's default
`swiftbuild` engine. Linux Swift 6.1 execution remains an owner-run check.

## Runtime

- `DecoderType` has an additive response-aware requirement with a legacy-forwarding
  default. `HTTPResponseJSONDecoder` creates a fresh JSONDecoder per call, applies
  its Sendable configuration closure, supplies status/headers in `userInfo`, and
  represents an empty JSON body as `null`.
- Async and all callback task overloads retain the HTTP response. Error decoding
  receives it too. The public `Definition.response(data:response:error:)` signature
  and existing response classification are preserved. Combine already delegates
  to async; its metadata delivery has a transport test.
- Repeated query and form values share scalar-first dispatch. Tests cover nil and
  empty arrays, nil elements, ordered repeated values, scalar/multi conformers,
  scalar nil without multi fallback, and unchanged fixed parameters.
- Int32, Int64, UUID and RawRepresentable default implementations support typed
  path/query parameters. No package dependency was added to Endpoints.
- Existing runtime tests were not edited. `PathTemplate.swift` and
  `Sources/EndpointsMocking` were not edited. The only change to
  `Endpoint+URLRequest.swift` is the localized parameter expansion block.

## Generator

- Success/error status enums, explicit codes, 2XX/4XX/5XX and default, body-less
  cases, JSON media priority, raw Data payloads, and frozen reason-phrase names.
  Members retain spec order; dispatch tries exact codes before ranges/default.
- Scalar widths, UUID, open/closed string and integer enums, repeated array query
  parameters, optional headers, and parameter overrides by wire name plus location (ASCII case-insensitive for
  headers, byte-exact otherwise). Unsupported serialization styles retain strict/lenient diagnostics.
- Coder overrides are emitted when required: Date bodies; Date or union responses;
  Date, union or raw error payloads. Date analysis follows named/inline payloads.
- Operations source goldens and compiled integration tests exercise typed request
  components, JSON/empty/raw response dispatch, error ranges/default/unmatched
  statuses, inline payloads, scalar dates, and deprecated endpoint enum conformances.
  SchemaEdges also compiles and requests closed string/integer enum parameters.
- Petstore and its public two-module example now include SearchPetsEndpoint with
  repeated tags and the `.ok([Pet])` / `.noContent` status union.
- Process determinism now exercises both Petstore and Operations across distinct
  directories, hash seeds, locales, timezones and ambient Yams encodings.

## Design details resolved during implementation

The updated design records these implementation details:

1. JSONDecoder parses input before invoking a union initializer, so raw binary
   unions require an additional hook. `HTTPResponseJSONDecoder.isRawDataStatus` is an
   opt-in Sendable status selector, defaulting to false. Selected data becomes a
   JSON base64 string. Generated overrides select it by the same status precedence
   as the union, independent of the HTTP Content-Type header.
2. Union payloads decode through `singleValueContainer().decode(T.self)`.
   Calling `Data(from:)` or `Date(from:)` directly bypasses JSONDecoder's special
   strategies. The raw/Date integration tests exercise this distinction.
3. Inline union payloads use §5.6's nested OptionN names, indexed by authored
   outcomes within the success/error category, including body-less outcomes.
4. Integer enum formats retain Int32/Int64 width; out-of-range Int32 enum literals
   receive an unsupported diagnostic instead of generating uncompilable Swift.
5. Enum conformance extensions for deprecated endpoints also have the deprecation
   attribute, preventing generated references to the enclosing endpoint from
   warning. Schema deprecation remains documentation-only.
6. Embedded enum path placeholders interpolate raw values before the existing
   runtime handles the computed path String. Scalar simple/form serialization
   accepts either explode value; exploded query arrays remain required.
7. An operation with no success/default outcome receives an unsupported diagnostic.
   No public response shape is invented for it.

## Checks

Every local Swift build/test used `--disable-sandbox` and
`-Xswiftc -warnings-as-errors`. The module cache environment overrides were:

```sh
export CLANG_MODULE_CACHE_PATH=/tmp/endpoints-module-cache
export SWIFT_MODULECACHE_PATH=/tmp/endpoints-module-cache
```

| Check | Result |
| --- | --- |
| `swift build --disable-sandbox` with warnings as errors | Pass |
| `swift build --disable-sandbox --product endpoints-generate` with warnings as errors | Pass |
| `swift build --disable-sandbox --build-tests` with warnings as errors | Pass; zero warnings, including generated sources |
| `swift test --disable-sandbox` with warnings as errors | Pass: runtime 95, mocking 20, Core 31, generated goldens 19; 165 total, with exactly 3 expected known issues |
| `swift build --disable-sandbox --disable-default-traits --product Endpoints` with warnings as errors | Pass |
| PetstoreClient build with `--build-tests`, then test, with warnings as errors | Pass; 2 tests, zero warnings |
| RuntimeOnlyClient build with `--build-tests`, then test, with warnings as errors | Pass; 1 test, zero warnings |
| RuntimeOnlyClient `.build/checkouts` | Exists and is empty; no OpenAPIKit or Yams |
| Unhandled spec/sidecar warning on Swift 6.4 | None observed in the example builds/tests |
| `git diff --check` | Pass |
| Linux Swift 6.1 / native Xcode | Not run here; owner reported 108 Linux tests passing before these review revisions; the revised code needs an owner-run Linux check |

One final Petstore relink hit disk exhaustion. Removing only disposable build
artifacts from the earlier checkout-specific scratch/probe directories freed
space; the subsequent example build and test passed.

CI sandbox settings are unchanged: CI builds with sandboxing enabled. The prior
foundation probe established that Codex blocks nested sandbox-exec at manifest
loading; these local runs do not establish plugin sandbox qualification.

## Every added known-issue wrapper

All are in `Tests/EndpointsGeneratedGoldenTests/OperationTests.swift`, with comments
naming `claude/endpoints-runtime-fixes`. None are intermittent; unexpected success
will flag the wrapper for removal.

- `optionalHeadersOmitNilAndDescribePresentValues`: correct omission and present
  header assertions; only `EndpointError.invalidHeader` is matched as known.
- `pathSpecialCharactersEncodeOnce`: request creation remains outside the wrapper;
  only the correct URL expectation is wrapped, exposing double percent encoding.
- `emptyBodyErrorUsesDefaultEmptyCodable`: expects a typed EmptyCodable error;
  only an empty-body `errorResponseParseError` containing DecodingError is matched.

The three bug implementations are intentionally unchanged.

## Runtime-hooks review revisions

1. Body-less union outcomes select raw decoding so arbitrary bodies are ignored.
   The text 202 and HTML 404 regression tests both failed with invalid JSON before
   the repair and pass after regeneration. Single Void responses and the default
   EmptyCodable error path retain their existing behavior.
2. New public runtime APIs have documentation, including protocol defaults and
   scalar representations. MultiValueParameterRepresentable has its own file.
   Request/error docs and the DocC topics/examples describe arrays and metadata.
   Int32/Int64/UUID implementations and shipping location remain unchanged pending
   the owner's separate decision; only documentation and extension grouping changed.
3. The selector is `isRawDataStatus: @Sendable (_ statusCode: Int) -> Bool`;
   configure is last and raw statuses force `.base64` after configuration. The
   JSON-only initializer defaults configure, while the raw-data initializer requires
   its selector; the signatures are disjoint. Tests cover
   deferred/custom strategies, selected raw bytes and empty data, and unselected JSON.
4. Support omits empty configuration closures. Selector arms are omitted only when
   their result agrees with the next matching lower-precedence arm, retaining exact
   exceptions to ranges and defaults. Pure code predicates become comparisons.
   Every explicit 204 arm is now pruned: Definition supplies empty data for 204
   before any decoder runs. With unmatched union statuses also raw, Download's
   success selector is `$0 != 200`; its error selector is `$0 != 400`. The Selection fixture covers raw defaults,
   JSON ranges and an exact body-less exception. Missing-status errors name the
   required `decode(_:from:response:)` overload.
5. Runtime tests have focused decoder behaviors, separate assertions and documented
   suites. Async and callback metadata tests each use status arguments with explicit
   unexpected-branch issues. No known-issue wrapper was added or broadened.
6. The outcomes test includes an error-only 400 response and checks the specific
   unsupported reason and source pointer.

Nits: example imports retain their original order with FoundationNetworking at the
top; dropped explicit 3xx and 1XX/3XX ranges have source-marked note diagnostics;
header parameter overrides use ASCII case-insensitive identity. The Operations
fixture overrides a path-item `x-count` String header with an operation `X-Count`
Int64 header; its existing typed request assertions exercise that merge.

The regression run initially hit disk exhaustion. Only disposable example/probe
build artifacts were removed; the baseline regressions and all subsequent checks
then ran. No source files were removed and no commits were created.

## Second runtime-hooks review

- Initializers are disjoint, with a defaulted configure-only JSON initializer and
  a required selector for raw decoding. Both are documented; generated call sites
  are unchanged.
- Raw selector pruning always treats explicit 204 as don't-care, with the reason
  documented in the renderer. Lowering's raw flags are unchanged. The new SearchPets
  integration test passes junk 204 bytes through Definition.response, observes
  empty data, then decodes `.noContent` with that HTTP response.
- Unmatched statuses in unions without a default are raw so invalid JSON cannot
  preempt status dispatch. The HTML 502 regression failed before the fix with
  "The given data was not valid JSON." and now reports "Unexpected status code 502."
- These two requests interact: unmatched raw statuses require selectors even when
  the only declared non-JSON status was 204. Download simplifies to `$0 != 200`,
  SearchPets likewise to `$0 != 200`, and Lookup retains a JSON 2XX range over a raw
  fallback. Plain factories for these unions would regress unmatched HTML status
  diagnostics. PlaceOrder's sample uses `$0 != 201`, covering body-less 202 and
  unmatched statuses. These are implementation-only predicate differences.
- Missing-status errors now name `HTTPResponseJSONDecoder.decode(_:from:response:)`
  exactly. Section 7's union initializer and Date-enabled decoder factory were
  copied from the goldens, with the sample namespace/payload substituted.
- Async/callback success and typed-error metadata have separately named tests;
  empty-body decoding has separate tests for each overload. Error-only operations
  have their own mapping test. The three known-issue wrappers remain unchanged.
