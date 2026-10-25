# Naming customization: design (revised after Astra review and owner decisions)

Replacement for `docs/OpenAPIGenerator-Naming.md`. Status: design for PR #23. When accepted it replaces §5.7 of `OpenAPIGenerator-Design.md` and amends §0, §1, §2, §3, §4, §5.1, §8, §9 and §10. Spike packages live outside the repo in the session scratchpad (`naming-spike/`: `SpikePackage/`, `Consumer/`, `XcodeConsumer/`, `direct/`).

## Changes from review

| # | Astra finding | Disposition | Where |
|---|---|---|---|
| 1 | Identities: parameter location, structured owners, operation id vs route, ambiguous/duplicate/unused renames, inline types as their own role | **Accept.** `NameTarget` is a structured enum (`TypeID`, `OperationID`, `ParameterLocation`); operations resolve by id first, then route; same target named twice, or by both forms, is an error; unused renames are warnings; inline types have role `.type(.inline(origin))`. | §4.1, §4.4 |
| 2 | Lowering: replace "lower twice" | **Accept.** A name-independent inventory with stable IDs is collected first, resolved in one batch, and lowering runs once against a resolution table. Candidates are `String?`; failures are deferred until renames are considered. | §5.1 |
| 3 | App vs host compile contract; strict concurrency and SE-0466 | **Accept.** The host contract is pinned (`-swift-version 6`, no default isolation, no extra imports, enforced lexically and by `-emit-imported-modules`). `EndpointsConfiguration` is `Sendable`; the entry symbol is a global `let`; verified to compile and run with and without `-default-isolation MainActor`; test matrix added. | §1 rule 10, §5.10, §8 |
| 4 | Cache: key, writes, tests | **Accept.** Key covers config bytes, version header, DSL bytes, generated runner and transport bytes, entry symbol, flags, compiler identity, SDK identity, generator version. Entries are built in a temp dir and published by atomic rename under an `flock`; per-run I/O dirs; eviction keeps the two newest entries and never touches an entry younger than the lock holder's run. Tests for restored caches and concurrent generation. | §5.10 |
| 5 | Platform table: Xcode is sandboxed; qualify claims | **Accept and corrected.** Xcode's saved wrapper script invokes `sandbox-exec` with the same profile as SwiftPM (quoted). The integrated spike used a Foundation/JSON runner and passed the full environment; only direct `swiftc` runs measured the Foundation-free transport. Pre-release verification list added. | §0 evidence, §5.10 |
| 6 | Spawn robustness | **Accept.** File-action and spawn errors, non-`EINTR` wait failures, signal termination, timeouts (watchdog + `SIGKILL`), bounded stderr (64 KB) specified. | §5.10 |
| 7 | DSL surface: closure-free context, private transport, evaluate once | **Accept.** `NameContext` holds identity, options and candidate names only. Transport and JSON dump live in a generator-emitted support file compiled into the config program, not in the public library. One batch evaluation per generation, with two separate program executions whose complete responses must match (`resolve` writes the dump and names in each execution). | §4.1, §5.10 |
| 8 | Protocol precision | **Accept.** Line protocol kept (the measured fastest); escaping, CR, empty vs absent, UTF-8, record ids, trailer, and stdout separation defined. | §5.10 |
| 9 | §5.7 precision and expanded table; `productionUs` vs `productionUS` | **Accept.** Reference algorithm written as Swift pseudocode plus an expanded table; the spike DSL lowercased every token (`productionUs`), the contract preserves uppercase runs (`productionUS`); the table is frozen only after the reference implementation's test passes (3N-1 acceptance). Acronym default recommendation stated. | §5.7, §9 |
| 10 | DSL drift | **Accept.** Embedded payloads are regenerated from the library file by `UPDATE_EMBEDDED=1 swift test` and a test fails when stale; the response handshake carries a DSL fingerprint; Linux `swift:6.1` and a macOS Xcode 16.x job compile the DSL with the oldest supported compiler. | §2, §5.10, §8 |
| 11 | Phasing | **Accept.** 3N-1 → 3N-2 → 3N-3 kept; native Xcode and host qualification gate 3N-2. | §10 |
| Owner | API modelled on `Package.swift`/`JSONEncoder`, per-category `…NamingStrategy` stored properties, `NamingStrategy` struct with `.verbatim/.camelCase/.upperCamelCase/.custom`, version header, global `let <stem>Configuration`, Swift config only (available from 3N-2), typed `renames` applied last, no lock file | **Adopted throughout.** The previous `EndpointsConfig` protocol, `CategoryNaming`, `stripPrefixes`, hooks-as-list and `preserve` are gone. | §4 |

## Verdict (unchanged in substance)

**3N-2 implementation status:** the Swift config program is implemented; current
local results and measured timings are in [the verification record](OpenAPIGenerator-Verification.md#3n-2-swift-config-program-2026-10-25-uncommitted).
The evidence below is historical spike evidence. The owner has since verified
the Linux launcher hang regression and both examples, plus fresh sandbox-on macOS
example builds. Native Xcode and the revised Linux signal regression await the
owner's rerun; see the verification record's qualification follow-up.

**A typed Swift config file, `<Stem>.endpoints.swift`, that is a normal source of the user's target and that the generator recompiles with the toolchain's `swiftc` into a small config program at build time.** Verified on SwiftPM CLI (macOS, sandbox on), native Xcode projects (macOS and iOS targets, sandboxed), and Linux `swift:6.1`. Cost 0.4–1.5 s once per config change, about 0.3 s when cached. No lock file: source and execution constraints enforce the determinism contract, with a dual-run runtime guard for user configs (§1 rule 10). The only user-facing configuration is `<Stem>.endpoints.swift`, available from 3N-2. There is no user-facing JSON sidecar; one could be added later as a separate decision.

### Spike evidence

| Platform / scenario | Result |
|---|---|
| macOS SwiftPM 6.4, sandbox on, clean | `context.tool(named: "swiftc")` resolved the toolchain `swiftc`; config compiled 1.42 s (empty module cache, Foundation runner), ran 0.20 s; build 7.4 s |
| Same, no change | build 0.17 s, generator not re-run |
| Same, config edited | re-run; compile 0.50–0.68 s (warm module cache); build 1.7 s |
| Cached executable, outside a build | first 1.57 s; second run `cached`, 0.073 s run, 0.29 s wall |
| Xcode 27.1 `.xcodeproj`, macOS tool target | `BUILD SUCCEEDED` 6.7 s; compile 1.40 s; config also compiled into the app module; no-change rebuild also ran the generator (corrected after inspecting script-GUID churn); config edit re-ran it |
| Xcode 27.1, iOS app target, simulator | failed while trusting `SDKROOT` (iPhoneSimulator SDK → "unable to load standard library for target 'arm64-apple-macosx27.0.0'"); succeeded with `xcrun --sdk macosx --show-sdk-path` (compile 1.46 s) |
| Linux `swift:6.1` (6.1.3, arm64) | `Foundation.Process` hung (child exited, `waitUntilExit` never returned; also when run directly, `timeout 60` → 124); with `posix_spawn`: first build 2.40 s, config edit 0.35 s compile, output identical to macOS |
| Direct `swiftc`, Foundation runner | DSL 0.41 s + runner 1.26–2.00 s; module cache 29 MB |
| Direct `swiftc`, Foundation-free runner | DSL 0.22 s + runner 0.18 s; `-O` 0.78 s total; module cache 236 KB; run < 10 ms |
| Type error in the user's file compiled in place | `…/Petstore.endpoints.swift:8:23: error: cannot convert value of type 'Int' to expected argument type '[String]'` |
| `swiftc -frontend -emit-imported-modules` on a file with `import EndpointsGeneratorConfig`, `#if os(Linux) import Glibc #else import Darwin #endif`, `import struct Foundation.Data` | prints `EndpointsGeneratorConfig`, `Darwin`, `Foundation` (active imports only, submodule imports resolved) |
| Global `let` of the config type read from top-level `main.swift` | compiles and runs with `-swift-version 6` and with `-swift-version 6 -default-isolation MainActor` |

**Sandboxing.** SwiftPM wraps every build-tool command (`LLBuildManifestBuilder.addBuildToolPlugins`: `Sandbox.apply(strictness: .writableTemporaryDirectory, writableDirectories: [pluginOutputDirectory])`). **Native Xcode does the same**: the saved wrapper script `XCBuildData/<id>.xcbuilddata/attachments/<id>` is `#!/bin/sh` + `/usr/bin/sandbox-exec -p "(version 1) (deny default) (import \"system.sb\") (allow file-read*) (allow process*) (allow file-write* (subpath /private/tmp) … ) (deny file-write* (subpath <project dir>)) (allow file-write* (subpath <…/BuildToolPluginIntermediates/…/SpikePlugin>) …)" "/${BUILD_DIR}/${CONFIGURATION}/spike-generate" …`. So compiling inside the plugin output directory is allowed on both, and writing anywhere else (including the user's project) is denied. The earlier claim "not sandboxed in Xcode" was wrong.

**Qualifications.** The integrated builds (SwiftPM, Xcode, Linux) ran a runner that imported Foundation, exchanged JSON, and inherited the full environment. The Foundation-free line transport, the empty environment and `SWIFT_DETERMINISTIC_HASHING=1` were exercised only in direct `swiftc` runs. 3N-2 acceptance re-runs the integrated matrix with the final transport. Not verified: Xcode 16.x (Swift 6.1) on macOS, Xcode Cloud, `TOOLCHAINS`-selected toolchains, cross-compilation (`--swift-sdk`, where the host compiler and target SDK differ). Supported hosts are macOS (SwiftPM and Xcode) and Linux; Endpoints doesn't target Windows.

---

## §0 Summary of decisions: changes

| Topic | Decision | One-line reason |
|---|---|---|
| Naming | Per-category strategies (`upperCamelCase` for types and operations, `camelCase` for members, `verbatim`, `custom`), a shared `acronyms` list, typed `renames` applied last, `x-swift-name`/`x-enum-varnames`. Wire names never change. Collisions and reserved names are errors, never auto-suffixed. One algorithm in a dependency-free library, versioned by the config version header. | Idiomatic by default, full developer control, one implementation shared by generator and config program. |
| Config surface | `<Stem>.endpoints.swift` in the user's target, first line `// endpoints-configuration-version: 1`, declaring `let <lowerCamel(stem)>Configuration: EndpointsConfiguration`; evaluated at build time by a generator-compiled config program. Available from 3N-2; no user-facing JSON sidecar. No lock file. | Verified on SwiftPM, Xcode (sandboxed), Linux; 0.4–1.5 s per config change. |
| Determinism of user code | Enforced: imports restricted to the DSL (compiler-checked), no conditional compilation or `#` directives or `@_` attributes or unsafe/random identifiers (lexically checked), empty environment with deterministic hashing, fixed argv, ASCII-only DSL helpers. | The promise in §1 stays "same inputs → same bytes" without a lock. |

Considered and rejected: option sets for strategies (independent toggles interact unpredictably; `.custom` covers the long tail); a lock file (owner decision 1); hooks as a list with a `preserved` candidate (replaced by `.custom` and `.verbatim`).

## §1 Determinism: amendments

**Definition (corrected).** For a fixed tuple **(spec bytes, config bytes, stem, generator version)** the generator writes byte-identical files on every supported machine and OS. For a Swift config, "config bytes" are the bytes of `<Stem>.endpoints.swift`. The generator constrains the config source and execution to enforce this contract. The lexical gate blocks cheap, known channels before compiling; the dual run is the runtime guard for user configs. CI's macOS+Linux `--check` covers this repo's fixtures, not users' configs. The portability contract excludes the explicitly listed host-dependent observations in §1(a):

- **(a) Source constraints**, checked before compiling (§5.10 "Pre-compile check"): the only `import` is `EndpointsGeneratorConfig`; no `#if`/`#elseif`/`#else`/`#endif`; no other `#` directive or literal (`#file`, `#filePath`, `#fileID`, `#line`, `#column`, `#function`, `#dsohandle`, `#sourceLocation`, `#warning`, `#error`, `#available`, `#unavailable`, macros); no underscored implementation identifiers (except the `_` placeholder); no `@_` attributes (`@_silgen_name`, `@_cdecl`, `@_exported`) or `@unchecked` conformances; no exact, case-sensitive identifier tokens naming these stdlib APIs: randomness (`random`, `randomElement`, `shuffled`, `shuffle`, `SystemRandomNumberGenerator`, `RandomNumberGenerator`); concurrency and time (`Task`, `TaskGroup`, `ThrowingTaskGroup`, `DiscardingTaskGroup`, `ThrowingDiscardingTaskGroup`, `TaskLocal`, `TaskPriority`, `TaskExecutor`, `UnownedTaskExecutor`, `withTaskGroup`, `withThrowingTaskGroup`, `withDiscardingTaskGroup`, `withThrowingDiscardingTaskGroup`, `withTaskCancellationHandler`, `withTaskCancellationShield`, `withTaskExecutorPreference`, `withTaskPriorityEscalationHandler`, `addTask`, `addTaskUnlessCancelled`, `addImmediateTask`, `addImmediateTaskUnlessCancelled`, `async`, `asyncDetached`, `asyncUnlessCancelled`, `await`, `Clock`, `ContinuousClock`, `SuspendingClock`, `Duration`, `sleep`); I/O (`readLine`, `CommandLine`); pointers, addresses, reflection and hashing (`withCString`, `withUTF8`, `withUTF8Buffer`, `withContiguousStorageIfAvailable`, `withContiguousMutableStorageIfAvailable`, `withVaList`, `getVaList`, `CVaListPointer`, `OpaquePointer`, `ManagedBufferPointer`, `AutoreleasingUnsafeMutablePointer`, `baseAddress`, `hasPointerRepresentation`, `Unmanaged`, `ObjectIdentifier`, `MemoryLayout`, `Mirror`, `MirrorPath`, `customMirror`, `superclassMirror`, `Hasher`, `hashValue`, `capacity`). Also reject bare-slash regex literals, key-path expressions, class/actor declarations, `===`/`!==`, calls spelled `hash(into:`, and identifiers beginning with `unsafe`, `Unsafe` or `withUnsafe` only when that prefix is followed by an uppercase letter or the end of the token. These checks apply in code, including interpolation, and ignore ordinary literal text and comments. Each violation is an error at `file:line:column`. **Measured allocator channel:** `Array.capacity` and `ManagedBuffer.capacity` follow allocator size classes (`malloc_size` and its platform equivalents) and can differ between macOS and Linux while remaining stable across two runs on one host; the exact-token `capacity` ban blocks these observations. `reserveCapacity` and `minimumCapacity` remain allowed. **Known host-dependent values outside scope:** standard-library Unicode properties can change with toolchain Unicode tables. On macOS the config program links the OS stdlib, so its Unicode tables can also change between macOS versions with the same Xcode. The dual run does not detect these stable cross-host/toolchain differences.
- **(b) Execution constraints**: two separate processes per successful evaluation, including cache hits, with byte-identical complete responses required; environment exactly `SWIFT_DETERMINISTIC_HASHING=1`, stdin `/dev/null`, argv `[exe, "resolve", requestPath, responsePath]`, host language mode `-swift-version 6`, `-Onone`.
- **(c) Library constraints**: `EndpointsGeneratorConfig` has no imports; its helpers are byte-based ASCII functions. A known host/toolchain-dependent channel is: Swift standard-library Unicode operations (`lowercased()`, `uppercased()`, `Character` properties, `Unicode.Scalar.properties`) on **non-ASCII** input, whose results follow the stdlib's Unicode data tables. On macOS the config program links the OS stdlib, so these tables can change between macOS versions even with the same Xcode. Hooks that only use the DSL helpers are unaffected.
- **(d) Fixture coverage**: goldens, process-determinism tests, and the Swift-config golden regenerated with CLI `--check` on both macOS and Linux CI. This verifies this repository's fixtures and does not check users' configs; their runtime guard is the paired execution in (b). The vendoring command plugin follows in Phase 6.

The lexical gate blocks cheap, known random, host-state, address and identity channels before compiling. It covers the measured regex-lexer and key-path-hash escapes and shuffle APIs; deterministic hashing alone does not stabilize address-derived values. Private and local type descriptions can still contain ASLR-dependent addresses without explicit reflection or unsafe APIs. Every evaluated user config therefore runs twice in separate processes and must return byte-identical responses. This dual run is the runtime guard for users' configs and detects observed run-to-run differences, including implicit descriptions. Two equal samples do not prove arbitrary Swift code deterministic or establish cross-host portability. CI's `--check` covers only this repo's fixtures; host/toolchain-dependent Unicode properties remain outside scope as listed in §1(a).

**Compatibility cost:** regexes, key-path conveniences (`map(\.name)`), reference-type helpers, shuffle APIs (including seeded variants) and hand-written hashing cannot be used in config files. Use value types and ordinary closures for naming transformations. The API bans match whole identifier tokens, case-sensitively, so helpers such as `randomPrefix`, `taskName`, `streetAddress`, `pointerStyle`, `asyncLabel`, `clockwise` and `mirrored` are allowed. The unsafe-prefix rule rejects `unsafeLabel`, `UnsafePointer` and `withUnsafeBytes`, but allows `unsafety`. Plain structs, enums, functions, closures, and ordinary String/Array/Dictionary/Set operations remain available. The exact-token `capacity` ban also excludes benign helpers with that name; capacity reservation APIs remain available. Unicode behavior can still vary with the toolchain or macOS version as described above.

- Rule 4 (banned tokens): `Sources/endpoints-generate/ConfigProgram.swift` is the only file allowed to read the environment and spawn processes; the lint allow-lists it with the invariant that nothing read there is interpolated into generated text.
- Rule 9: the Swift config is a build-command input. The DSL and transport sources are not inputs (they are embedded in the generator; a generator change already invalidates commands).
- **New rule 10, config program.** The program is compiled and run as in §5.10 with the constraints (a)–(c); the generator reads only `responsePath`. The header comment `// Inputs: spec sha256 …, config sha256 …` hashes the authored `.swift` bytes. Internal transport fixtures hash their transport bytes; direct in-process calls without source bytes use `none` for the config fingerprint.

## §2 Package and consumer usage

```swift
.target(name: "EndpointsGeneratorConfig", dependencies: []),      // no imports at all; platforms as the runtime (iOS 13, macOS 10.15)
.target(name: "EndpointsGeneratorCore", dependencies: ["EndpointsGeneratorConfig", /* OpenAPIKit, Yams under the trait */]),
// products += .library(name: "EndpointsGeneratorConfig", targets: ["EndpointsGeneratorConfig"])  in both #if branches
```

`EndpointsGeneratorConfig` is a single file, `Sources/EndpointsGeneratorConfig/EndpointsGeneratorConfig.swift`, holding `EndpointsConfiguration`, `NamingStrategy`, `NameTarget` and its identity types, `NameContext`, the ASCII helpers and the reference naming algorithm. It is public API of the package (apps link it) and is **not** trait-guarded. It contains no serialization and no transport. `EndpointsGeneratorCore` imports it and uses the same algorithm in-process for typed configurations, private transport fixtures, and no-config runs.

The generator embeds two generated payloads in `Sources/endpoints-generate/Embedded.swift`: the DSL source and the transport/runner support source (`_EndpointsConfigTransport.swift`, see §5.10). Both are regenerated from their single sources by `UPDATE_EMBEDDED=1 swift test --filter Embedded`; `EmbeddedPayloadTests` fails when stale.

Consumer:
```swift
.target(name: "App",
        dependencies: [
            .product(name: "Endpoints", package: "Endpoints"),
            .product(name: "EndpointsGeneratorConfig", package: "Endpoints"),   // required when App has a <Stem>.endpoints.swift
        ],
        plugins: [.plugin(name: "EndpointsGeneratorPlugin", package: "Endpoints")])
```
In an Xcode project: link `EndpointsGeneratorConfig` to the target and add the plugin under Build Tool Plug-ins. The config file compiles into the app module like any other source; its runtime footprint is one global constant plus the small library (dead-strippable).

## §3 Plugin UX: amendments

- **Discovery (3N-2).** Only `<Stem>.endpoints.swift` beside the spec (`API.endpoints.swift` for bare `openapi.yaml`). 3N-1 discovers no config files and uses defaults. In 3N-2 the Swift file is a build-command input and remains a regular source of the target. In SwiftPM, if it exists and `target.recursiveTargetDependencies` does not contain `EndpointsGeneratorConfig`, the plugin emits `error: Petstore.endpoints.swift requires the EndpointsGeneratorConfig product as a dependency of target 'App'`. Native Xcode's `XcodeTarget.dependencies` omits package-product dependencies, so the plugin skips this check there; the target compiler diagnoses a missing `EndpointsGeneratorConfig` import. A correctly linked native target must not be rejected for unavailable dependency metadata. The plugin cannot know the namespace without evaluating the file; two specs configured to one namespace fail in the consumer compile as "invalid redeclaration" (§9 item 3).
- **Command (Swift config flags from 3N-2).** `endpoints-generate generate --spec <path> --stem <Stem> --output-dir <dir> [--config-swift <swift> [--swiftc <path>]] [--check]`. The plugin resolves and passes `--swiftc` from `context.tool(named: "swiftc")` lazily, only when a Swift config exists, in both entry points (verified to resolve in SwiftPM and Xcode; `/usr/bin/swiftc` on Linux). Without it the CLI tries `xcrun --find swiftc` (Darwin), then `PATH`, then errors. The cache lives in `<pluginWorkDirectory>/ConfigProgram/`. `--config-cache <dir>` selects it for direct CLI use. CLI `--check` compares regenerated bytes with existing outputs and fails on drift without writing them.
- **No-change builds.** SwiftPM must skip the command on unchanged inputs (verified). Native Xcode re-applies the plugin and changes the script GUID in llbuild's command key on every build, so the command runs again; the observed cached path is about 0.2 s, and unchanged generated bytes leave output mtimes untouched. The plugin cannot remove that Xcode scheduling behavior.
- **Diagnostics**, all `path:line:column: severity: message`. Every diagnostic for one config uses its path spelling as supplied to the generator, including compiler headers and cached warnings; canonical paths are used only for file access and identity comparisons:
  - version header missing/unknown: `Petstore.endpoints.swift:1:1: error: first line must be '// endpoints-configuration-version: 1'`;
  - pre-compile violations at their position, e.g. `Petstore.endpoints.swift:3:1: error: configuration files may only import EndpointsGeneratorConfig` or `…:12:1: error: conditional compilation is not allowed in configuration files`;
  - `swiftc` stderr is parsed into blocks beginning at `path:line:column: severity:`. Only blocks whose standardized/resolved path identifies the user's config are forwarded with the supplied config path spelling in their headers and otherwise unchanged, including warnings, which do not fail generation. Notes from other files are dropped, including DSL notes in temporary compile directories. Cached diagnostics are filtered by the same rule, including restored metadata. Non-config errors are replaced with one entry error at the declaration when there is no authored error; a process status/signal/timeout error is added only when no located error was forwarded;
  - entry symbol: `Petstore.endpoints.swift:<line>:<col>: error: configuration must declare exactly one 'let petstoreConfiguration: EndpointsConfiguration'`. Missing/duplicate declarations use this same wording from the lexical check; wrong-type and inaccessible entries use the declaration position instead of deleted temporary files;
  - program failure: `error: configuration program exited with status N` or `… was terminated by signal N` or `… timed out after 60 s`, plus up to 20 stderr lines as notes;
  - nondeterminism: `<config>:<entryLine>:<entryColumn>: error: configuration program is not deterministic: two runs produced different results`, plus a note at the same declaration position naming the first differing `NameTarget`. A declarative-only difference gets a settings note;
  - naming: invalid identifier, reserved name, collision, ambiguous/duplicate rename → errors; unused rename → warning. Prefer the first line containing all the target's quoted wire values, then its own leading value, then any value, else `1:1`. Among otherwise identical quoted targets, prefer their method/location enum spelling (`.query` vs `.header`). Hints use Swift configuration syntax (`renames: [.property("user_id", in: "Pet"): "…"]`). Swift-config rename diagnostics omit internal JSON-pointer suffixes; those pointers remain internal bookkeeping.

## §4 Configuration (replaces the section)

### §4.1 `<Stem>.endpoints.swift`

The owner's example, verbatim, is valid under this design:

```swift
// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let petstoreConfiguration = EndpointsConfiguration(
    namespace: "PetStore",
    accessLevel: .public,
    enumCaseNamingStrategy: .verbatim,
    operationNamingStrategy: .custom { $0.removingPrefix("legacy_").upperCamelCased },
    acronyms: ["ID", "URL"],
    renames: [.property("owner_name", in: "Pet"): "owner"]
)
```

**Rules.** Line 1 is exactly `// endpoints-configuration-version: 1` (ASCII, single space after the colon, optional trailing whitespace). The file declares exactly one global constant named `<lowerCamel(stem)>Configuration` of type `EndpointsConfiguration` (`petstoreConfiguration`; stem `API` → `apiConfiguration`; stem `Pet_store` is already rejected by the file rule). Any other declarations (helper functions, constants) are allowed as long as they satisfy §1(a). The generator reads exactly that symbol; the compiler reports a missing or duplicated one at the exact line.

**Public API** (`EndpointsGeneratorConfig`, Swift 6, all types `Sendable`):

```swift
public struct EndpointsConfiguration: Sendable {
    public var namespace: String? = nil
    public var accessLevel: AccessLevel = .internal                 // .internal, .package, .public
    public var server: ServerConfiguration = .fromSpec              // .fromSpec | .type("MyServer") | .environments([.production: "https://…"], default: .production)
    public var operations: OperationFilter = .all                   // .all | OperationFilter(include: ["*"], exclude: ["DELETE /store/*"])
    public var enums: EnumStyle = .extensible                       // .extensible | .closed
    public var strict: Bool = true
    public var typeNamingStrategy: NamingStrategy = .upperCamelCase       // component and inline types
    public var propertyNamingStrategy: NamingStrategy = .camelCase
    public var parameterNamingStrategy: NamingStrategy = .camelCase      // path, query, header
    public var enumCaseNamingStrategy: NamingStrategy = .camelCase
    public var operationNamingStrategy: NamingStrategy = .upperCamelCase  // without the Endpoint suffix
    public var environmentNamingStrategy: NamingStrategy = .camelCase
    public var acronyms: [String] = []                              // shared by the camel-case styles
    public var renames: [NameTarget: String] = [:]                  // applied last

    public init(namespace: String? = nil, accessLevel: AccessLevel = .internal, server: ServerConfiguration = .fromSpec,
                operations: OperationFilter = .all, enums: EnumStyle = .extensible, strict: Bool = true,
                typeNamingStrategy: NamingStrategy = .upperCamelCase, propertyNamingStrategy: NamingStrategy = .camelCase,
                parameterNamingStrategy: NamingStrategy = .camelCase, enumCaseNamingStrategy: NamingStrategy = .camelCase,
                operationNamingStrategy: NamingStrategy = .upperCamelCase, environmentNamingStrategy: NamingStrategy = .camelCase,
                acronyms: [String] = [], renames: [NameTarget: String] = [:])
    public init(_ configure: (inout EndpointsConfiguration) -> Void)   // let c = EndpointsConfiguration { $0.namespace = "X" }
}

public struct NamingStrategy: Sendable {
    public static let verbatim: NamingStrategy
    public static let camelCase: NamingStrategy
    public static let upperCamelCase: NamingStrategy
    public static func custom(_ name: @escaping @Sendable (NameContext) -> String?) -> NamingStrategy
    public func name(for context: NameContext) -> String?             // nil = no name (an error unless a rename applies)
}

/// Closure-free. Identity, options, and candidate names; nothing else.
public struct NameContext: Sendable {
    public let target: NameTarget            // role and owner
    public let wireName: String              // server spelling (enum raw value; int enums as decimal text)
    public let specName: String?             // x-swift-name / x-enum-varnames, validated; already folded into the candidates below
    public let acronyms: [String]
    public let camelCased: String?           // nil when the name has no ASCII letter or digit
    public let upperCamelCased: String?
    public let verbatim: String?             // nil for empty non-enum, `_` alone, and non-ASCII-only names
    public var isType: Bool { get }          // .type and .operation targets

    public func removingPrefix(_ prefix: String) -> NameContext   // case-sensitive, once; unchanged if nothing is left
    public func removingSuffix(_ suffix: String) -> NameContext
    public func replacing(_ wireName: String) -> NameContext      // same identity/acronyms, clears specName; candidates recomputed
    public func lowercasedASCII(_ value: String) -> String
    public func uppercasedASCII(_ value: String) -> String
}

public enum NameTarget: Hashable, Sendable {
    case type(TypeID)
    case property(String, in: TypeID)
    case parameter(String, in: ParameterLocation, of: OperationID)   // .path, .query, .header
    case enumCase(String, in: TypeID)
    case operation(OperationID)
    case environment(String)                                          // servers[].description, or "server<N>" (1-based)
    public var owner: TypeID? { get } // .type returns itself; properties/cases return their declaring type
    // sugar used in the owner's example: .property("owner_name", in: "Pet") — TypeID and OperationID are ExpressibleByStringLiteral
}
public indirect enum TypeID: Hashable, Sendable, ExpressibleByStringLiteral {
    case component(String)                                  // "Pet"
    case inline(InlineOrigin)
}
public indirect enum InlineOrigin: Hashable, Sendable {
    case property(String, in: TypeID)                       // Pet.owner → Pet.Owner
    case items(of: TypeID)                                  // array item schema of a property/parameter/body type
    case parameter(String, in: ParameterLocation, of: OperationID)
    case body(OperationID)
    case response(OperationID, status: String)              // "200", "2XX", "default"
    case errorResponse(OperationID, status: String)
}
public enum OperationID: Hashable, Sendable, ExpressibleByStringLiteral {
    case id(String)                                         // operationId; "listPets" literal
    case route(method: HTTPMethod, path: String)            // .route(method: .get, path: "/pets/{petId}")
}
public enum ParameterLocation: String, Hashable, Sendable { case path, query, header }
public enum HTTPMethod: String, Hashable, Sendable { case get, put, post, delete, options, head, patch, trace, query }
```

The algorithm, keyword/reserved sets, `ASCII`, `NameError`, category dispatch and
prepared-candidate initializer are package implementation details, not app API.
All public declarations have developer documentation. Identity equality/hashing
is byte-exact, preserving canonically equivalent Unicode spellings as distinct.
Prefix/suffix helpers operate once and case-sensitively on `specName ?? wireName`;
a successful removal clears `specName` and recomputes candidates, while a mismatch
or a removal leaving no input returns the original context. The actual type or
member’s wire value is unchanged.

**Strategies.**
- `.upperCamelCase` / `.camelCase`: the algorithm in §5.7, using `acronyms`.
- `.verbatim`: the server spelling, changed only where Swift requires: every Unicode scalar outside `[A-Za-z0-9_]` becomes one `_`; a leading digit gets a `_` prefix; `""` becomes `empty` for enum cases and is an error elsewhere; `_` alone is an error; keywords get backticks in member position and are an error in type position. `IN_PROGRESS` stays `IN_PROGRESS`; `on-hold` → `on_hold`; `2fa_required` → `_2fa_required`; `X-Request-ID` → `X_Request_ID`.
- `.custom { context in … }`: receives candidates and helpers; returns the name or `nil`. Transformations are helpers on the context, not knobs: `.custom { $0.removingPrefix("Api").upperCamelCased }`. The closure must be `@Sendable` and satisfy the source constraints in §1.

**Precedence per name, lowest to highest:** category strategy applied to the wire name (with `specName`, when present, replacing the wire name as the strategy's input) → `renames[target]`. Core then validates the final name (identifier, keyword, reserved, collision) and only ever adds backticks for member keywords. A strategy that returns `nil` is an error **unless** a rename supplies the name.

**Examples.**

Nothing configured — no file: `Petstore.PetRecord`, `.ownerName`, `.Status.inProgress`, `GetPetByIdEndpoint`, `Environment.productionUS`.

`PetStore` for a `Petstore` spec (namespace, and a schema the backend spelled `Petstore`):
```swift
let petstoreConfiguration = EndpointsConfiguration(
    namespace: "PetStoreAPI",
    renames: [.type("Petstore"): "PetStore"]
)
```

Keep the server's enum spelling for one enum (via rename or a targeted custom strategy) or for all:
```swift
renames: [.enumCase("IN_PROGRESS", in: .inline(.property("status", in: "Order"))): "IN_PROGRESS"]
enumCaseNamingStrategy: .custom { $0.target.owner == .inline(.property("status", in: "Order")) ? $0.verbatim : $0.camelCased }
enumCaseNamingStrategy: .verbatim
```

Strip an `Api` prefix from every schema:
```swift
typeNamingStrategy: .custom { $0.removingPrefix("Api").upperCamelCased }
```

Single-name overrides, including the two operation identities and a located parameter:
```swift
renames: [
    .property("owner_name", in: "Pet"): "owner",
    .operation("listPets"): "FetchPets",                                   // by operationId
    .operation(.route(method: .get, path: "/pets/{petId}")): "FetchPet",  // operation without operationId
    .parameter("id", in: .query, of: "listPets"): "identifier",
    .environment("Production US"): "production",
]
```

### §4.2 Private declarative serialization

The only user-facing configuration is `<Stem>.endpoints.swift`, available from
3N-2. JSON is a private serialization of `EndpointsConfiguration`'s declarative
settings, used by the 3N-2 config program's response and by CLI tests and fixtures.
It is not a sidecar, is never discovered by the plugin, and has no public API or
vocabulary compatibility promise. No public type or member in
`EndpointsGeneratorConfig` exists solely to support this serialization.

Core retains its reader and JSON-pointer diagnostics for malformed transport.
The CLI's internal `--configuration-json` flag feeds this reader; it is omitted
from public usage, README and DocC. Fixtures use `<Stem>.configuration.json` to
make this distinction clear. Core tests construct `EndpointsConfiguration`
values in process where practical; they use transport bytes when testing the
reader, CLI behavior, or fixture-based goldens. There is no legacy-map migration
contract or special migration diagnostic.

### §4.3 Spec extensions
`x-swift-name` on a schema (component or inline), property, parameter, operation or server; `x-enum-varnames` on an enum schema (array parallel to `enum`, same length else error). Values must be ASCII identifiers (error at the extension's pointer otherwise). They replace the wire name as the strategy's input and appear as `specName` in `NameContext`; renames still win. Only these two keys are read, by direct lookup (`vendorExtensions["x-swift-name"]` exists on `JSONSchema`, `OpenAPI.Operation`, `OpenAPI.Parameter`, `OpenAPI.Server` in OpenAPIKit 6.4.0); no dictionary iteration.

### §4.4 Rename diagnostics
- **Duplicate**: the same `NameTarget` twice is impossible in a dictionary literal (compiler error) and an error in the private transport reader.
- **Ambiguous**: an operation renamed both by `.id` and by `.route` → error naming both keys. An inline enum renamed both via `.type(.inline(…))` and via `x-swift-name` is not ambiguous (rename wins).
- **Unused**: a rename whose target does not exist in the (filtered) inventory → warning (§3 location rule). Excluded operations count as absent.
- **Invalid value**: not an ASCII identifier, a keyword in type position, or a reserved name → error.

## §5.1 Pipeline: amendments

```
Inputs(spec bytes, config: .none | .swift(bytes, path, swiftc), stem)
  → Loader, Validator (unchanged)
  → Inventory: one name-independent walk of the document producing [NameRequest] in spec order, each with a stable NameTarget,
               wire name, specName, and source pointer (components, their properties and enum values; inline schemas by origin;
               operations by id/route with located parameters, body, responses; servers). Swift inputs initially inventory all operations and spec servers; records include selection metadata so the config program skips excluded closures. Core filters this inventory and its diagnostics after reading the declarative settings, without a second walk.
  → Resolve: .swift → two separate config program executions (each "resolve" writes the dump and names);
                       require byte-identical responses before using the single resulting resolution table;
             .none → EndpointsGeneratorConfig algorithm in-process (also used by typed and private-transport test inputs). Result: [NameTarget: Resolution] where
             Resolution = .name(String) | .unresolved(reason) ; renames applied last; unused/ambiguous renames diagnosed.
  → Lowering (once): as today, but every name comes from the resolution table; NameAllocator checks reserved/collisions
                     per scope on decided names; .unresolved → error at the request's pointer with a rename hint.
  → Rendering, Diagnostics (unchanged)
```
Derived declarations are built by Core and are not independently resolvable: the `Endpoint` suffix, status-union wrapper names (`Response`, `ErrorResponse`), `_` backing storage, `CodingKeys`, `DiscriminatorKeys`, and status case names (fixed table). Inline body/payload names such as `Body` and `Option<N>` are default candidates, not fixed names. Inline types **are** resolvable (`.type(.inline(origin))`), with a default candidate derived from the origin: property `owner` → `Owner`; items of `tags` → `TagsItem`; `.body` → `Body`; `.response(_, status: "200")` → `Response` for a single outcome or `Option<N>` inside a status union. Status-union payloads always retain `.response`/`.errorResponse` identities; there is no unused union-member identity case.

## §5.7 Naming (replaces the section; frozen when the reference test passes)

The reference algorithm lives in `EndpointsGeneratorConfig` and is used by both the generator and the config program.

```swift
// Byte-level, ASCII-only. Non-ASCII scalars are separators and never classified.
func tokens(_ s: String) -> [String] {
    var out: [[UInt8]] = [], cur: [UInt8] = []
    let b = Array(s.utf8)
    for i in b.indices {
        let c = b[i]
        guard isAlnum(c) else { flush(); continue }                       // every non-[A-Za-z0-9] byte separates
        if let p = cur.last {
            if isLower(p) && isUpper(c) { flush() }                        // petId → pet | Id
            else if isUpper(p) && isUpper(c), i + 1 < b.count, isLower(b[i + 1]) { flush() }   // HTTPStatus → HTTP | Status
            else if isDigit(p) && isUpper(c), i + 1 < b.count, isLower(b[i + 1]) { flush() } // HTTP2 | Status, UTF8 | String, v2 | Beta; 2FA stays one token
        }
        cur.append(c)
    }
    flush(); return out.map { String(decoding: $0, as: UTF8.self) }
}

func camel(_ wire: String, upper: Bool, acronyms: [String]) -> String? {
    let parts = tokens(wire)
    guard !parts.isEmpty else { return nil }
    let screaming = !wire.utf8.contains(where: isLower)                   // IN_PROGRESS, FOO BAR, SOLD
    var out = ""
    for (i, raw) in parts.enumerated() {
        let token = screaming ? asciiLower(raw) : raw
        let lower = asciiLower(token)
        let acronym = acronyms.first { asciiLower($0) == lower }
        if i == 0 && !upper {                                              // first member token
            out += (token.utf8.allSatisfy { !isLower($0) }) ? lower : firstLower(token)   // URL → url, HTTP → http, Production → production
        } else if let acronym {
            out += acronym                                                 // spelled as listed
        } else if token.utf8.allSatisfy({ !isLower($0) }) {
            out += token                                                   // uppercase run kept: userID, X-Request-ID → xRequestID, Production US → productionUS
        } else {
            out += firstUpper(token)                                       // rest of the token unchanged: iPhone → IPhone
        }
    }
    return isDigit(out.utf8.first!) ? "_" + out : out
}
```

Rules, in order:
1. **Input** is the wire name, or `specName` when present, or the `.custom` context's current spelling.
2. **Tokenise** as above. Split on lowercase → uppercase, uppercase → uppercase → lowercase (before the second capital), and digit → uppercase → lowercase (before the capital). Digits otherwise attach to the token in progress. Thus `HTTP2|Status`, `UTF8|String`, `v2|Beta`, but `2FA` is one token and becomes `_2fa` in lower camel case. `IDs` → `I`,`Ds` (the last capital before a lowercase run starts the next token), yielding `iDs`/`IDs`: documented wart, fix with a rename or acronym `"IDs"`.
3. **Screaming case**: when the whole name has no lowercase ASCII letter, every token is lowercased before casing (`IN_PROGRESS` → `inProgress`, `HTTP_2_STATUS` → `http2Status`/`Http2Status`). Otherwise all-uppercase tokens are kept as runs (`userID`, `HTTPStatus` → member `httpStatus`, type `HTTPStatus`).
4. **Acronyms**: whole-token, case-insensitive match; spelled as listed; the first member token is always all-lowercase (`url_string` → `urlString`, `image_url` → `imageURL`). Entries must be non-empty `[A-Za-z0-9]+`; two entries equal under ASCII lowercase → config error "duplicate acronym". Interiors never match (`IDs`, `URLs`).
5. **Casing**: types and operations join capitalised tokens (first letter uppercased, rest of token unchanged); members lower the first token as shown and capitalise the rest.
6. **Leading digit** → `_` prefix. Leading/trailing/multiple separators vanish (`__private` → `` `private` ``, `a..b` → `aB`).
7. **Empty results**: no tokens (empty string, punctuation-only like `---`, non-ASCII-only like `東京`) → `nil` → `empty` for enum raw values, otherwise an error unless a rename applies.
8. **Keywords**: members get backticks; a type equal to a keyword or `Type`/`Protocol`/`Self`/`Any` is an error. The keyword set is the one in `Naming.swift` today, moved to the library.
9. **Operations**: with `operationId`, the id is the input. Without one, the input is constructed as `method.rawValue + " " + path` where each `{name}` in the path is replaced by `" By " + name + " "` (`GET /pets/{pet_id}/photos.json` → `"get /pets/ By pet_id /photos.json"` → tokens `get`,`pets`,`By`,`pet`,`id`,`photos`,`json` → `GetPetsByPetIdPhotosJson`), then `Endpoint` is appended after resolution (renames supply the name without the suffix).
10. **Integer enum values**: `value<N>` / `valueMinus<N>` as today; `x-enum-varnames` and renames override.
11. **Environments**: `servers[].description` or `server<N>` through `environmentNamingStrategy`.
12. **Reserved names and collisions**: unchanged in substance; applied to final decided names within a scope whatever produced them. A collision error lists every wire identity that mapped to the name and a Swift rename hint for each. Library validation messages contain no hints; Core adds one only for a strategy-derived name, and diagnoses invalid explicit rename values directly.

Expanded table (default configuration unless stated; "today" = current branch, probed):

| Wire | Role | Today | `camelCase`/`upperCamelCase` default | with `acronyms: ["ID","URL","HTTP"]` | `.verbatim` |
|---|---|---|---|---|---|
| `Petstore` | type | `Petstore` | `Petstore` | same | `Petstore` |
| `pet_record` | type | `Pet_record` | `PetRecord` | same | `pet_record` |
| `ApiUser` with `.custom { $0.removingPrefix("Api").upperCamelCased }` | type | `ApiUser` | `User` | same | n/a |
| `HTTPStatus` | type / property | `HTTPStatus` / `httpStatus` | `HTTPStatus` / `httpStatus` | same | same / `HTTPStatus` |
| `HTTP2Status` | type / property | `HTTP2Status` / `http2Status` | `HTTP2Status` / `http2Status` | same | same |
| `UTF8String` | property | `utf8String` | `utf8String` | same | `UTF8String` |
| `2FA` | enum case | `_2fa` | `_2fa` | same | `_2FA` |
| `OAuth2Token` | property / type | `oAuth2Token` / `OAuth2Token` | `oAuth2Token` / `OAuth2Token` | same | `OAuth2Token` |
| `v2Beta` | property / type | `v2Beta` / `V2Beta` | `v2Beta` / `V2Beta` | same | `v2Beta` |
| `HTTP_2_STATUS` | property | `http_2_status` | `http2Status` | `http2Status` (first token lowercased) | `HTTP_2_STATUS` |
| `iOS_version` | property / type | `iOS_version` | `iOSVersion` / `IOSVersion` | same | `iOS_version` |
| `owner_name` | property | `owner_name` | `ownerName` | same | `owner_name` |
| `user_id` | property | `user_id` | `userId` | `userID` | `user_id` |
| `userID` | property / type | `userID` | `userID` / `UserID` | same | same |
| `user_IDs` | property | `user_IDs` | `userIDs` | same | `user_IDs` |
| `image_url` | property | `image_url` | `imageUrl` | `imageURL` | `image_url` |
| `url_string` | property | `url_string` | `urlString` | `urlString` | `url_string` |
| `fooBar_bazQux` | property | `fooBar_bazQux` | `fooBarBazQux` | same | `fooBar_bazQux` |
| `__private` | property | `__private` | `` `private` `` | same | `__private` |
| `class` | property | `` `class` `` | `` `class` `` | same | `` `class` `` |
| `X-Request-ID` | header | `xRequestID` | `xRequestID` | same | `X_Request_ID` |
| `page_size` | query | `page_size` | `pageSize` | same | `page_size` |
| `pet_id` | path | `pet_id` | `petId` | `petID` | `pet_id` |
| `IN_PROGRESS` | enum case | `in_progress` | `inProgress` | same | `IN_PROGRESS` |
| `on-hold` | enum case | `onHold` | `onHold` | same | `on_hold` |
| `2fa_required` | enum case | `_2fa_required` | `_2faRequired` | same | `_2fa_required` |
| `Sold` | enum case | `sold` | `sold` | same | `Sold` |
| `""` | enum case | `empty` | `empty` | same | `empty` |
| `a.b` / `a..b` | enum case | `aB` | `aB` | same | `a_b` / `a__b` |
| `FOO BAR` | enum case | `fooBAR` | `fooBar` | same | `FOO_BAR` |
| `URLString` | enum case | `urlString` | `urlString` | same | `URLString` |
| `v2` | enum case | `v2` | `v2` | same | `v2` |
| `---` | enum case | error | `empty` | same | `___` |
| `東京` | enum case / type | error | `empty` / error | same | error |
| `get_pet_by_id` | operation | `Get_pet_by_idEndpoint` | `GetPetByIdEndpoint` | `GetPetByIDEndpoint` | `get_pet_by_idEndpoint` |
| `GET /pets/{pet_id}` (no id) | operation | `GetPetsByPet_idEndpoint` | `GetPetsByPetIdEndpoint` | `GetPetsByPetIDEndpoint` | `get__pets__By_pet_id_Endpoint` (legal, ugly; use a rename) |
| `Production US` | environment | `productionUS` | `productionUS` | same | `Production_US` |
| `foo_bar`, `foo-bar`, `fooBar` in one scope | property | three names | **collision**: `fooBar` ← `foo_bar`, `foo-bar`, `fooBar` | | no collision (`foo_bar`, `foo_bar` ← collision between `foo_bar` and `foo-bar`!) |
| `_id` and `id` in one scope | property | two names | **collision** `id` | | `_id`, `id` |
| `""` and `"empty"` in one enum | enum case | collision | **collision** `empty` | | collision |
| `Type` | type | error | error | | error |

Note on the spike discrepancy: the spike DSL lowercased every non-acronym token (`productionUs`); the contract keeps uppercase runs (`productionUS`), consistent with `xRequestID`. The table above is the contract; the reference implementation's test must reproduce every row before §5.7 is frozen.

Wire names never change: `CodingKeys` raw strings, `rawValue` literals, `Definition` parameter names and header names keep the server spelling in every mode.

## §5.10 Config program: contract, compile, run, cache, platforms

**Version header.** `// endpoints-configuration-version: 1` governs three things for that file: the `EndpointsGeneratorConfig` API generation it was written against (the generator supports a set, currently `{1}`), the host compile settings (v1: `-swift-version 6`, `-Onone`, no default isolation), and the pre-compile rule set and transport version. An unsupported value is an error with the supported list. The header's value is part of the cache key.

**Pre-compile check (enforcing §1(a)).** Two layers:
1. **Lexical scan** of the file bytes with this state machine (ASCII-driven; non-ASCII bytes are opaque): states `code`, `lineComment`, `blockComment(depth)` (nested), `string(kind)` where kind ∈ {`single`, `multiline`, `raw(hashes: n, multiline: Bool)`}, and an `interpolation(parenDepth)` frame pushed on `\(` inside non-raw or correctly-hashed raw strings (raw strings use `\#…#(` with the string's hash count); the frame pops when `parenDepth` returns to 0, resuming the enclosing string. Entering strings: `"""` (then newline) → multiline; `"` → single; `#`+ followed by `"` → raw with that hash count (`#"…"#`, `##"""…"""##`). Escapes `\\`, `\"` inside single/multiline; in raw strings only `\#…` with the matching hash count escapes. Comments: `//` to end of line; `/*` … `*/` nested. In `code` and `interpolation` states the scanner emits identifier tokens (`[A-Za-z_][A-Za-z0-9_]*`), `#`+identifier, `@`+identifier, and punctuation. Violations: identifier `import` whose following module path is not exactly `EndpointsGeneratorConfig` (the token after `import`, skipping `typealias|struct|class|enum|protocol|let|var|func` import kinds, must be `EndpointsGeneratorConfig` followed by a non-`.` token); any `#identifier`; any identifier beginning with `_` except the `_` placeholder; any underscored attribute or `@unchecked` conformance (including whitespace or comments between `@` and its name); exact, case-sensitive identifier tokens for the explicit stdlib API list in §1(a); identifiers with the case-sensitive prefixes `unsafe`, `Unsafe` or `withUnsafe` followed by an uppercase letter or the end of the token. Helper names such as `randomPrefix` and `taskName` are allowed, as is `unsafety`; `unsafeLabel` is rejected. Each violation is reported at `line:column` (1-based, columns in UTF-8 bytes like `swiftc`). The byte scan is linear and has no SwiftSyntax dependency. Fuzz test: every token in the ban list placed in a line comment, a block comment, a nested block comment, a single string, a multiline string, raw strings with 1–3 hashes, and inside an interpolation nested in a string must **not** be reported; the same tokens in code must be.
   In code, a `/` not starting `//` or `/*` and followed by a non-whitespace byte is rejected as `regex literals are not allowed in configuration files; put spaces around '/' for division`; `/=` followed by whitespace and spaced division `a / b` remain allowed. After rejecting a regex-looking slash, skip the invalid line so its quotes/comment-looking bytes cannot hide following lines. A code-state `\` is rejected as `key-path expressions are not allowed in configuration files`. Identifier tokens reject address/identity/hashing families listed in §1(a); class/actor declarations and identity operators are also errors. Contextual `actor`/`class` uses preceded by `for`, `case`, `.`, `let` or `var` are skipped. The lexical gate blocks cheap, known channels before compiling; the dual run is the runtime guard for user configs, and CI's `--check` covers only this repo's fixtures. The compatibility costs and supported ordinary Swift constructs are explicit in §1(a).
2. **Compiler check** (authoritative for imports): `swiftc -frontend -emit-imported-modules <file>` lists the active imported modules after evaluating conditional compilation and resolving `import struct X.Y` to `X` (measured: `EndpointsGeneratorConfig`, `Darwin`, `Foundation` for the test file). Any module other than `EndpointsGeneratorConfig` and `Swift` is an error. This closes the gap if the lexer ever misses an import; the lexer closes the gaps the compiler cannot see (`#if`, `#file`, `@_silgen_name`, unsafe identifiers).

**Layout** under `<pluginWorkDirectory>/ConfigProgram/`:
```
lock                         # flock(2), close-on-exec
ModuleCache/                 # shared under the compile lock
ModuleCache.identity         # root + compiler + SDK + payload identity; reset on change
ToolchainIdentity.json       # cached compiler version and macOS SDK identity
ToolchainIdentity.lock       # serialize identity probes and atomic publication
entries/<key>/               # immutable: config, manifest, lease, diagnostics.json
usage/<key>                  # mutable access timestamp, outside the immutable entry
runs/<stem>-<UUID>/           # request.txt, response.txt, stdout.log, stderr.log; removed after use
```
**Key** = full SHA-256 over length-prefixed config bytes; version header; authoritative DSL and transport bytes; generated main bytes; stem and entry symbol; flags for both compiler steps (incidental cache and user-source paths normalized to placeholders); compiler identity (`swiftc --version`, selected driver path and its realpath); SDK identity (Darwin: explicit macOS SDK path and build version; Linux: compiler directory realpath); generator version. Spec bytes do not change the key. The executable retains the selected `swiftc` driver path: resolving its symlink for execution can accidentally invoke `swift-frontend` instead.

**Compile** (under the lock, only when `entries/<key>/config` is absent): build in `entries/.tmp-<key>-<pid>-<nonce>/`, then `rename(2)` to `entries/<key>/`; if the destination appeared meanwhile, discard the temp dir and use it. Steps (Darwin adds `-sdk <host sdk>` to both; never `SDKROOT`):
1. `swiftc -swift-version 6 -package-name EndpointsConfigProgram -Onone -parse-as-library -emit-library -static -emit-module -emit-module-path <entry>/EndpointsGeneratorConfig.swiftmodule -module-name EndpointsGeneratorConfig -module-cache-path <ModuleCache> -o <entry>/libEndpointsGeneratorConfig.a <entry>/EndpointsGeneratorConfig.swift`
2. `swiftc -swift-version 6 -package-name EndpointsConfigProgram -Onone -I <entry> -L <entry> -lEndpointsGeneratorConfig -module-cache-path <ModuleCache> -module-name EndpointsConfigProgram -o <entry>/config <user's Petstore.endpoints.swift at its original path> <entry>/_EndpointsConfigTransport.swift <entry>/main.swift`
Only the DSL-library step uses `-warnings-as-errors`. Compiling the user's file and the import-list check omit it; warnings are forwarded with the supplied config path spelling and otherwise unchanged, and do not fail generation. Warning blocks are stored as immutable entry metadata with normalized config-header paths and replayed on cache hits/restores. The executable adds `-D ENDPOINTS_CONFIG_PROGRAM`. The linker discards unused code/symbols (Darwin exports only `_main`); Swift compilation remains `-Onone`. Compiler stderr is bounded to its final 64 KB and processed as the diagnostic blocks specified in §3; authored blocks retain their original text except for the config path spelling in the header (§3). Timeout 300 s per compiler step. The generated `main.swift` imports the DSL and calls `_EndpointsConfigTransport.main(configuration: petstoreConfiguration, fingerprint: "…")`. The support source checks argv and handles private request/response I/O. It is top-level code (implicitly `@MainActor`), so a MainActor-isolated global in a `-default-isolation MainActor` app module and a nonisolated global both work (verified). The host program itself is compiled without default isolation.

**Host vs app contract.** The same file compiles in two modules: the app target (user's language mode and isolation settings) and the host program (`-swift-version 6`, nonisolated default, `-Onone`). It is self-contained by §1(a): no other imports, no conditional compilation, so nothing differs between the two compiles except the module's own settings. `EndpointsConfiguration` and all nested types are `Sendable`; `.custom` closures are `@Sendable`; so the global `let` compiles in Swift 5 mode, Swift 6 mode and Swift 6 + `-default-isolation MainActor` without warnings (tests in §8).

**Package access in 3N-2.** Pass the same explicit `-package-name EndpointsConfigProgram`
to both `swiftc` steps: compilation of the embedded DSL module/library and compilation
of the config/runner executable. Package helpers must remain accessible to the
private transport in that executable while staying outside the app-linked public API.

**Transport** (`_EndpointsConfigTransport.swift`, generator-owned, compiled into the program, never in the public library): files, UTF-8, `\n` line terminators (`\r` is escaped like any control byte). Fields are tab-separated; the field encoding is `-` for absent, else `=` followed by the escaped value where `\` → `\\`, TAB → `\t`, LF → `\n`, CR → `\r`; an empty present string is `=`. Request: line 1 `endpoints-config-request 1`; then records `<id>\t<role>\t<identity…>\t<wire>\t<specName>\t<integerCandidate>\t<operationID>\t<route>` where request fields (including the decimal `<id>`) use the field encoding above, and `<identity…>` is the serialized `NameTarget` (role tag then owner segments, each a field); trailer `end <count>`. Response: line 1 `endpoints-config-response 1 <dsl-fingerprint-16>` where the fingerprint is a length-prefixed SHA-256 over the embedded DSL, transport and protocol version (a compile-time constant in generated main); then the configuration dump as `config\t<json>` (one line, hand-written JSON with escaped `\n`, private declarative serialization (§4.2), with custom-strategy markers so the generator knows which names came from closures); then `<id>\t<name-or-absent>` per record in request order; trailer `end <count>`. The generator rejects a wrong fingerprint, a wrong version, a missing trailer, a count or id mismatch, or a non-UTF-8 byte. The program's stdout and stderr go to `stdout.log`/`stderr.log` and are never parsed; stderr is shown (bounded) only on failure. The historical direct spike measured 0.18 s without Foundation versus 1.26–2.00 s with Foundation/JSON (module cache 236 KB versus 29 MB). Current integrated measurements are in the verification record.

**Run:** two separate executions per evaluation through `ConfigProcessRunner`, using `Foundation.Process`, even when the executable is cached. Each execution has its own request/response files and logs, with identical request bytes. Both responses are validated and compared as raw bytes before Core resolves or lowers names. A mismatch reports the §3 error and the first differing entry by Swift target spelling; a declarative-only difference is identified as settings. The entry lease covers both executions. A failed execution/protocol aborts generation; a successful first run always receives the second check. Argv is `[exe, "resolve", requestPath, responsePath]`; environment is exactly `SWIFT_DETERMINISTIC_HASHING=1`; stdin is a `FileHandle` for `/dev/null`, stdout/stderr are separately opened per-execution file handles, never pipes. The private transport has no Foundation or platform-module import: file-private C ABI declarations cover fixed-arity stdio calls on the supported 64-bit hosts. They are unavailable to the user's file. Only `response.txt` is parsed; user stdout cannot corrupt it. Compiler and SDK probes use the same launcher with the inherited environment.

**Process API (owner decision for implementation).** Use `Foundation.Process` behind the small interface, without `waitUntilExit()`. A termination handler signals a semaphore; its bounded wait sends `SIGKILL` after 60 s (compiler steps: 300 s), to the child's process group, including compiler frontend descendants, followed by at most two seconds for termination notification. Failures distinguish launch errors, exit status, signal and timeout. Runtime failures include at most 20 lines from the final 64 KB of stderr. `processRunnerDoesNotHangOnLinux` repeats a child writing to the two redirected files 50 times, with a two-second deadline each. The owner has verified this hang regression on Linux `swift:6.1`; keep Foundation.Process, with no posix_spawn replacement. Signal tests use a tiny Swift child that restores SIGTERM's default disposition and unblocks it before signalling itself, since shell children can inherit blocked SIGTERM on Linux. Normal exits 15 and 143 are separately checked. Fresh sandbox-on SwiftPM example builds also passed on the owner's macOS host; the revised Linux signal test and native Xcode qualification await the owner's rerun.

**Identity probes and native Xcode rebuilds.** `swiftc --version`, `xcrun --sdk macosx --show-sdk-path` and `xcrun --sdk macosx --show-sdk-build-version` are cached under a separate lock and published atomically. The key covers the swiftc driver path, resolved path, size and mtime, and `DEVELOPER_DIR`; on Darwin it also covers the active xcode-select symlink and selected SDK-directory metadata/symlink. Changed metadata, a missing SDK or an invalid cache file re-runs the probes. Host SDK selection still ignores `SDKROOT`. This makes Xcode's repeated cached command cheaper; its changing script GUID prevents no-change command skipping. The command still evaluates the config and compares output bytes every time; write-if-changed preserves output mtimes.

**Eviction:** the compile lock serializes publication and shared module-cache access. Executions hold a shared entry lease until their response has been read; eviction needs a nonblocking exclusive lease. Keep the two most recently used entries and normally a ten-minute grace period for others. The grace period yields to a 2 MB persistent-cache budget (entries plus module cache), evicting oldest unleased entries first; the two newest and active entries always remain protected. This bounds rapid edit bursts while preserving safe execution; exceptionally large programs or concurrent leases can exceed the budget. Rename victims to `.trash-<UUID>` before removal. Remove abandoned run/temp/trash directories older than one hour. After linking, discard intermediate sources, modules, archives and compiler logs before publishing; the manifest checks both the key and executable SHA-256. A relocated, changed-payload or changed-toolchain module cache is reset before the next use, while restored executable hits need no module cache.

**Restored CI caches:** entries are content-addressed and include compiler and SDK identity, so a restored `.build` from another runner either hits (identical toolchain) or misses; a corrupt or partial entry cannot be published because publication is an atomic rename of a fully built directory. Test: copy an entry between two scratch paths and assert a hit; truncate `config` and assert a recompile.

**Platform coverage (historical spike; current implementation qualification is in the verification record):**

| Platform | swiftc discovery | Sandbox | Status |
|---|---|---|---|
| SwiftPM CLI, macOS | `context.tool(named: "swiftc")` (toolchain bin dir from `BuildPlan.swift`/`PIFBuilder.swift`) | build command wrapped by `Sandbox.apply` (`writableTemporaryDirectory` + plugin output dir) | verified with Swift 6.4 / Xcode 27.1 toolchain, Foundation runner, full env |
| Native Xcode project, macOS and iOS targets | `XcodePluginContext.tool(named:)` | **sandboxed**: wrapper script runs `sandbox-exec` with the same profile, denying writes to the project directory | verified with Xcode 27.1 (iOS needs the host SDK from `xcrun`) |
| Linux `swift:6.1` | `/usr/bin/swiftc` via tool search dirs; `PATH` fallback observed | none | verified (posix_spawn) |
| Command plugin (Phase 6 `--check`) | `context.tool` (`PluginCommand` passes toolchain bin) | package dir writable | not verified; Phase 6 |
| Xcode 16.3/16.4 (Swift 6.1) on macOS | same | same | **must verify before release** (3N-2 gate: CI `macos-15` job with Xcode 16.x) |
| Xcode Cloud; `TOOLCHAINS`/custom toolchains; cross-compilation with `--swift-sdk` | same mechanism; cross-compilation needs the host compiler, which `context.tool` returns, but `-sdk` must be the host SDK | — | **must verify before release**; cross-compilation documented as unsupported for Swift configs until verified |

## §8 Testing: additions

1. **`EndpointsGeneratorConfigTests`** (imports only the library): every row of the §5.7 table for all three strategies and the acronym column; tokeniser edge cases (`HTTP2Status`, `UTF8String`, `2FA`, `OAuth2Token`, `v2Beta`, `IDs`, `iOS`, digits, repeated separators); acronym validation (duplicates, non-ASCII); `NameContext` helpers; every declarative field of the default and closure init checked against the default contract, with all six strategies compared through `name(for:)` on probe contexts.
2. **Core:** inventory stability (same `[NameRequest]` for shuffled top-level keys, per the existing shuffle test); private transport reader with pointers; in-process typed configuration tests; rename diagnostics (ambiguous id/route, unused, invalid); deferred failure (`東京` type with a rename passes, without one errors at the schema pointer); collisions `foo_bar`/`foo-bar`/`fooBar`, `_id`/`id`, `""`/`"empty"`; `x-swift-name`/`x-enum-varnames`.
3. **Config program unit tests** (`endpoints-generate` test target): lexer fuzz (ban-list tokens in every comment/string/raw-string/interpolation position are not reported; in code they are, at the right line:column); version header parsing; transport encode/decode round trip including CR, tabs, empty vs absent, non-ASCII, 10k records; fingerprint, trailer and count mismatch rejection; key stability (spec change → same key; each other input → different key).
4. **Goldens:** `Naming` fixture with `Naming.endpoints.swift` (a `.custom` strategy, `.verbatim` for enum cases, acronyms, structured renames of every `NameTarget` case); the Swift result must match the equivalent typed configuration byte for byte; existing `NamingConfigured` continues to cover private fixture transport; a `NamingErrors` fixture whose config violates the §1(a) source constraints with golden diagnostics; all existing goldens regenerated for the new default and reviewed.
5. **Process tests:** local/private-type descriptions in custom closures and declarative settings must fail the dual-run runtime guard on cold and cached evaluations; the owner's example must pass both runs. Three generations with the Swift config in different working directories and `SWIFT_DETERMINISTIC_HASHING` toggled for the *generator* → identical bytes; second run hits the cache; a `.custom` closure that enumerates a `Set` → identical output across runs (deterministic hashing in the program); two generators started concurrently on the same work directory → both succeed, one entry; restored-cache copy and truncation tests.
6. **Host qualification matrix:** a consumer-module compile test checks the config in Swift 5 mode, Swift 6 mode and, when supported by the compiler, Swift 6 with `-default-isolation MainActor`. The integrated `Examples/PetstoreClient` build compiles the same config as a regular target source and evaluates it through the plugin. Linux `swift:6.1` and a macOS job on the oldest supported Xcode (16.x, Swift 6.1) compile the DSL and the example config program; the current macOS job uses the latest Xcode.
7. **Native Xcode checklist (owner-run, gates 3N-2):** macOS target and iOS simulator target with a Swift config build; config edit re-runs the generator; a type error and a §1(a) violation appear in the issue navigator on the config file; `ENABLE_USER_SCRIPT_SANDBOXING=YES` build log shows the sandboxed wrapper and the build succeeds.
8. **Lint:** `BannedAPITests` allow-lists `ConfigProgram.swift` and `Embedded.swift`; `EmbeddedPayloadTests` compares the embedded DSL and transport with their source files.

## §9 Owner decisions

**Final: Swift config only.** `<Stem>.endpoints.swift` is the sole user-facing
config, available from 3N-2. JSON remains private serialization for the config
program and tests. A public JSON format may be considered later; none is promised.

The following previously recorded naming recommendations are unchanged.

1. **Default `acronyms`**: empty (`userId`, `imageUrl`) or `["ID", "URL"]` (`userID`, `imageURL`). Recommend **empty**: it never invents casing the server did not write, keeps uppercase runs the server did write (`userID` stays), matches the existing goldens (`petId`, `storeId`), and the Apple-style spelling is one line away. The Swift API Design Guidelines favour `imageURL`, so this is a taste call; whichever is chosen is frozen with §5.7.
2. **Unused rename severity**: warning (recommended) or error. A spec that drops a field should not break the build because of a stale rename; `strict` does not affect it.
3. **Duplicate-namespace pre-check for Swift configs**: skip in the plugin and rely on the compiler's "invalid redeclaration" (recommended), or have the plugin also compile and run the program (adds ~0.3–1.5 s to every build plan).
4. **Reserve the entry symbol against generated namespaces?** Recommend **no**. Generated code declares only the namespace enum at top level (`PetStore`), and the symbol is lowerCamel with a `Configuration` suffix (`petstoreConfiguration`), so no generated declaration can collide with it; a user's own global of that name is an ordinary compiler error on their side. Stems are already checked case-insensitively, so two configs cannot collide either. Reserving it would only add a rule nobody can trip.
5. **Keep `x-swift-name` / `x-enum-varnames`?** Recommend **yes**: zero cost, lets spec owners fix names at the source; precedence strategy input < rename.

## §10 Phased plan (inserted before Phase 4; each phase one reviewable commit, sized for GPT-6.1 Sol)

**3N-1 — Algorithm, identities, typed config and private transport (no config program).**
Scope: `EndpointsGeneratorConfig` target and product with the full §4.1 API (custom strategies run only for in-process typed configuration; no Swift config files are evaluated yet); reference algorithm and §5.7 table test; `NameTarget` identity types; Core: inventory walk, resolution table, single lowering, rename diagnostics, deferred failures, `x-swift-name`/`x-enum-varnames`; in-process typed configuration entry point and private JSON reader with pointer diagnostics (§4.2); Swift rename hints; no plugin config discovery; goldens regenerated; `NamingConfigured` golden. `Examples/PetstoreClient` uses default internal access and `@testable import` temporarily, with a 3N-2 TODO to restore a Swift config with public access and the ordinary second-module import.
Acceptance: `swift test` green on macOS and Linux; every §5.7 row asserted; inventory shuffle test green; all goldens compile warning-free; a review note listing every identifier that changed in existing goldens; malformed private transport receives pointer diagnostics, without migration promises. Both examples pass; exactly the two deferred runtime issues remain.

**3N-2 — Swift config program (gated by native Xcode and host qualification).**
Scope: `Sources/endpoints-generate/ConfigProgram.swift` (version header, lexical check, `-emit-imported-modules` check, a file-based Foundation.Process runner behind one internal interface (owner-run Linux hang regression passed; Foundation.Process retained) with timeouts/signals/bounded stderr, swiftc/SDK discovery, key, locked atomic compile and publish, eviction, run), `_EndpointsConfigTransport.swift` source plus `Embedded.swift` and `UPDATE_EMBEDDED`; `--config-swift`/`--swiftc`; Swift config discovery and `context.tool(named: "swiftc")` in both entry points, configuration-library dependency check in SwiftPM only; `Naming` golden added with a Swift config; PetstoreClient public API test restored; `NamingErrors` golden; process, concurrency and restored-cache tests; host matrix examples; CI jobs (Linux 6.1, macOS oldest Xcode, macOS latest).
Acceptance: `Examples/PetstoreClient` with `Petstore.endpoints.swift` builds and tests with the sandbox on, on macOS (both Xcode jobs) and `swift:6.1`; the three isolation variants compile; SwiftPM no-change rebuild does not re-run the generator; native Xcode re-runs its changing-GUID script on every build (about 0.2 s observed before identity-probe caching), leaves unchanged output files untouched, and uses the identity-probe cache; config edit re-runs it, compile under 2 s on CI; cache hit path including both config executions under 0.5 s; mismatched responses are rejected before lowering; a type error reports at `Petstore.endpoints.swift:<line>:<col>`; each §1(a) violation reports at its line; `ProcessDeterminismTests`, concurrency and restored-cache tests green; `ConfigProgram/` under 2 MB after ten edits; **the owner-run native Xcode checklist (§8 item 7) is complete and recorded for a macOS target and an iOS simulator target**; the integrated run is re-measured with the Foundation-free transport and empty environment and the numbers replace the spike's in the verification doc.

**3N-3 — Docs, examples, verification.**
Scope: `Generating.md` sections (Naming with the table, Configuring in Swift, Determinism rules for config files, Platforms and what is unsupported); README requirements (`EndpointsGeneratorConfig` dependency when using a Swift config; cross-compilation notes); `OpenAPIGenerator-Verification.md` entries with timings; `OpenAPIGenerator-Design.md` §0/§1/§2/§3/§4/§5.1/§5.7/§8/§9/§10 updated from this document.
Acceptance: docs reviewed; CI green; verification doc lists the pre-release items still open (Xcode Cloud, custom toolchains, cross-compilation) as owner-run.

---

### Critical Files for Implementation
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/EndpointsGeneratorCore/Naming.swift` — algorithm moves to the new library; Core keeps `NameAllocator`, keyword/reserved sets move with the algorithm
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/EndpointsGeneratorCore/Lowering.swift` (with `Lowering/Operations.swift`) — inventory walk, resolution table, single lowering, rename diagnostics
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/EndpointsGeneratorCore/Configuration.swift` — typed settings adapter and private declarative transport reader with pointer diagnostics
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Sources/endpoints-generate/main.swift` — `--config-swift`/`--swiftc`; new `ConfigProgram.swift`, `Embedded.swift`, and the transport source beside it
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Plugins/EndpointsGeneratorPlugin/Plugin.swift` — `.endpoints.swift` discovery and `context.tool(named: "swiftc")` in both entry points; dependency check in SwiftPM only
- `/Users/zac/Projects/velos/Endpoints/.claude/worktrees/openapi-endpoint-generation-f58e25/Package.swift` — `EndpointsGeneratorConfig` target and product in both `#if os(Linux)` branches; Core depends on it

Spike sources to crib from (outside the repo): `naming-spike/SpikePackage/Sources/spike-generate/main.swift` (posix_spawn helper, SDK/swiftc discovery, two-step compile), `naming-spike/SpikePackage/Plugins/SpikePlugin/Plugin.swift` (tool lookup in both plugin contexts), `naming-spike/direct/nf/main.swift` (Foundation-free line protocol), `naming-spike/XcodeConsumer/project.yml` (xcodegen project with `buildToolPlugins` for macOS and iOS targets) and its `DD/Build/Intermediates.noindex/XCBuildData/*/attachments/*` sandbox wrapper scripts.